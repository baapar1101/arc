"""محاسبه entitlement دسترسی کاربر به تیکت‌های پشتیبانی."""

from __future__ import annotations

from datetime import datetime
from typing import Any, Dict, Optional

from sqlalchemy.orm import Session, joinedload

from adapters.db.models.support.billing import SupportSubscription, SupportUsageCounter
from adapters.db.models.support.ticket import Ticket
from app.core.responses import ApiError
from app.services.support.support_billing_settings import (
	get_support_allow_read_without_subscription,
	get_support_billing_mode,
	get_support_free_quota_per_month,
	get_support_require_subscription_to_reply,
)
from app.services.system_settings_service import (
	assert_end_user_support_tickets_allowed,
	is_support_tickets_enabled_for_users,
)


def current_period_key(now: Optional[datetime] = None) -> str:
	dt = now or datetime.utcnow()
	return f"{dt.year:04d}-{dt.month:02d}"


def _serialize_subscription(sub: Optional[SupportSubscription]) -> Optional[Dict[str, Any]]:
	if not sub:
		return None
	plan = sub.plan
	return {
		"id": sub.id,
		"status": sub.status,
		"starts_at": sub.starts_at.isoformat() if sub.starts_at else None,
		"ends_at": sub.ends_at.isoformat() if sub.ends_at else None,
		"grace_ends_at": sub.grace_ends_at.isoformat() if sub.grace_ends_at else None,
		"plan": (
			{
				"id": plan.id,
				"name": plan.name,
				"code": plan.code,
				"period_months": plan.period_months,
				"max_open_tickets": plan.max_open_tickets,
				"includes_priority_support": bool(plan.includes_priority_support),
				"priority_weight": int(plan.priority_weight or 0),
				"sla_policy_id": plan.sla_policy_id,
			}
			if plan
			else None
		),
	}


def get_active_or_grace_subscription(db: Session, user_id: int) -> Optional[SupportSubscription]:
	return (
		db.query(SupportSubscription)
		.options(joinedload(SupportSubscription.plan))
		.filter(
			SupportSubscription.user_id == int(user_id),
			SupportSubscription.status.in_(("active", "grace")),
		)
		.order_by(SupportSubscription.ends_at.desc().nullslast(), SupportSubscription.id.desc())
		.first()
	)


def get_usage_counter(db: Session, user_id: int, period_key: Optional[str] = None) -> SupportUsageCounter:
	key = period_key or current_period_key()
	row = (
		db.query(SupportUsageCounter)
		.filter(
			SupportUsageCounter.user_id == int(user_id),
			SupportUsageCounter.period_key == key,
		)
		.first()
	)
	if row:
		return row
	row = SupportUsageCounter(
		user_id=int(user_id),
		period_key=key,
		tickets_created=0,
		updated_at=datetime.utcnow(),
	)
	db.add(row)
	db.flush()
	return row


def count_open_tickets(db: Session, user_id: int) -> int:
	from adapters.db.models.support.status import Status

	final_ids = [r.id for r in db.query(Status.id).filter(Status.is_final.is_(True)).all()]
	q = db.query(Ticket).filter(Ticket.user_id == int(user_id))
	if final_ids:
		q = q.filter(~Ticket.status_id.in_(final_ids))
	else:
		q = q.filter(Ticket.closed_at.is_(None))
	return int(q.count())

def get_support_entitlement(db: Session, user_id: int) -> Dict[str, Any]:
	enabled = is_support_tickets_enabled_for_users(db)
	mode = get_support_billing_mode(db)
	allow_read = get_support_allow_read_without_subscription(db)
	require_reply_sub = get_support_require_subscription_to_reply(db)
	sub = get_active_or_grace_subscription(db, user_id) if enabled else None
	has_active = bool(sub and sub.status == "active")
	has_grace = bool(sub and sub.status == "grace")

	quota_limit = get_support_free_quota_per_month(db) if mode == "hybrid" else None
	period_key = current_period_key()
	quota_used = 0
	if mode == "hybrid" and enabled:
		counter = get_usage_counter(db, user_id, period_key)
		quota_used = int(counter.tickets_created or 0)

	can_create = False
	can_reply = False
	can_read = False
	reason = "ok"
	upsell = False

	if not enabled:
		reason = "billing_disabled"
		can_read = False
	elif mode == "free":
		can_create = True
		can_reply = True
		can_read = True
	elif has_active:
		can_create = True
		can_reply = True
		can_read = True
		# سقف تیکت باز
		if sub and sub.plan and sub.plan.max_open_tickets:
			open_count = count_open_tickets(db, user_id)
			if open_count >= int(sub.plan.max_open_tickets):
				can_create = False
				reason = "max_open_tickets"
	elif mode == "paid":
		can_read = allow_read
		if has_grace:
			can_reply = True
			can_create = False
			reason = "grace_reply_only"
			upsell = True
		else:
			can_reply = False if require_reply_sub else allow_read
			can_create = False
			reason = "no_subscription"
			upsell = True
	elif mode == "hybrid":
		can_read = True
		if has_grace:
			can_reply = True
			can_create = False
			reason = "grace_reply_only"
			upsell = True
		else:
			remaining = max(0, int(quota_limit or 0) - quota_used)
			if remaining > 0:
				can_create = True
				can_reply = True
			else:
				can_create = False
				can_reply = False if require_reply_sub else True
				reason = "quota_exceeded"
				upsell = True
	else:
		can_create = True
		can_reply = True
		can_read = True

	return {
		"tickets_enabled": enabled,
		"mode": mode,
		"can_create_ticket": can_create,
		"can_reply": can_reply,
		"can_read": can_read,
		"reason_code": reason,
		"upsell_required": upsell,
		"subscription": _serialize_subscription(sub),
		"quota": (
			{
				"used": quota_used,
				"limit": int(quota_limit or 0),
				"period_key": period_key,
				"remaining": max(0, int(quota_limit or 0) - quota_used),
			}
			if mode == "hybrid"
			else None
		),
	}


def assert_can_create_ticket(db: Session, user_id: int) -> Dict[str, Any]:
	assert_end_user_support_tickets_allowed(db)
	ent = get_support_entitlement(db, user_id)
	if not ent["can_create_ticket"]:
		raise ApiError(
			"SUPPORT_ENTITLEMENT_DENIED",
			_message_for_reason(ent["reason_code"]),
			http_status=403,
			details=ent,
		)
	return ent


def assert_can_reply_ticket(db: Session, user_id: int) -> Dict[str, Any]:
	assert_end_user_support_tickets_allowed(db)
	ent = get_support_entitlement(db, user_id)
	if not ent["can_reply"]:
		raise ApiError(
			"SUPPORT_ENTITLEMENT_DENIED",
			_message_for_reason(ent["reason_code"]),
			http_status=403,
			details=ent,
		)
	return ent


def increment_hybrid_quota_if_needed(db: Session, user_id: int, entitlement: Optional[Dict[str, Any]] = None) -> None:
	"""فقط وقتی ایجاد از سهمیه hybrid بوده (نه اشتراک فعال)."""
	ent = entitlement or get_support_entitlement(db, user_id)
	if ent.get("mode") != "hybrid":
		return
	sub = ent.get("subscription") or {}
	if sub.get("status") == "active":
		return
	counter = get_usage_counter(db, user_id)
	counter.tickets_created = int(counter.tickets_created or 0) + 1
	counter.updated_at = datetime.utcnow()
	db.flush()


def _message_for_reason(code: str) -> str:
	mapping = {
		"billing_disabled": "سیستم تیکت‌های پشتیبانی غیرفعال است.",
		"no_subscription": "برای ارسال تیکت نیاز به خرید اشتراک پشتیبانی دارید.",
		"quota_exceeded": "سهمیه رایگان ماهانه شما تمام شده است. لطفاً اشتراک پشتیبانی تهیه کنید.",
		"grace_reply_only": "اشتراک شما منقضی شده است. در مهلت ارفاق فقط پاسخ به تیکت‌های باز مجاز است.",
		"max_open_tickets": "سقف تعداد تیکت‌های باز پلن شما پر شده است.",
	}
	return mapping.get(code, "دسترسی به پشتیبانی مجاز نیست.")
