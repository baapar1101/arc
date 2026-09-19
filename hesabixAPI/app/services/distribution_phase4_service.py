"""فاز ۴ افزونه پخش مویرگی: هدف فروش، تسویه روزانه، خروجی چاپ."""

from __future__ import annotations

import calendar
import logging
from datetime import date, datetime
from decimal import Decimal
from typing import Any, Dict, List, Optional, Tuple

from fastapi import Request
from fastapi.responses import Response
from sqlalchemy import func
from sqlalchemy.orm import Session

from adapters.db.models.distribution import (
	DistributionDailySettlement,
	DistributionFieldVisit,
	DistributionSalesTarget,
	DistributionVan,
)
from adapters.db.models.business import Business
from app.core.auth_dependency import AuthContext
from app.core.business_calendar import business_today
from app.core.datetime_utils import export_filename_timestamp, format_generated_at_for_pdf, resolve_calendar_type_for_request
from app.core.i18n import negotiate_locale
from app.core.responses import ApiError
from app.services import distribution_service as dist_svc
from app.services.distribution_documents import document_net_amount, person_label, user_label
from app.services.list_report_export_service import ListReportColumn, list_pdf_response
from app.services.pdf.template_renderer import load_farsi_font_data_uris

logger = logging.getLogger(__name__)


def _is_fa(request: Request) -> bool:
	return negotiate_locale(request.headers.get("Accept-Language")) == "fa"


def _generated_at(request: Request, business_id: int) -> str:
	return format_generated_at_for_pdf(business_id, resolve_calendar_type_for_request(request))


def _money(v: Any) -> float:
	try:
		return float(Decimal(str(v or 0)))
	except Exception:
		return 0.0


def _period_bounds(period_type: str, period_start: date) -> Tuple[date, date]:
	pt = (period_type or "").strip().lower()
	if pt == "day":
		return period_start, period_start
	if pt == "month":
		start = period_start.replace(day=1)
		last = calendar.monthrange(start.year, start.month)[1]
		return start, start.replace(day=last)
	raise ApiError("VALIDATION_ERROR", "period_type must be day|month", http_status=400)


def _normalize_period_start(period_type: str, period_start: date) -> date:
	pt = (period_type or "").strip().lower()
	if pt == "month":
		return period_start.replace(day=1)
	return period_start


def _sales_for_user_range(
	db: Session,
	business_id: int,
	user_id: int,
	from_date: date,
	to_date: date,
) -> Tuple[float, int]:
	rows = (
		db.query(DistributionFieldVisit)
		.filter(
			DistributionFieldVisit.business_id == business_id,
			DistributionFieldVisit.user_id == user_id,
			DistributionFieldVisit.status == "completed",
			func.date(DistributionFieldVisit.started_at) >= from_date,
			func.date(DistributionFieldVisit.started_at) <= to_date,
		)
		.all()
	)
	total = 0.0
	count = 0
	for v in rows:
		if not v.document_id:
			continue
		amt = document_net_amount(db, int(v.document_id))
		if amt is not None:
			total += float(amt)
			count += 1
	return total, count


def target_to_dict(row: DistributionSalesTarget, *, actual: Optional[float] = None, visit_docs: Optional[int] = None) -> Dict[str, Any]:
	start, end = _period_bounds(row.period_type, row.period_start)
	target = _money(row.target_amount)
	out: Dict[str, Any] = {
		"id": row.id,
		"user_id": row.user_id,
		"period_type": row.period_type,
		"period_start": row.period_start.isoformat(),
		"period_end": end.isoformat(),
		"target_amount": target,
		"metric": getattr(row, "metric", None) or "amount",
		"product_id": getattr(row, "product_id", None),
		"target_value": _money(getattr(row, "target_value", None) or target),
		"notes": row.notes,
		"created_at": row.created_at.isoformat() if row.created_at else None,
	}
	if actual is not None:
		out["actual_amount"] = actual
		out["achievement_percent"] = round(100.0 * actual / target, 1) if target > 0 else None
		out["visit_docs_count"] = visit_docs or 0
	return out


def list_sales_targets(
	db: Session,
	business_id: int,
	ctx: AuthContext,
	*,
	user_id: Optional[int] = None,
	period_type: Optional[str] = None,
) -> List[Dict[str, Any]]:
	dist_svc._ensure_plugin(db, business_id)
	q = db.query(DistributionSalesTarget).filter(DistributionSalesTarget.business_id == business_id)
	scope = dist_svc._scope_visit_user_id(ctx, business_id)
	if scope is not None:
		q = q.filter(DistributionSalesTarget.user_id == scope)
	elif user_id:
		q = q.filter(DistributionSalesTarget.user_id == int(user_id))
	if period_type:
		q = q.filter(DistributionSalesTarget.period_type == period_type.strip().lower())
	rows = q.order_by(DistributionSalesTarget.period_start.desc(), DistributionSalesTarget.user_id.asc()).limit(200).all()
	out = []
	for r in rows:
		start, end = _period_bounds(r.period_type, r.period_start)
		actual, docs = _sales_for_user_range(db, business_id, int(r.user_id), start, end)
		d = target_to_dict(r, actual=actual, visit_docs=docs)
		d["user_name"] = user_label(db, r.user_id)
		out.append(d)
	return out


def upsert_sales_target(
	db: Session,
	business_id: int,
	actor_user_id: int,
	payload: Dict[str, Any],
) -> Dict[str, Any]:
	dist_svc._ensure_plugin(db, business_id)
	uid = int(payload.get("user_id") or 0)
	period_type = str(payload.get("period_type") or "").strip().lower()
	if uid <= 0:
		raise ApiError("VALIDATION_ERROR", "user_id required", http_status=400)
	if period_type not in ("day", "month"):
		raise ApiError("VALIDATION_ERROR", "period_type must be day|month", http_status=400)
	ps_raw = payload.get("period_start")
	if not ps_raw:
		raise ApiError("VALIDATION_ERROR", "period_start required", http_status=400)
	period_start = _normalize_period_start(period_type, date.fromisoformat(str(ps_raw)[:10]))
	amount = _money(payload.get("target_amount"))
	if amount <= 0:
		raise ApiError("VALIDATION_ERROR", "target_amount must be positive", http_status=400)
	metric = str(payload.get("metric") or "amount").strip().lower()
	if metric not in ("amount", "visits", "sku_qty", "coverage_pct"):
		raise ApiError("VALIDATION_ERROR", "Invalid metric", http_status=400)
	# برای یکتایی پایدار: بدون SKU مقدار 0 ذخیره می‌شود (نه NULL)
	product_id = int(payload["product_id"]) if payload.get("product_id") else 0
	if metric != "sku_qty":
		product_id = 0
	target_value = _money(payload.get("target_value")) if payload.get("target_value") is not None else amount

	row = (
		db.query(DistributionSalesTarget)
		.filter(
			DistributionSalesTarget.business_id == business_id,
			DistributionSalesTarget.user_id == uid,
			DistributionSalesTarget.period_type == period_type,
			DistributionSalesTarget.period_start == period_start,
			DistributionSalesTarget.metric == metric,
			DistributionSalesTarget.product_id == product_id,
		)
		.first()
	)
	if row:
		row.target_amount = amount
		row.metric = metric
		row.product_id = product_id
		row.target_value = target_value
		row.notes = payload.get("notes")
		row.updated_at = datetime.utcnow()
	else:
		row = DistributionSalesTarget(
			business_id=business_id,
			user_id=uid,
			period_type=period_type,
			period_start=period_start,
			target_amount=amount,
			metric=metric,
			product_id=product_id,
			target_value=target_value,
			notes=payload.get("notes"),
			created_by_user_id=actor_user_id,
		)
		db.add(row)
	db.commit()
	db.refresh(row)
	start, end = _period_bounds(row.period_type, row.period_start)
	actual, docs = _sales_for_user_range(db, business_id, uid, start, end)
	d = target_to_dict(row, actual=actual, visit_docs=docs)
	d["user_name"] = user_label(db, uid)
	return d


def delete_sales_target(db: Session, business_id: int, target_id: int) -> None:
	dist_svc._ensure_plugin(db, business_id)
	row = (
		db.query(DistributionSalesTarget)
		.filter(DistributionSalesTarget.id == target_id, DistributionSalesTarget.business_id == business_id)
		.first()
	)
	if not row:
		raise ApiError("NOT_FOUND", "Target not found", http_status=404)
	db.delete(row)
	db.commit()


def build_day_visit_snapshot(
	db: Session,
	business_id: int,
	user_id: int,
	settlement_date: date,
) -> Tuple[List[Dict[str, Any]], float]:
	start = datetime.combine(settlement_date, datetime.min.time())
	end = datetime.combine(settlement_date, datetime.max.time())
	rows = (
		db.query(DistributionFieldVisit)
		.filter(
			DistributionFieldVisit.business_id == business_id,
			DistributionFieldVisit.user_id == user_id,
			DistributionFieldVisit.started_at >= start,
			DistributionFieldVisit.started_at <= end,
		)
		.order_by(DistributionFieldVisit.started_at.asc())
		.all()
	)
	items: List[Dict[str, Any]] = []
	expected = 0.0
	for v in rows:
		amt = None
		if v.document_id:
			net = document_net_amount(db, int(v.document_id))
			if net is not None:
				amt = float(net)
				if v.status == "completed" and v.outcome == "order":
					expected += amt
		items.append(
			{
				"visit_id": v.id,
				"person_id": v.person_id,
				"person_name": person_label(db, v.person_id),
				"status": v.status,
				"outcome": v.outcome,
				"document_id": v.document_id,
				"amount": amt,
				"started_at": v.started_at.isoformat() if v.started_at else None,
			}
		)
	return items, expected


def settlement_to_dict(row: DistributionDailySettlement, db: Optional[Session] = None) -> Dict[str, Any]:
	collected = (
		_money(row.cash_collected)
		+ _money(row.cheque_collected)
		+ _money(row.card_collected)
		+ _money(row.other_collected)
	)
	d: Dict[str, Any] = {
		"id": row.id,
		"user_id": row.user_id,
		"settlement_date": row.settlement_date.isoformat() if row.settlement_date else None,
		"status": row.status,
		"expected_sales": _money(row.expected_sales),
		"cash_collected": _money(row.cash_collected),
		"cheque_collected": _money(row.cheque_collected),
		"card_collected": _money(row.card_collected),
		"other_collected": _money(row.other_collected),
		"expenses": _money(row.expenses),
		"total_collected": collected,
		"variance": _money(row.variance),
		"visit_snapshot": row.visit_snapshot or [],
		"notes": row.notes,
		"receipt_document_id": row.receipt_document_id,
		"cash_register_id": row.cash_register_id,
		"cheque_refs": getattr(row, "cheque_refs", None) or [],
		"confirmed_at": row.confirmed_at.isoformat() if row.confirmed_at else None,
		"created_at": row.created_at.isoformat() if row.created_at else None,
	}
	if db is not None:
		d["user_name"] = user_label(db, row.user_id)
	return d


def preview_settlement(
	db: Session,
	business_id: int,
	ctx: AuthContext,
	user_id: int,
	settlement_date: date,
) -> Dict[str, Any]:
	dist_svc._ensure_plugin(db, business_id)
	scope = dist_svc._scope_visit_user_id(ctx, business_id)
	if scope is not None and int(scope) != int(user_id):
		raise ApiError("FORBIDDEN", "Cannot preview another visitor settlement", http_status=403)
	snapshot, expected = build_day_visit_snapshot(db, business_id, user_id, settlement_date)
	existing = (
		db.query(DistributionDailySettlement)
		.filter(
			DistributionDailySettlement.business_id == business_id,
			DistributionDailySettlement.user_id == user_id,
			DistributionDailySettlement.settlement_date == settlement_date,
		)
		.first()
	)
	return {
		"user_id": user_id,
		"user_name": user_label(db, user_id),
		"settlement_date": settlement_date.isoformat(),
		"expected_sales": expected,
		"visit_snapshot": snapshot,
		"existing": settlement_to_dict(existing, db) if existing else None,
	}


def _compute_variance(
	expected: float,
	cash: float,
	cheque: float,
	card: float,
	other: float,
	expenses: float,
) -> float:
	collected = cash + cheque + card + other
	return round(collected - expected - expenses, 2)


def upsert_settlement(
	db: Session,
	business_id: int,
	actor_user_id: int,
	ctx: AuthContext,
	payload: Dict[str, Any],
) -> Dict[str, Any]:
	dist_svc._ensure_plugin(db, business_id)
	uid = int(payload.get("user_id") or actor_user_id or 0)
	if uid <= 0:
		raise ApiError("VALIDATION_ERROR", "user_id required", http_status=400)
	scope = dist_svc._scope_visit_user_id(ctx, business_id)
	if scope is not None and int(scope) != uid:
		raise ApiError("FORBIDDEN", "Cannot settle for another visitor", http_status=403)
	sd_raw = payload.get("settlement_date")
	settlement_date = date.fromisoformat(str(sd_raw)[:10]) if sd_raw else business_today(business_id)

	snapshot, expected = build_day_visit_snapshot(db, business_id, uid, settlement_date)
	cash = _money(payload.get("cash_collected"))
	cheque = _money(payload.get("cheque_collected"))
	card = _money(payload.get("card_collected"))
	other = _money(payload.get("other_collected"))
	expenses = _money(payload.get("expenses"))
	# اگر expected از کلاینت نیامده، از snapshot استفاده کن
	if payload.get("expected_sales") is not None:
		expected = _money(payload.get("expected_sales"))
	variance = _compute_variance(expected, cash, cheque, card, other, expenses)

	row = (
		db.query(DistributionDailySettlement)
		.filter(
			DistributionDailySettlement.business_id == business_id,
			DistributionDailySettlement.user_id == uid,
			DistributionDailySettlement.settlement_date == settlement_date,
		)
		.first()
	)
	if row and row.status == "confirmed":
		raise ApiError("VALIDATION_ERROR", "Settlement already confirmed", http_status=400)

	if row:
		row.expected_sales = expected
		row.cash_collected = cash
		row.cheque_collected = cheque
		row.card_collected = card
		row.other_collected = other
		row.expenses = expenses
		row.variance = variance
		row.visit_snapshot = snapshot
		row.notes = payload.get("notes")
		if payload.get("cash_register_id") is not None:
			row.cash_register_id = int(payload["cash_register_id"]) if payload.get("cash_register_id") else None
		row.updated_at = datetime.utcnow()
	else:
		row = DistributionDailySettlement(
			business_id=business_id,
			user_id=uid,
			settlement_date=settlement_date,
			status="draft",
			expected_sales=expected,
			cash_collected=cash,
			cheque_collected=cheque,
			card_collected=card,
			other_collected=other,
			expenses=expenses,
			variance=variance,
			visit_snapshot=snapshot,
			notes=payload.get("notes"),
			cash_register_id=int(payload["cash_register_id"]) if payload.get("cash_register_id") else None,
			created_by_user_id=actor_user_id,
		)
		db.add(row)
	db.commit()
	db.refresh(row)
	return settlement_to_dict(row, db)


def list_settlements(
	db: Session,
	business_id: int,
	ctx: AuthContext,
	*,
	from_date: Optional[date] = None,
	to_date: Optional[date] = None,
	user_id: Optional[int] = None,
) -> List[Dict[str, Any]]:
	dist_svc._ensure_plugin(db, business_id)
	q = db.query(DistributionDailySettlement).filter(DistributionDailySettlement.business_id == business_id)
	scope = dist_svc._scope_visit_user_id(ctx, business_id)
	if scope is not None:
		q = q.filter(DistributionDailySettlement.user_id == scope)
	elif user_id:
		q = q.filter(DistributionDailySettlement.user_id == int(user_id))
	if from_date:
		q = q.filter(DistributionDailySettlement.settlement_date >= from_date)
	if to_date:
		q = q.filter(DistributionDailySettlement.settlement_date <= to_date)
	rows = q.order_by(DistributionDailySettlement.settlement_date.desc()).limit(200).all()
	return [settlement_to_dict(r, db) for r in rows]


def confirm_settlement(
	db: Session,
	business_id: int,
	actor_user_id: int,
	ctx: AuthContext,
	settlement_id: int,
	payload: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
	dist_svc._ensure_plugin(db, business_id)
	payload = payload or {}
	row = (
		db.query(DistributionDailySettlement)
		.filter(
			DistributionDailySettlement.id == settlement_id,
			DistributionDailySettlement.business_id == business_id,
		)
		.first()
	)
	if not row:
		raise ApiError("NOT_FOUND", "Settlement not found", http_status=404)
	scope = dist_svc._scope_visit_user_id(ctx, business_id)
	can_manage = dist_svc._can_see_full_distribution_catalog(ctx, business_id) or ctx.has_business_permission(
		"distribution", "manage"
	)
	can_settle = can_manage or ctx.has_business_permission("distribution", "settle")
	if scope is not None and int(row.user_id) != int(scope) and not can_manage:
		raise ApiError("FORBIDDEN", "Cannot confirm this settlement", http_status=403)
	if row.status == "confirmed":
		return settlement_to_dict(row, db)

	# تأیید نهایی: manage یا settle (اپراتور عادی فقط پیش‌نویس می‌سازد)
	if not can_settle:
		raise ApiError(
			"FORBIDDEN",
			"Confirming settlement requires distribution.manage or distribution.settle",
			http_status=403,
		)

	# تازه‌سازی snapshot قبل از تأیید
	snapshot, expected = build_day_visit_snapshot(db, business_id, int(row.user_id), row.settlement_date)
	row.visit_snapshot = snapshot
	row.expected_sales = expected
	row.variance = _compute_variance(
		expected,
		_money(row.cash_collected),
		_money(row.cheque_collected),
		_money(row.card_collected),
		_money(row.other_collected),
		_money(row.expenses),
	)

	allow_variance = bool(payload.get("allow_variance"))
	if abs(_money(row.variance)) >= 0.01:
		if not allow_variance:
			raise ApiError(
				"SETTLEMENT_VARIANCE",
				"Settlement variance must be zero or allow_variance with manage permission",
				http_status=400,
				details={"variance": _money(row.variance)},
			)
		if not can_manage:
			raise ApiError("FORBIDDEN", "allow_variance requires distribution.manage", http_status=403)

	create_receipt = bool(payload.get("create_receipt"))
	cash_register_id = payload.get("cash_register_id") or row.cash_register_id
	bank_id = payload.get("bank_id")
	cash_amt = _money(row.cash_collected)
	card_amt = _money(row.card_collected)
	cheque_amt = _money(row.cheque_collected)
	if create_receipt and (cash_amt > 0 or card_amt > 0):
		if cash_amt > 0 and not cash_register_id:
			raise ApiError("VALIDATION_ERROR", "cash_register_id required for cash receipt", http_status=400)
		if card_amt > 0 and not bank_id:
			raise ApiError("VALIDATION_ERROR", "bank_id required for card receipt", http_status=400)
		receipt_id = _create_settlement_receipts(
			db,
			business_id,
			actor_user_id,
			row,
			cash_register_id=int(cash_register_id) if cash_register_id else None,
			bank_id=int(bank_id) if bank_id else None,
			allocations=payload.get("invoice_allocations"),
		)
		if receipt_id:
			row.receipt_document_id = receipt_id
		if cash_register_id:
			row.cash_register_id = int(cash_register_id)

	# ثبت چک‌های دریافتی از فیلد cheque_items
	cheque_items = payload.get("cheque_items") if isinstance(payload.get("cheque_items"), list) else []
	if create_receipt and cheque_amt > 0 and cheque_items:
		refs = _create_settlement_cheques(
			db,
			business_id,
			actor_user_id,
			row,
			cheque_items,
		)
		row.cheque_refs = refs
	elif create_receipt and cheque_amt > 0 and not cheque_items:
		raise ApiError(
			"VALIDATION_ERROR",
			"cheque_items required when create_receipt and cheque_collected > 0",
			http_status=400,
		)

	row.status = "confirmed"
	row.confirmed_by_user_id = actor_user_id
	row.confirmed_at = datetime.utcnow()
	row.updated_at = datetime.utcnow()
	db.commit()
	db.refresh(row)
	return settlement_to_dict(row, db)


def _create_settlement_cheques(
	db: Session,
	business_id: int,
	user_id: int,
	row: DistributionDailySettlement,
	cheque_items: List[Dict[str, Any]],
) -> List[Dict[str, Any]]:
	"""ایجاد چک دریافتی برای هر قلم cheque_items و برگرداندن refs."""
	from adapters.db.models.business import Business
	from app.services.check_service import create_check

	business = db.query(Business).filter(Business.id == business_id).first()
	if not business or not business.default_currency_id:
		raise ApiError("VALIDATION_ERROR", "Business default currency required", http_status=400)

	refs: List[Dict[str, Any]] = []
	sum_amt = 0.0
	for item in cheque_items:
		if not isinstance(item, dict):
			continue
		pid = int(item.get("person_id") or 0)
		amt = _money(item.get("amount"))
		check_number = str(item.get("check_number") or "").strip()
		if pid <= 0 or amt <= 0 or not check_number:
			raise ApiError(
				"VALIDATION_ERROR",
				"Each cheque item needs person_id, amount, check_number",
				http_status=400,
			)
		issue = str(item.get("issue_date") or row.settlement_date.isoformat())[:10]
		due = str(item.get("due_date") or issue)[:10]
		payload = {
			"type": "received",
			"person_id": pid,
			"issue_date": issue,
			"due_date": due,
			"check_number": check_number,
			"amount": amt,
			"currency_id": int(business.default_currency_id),
			"bank_name": item.get("bank_name"),
			"branch_name": item.get("branch_name"),
			"sayad_code": item.get("sayad_code"),
			"document_date": row.settlement_date.isoformat(),
			"document_description": f"چک تسویه پخش — کاربر {row.user_id} — {row.settlement_date.isoformat()}",
			"extra_info": {
				"distribution_settlement_id": row.id,
				"source": "distribution_daily_settlement",
				"invoice_id": item.get("invoice_id") or item.get("document_id"),
			},
		}
		with db.begin_nested():
			created = create_check(db, business_id, user_id, payload, commit=False)
		refs.append({
			"check_id": created.get("id"),
			"document_id": created.get("document_id"),
			"person_id": pid,
			"amount": amt,
			"check_number": check_number,
		})
		sum_amt = round(sum_amt + amt, 2)

	expected = _money(row.cheque_collected)
	if abs(sum_amt - expected) >= 0.02:
		raise ApiError(
			"VALIDATION_ERROR",
			f"cheque_items total {sum_amt} != cheque_collected {expected}",
			http_status=400,
		)
	return refs


def _build_allocation_person_lines(
	row: DistributionDailySettlement,
	total_to_allocate: float,
	allocations: Optional[List[Dict[str, Any]]] = None,
) -> List[Dict[str, Any]]:
	"""تخصیص وصول به فاکتور/شخص از snapshot یا از allocations صریح."""
	if total_to_allocate <= 0:
		return []
	if allocations:
		lines = []
		for a in allocations:
			if not isinstance(a, dict):
				continue
			pid = int(a.get("person_id") or 0)
			amt = _money(a.get("amount"))
			if pid <= 0 or amt <= 0:
				continue
			pl: Dict[str, Any] = {
				"person_id": pid,
				"amount": amt,
				"description": a.get("description") or "وصول تسویه پخش",
			}
			inv = a.get("invoice_id") or a.get("document_id")
			if inv:
				pl["extra_info"] = {"invoice_id": int(inv), "link_to_invoice": True}
			lines.append(pl)
		return lines

	# از snapshot: فقط ویزیت‌های سفارش با document
	candidates: List[Dict[str, Any]] = []
	for it in row.visit_snapshot or []:
		if not isinstance(it, dict):
			continue
		if it.get("status") != "completed" or it.get("outcome") != "order":
			continue
		if not it.get("person_id") or not it.get("document_id"):
			continue
		amt = _money(it.get("amount"))
		if amt <= 0:
			continue
		candidates.append(
			{
				"person_id": int(it["person_id"]),
				"invoice_id": int(it["document_id"]),
				"amount": amt,
				"person_name": it.get("person_name"),
			}
		)
	if not candidates:
		return []

	sum_amt = sum(c["amount"] for c in candidates)
	remaining = total_to_allocate
	lines = []
	for i, c in enumerate(candidates):
		if remaining <= 0:
			break
		if i == len(candidates) - 1:
			share = remaining
		else:
			share = min(c["amount"], _money(total_to_allocate * (c["amount"] / sum_amt)) if sum_amt > 0 else 0)
			share = min(share, remaining)
		share = round(share, 2)
		if share <= 0:
			continue
		remaining = round(remaining - share, 2)
		lines.append(
			{
				"person_id": c["person_id"],
				"amount": share,
				"description": f"وصول تسویه — {c.get('person_name') or c['person_id']}",
				"extra_info": {"invoice_id": c["invoice_id"], "link_to_invoice": True},
			}
		)
	# اگر هنوز مانده (بدون فاکتور کافی)، به آخرین شخص بده بدون لینک فاکتور
	if remaining >= 0.01 and lines:
		lines[-1]["amount"] = round(_money(lines[-1]["amount"]) + remaining, 2)
	elif remaining >= 0.01 and candidates:
		c0 = candidates[0]
		lines.append(
			{
				"person_id": c0["person_id"],
				"amount": remaining,
				"description": "وصول تسویه پخش (مانده)",
				"extra_info": {"invoice_id": c0["invoice_id"], "link_to_invoice": True},
			}
		)
	return lines


def _create_settlement_receipts(
	db: Session,
	business_id: int,
	user_id: int,
	row: DistributionDailySettlement,
	*,
	cash_register_id: Optional[int],
	bank_id: Optional[int],
	allocations: Optional[List[Dict[str, Any]]] = None,
) -> Optional[int]:
	"""ایجاد رسید(ها) نقد/کارت با تخصیص به فاکتورها. اولین id رسید را برمی‌گرداند."""
	from app.services.receipt_payment_service import create_receipt_payment

	business = db.query(Business).filter(Business.id == business_id).first()
	if not business or not business.default_currency_id:
		raise ApiError("VALIDATION_ERROR", "Business default currency required", http_status=400)

	cash_amt = _money(row.cash_collected)
	card_amt = _money(row.card_collected)
	first_id: Optional[int] = None

	def _post(person_lines: List[Dict[str, Any]], account_lines: List[Dict[str, Any]], label: str) -> Optional[int]:
		nonlocal first_id
		if not person_lines or not account_lines:
			return None
		pl_sum = round(sum(_money(p.get("amount")) for p in person_lines), 2)
		ac_sum = round(sum(_money(a.get("amount")) for a in account_lines), 2)
		if abs(pl_sum - ac_sum) >= 0.02:
			raise ApiError(
				"VALIDATION_ERROR",
				f"receipt imbalance person={pl_sum} account={ac_sum}",
				http_status=400,
			)
		payload: Dict[str, Any] = {
			"document_type": "receipt",
			"document_date": row.settlement_date.isoformat(),
			"currency_id": int(business.default_currency_id),
			"description": f"تسویه روزانه پخش ({label}) — کاربر {row.user_id} — {row.settlement_date.isoformat()}",
			"person_lines": person_lines,
			"account_lines": account_lines,
			"extra_info": {
				"distribution_settlement_id": row.id,
				"source": "distribution_daily_settlement",
				"channel": label,
			},
		}
		with db.begin_nested():
			result = create_receipt_payment(db, business_id, user_id, payload, commit=False)
		rid = int(result["id"]) if isinstance(result, dict) and result.get("id") else None
		if rid and first_id is None:
			first_id = rid
		return rid

	if cash_amt > 0 and cash_register_id:
		person_lines = _build_allocation_person_lines(row, cash_amt, allocations)
		if not person_lines:
			raise ApiError(
				"VALIDATION_ERROR",
				"No invoice/person available to allocate cash receipt",
				http_status=400,
			)
		_post(
			person_lines,
			[
				{
					"amount": cash_amt,
					"transaction_type": "cash_register",
					"cash_register_id": int(cash_register_id),
					"description": "واریز صندوق از تسویه پخش",
				}
			],
			"cash",
		)

	if card_amt > 0 and bank_id:
		# تخصیص کارت جدا: اگر allocations داده شده، فقط برای نقد بود؛ برای کارت نسبت به snapshot دوباره بساز
		person_lines = _build_allocation_person_lines(row, card_amt, None)
		if not person_lines:
			raise ApiError(
				"VALIDATION_ERROR",
				"No invoice/person available to allocate card receipt",
				http_status=400,
			)
		_post(
			person_lines,
			[
				{
					"amount": card_amt,
					"transaction_type": "bank",
					"bank_id": int(bank_id),
					"description": "واریز بانک (کارت) از تسویه پخش",
				}
			],
			"card",
		)

	# چک: از طریق create_check در _create_settlement_cheques ساخته می‌شود
	return first_id


def _try_create_settlement_receipt(
	db: Session,
	business_id: int,
	user_id: int,
	row: DistributionDailySettlement,
	cash_register_id: int,
	cash_amount: float,
) -> Optional[int]:
	"""سازگاری عقب‌رو."""
	row.cash_collected = cash_amount
	return _create_settlement_receipts(
		db,
		business_id,
		user_id,
		row,
		cash_register_id=cash_register_id,
		bank_id=None,
		allocations=None,
	)


def export_daily_plan_pdf(
	db: Session,
	request: Request,
	business_id: int,
	user_id: int,
	plan_date: date,
) -> Response:
	dist_svc._ensure_plugin(db, business_id)
	plan = dist_svc.get_daily_plan(db, business_id, user_id, plan_date)
	items = []
	for it in plan.get("items") or []:
		items.append(
			{
				"sort_order": it.get("sort_order"),
				"route_code": it.get("route_code"),
				"route_name": it.get("route_name"),
				"person_name": it.get("person_name"),
				"person_id": it.get("person_id"),
				"weekday": it.get("weekday"),
			}
		)
	is_fa = _is_fa(request)
	uname = user_label(db, user_id) or str(user_id)
	title = (
		f"برنامه روز پخش — {uname} — {plan_date.isoformat()}"
		if is_fa
		else f"Distribution daily plan — {uname} — {plan_date.isoformat()}"
	)
	columns = [
		ListReportColumn("sort_order", "ترتیب", "Order", "number"),
		ListReportColumn("route_code", "کد مسیر", "Route code"),
		ListReportColumn("route_name", "مسیر", "Route"),
		ListReportColumn("person_name", "مشتری", "Customer"),
		ListReportColumn("person_id", "شناسه", "ID", "number"),
	]
	return list_pdf_response(
		items,
		columns,
		db=db,
		business_id=business_id,
		filename_prefix="distribution_daily_plan",
		is_fa=is_fa,
		title=title,
		generated_at=_generated_at(request, business_id),
		summary={
			("ویزیتور" if is_fa else "Visitor"): uname,
			("تعداد توقف" if is_fa else "Stops"): len(items),
		},
		export_filename_timestamp=export_filename_timestamp,
		load_farsi_font_data_uris=load_farsi_font_data_uris,
	)


def export_van_loading_list_pdf(
	db: Session,
	request: Request,
	business_id: int,
	van_id: int,
) -> Response:
	from app.services.distribution_phase3_service import get_van_stock

	dist_svc._ensure_plugin(db, business_id)
	van = db.query(DistributionVan).filter(DistributionVan.id == van_id, DistributionVan.business_id == business_id).first()
	if not van:
		raise ApiError("NOT_FOUND", "Van not found", http_status=404)
	stock = get_van_stock(db, business_id, van_id)
	items = []
	for it in stock.get("items") or []:
		items.append(
			{
				"product_id": it.get("product_id"),
				"product_name": it.get("product_name"),
				"quantity": it.get("quantity"),
			}
		)
	is_fa = _is_fa(request)
	title = (
		f"لیست بارگیری ون — {van.code} {van.name}"
		if is_fa
		else f"Van loading list — {van.code} {van.name}"
	)
	columns = [
		ListReportColumn("product_id", "کد کالا", "Product ID", "number"),
		ListReportColumn("product_name", "نام کالا", "Product"),
		ListReportColumn("quantity", "موجودی", "Qty", "number"),
	]
	return list_pdf_response(
		items,
		columns,
		db=db,
		business_id=business_id,
		filename_prefix="distribution_van_loading",
		is_fa=is_fa,
		title=title,
		generated_at=_generated_at(request, business_id),
		summary={
			("ون" if is_fa else "Van"): f"{van.code} — {van.name}",
			("تعداد قلم" if is_fa else "SKUs"): len(items),
		},
		export_filename_timestamp=export_filename_timestamp,
		load_farsi_font_data_uris=load_farsi_font_data_uris,
	)


def export_settlement_pdf(
	db: Session,
	request: Request,
	business_id: int,
	settlement_id: int,
) -> Response:
	dist_svc._ensure_plugin(db, business_id)
	row = (
		db.query(DistributionDailySettlement)
		.filter(
			DistributionDailySettlement.id == settlement_id,
			DistributionDailySettlement.business_id == business_id,
		)
		.first()
	)
	if not row:
		raise ApiError("NOT_FOUND", "Settlement not found", http_status=404)
	is_fa = _is_fa(request)
	items = []
	for it in row.visit_snapshot or []:
		if not isinstance(it, dict):
			continue
		items.append(
			{
				"visit_id": it.get("visit_id"),
				"person_name": it.get("person_name"),
				"status": it.get("status"),
				"outcome": it.get("outcome"),
				"document_id": it.get("document_id"),
				"amount": it.get("amount"),
			}
		)
	uname = user_label(db, row.user_id) or str(row.user_id)
	title = (
		f"تسویه روزانه — {uname} — {row.settlement_date.isoformat()}"
		if is_fa
		else f"Daily settlement — {uname} — {row.settlement_date.isoformat()}"
	)
	columns = [
		ListReportColumn("visit_id", "ویزیت", "Visit", "number"),
		ListReportColumn("person_name", "مشتری", "Customer"),
		ListReportColumn("status", "وضعیت", "Status"),
		ListReportColumn("outcome", "نتیجه", "Outcome"),
		ListReportColumn("document_id", "سند", "Doc", "number"),
		ListReportColumn("amount", "مبلغ", "Amount", "number"),
	]
	return list_pdf_response(
		items,
		columns,
		db=db,
		business_id=business_id,
		filename_prefix="distribution_settlement",
		is_fa=is_fa,
		title=title,
		generated_at=_generated_at(request, business_id),
		summary={
			("وضعیت" if is_fa else "Status"): row.status,
			("فروش مورد انتظار" if is_fa else "Expected"): _money(row.expected_sales),
			("نقد" if is_fa else "Cash"): _money(row.cash_collected),
			("چک" if is_fa else "Cheque"): _money(row.cheque_collected),
			("کارت" if is_fa else "Card"): _money(row.card_collected),
			("سایر" if is_fa else "Other"): _money(row.other_collected),
			("هزینه" if is_fa else "Expenses"): _money(row.expenses),
			("مغایرت" if is_fa else "Variance"): _money(row.variance),
		},
		export_filename_timestamp=export_filename_timestamp,
		load_farsi_font_data_uris=load_farsi_font_data_uris,
	)
