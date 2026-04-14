"""
سرویس مدیریت پلن‌های ذخیره‌سازی
"""

from __future__ import annotations

from typing import Dict, Any, List, Optional
from datetime import datetime
from decimal import Decimal

from sqlalchemy.orm import Session
from sqlalchemy import and_, or_

from adapters.db.models.storage_plan import StoragePlan
from adapters.db.models.currency import Currency
from app.core.responses import ApiError


def create_storage_plan(
	db: Session,
	payload: Dict[str, Any],
) -> Dict[str, Any]:
	"""ایجاد پلن جدید توسط مدیر"""
	name = str(payload.get("name") or "").strip()
	if not name:
		raise ApiError("VALIDATION_ERROR", "نام پلن الزامی است", http_status=422)
	
	code = str(payload.get("code") or "").strip()
	if not code:
		raise ApiError("VALIDATION_ERROR", "کد پلن الزامی است", http_status=422)
	
	# بررسی یکتایی کد
	existing = db.query(StoragePlan).filter(StoragePlan.code == code).first()
	if existing:
		raise ApiError("DUPLICATE_CODE", "پلن با این کد قبلاً ایجاد شده است", http_status=400)
	
	# بررسی storage_limit_gb
	try:
		storage_limit_gb = float(payload.get("storage_limit_gb") or 0)
		if storage_limit_gb <= 0:
			raise ApiError("VALIDATION_ERROR", "محدودیت حجم باید بیشتر از صفر باشد", http_status=422)
	except (ValueError, TypeError):
		raise ApiError("VALIDATION_ERROR", "محدودیت حجم نامعتبر است", http_status=422)
	
	# بررسی period
	period = str(payload.get("period") or "").strip().lower()
	if period not in ("monthly", "yearly", "lifetime"):
		raise ApiError("VALIDATION_ERROR", "دوره باید یکی از: monthly, yearly, lifetime باشد", http_status=422)
	
	# بررسی period_months
	period_months = None
	if period != "lifetime":
		try:
			period_months = int(payload.get("period_months") or 0)
			if period_months <= 0:
				raise ApiError("VALIDATION_ERROR", "تعداد ماه‌ها باید بیشتر از صفر باشد", http_status=422)
		except (ValueError, TypeError):
			raise ApiError("VALIDATION_ERROR", "تعداد ماه‌ها نامعتبر است", http_status=422)
	
	# بررسی currency_id
	try:
		currency_id = int(payload.get("currency_id") or 0)
		if currency_id <= 0:
			raise ApiError("VALIDATION_ERROR", "ارز الزامی است", http_status=422)
		currency = db.query(Currency).filter(Currency.id == currency_id).first()
		if not currency:
			raise ApiError("CURRENCY_NOT_FOUND", "ارز یافت نشد", http_status=404)
	except (ValueError, TypeError):
		raise ApiError("VALIDATION_ERROR", "شناسه ارز نامعتبر است", http_status=422)
	
	# بررسی price
	try:
		price = float(payload.get("price") or 0)
		if price < 0:
			raise ApiError("VALIDATION_ERROR", "قیمت نمی‌تواند منفی باشد", http_status=422)
	except (ValueError, TypeError):
		price = 0.0
	
	# بررسی price_per_gb
	price_per_gb = None
	if payload.get("price_per_gb") is not None:
		try:
			price_per_gb = float(payload.get("price_per_gb") or 0)
			if price_per_gb < 0:
				raise ApiError("VALIDATION_ERROR", "قیمت هر گیگابایت نمی‌تواند منفی باشد", http_status=422)
		except (ValueError, TypeError):
			price_per_gb = None
	
	# بررسی is_free
	is_free = bool(payload.get("is_free", False))
	if is_free:
		price = 0.0
	
	# بررسی grace_period_days
	try:
		grace_period_days = int(payload.get("grace_period_days") or 30)
		if grace_period_days < 0:
			grace_period_days = 30
	except (ValueError, TypeError):
		grace_period_days = 30
	
	# ایجاد پلن
	plan = StoragePlan(
		name=name,
		code=code,
		storage_limit_gb=storage_limit_gb,
		period=period,
		period_months=period_months,
		price=price,
		price_per_gb=price_per_gb,
		is_free=is_free,
		is_active=bool(payload.get("is_active", True)),
		currency_id=currency_id,
		description=payload.get("description"),
		grace_period_days=grace_period_days,
	)
	
	db.add(plan)
	db.commit()
	db.refresh(plan)
	
	return get_storage_plan(db, plan.id)


def update_storage_plan(
	db: Session,
	plan_id: int,
	payload: Dict[str, Any],
) -> Dict[str, Any]:
	"""ویرایش پلن"""
	plan = db.query(StoragePlan).filter(StoragePlan.id == plan_id).first()
	if not plan:
		raise ApiError("PLAN_NOT_FOUND", "پلن یافت نشد", http_status=404)
	
	# به‌روزرسانی فیلدها
	if "name" in payload:
		name = str(payload.get("name") or "").strip()
		if name:
			plan.name = name
	
	if "code" in payload:
		code = str(payload.get("code") or "").strip()
		if code and code != plan.code:
			existing = db.query(StoragePlan).filter(
				and_(StoragePlan.code == code, StoragePlan.id != plan_id)
			).first()
			if existing:
				raise ApiError("DUPLICATE_CODE", "پلن با این کد قبلاً ایجاد شده است", http_status=400)
			plan.code = code
	
	if "storage_limit_gb" in payload:
		try:
			storage_limit_gb = float(payload.get("storage_limit_gb") or 0)
			if storage_limit_gb > 0:
				plan.storage_limit_gb = storage_limit_gb
		except (ValueError, TypeError):
			pass
	
	if "period" in payload:
		period = str(payload.get("period") or "").strip().lower()
		if period in ("monthly", "yearly", "lifetime"):
			plan.period = period
			if period == "lifetime":
				plan.period_months = None
	
	if "period_months" in payload and plan.period != "lifetime":
		try:
			period_months = int(payload.get("period_months") or 0)
			if period_months > 0:
				plan.period_months = period_months
		except (ValueError, TypeError):
			pass
	
	if "price" in payload:
		try:
			price = float(payload.get("price") or 0)
			if price >= 0:
				plan.price = price
		except (ValueError, TypeError):
			pass
	
	if "price_per_gb" in payload:
		try:
			price_per_gb = float(payload.get("price_per_gb") or 0)
			if price_per_gb >= 0:
				plan.price_per_gb = price_per_gb
		except (ValueError, TypeError):
			pass
	
	if "is_free" in payload:
		is_free = bool(payload.get("is_free", False))
		plan.is_free = is_free
		if is_free:
			plan.price = 0.0
	
	if "is_active" in payload:
		plan.is_active = bool(payload.get("is_active", True))
	
	if "currency_id" in payload:
		try:
			currency_id = int(payload.get("currency_id") or 0)
			if currency_id > 0:
				currency = db.query(Currency).filter(Currency.id == currency_id).first()
				if currency:
					plan.currency_id = currency_id
		except (ValueError, TypeError):
			pass
	
	if "description" in payload:
		plan.description = payload.get("description")
	
	if "grace_period_days" in payload:
		try:
			grace_period_days = int(payload.get("grace_period_days") or 30)
			if grace_period_days >= 0:
				plan.grace_period_days = grace_period_days
		except (ValueError, TypeError):
			pass
	
	plan.updated_at = datetime.utcnow()
	db.commit()
	db.refresh(plan)
	
	return get_storage_plan(db, plan.id)


def get_storage_plan(db: Session, plan_id: int) -> Dict[str, Any]:
	"""دریافت جزئیات یک پلن"""
	plan = db.query(StoragePlan).filter(StoragePlan.id == plan_id).first()
	if not plan:
		raise ApiError("PLAN_NOT_FOUND", "پلن یافت نشد", http_status=404)
	
	return {
		"id": plan.id,
		"name": plan.name,
		"code": plan.code,
		"storage_limit_gb": float(plan.storage_limit_gb),
		"period": plan.period,
		"period_months": plan.period_months,
		"price": float(plan.price),
		"price_per_gb": float(plan.price_per_gb) if plan.price_per_gb else None,
		"is_free": plan.is_free,
		"is_active": plan.is_active,
		"currency_id": plan.currency_id,
		"currency_code": plan.currency.code if plan.currency else None,
		"description": plan.description,
		"grace_period_days": plan.grace_period_days,
		"created_at": plan.created_at.isoformat() if plan.created_at else None,
		"updated_at": plan.updated_at.isoformat() if plan.updated_at else None,
	}


def list_storage_plans(
	db: Session,
	only_active: Optional[bool] = None,
) -> List[Dict[str, Any]]:
	"""لیست پلن‌ها"""
	query = db.query(StoragePlan)
	
	if only_active is not None:
		query = query.filter(StoragePlan.is_active == only_active)
	
	plans = query.order_by(StoragePlan.created_at.desc()).all()
	
	return [get_storage_plan(db, plan.id) for plan in plans]


def delete_storage_plan(db: Session, plan_id: int) -> bool:
	"""حذف/غیرفعال کردن پلن"""
	plan = db.query(StoragePlan).filter(StoragePlan.id == plan_id).first()
	if not plan:
		raise ApiError("PLAN_NOT_FOUND", "پلن یافت نشد", http_status=404)
	
	# بررسی اینکه آیا اشتراک فعالی برای این پلن وجود دارد
	from adapters.db.models.storage_plan import BusinessStorageSubscription
	active_subscriptions = db.query(BusinessStorageSubscription).filter(
		and_(
			BusinessStorageSubscription.plan_id == plan_id,
			BusinessStorageSubscription.status == "active"
		)
	).count()
	
	if active_subscriptions > 0:
		# فقط غیرفعال می‌کنیم
		plan.is_active = False
		db.commit()
		return False
	else:
		# حذف کامل
		db.delete(plan)
		db.commit()
		return True

