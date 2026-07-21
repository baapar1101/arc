"""CRUD پلن‌های پشتیبانی."""

from __future__ import annotations

from datetime import datetime
from typing import Any, Dict, List, Optional

from sqlalchemy.orm import Session

from adapters.db.models.currency import Currency
from adapters.db.models.support.billing import ALLOWED_PERIOD_MONTHS, SupportPlan, SupportSubscription
from app.core.responses import ApiError


def _serialize_plan(plan: SupportPlan) -> Dict[str, Any]:
	return {
		"id": plan.id,
		"name": plan.name,
		"code": plan.code,
		"period_months": plan.period_months,
		"price": float(plan.price or 0),
		"currency_id": plan.currency_id,
		"currency_code": getattr(plan.currency, "code", None) if plan.currency else None,
		"is_free": bool(plan.is_free),
		"is_active": bool(plan.is_active),
		"sort_order": int(plan.sort_order or 0),
		"description": plan.description,
		"features_json": plan.features_json,
		"max_open_tickets": plan.max_open_tickets,
		"sla_policy_id": plan.sla_policy_id,
		"priority_weight": int(plan.priority_weight or 0),
		"includes_priority_support": bool(plan.includes_priority_support),
		"trial_days": int(plan.trial_days or 0),
		"created_at": plan.created_at.isoformat() if plan.created_at else None,
		"updated_at": plan.updated_at.isoformat() if plan.updated_at else None,
	}


def _validate_period_months(value: Any) -> int:
	try:
		months = int(value)
	except (TypeError, ValueError):
		raise ApiError("VALIDATION_ERROR", "مدت پلن نامعتبر است", http_status=422)
	if months not in ALLOWED_PERIOD_MONTHS:
		raise ApiError(
			"VALIDATION_ERROR",
			"مدت پلن باید یکی از ۱، ۳، ۶ یا ۱۲ ماه باشد",
			http_status=422,
		)
	return months


def _resolve_currency_id(db: Session, payload: Dict[str, Any]) -> int:
	try:
		currency_id = int(payload.get("currency_id") or 0)
	except (TypeError, ValueError):
		currency_id = 0
	if currency_id <= 0:
		cur = db.query(Currency).filter(Currency.code == "IRR").first()
		if not cur:
			raise ApiError("CURRENCY_NOT_FOUND", "ارز پایه یافت نشد", http_status=400)
		return int(cur.id)
	currency = db.query(Currency).filter(Currency.id == currency_id).first()
	if not currency:
		raise ApiError("CURRENCY_NOT_FOUND", "ارز یافت نشد", http_status=404)
	return int(currency.id)


def create_support_plan(db: Session, payload: Dict[str, Any]) -> Dict[str, Any]:
	name = str(payload.get("name") or "").strip()
	if not name:
		raise ApiError("VALIDATION_ERROR", "نام پلن الزامی است", http_status=422)

	code = str(payload.get("code") or "").strip()
	if not code:
		raise ApiError("VALIDATION_ERROR", "کد پلن الزامی است", http_status=422)
	existing = db.query(SupportPlan).filter(SupportPlan.code == code).first()
	if existing:
		raise ApiError("DUPLICATE_CODE", "پلن با این کد قبلاً ایجاد شده است", http_status=400)

	period_months = _validate_period_months(payload.get("period_months"))
	currency_id = _resolve_currency_id(db, payload)

	try:
		price = float(payload.get("price") or 0)
	except (TypeError, ValueError):
		price = 0.0
	if price < 0:
		raise ApiError("VALIDATION_ERROR", "قیمت نمی‌تواند منفی باشد", http_status=422)

	is_free = bool(payload.get("is_free", False))
	if is_free:
		price = 0.0

	max_open = payload.get("max_open_tickets")
	max_open_tickets = None
	if max_open is not None and str(max_open).strip() != "":
		try:
			max_open_tickets = int(max_open)
			if max_open_tickets <= 0:
				max_open_tickets = None
		except (TypeError, ValueError):
			raise ApiError("VALIDATION_ERROR", "سقف تیکت باز نامعتبر است", http_status=422)

	sla_policy_id = None
	if payload.get("sla_policy_id") is not None and str(payload.get("sla_policy_id")).strip() != "":
		try:
			sla_policy_id = int(payload.get("sla_policy_id"))
		except (TypeError, ValueError):
			raise ApiError("VALIDATION_ERROR", "شناسه سیاست SLA نامعتبر است", http_status=422)

	plan = SupportPlan(
		name=name,
		code=code,
		period_months=period_months,
		price=price,
		currency_id=currency_id,
		is_free=is_free,
		is_active=bool(payload.get("is_active", True)),
		sort_order=int(payload.get("sort_order") or 0),
		description=payload.get("description"),
		features_json=payload.get("features_json") if isinstance(payload.get("features_json"), (list, dict)) else None,
		max_open_tickets=max_open_tickets,
		sla_policy_id=sla_policy_id,
		priority_weight=int(payload.get("priority_weight") or 0),
		includes_priority_support=bool(payload.get("includes_priority_support", False)),
		trial_days=max(0, int(payload.get("trial_days") or 0)),
	)
	db.add(plan)
	db.commit()
	db.refresh(plan)
	return _serialize_plan(plan)


def update_support_plan(db: Session, plan_id: int, payload: Dict[str, Any]) -> Dict[str, Any]:
	plan = db.query(SupportPlan).filter(SupportPlan.id == int(plan_id)).first()
	if not plan:
		raise ApiError("PLAN_NOT_FOUND", "پلن یافت نشد", http_status=404)

	if "name" in payload:
		name = str(payload.get("name") or "").strip()
		if not name:
			raise ApiError("VALIDATION_ERROR", "نام پلن الزامی است", http_status=422)
		plan.name = name

	if "code" in payload:
		code = str(payload.get("code") or "").strip()
		if not code:
			raise ApiError("VALIDATION_ERROR", "کد پلن الزامی است", http_status=422)
		dup = (
			db.query(SupportPlan)
			.filter(SupportPlan.code == code, SupportPlan.id != plan.id)
			.first()
		)
		if dup:
			raise ApiError("DUPLICATE_CODE", "پلن با این کد قبلاً ایجاد شده است", http_status=400)
		plan.code = code

	if "period_months" in payload:
		plan.period_months = _validate_period_months(payload.get("period_months"))

	if "currency_id" in payload:
		plan.currency_id = _resolve_currency_id(db, payload)

	if "price" in payload:
		try:
			price = float(payload.get("price") or 0)
		except (TypeError, ValueError):
			raise ApiError("VALIDATION_ERROR", "قیمت نامعتبر است", http_status=422)
		if price < 0:
			raise ApiError("VALIDATION_ERROR", "قیمت نمی‌تواند منفی باشد", http_status=422)
		plan.price = price

	if "is_free" in payload:
		plan.is_free = bool(payload.get("is_free"))
		if plan.is_free:
			plan.price = 0

	if "is_active" in payload:
		plan.is_active = bool(payload.get("is_active"))

	if "sort_order" in payload:
		plan.sort_order = int(payload.get("sort_order") or 0)

	if "description" in payload:
		plan.description = payload.get("description")

	if "features_json" in payload:
		fj = payload.get("features_json")
		plan.features_json = fj if isinstance(fj, (list, dict)) else None

	if "max_open_tickets" in payload:
		max_open = payload.get("max_open_tickets")
		if max_open is None or str(max_open).strip() == "":
			plan.max_open_tickets = None
		else:
			plan.max_open_tickets = int(max_open) if int(max_open) > 0 else None

	if "sla_policy_id" in payload:
		sid = payload.get("sla_policy_id")
		plan.sla_policy_id = int(sid) if sid not in (None, "", 0, "0") else None

	if "priority_weight" in payload:
		plan.priority_weight = int(payload.get("priority_weight") or 0)

	if "includes_priority_support" in payload:
		plan.includes_priority_support = bool(payload.get("includes_priority_support"))

	if "trial_days" in payload:
		plan.trial_days = max(0, int(payload.get("trial_days") or 0))

	plan.updated_at = datetime.utcnow()
	db.commit()
	db.refresh(plan)
	return _serialize_plan(plan)


def get_support_plan(db: Session, plan_id: int) -> Dict[str, Any]:
	plan = db.query(SupportPlan).filter(SupportPlan.id == int(plan_id)).first()
	if not plan:
		raise ApiError("PLAN_NOT_FOUND", "پلن یافت نشد", http_status=404)
	return _serialize_plan(plan)


def list_support_plans(db: Session, *, only_active: Optional[bool] = None) -> List[Dict[str, Any]]:
	q = db.query(SupportPlan)
	if only_active is True:
		q = q.filter(SupportPlan.is_active.is_(True))
	elif only_active is False:
		q = q.filter(SupportPlan.is_active.is_(False))
	plans = q.order_by(SupportPlan.sort_order.asc(), SupportPlan.id.asc()).all()
	return [_serialize_plan(p) for p in plans]


def delete_support_plan(db: Session, plan_id: int) -> bool:
	"""اگر اشتراک داشته باشد فقط غیرفعال می‌شود؛ در غیر این صورت حذف."""
	plan = db.query(SupportPlan).filter(SupportPlan.id == int(plan_id)).first()
	if not plan:
		raise ApiError("PLAN_NOT_FOUND", "پلن یافت نشد", http_status=404)

	has_subs = (
		db.query(SupportSubscription.id)
		.filter(SupportSubscription.plan_id == plan.id)
		.limit(1)
		.first()
	)
	if has_subs:
		plan.is_active = False
		plan.updated_at = datetime.utcnow()
		db.commit()
		return False

	db.delete(plan)
	db.commit()
	return True
