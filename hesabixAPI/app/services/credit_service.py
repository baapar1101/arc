from __future__ import annotations

from decimal import Decimal
from typing import Any, Dict, List

from sqlalchemy.orm import Session
from sqlalchemy import and_

from adapters.db.models.business import Business
from adapters.db.models.credit import BusinessCreditSetting, InstallmentPlanTemplate
from adapters.db.models.person import Person
from app.core.responses import ApiError


def _to_decimal_or_none(value) -> Decimal | None:
	try:
		if value is None or str(value).strip() == "":
			return None
		return Decimal(str(value))
	except Exception:
		return None


def get_business_credit_settings(db: Session, business_id: int) -> Dict[str, Any]:
	obj = (
		db.query(BusinessCreditSetting)
		.filter(BusinessCreditSetting.business_id == int(business_id))
		.first()
	)
	if not obj:
		# Fallback to Business defaults, if any
		biz = db.query(Business).filter(Business.id == int(business_id)).first()
		return {
			"business_id": int(business_id),
			"is_enabled": bool((biz.check_credit_enabled_by_default if biz else False) or False),
			"default_limit": float(biz.default_credit_limit) if (biz and biz.default_credit_limit is not None) else None,
			"grace_days": None,
			"late_fee_rate": None,
			"auto_block_after_days": None,
			"strategy": "single-default",
		}
	return {
		"business_id": int(business_id),
		"is_enabled": bool(obj.is_enabled),
		"default_limit": float(obj.default_limit) if obj.default_limit is not None else None,
		"grace_days": int(obj.grace_days) if obj.grace_days is not None else None,
		"late_fee_rate": float(obj.late_fee_rate) if obj.late_fee_rate is not None else None,
		"auto_block_after_days": int(obj.auto_block_after_days) if obj.auto_block_after_days is not None else None,
		"strategy": obj.strategy or "single-default",
	}


def update_business_credit_settings(db: Session, business_id: int, payload: Dict[str, Any]) -> Dict[str, Any]:
	obj = (
		db.query(BusinessCreditSetting)
		.filter(BusinessCreditSetting.business_id == int(business_id))
		.first()
	)
	if not obj:
		obj = BusinessCreditSetting(business_id=int(business_id))
		db.add(obj)
	# Normalize
	is_enabled = bool(payload.get("is_enabled") or False)
	obj.is_enabled = is_enabled
	obj.default_limit = _to_decimal_or_none(payload.get("default_limit"))
	try:
		obj.grace_days = int(payload.get("grace_days")) if payload.get("grace_days") is not None else None
	except Exception:
		obj.grace_days = None
	obj.late_fee_rate = _to_decimal_or_none(payload.get("late_fee_rate"))
	try:
		obj.auto_block_after_days = int(payload.get("auto_block_after_days")) if payload.get("auto_block_after_days") is not None else None
	except Exception:
		obj.auto_block_after_days = None
	strategy = str(payload.get("strategy") or "").strip().lower() or "single-default"
	if strategy not in ("single-default", "by-group", "per-user"):
		strategy = "single-default"
	obj.strategy = strategy
	db.flush()
	db.commit()
	return get_business_credit_settings(db, business_id)


def list_installment_plans(db: Session, business_id: int, only_active: bool | None = None) -> List[Dict[str, Any]]:
	q = db.query(InstallmentPlanTemplate).filter(InstallmentPlanTemplate.business_id == int(business_id))
	if only_active is True:
		q = q.filter(InstallmentPlanTemplate.is_active == True)  # noqa: E712
	items = q.order_by(InstallmentPlanTemplate.created_at.desc()).all()
	def to_dict(p: InstallmentPlanTemplate) -> Dict[str, Any]:
		return {
			"id": int(p.id),
			"business_id": int(p.business_id),
			"name": p.name,
			"method": p.method,
			"num_installments": int(p.num_installments),
			"period_days": int(p.period_days),
			"down_payment_percent": float(p.down_payment_percent) if p.down_payment_percent is not None else None,
			"interest_rate": float(p.interest_rate) if p.interest_rate is not None else None,
			"late_fee_rate": float(p.late_fee_rate) if p.late_fee_rate is not None else None,
			"issue_fee": float(p.issue_fee) if p.issue_fee is not None else None,
			"description": p.description,
			"is_active": bool(p.is_active),
			"created_at": p.created_at.isoformat() if p.created_at else None,
			"updated_at": p.updated_at.isoformat() if p.updated_at else None,
		}
	return [to_dict(p) for p in items]


def create_installment_plan(db: Session, business_id: int, payload: Dict[str, Any]) -> Dict[str, Any]:
	name = str(payload.get("name") or "").strip()
	if not name:
		raise ApiError("VALIDATION_ERROR", "name is required", http_status=422)
	# Uniqueness per business
	exists = db.query(InstallmentPlanTemplate).filter(
		and_(
			InstallmentPlanTemplate.business_id == int(business_id),
			InstallmentPlanTemplate.name == name,
		)
	).first()
	if exists:
		raise ApiError("DUPLICATE_NAME", "plan with the same name already exists", http_status=400)
	try:
		num_installments = int(payload.get("num_installments") or 0)
	except Exception:
		num_installments = 0
	if num_installments <= 0:
		raise ApiError("VALIDATION_ERROR", "num_installments must be > 0", http_status=422)
	try:
		period_days = int(payload.get("period_days") or 30)
	except Exception:
		period_days = 30
	method = str(payload.get("method") or "flat").strip().lower()
	if method not in ("flat", "amortized"):
		method = "flat"
	obj = InstallmentPlanTemplate(
		business_id=int(business_id),
		name=name,
		method=method,
		num_installments=num_installments,
		period_days=period_days,
		is_active=bool(payload.get("is_active", True)),
	)
	obj.down_payment_percent = _to_decimal_or_none(payload.get("down_payment_percent"))
	obj.interest_rate = _to_decimal_or_none(payload.get("interest_rate"))
	obj.late_fee_rate = _to_decimal_or_none(payload.get("late_fee_rate"))
	obj.issue_fee = _to_decimal_or_none(payload.get("issue_fee"))
	desc = payload.get("description")
	obj.description = str(desc) if desc is not None else None
	db.add(obj)
	db.flush()
	db.commit()
	return get_installment_plan(db, business_id, int(obj.id))


def get_installment_plan(db: Session, business_id: int, plan_id: int) -> Dict[str, Any]:
	p = db.query(InstallmentPlanTemplate).filter(
		and_(
			InstallmentPlanTemplate.id == int(plan_id),
			InstallmentPlanTemplate.business_id == int(business_id),
		)
	).first()
	if not p:
		raise ApiError("NOT_FOUND", "installment plan not found", http_status=404)
	return {
		"id": int(p.id),
		"business_id": int(p.business_id),
		"name": p.name,
		"method": p.method,
		"num_installments": int(p.num_installments),
		"period_days": int(p.period_days),
		"down_payment_percent": float(p.down_payment_percent) if p.down_payment_percent is not None else None,
		"interest_rate": float(p.interest_rate) if p.interest_rate is not None else None,
		"late_fee_rate": float(p.late_fee_rate) if p.late_fee_rate is not None else None,
		"issue_fee": float(p.issue_fee) if p.issue_fee is not None else None,
		"description": p.description,
		"is_active": bool(p.is_active),
		"created_at": p.created_at.isoformat() if p.created_at else None,
		"updated_at": p.updated_at.isoformat() if p.updated_at else None,
	}


def update_installment_plan(db: Session, business_id: int, plan_id: int, payload: Dict[str, Any]) -> Dict[str, Any]:
	p = db.query(InstallmentPlanTemplate).filter(
		and_(
			InstallmentPlanTemplate.id == int(plan_id),
			InstallmentPlanTemplate.business_id == int(business_id),
		)
	).first()
	if not p:
		raise ApiError("NOT_FOUND", "installment plan not found", http_status=404)
	# Update fields
	if "name" in payload:
		name = str(payload.get("name") or "").strip()
		if not name:
			raise ApiError("VALIDATION_ERROR", "name cannot be empty", http_status=422)
		dup = db.query(InstallmentPlanTemplate).filter(
			and_(
				InstallmentPlanTemplate.business_id == int(business_id),
				InstallmentPlanTemplate.name == name,
				InstallmentPlanTemplate.id != int(plan_id),
			)
		).first()
		if dup:
			raise ApiError("DUPLICATE_NAME", "plan with the same name already exists", http_status=400)
		p.name = name
	if "method" in payload:
		method = str(payload.get("method") or "").strip().lower()
		if method not in ("flat", "amortized", ""):
			raise ApiError("VALIDATION_ERROR", "invalid method", http_status=422)
		if method:
			p.method = method
	if "num_installments" in payload:
		try:
			n = int(payload.get("num_installments") or 0)
		except Exception:
			n = 0
		if n <= 0:
			raise ApiError("VALIDATION_ERROR", "num_installments must be > 0", http_status=422)
		p.num_installments = n
	if "period_days" in payload:
		try:
			days = int(payload.get("period_days") or 30)
		except Exception:
			days = 30
		if days <= 0:
			days = 30
		p.period_days = days
	if "down_payment_percent" in payload:
		p.down_payment_percent = _to_decimal_or_none(payload.get("down_payment_percent"))
	if "interest_rate" in payload:
		p.interest_rate = _to_decimal_or_none(payload.get("interest_rate"))
	if "late_fee_rate" in payload:
		p.late_fee_rate = _to_decimal_or_none(payload.get("late_fee_rate"))
	if "issue_fee" in payload:
		p.issue_fee = _to_decimal_or_none(payload.get("issue_fee"))
	if "description" in payload:
		desc = payload.get("description")
		p.description = str(desc) if desc is not None else None
	if "is_active" in payload:
		p.is_active = bool(payload.get("is_active"))
	db.flush()
	db.commit()
	return get_installment_plan(db, business_id, plan_id)


def delete_installment_plan(db: Session, business_id: int, plan_id: int) -> Dict[str, Any]:
	p = db.query(InstallmentPlanTemplate).filter(
		and_(
			InstallmentPlanTemplate.id == int(plan_id),
			InstallmentPlanTemplate.business_id == int(business_id),
		)
	).first()
	if not p:
		raise ApiError("NOT_FOUND", "installment plan not found", http_status=404)
	db.delete(p)
	db.flush()
	db.commit()
	return {"ok": True}


# ---- Person credit override ----
def get_person_credit(db: Session, business_id: int, person_id: int) -> Dict[str, Any]:
	person = db.query(Person).filter(
		and_(Person.id == int(person_id), Person.business_id == int(business_id))
	).first()
	if not person:
		raise ApiError("PERSON_NOT_FOUND", "person not found", http_status=404)
	# Effective values
	biz = db.query(Business).filter(Business.id == int(business_id)).first()
	effective_limit = person.credit_limit
	if effective_limit is None and biz and biz.default_credit_limit is not None:
		effective_limit = biz.default_credit_limit
	return {
		"person_id": int(person.id),
		"business_id": int(business_id),
		"credit_limit": float(person.credit_limit) if person.credit_limit is not None else None,
		"credit_check_enabled": person.credit_check_enabled,
		"effective_credit_limit": float(effective_limit) if effective_limit is not None else None,
	}


def update_person_credit(db: Session, business_id: int, person_id: int, payload: Dict[str, Any]) -> Dict[str, Any]:
	person = db.query(Person).filter(
		and_(Person.id == int(person_id), Person.business_id == int(business_id))
	).first()
	if not person:
		raise ApiError("PERSON_NOT_FOUND", "person not found", http_status=404)
	# Normalize inputs
	cl_raw = payload.get("credit_limit", "__MISSING__")
	if cl_raw != "__MISSING__":
		person.credit_limit = _to_decimal_or_none(cl_raw)
	if "credit_check_enabled" in payload:
		val = payload.get("credit_check_enabled")
		if val is None:
			person.credit_check_enabled = None
		else:
			person.credit_check_enabled = bool(val)
	db.flush()
	return get_person_credit(db, business_id, person_id)


