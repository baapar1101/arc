"""خرید، تمدید و تأیید پرداخت اشتراک پشتیبانی."""

from __future__ import annotations

import logging
from datetime import datetime, timedelta
from typing import Any, Dict, List, Optional

from sqlalchemy.orm import Session, joinedload

from adapters.db.models.support.billing import (
	SupportInvoice,
	SupportPaymentSession,
	SupportPlan,
	SupportSubscription,
)
from adapters.db.models.user import User
from app.core.responses import ApiError
from app.services.support.support_billing_settings import (
	get_support_grace_period_days,
	get_support_invoice_prefix,
)
from app.services.support.support_payment_gateway import (
	initiate_support_gateway_payment,
	list_active_system_gateways,
	resolve_support_gateway,
)

logger = logging.getLogger(__name__)

SESSION_TTL_MINUTES = 30


def _next_invoice_code(db: Session) -> str:
	prefix = get_support_invoice_prefix(db)
	day = datetime.utcnow().strftime("%Y%m%d")
	# شمارنده ساده بر اساس تعداد امروز
	like = f"{prefix}-{day}-%"
	count = db.query(SupportInvoice).filter(SupportInvoice.code.like(like)).count()
	return f"{prefix}-{day}-{count + 1:06d}"


def _serialize_invoice(inv: SupportInvoice) -> Dict[str, Any]:
	return {
		"id": inv.id,
		"code": inv.code,
		"user_id": inv.user_id,
		"plan_id": inv.plan_id,
		"plan_name": inv.plan.name if inv.plan else None,
		"invoice_type": inv.invoice_type,
		"amount": float(inv.amount or 0),
		"discount_amount": float(inv.discount_amount or 0),
		"currency_id": inv.currency_id,
		"status": inv.status,
		"issued_at": inv.issued_at.isoformat() if inv.issued_at else None,
		"due_at": inv.due_at.isoformat() if inv.due_at else None,
		"paid_at": inv.paid_at.isoformat() if inv.paid_at else None,
		"gateway_id": inv.gateway_id,
		"gateway_provider": inv.gateway_provider,
		"gateway_ref": inv.gateway_ref,
		"gateway_trace": inv.gateway_trace,
		"period_months": inv.period_months,
		"coverage_starts_at": inv.coverage_starts_at.isoformat() if inv.coverage_starts_at else None,
		"coverage_ends_at": inv.coverage_ends_at.isoformat() if inv.coverage_ends_at else None,
		"payment_session_id": inv.payment_session_id,
	}


def _cancel_open_sessions(db: Session, user_id: int) -> None:
	now = datetime.utcnow()
	rows = (
		db.query(SupportPaymentSession)
		.filter(
			SupportPaymentSession.user_id == int(user_id),
			SupportPaymentSession.status.in_(("created", "redirected")),
		)
		.all()
	)
	for s in rows:
		s.status = "cancelled"
		s.updated_at = now
		inv = db.query(SupportInvoice).filter(SupportInvoice.id == s.invoice_id).first()
		if inv and inv.status == "awaiting_payment":
			inv.status = "expired"
			inv.updated_at = now


def _activate_or_extend_subscription(
	db: Session,
	*,
	user_id: int,
	plan: SupportPlan,
	invoice: SupportInvoice,
) -> SupportSubscription:
	now = datetime.utcnow()
	grace_days = get_support_grace_period_days(db)
	period_days = int(plan.period_months) * 30

	current = (
		db.query(SupportSubscription)
		.filter(
			SupportSubscription.user_id == int(user_id),
			SupportSubscription.status.in_(("active", "grace")),
		)
		.order_by(SupportSubscription.id.desc())
		.first()
	)

	invoice_type = "purchase"
	if current and current.status == "active" and current.ends_at and current.ends_at > now:
		# تمدید: افزودن مدت به انتهای اشتراک فعلی
		starts = current.starts_at or now
		ends = current.ends_at + timedelta(days=period_days)
		current.plan_id = plan.id
		current.ends_at = ends
		current.grace_ends_at = ends + timedelta(days=grace_days) if grace_days else ends
		current.source_invoice_id = invoice.id
		current.status = "active"
		current.updated_at = now
		invoice_type = "renewal"
		sub = current
	else:
		if current and current.status in ("active", "grace"):
			current.status = "replaced"
			current.updated_at = now
		starts = now
		ends = now + timedelta(days=period_days)
		sub = SupportSubscription(
			user_id=int(user_id),
			plan_id=plan.id,
			status="active",
			starts_at=starts,
			ends_at=ends,
			grace_ends_at=ends + timedelta(days=grace_days) if grace_days else ends,
			auto_renew=False,
			source_invoice_id=invoice.id,
		)
		db.add(sub)
		invoice_type = "purchase" if not current else "renewal"

	invoice.invoice_type = invoice_type
	invoice.coverage_starts_at = starts
	invoice.coverage_ends_at = ends
	db.flush()
	return sub


def checkout_support_plan(
	db: Session,
	*,
	user_id: int,
	plan_id: int,
	gateway_id: Optional[int] = None,
	client_return_path: Optional[str] = None,
	source: str = "app",
) -> Dict[str, Any]:
	plan = db.query(SupportPlan).filter(SupportPlan.id == int(plan_id)).first()
	if not plan or not plan.is_active:
		raise ApiError("PLAN_NOT_FOUND", "پلن فعال یافت نشد", http_status=404)

	_cancel_open_sessions(db, user_id)

	now = datetime.utcnow()
	amount = float(plan.price or 0)
	if plan.is_free:
		amount = 0.0

	invoice = SupportInvoice(
		user_id=int(user_id),
		plan_id=plan.id,
		code=_next_invoice_code(db),
		invoice_type="purchase",
		amount=amount,
		discount_amount=0,
		currency_id=plan.currency_id,
		status="awaiting_payment",
		issued_at=now,
		due_at=now + timedelta(minutes=SESSION_TTL_MINUTES),
		period_months=int(plan.period_months),
	)
	db.add(invoice)
	db.flush()

	# رایگان: بدون درگاه
	if amount <= 0 or plan.is_free:
		invoice.status = "paid"
		invoice.paid_at = now
		invoice.invoice_type = "trial" if plan.trial_days and amount <= 0 else "purchase"
		_activate_or_extend_subscription(db, user_id=user_id, plan=plan, invoice=invoice)
		db.commit()
		db.refresh(invoice)
		return {
			"invoice": _serialize_invoice(invoice),
			"payment_url": None,
			"session_id": None,
			"requires_payment": False,
		}

	gateway = resolve_support_gateway(db, gateway_id)
	session = SupportPaymentSession(
		user_id=int(user_id),
		invoice_id=invoice.id,
		gateway_id=gateway.id,
		amount=amount,
		currency_id=plan.currency_id,
		status="created",
		client_return_path=client_return_path or "/user/profile/support/billing",
		expires_at=now + timedelta(minutes=SESSION_TTL_MINUTES),
	)
	db.add(session)
	db.flush()

	invoice.payment_session_id = session.id
	invoice.gateway_id = gateway.id
	invoice.gateway_provider = gateway.provider

	user = db.query(User).filter(User.id == int(user_id)).first()
	user_name = None
	user_email = None
	if user:
		user_name = f"{user.first_name or ''} {user.last_name or ''}".strip() or None
		user_email = user.email

	try:
		init = initiate_support_gateway_payment(
			db,
			session=session,
			gateway=gateway,
			description=f"اشتراک پشتیبانی: {plan.name}",
			source=source,
			user_name=user_name,
			user_email=user_email,
		)
	except Exception:
		invoice.status = "failed"
		session.status = "failed"
		db.commit()
		raise

	invoice.gateway_ref = init.external_ref
	db.commit()
	db.refresh(invoice)

	return {
		"invoice": _serialize_invoice(invoice),
		"payment_url": init.payment_url,
		"session_id": session.id,
		"requires_payment": True,
	}


def retry_invoice_payment(
	db: Session,
	*,
	user_id: int,
	invoice_id: int,
	gateway_id: Optional[int] = None,
	source: str = "app",
) -> Dict[str, Any]:
	invoice = (
		db.query(SupportInvoice)
		.options(joinedload(SupportInvoice.plan))
		.filter(SupportInvoice.id == int(invoice_id), SupportInvoice.user_id == int(user_id))
		.first()
	)
	if not invoice:
		raise ApiError("INVOICE_NOT_FOUND", "صورت‌حساب یافت نشد", http_status=404)
	if invoice.status == "paid":
		raise ApiError("ALREADY_PAID", "این صورت‌حساب قبلاً پرداخت شده است", http_status=400)
	if float(invoice.amount or 0) <= 0:
		raise ApiError("INVALID_AMOUNT", "این صورت‌حساب نیاز به پرداخت ندارد", http_status=400)

	# فقط از روی پلن فعلی checkout جدید بساز (ساده‌تر و امن‌تر)
	return checkout_support_plan(
		db,
		user_id=user_id,
		plan_id=invoice.plan_id,
		gateway_id=gateway_id or invoice.gateway_id,
		source=source,
	)


def confirm_support_payment(
	db: Session,
	*,
	session: SupportPaymentSession,
	success: bool,
	external_ref: Optional[str] = None,
	gateway_trace: Optional[str] = None,
) -> Dict[str, Any]:
	"""Idempotent تأیید پرداخت و فعال‌سازی اشتراک."""
	now = datetime.utcnow()

	if session.status == "paid":
		return {"success": True, "already_paid": True, "invoice_id": session.invoice_id}

	if session.expires_at and session.expires_at < now and not success:
		session.status = "expired"
		inv = db.query(SupportInvoice).filter(SupportInvoice.id == session.invoice_id).first()
		if inv and inv.status == "awaiting_payment":
			inv.status = "expired"
		db.commit()
		return {"success": False, "already_paid": False, "invoice_id": session.invoice_id}

	invoice = (
		db.query(SupportInvoice)
		.options(joinedload(SupportInvoice.plan))
		.filter(SupportInvoice.id == session.invoice_id)
		.first()
	)
	if not invoice:
		session.status = "failed"
		db.commit()
		raise ApiError("INVOICE_NOT_FOUND", "صورت‌حساب یافت نشد", http_status=404)

	if not success:
		session.status = "failed"
		invoice.status = "failed"
		if external_ref:
			session.external_ref = external_ref
			invoice.gateway_ref = external_ref
		db.commit()
		return {"success": False, "already_paid": False, "invoice_id": invoice.id}

	# مبلغ باید با نشست یکی باشد (قبلاً در initiate قفل شده)
	plan = invoice.plan or db.query(SupportPlan).filter(SupportPlan.id == invoice.plan_id).first()
	if not plan:
		session.status = "failed"
		invoice.status = "failed"
		db.commit()
		raise ApiError("PLAN_NOT_FOUND", "پلن یافت نشد", http_status=404)

	session.status = "paid"
	session.paid_at = now
	if external_ref:
		session.external_ref = external_ref
	session.updated_at = now

	invoice.status = "paid"
	invoice.paid_at = now
	invoice.gateway_ref = external_ref or invoice.gateway_ref
	invoice.gateway_trace = gateway_trace
	invoice.payment_session_id = session.id
	invoice.updated_at = now

	_activate_or_extend_subscription(
		db,
		user_id=int(session.user_id),
		plan=plan,
		invoice=invoice,
	)
	db.commit()
	return {"success": True, "already_paid": False, "invoice_id": invoice.id}


def list_user_invoices(db: Session, user_id: int, *, limit: int = 50, offset: int = 0) -> Dict[str, Any]:
	q = (
		db.query(SupportInvoice)
		.options(joinedload(SupportInvoice.plan))
		.filter(SupportInvoice.user_id == int(user_id))
		.order_by(SupportInvoice.id.desc())
	)
	total = q.count()
	items = q.offset(max(0, offset)).limit(min(100, max(1, limit))).all()
	return {"items": [_serialize_invoice(i) for i in items], "total": total}


def get_user_invoice(db: Session, user_id: int, invoice_id: int) -> Dict[str, Any]:
	inv = (
		db.query(SupportInvoice)
		.options(joinedload(SupportInvoice.plan))
		.filter(SupportInvoice.id == int(invoice_id), SupportInvoice.user_id == int(user_id))
		.first()
	)
	if not inv:
		raise ApiError("INVOICE_NOT_FOUND", "صورت‌حساب یافت نشد", http_status=404)
	return _serialize_invoice(inv)


def get_user_subscription(db: Session, user_id: int) -> Optional[Dict[str, Any]]:
	from app.services.support.support_entitlement_service import get_active_or_grace_subscription

	sub = get_active_or_grace_subscription(db, user_id)
	if not sub:
		return None
	from app.services.support.support_entitlement_service import _serialize_subscription

	return _serialize_subscription(sub)


def admin_list_invoices(
	db: Session,
	*,
	status: Optional[str] = None,
	user_id: Optional[int] = None,
	search: Optional[str] = None,
	limit: int = 50,
	offset: int = 0,
) -> Dict[str, Any]:
	q = db.query(SupportInvoice).options(joinedload(SupportInvoice.plan))
	if status:
		q = q.filter(SupportInvoice.status == status)
	if user_id:
		q = q.filter(SupportInvoice.user_id == int(user_id))
	if search:
		like = f"%{search.strip()}%"
		q = q.filter(SupportInvoice.code.ilike(like))
	total = q.count()
	items = q.order_by(SupportInvoice.id.desc()).offset(max(0, offset)).limit(min(200, max(1, limit))).all()
	return {"items": [_serialize_invoice(i) for i in items], "total": total}


def admin_void_invoice(db: Session, invoice_id: int) -> Dict[str, Any]:
	inv = db.query(SupportInvoice).filter(SupportInvoice.id == int(invoice_id)).first()
	if not inv:
		raise ApiError("INVOICE_NOT_FOUND", "صورت‌حساب یافت نشد", http_status=404)
	if inv.status == "paid":
		raise ApiError("CANNOT_VOID_PAID", "صورت‌حساب پرداخت‌شده قابل ابطال نیست", http_status=400)
	inv.status = "void"
	inv.updated_at = datetime.utcnow()
	db.commit()
	return _serialize_invoice(inv)


def refresh_subscription_statuses(db: Session) -> int:
	"""به‌روزرسانی active→grace→expired."""
	now = datetime.utcnow()
	changed = 0
	actives = (
		db.query(SupportSubscription)
		.filter(SupportSubscription.status == "active", SupportSubscription.ends_at.isnot(None))
		.all()
	)
	for sub in actives:
		if sub.ends_at and sub.ends_at < now:
			grace_end = sub.grace_ends_at
			if grace_end and grace_end >= now:
				sub.status = "grace"
			else:
				sub.status = "expired"
			sub.updated_at = now
			changed += 1

	graces = db.query(SupportSubscription).filter(SupportSubscription.status == "grace").all()
	for sub in graces:
		if sub.grace_ends_at and sub.grace_ends_at < now:
			sub.status = "expired"
			sub.updated_at = now
			changed += 1
		elif not sub.grace_ends_at and sub.ends_at and sub.ends_at < now:
			sub.status = "expired"
			sub.updated_at = now
			changed += 1

	# منقضی کردن نشست‌های باز
	sessions = (
		db.query(SupportPaymentSession)
		.filter(
			SupportPaymentSession.status.in_(("created", "redirected")),
			SupportPaymentSession.expires_at < now,
		)
		.all()
	)
	for s in sessions:
		s.status = "expired"
		s.updated_at = now
		inv = db.query(SupportInvoice).filter(SupportInvoice.id == s.invoice_id).first()
		if inv and inv.status == "awaiting_payment":
			inv.status = "expired"
		changed += 1

	if changed:
		db.commit()
	return changed
