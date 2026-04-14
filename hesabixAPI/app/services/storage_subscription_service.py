"""
سرویس مدیریت اشتراک‌های ذخیره‌سازی
"""

from __future__ import annotations

from typing import Dict, Any, List, Optional
from datetime import datetime, timedelta
from decimal import Decimal

from sqlalchemy.orm import Session
from sqlalchemy import and_, func, or_

from adapters.db.models.storage_plan import StoragePlan, BusinessStorageSubscription, StorageUsageTransaction
from adapters.db.models.file_storage import FileStorage
from adapters.db.models.business import Business
from app.core.responses import ApiError


def subscribe_to_plan(
	db: Session,
	business_id: int,
	plan_id: int,
	auto_renew: bool = False,
) -> Dict[str, Any]:
	"""اشتراک کسب‌وکار به یک پلن"""
	# بررسی کسب‌وکار
	business = db.query(Business).filter(Business.id == business_id).first()
	if not business:
		raise ApiError("BUSINESS_NOT_FOUND", "کسب‌وکار یافت نشد", http_status=404)
	
	# بررسی پلن
	plan = db.query(StoragePlan).filter(
		and_(StoragePlan.id == plan_id, StoragePlan.is_active == True)
	).first()
	if not plan:
		raise ApiError("PLAN_NOT_FOUND", "پلن یافت نشد یا غیرفعال است", http_status=404)
	
	# اگر پلن رایگان است، بررسی می‌کنیم که قبلاً فعال نشده باشد
	if plan.is_free:
		existing_free_subscription = db.query(BusinessStorageSubscription).filter(
			and_(
				BusinessStorageSubscription.business_id == business_id,
				BusinessStorageSubscription.plan_id == plan_id,
				BusinessStorageSubscription.status == "active"
			)
		).first()
		if existing_free_subscription:
			raise ApiError(
				"FREE_PLAN_ALREADY_ACTIVE",
				"این پلن رایگان قبلاً فعال شده است. هر کسب‌وکار فقط می‌تواند یک بار از پلن رایگان استفاده کند.",
				http_status=400
			)
	
	# محاسبه تاریخ شروع و پایان
	starts_at = datetime.utcnow()
	ends_at = None
	grace_period_ends_at = None
	
	if plan.period == "lifetime":
		ends_at = None
		grace_period_ends_at = None
	else:
		if plan.period_months:
			ends_at = starts_at + timedelta(days=plan.period_months * 30)
			grace_period_ends_at = ends_at + timedelta(days=plan.grace_period_days)
	
	# ایجاد اشتراک (در وضعیت در انتظار پرداخت تا تسویه کامل شود)
	subscription = BusinessStorageSubscription(
		business_id=business_id,
		plan_id=plan_id,
		status="pending",
		starts_at=starts_at,
		ends_at=ends_at,
		auto_renew=auto_renew,
		grace_period_ends_at=grace_period_ends_at,
	)
	
	db.add(subscription)
	db.commit()
	db.refresh(subscription)
	
	return get_subscription(db, business_id, subscription.id)


def get_active_subscriptions(
	db: Session,
	business_id: int,
) -> List[Dict[str, Any]]:
	"""دریافت تمام اشتراک‌های فعال کسب‌وکار"""
	subscriptions = db.query(BusinessStorageSubscription).filter(
		and_(
			BusinessStorageSubscription.business_id == business_id,
			BusinessStorageSubscription.status == "active"
		)
	).order_by(BusinessStorageSubscription.created_at.desc()).all()
	
	return [get_subscription(db, business_id, sub.id) for sub in subscriptions]


def get_subscription(
	db: Session,
	business_id: int,
	subscription_id: int,
) -> Dict[str, Any]:
	"""دریافت جزئیات یک اشتراک"""
	subscription = db.query(BusinessStorageSubscription).filter(
		and_(
			BusinessStorageSubscription.id == subscription_id,
			BusinessStorageSubscription.business_id == business_id
		)
	).first()
	
	if not subscription:
		raise ApiError("SUBSCRIPTION_NOT_FOUND", "اشتراک یافت نشد", http_status=404)
	
	plan = subscription.plan
	
	return {
		"id": subscription.id,
		"business_id": subscription.business_id,
		"plan_id": subscription.plan_id,
		"plan_name": plan.name if plan else None,
		"plan_code": plan.code if plan else None,
		"storage_limit_gb": float(plan.storage_limit_gb) if plan else 0,
		"period": plan.period if plan else None,
		"status": subscription.status,
		"starts_at": subscription.starts_at.isoformat() if subscription.starts_at else None,
		"ends_at": subscription.ends_at.isoformat() if subscription.ends_at else None,
		"auto_renew": subscription.auto_renew,
		"grace_period_ends_at": subscription.grace_period_ends_at.isoformat() if subscription.grace_period_ends_at else None,
		"created_at": subscription.created_at.isoformat() if subscription.created_at else None,
		"updated_at": subscription.updated_at.isoformat() if subscription.updated_at else None,
	}


def calculate_total_storage_limit(
	db: Session,
	business_id: int,
) -> float:
	"""محاسبه کل محدودیت حجم از تمام پلن‌های فعال"""
	subscriptions = db.query(BusinessStorageSubscription).filter(
		and_(
			BusinessStorageSubscription.business_id == business_id,
			BusinessStorageSubscription.status == "active"
		)
	).all()
	
	total_limit = 0.0
	for sub in subscriptions:
		if sub.plan:
			total_limit += float(sub.plan.storage_limit_gb)
	
	return total_limit


def calculate_storage_usage(
	db: Session,
	business_id: int,
) -> float:
	"""محاسبه استفاده فعلی کسب‌وکار (بر اساس فایل‌های فعال)"""
	# محاسبه حجم کل فایل‌های فعال کسب‌وکار
	total_size = db.query(func.sum(FileStorage.file_size)).filter(
		and_(
			FileStorage.business_id == business_id,
			FileStorage.deleted_at.is_(None),
			FileStorage.is_active == True,
			FileStorage.is_marked_for_deletion == False
		)
	).scalar() or 0
	
	# تبدیل بایت به گیگابایت
	usage_gb = float(total_size) / (1024 * 1024 * 1024)
	return round(usage_gb, 6)  # دقت 6 رقم اعشار


def check_storage_limit(
	db: Session,
	business_id: int,
	additional_size_bytes: Optional[int] = None,
) -> Dict[str, Any]:
	"""بررسی محدودیت حجم"""
	total_limit = calculate_total_storage_limit(db, business_id)
	current_usage = calculate_storage_usage(db, business_id)
	
	if additional_size_bytes:
		additional_gb = float(additional_size_bytes) / (1024 * 1024 * 1024)
		projected_usage = current_usage + additional_gb
	else:
		additional_gb = 0.0
		projected_usage = current_usage
	
	available_gb = total_limit - current_usage
	over_limit = projected_usage > total_limit
	over_usage_gb = max(0, projected_usage - total_limit) if over_limit else 0.0
	
	return {
		"total_limit_gb": total_limit,
		"current_usage_gb": current_usage,
		"available_gb": available_gb,
		"projected_usage_gb": projected_usage,
		"over_limit": over_limit,
		"over_usage_gb": over_usage_gb,
		"additional_gb": additional_gb,
	}


def renew_subscription(
	db: Session,
	business_id: int,
	subscription_id: int,
) -> Dict[str, Any]:
	"""تمدید اشتراک"""
	subscription = db.query(BusinessStorageSubscription).filter(
		and_(
			BusinessStorageSubscription.id == subscription_id,
			BusinessStorageSubscription.business_id == business_id
		)
	).first()
	
	if not subscription:
		raise ApiError("SUBSCRIPTION_NOT_FOUND", "اشتراک یافت نشد", http_status=404)
	
	plan = subscription.plan
	if not plan:
		raise ApiError("PLAN_NOT_FOUND", "پلن یافت نشد", http_status=404)
	
	if plan.period == "lifetime":
		raise ApiError("INVALID_OPERATION", "پلن مادام‌العمر قابل تمدید نیست", http_status=400)
	
	# محاسبه تاریخ پایان جدید
	if subscription.ends_at:
		new_ends_at = subscription.ends_at + timedelta(days=plan.period_months * 30)
	else:
		new_ends_at = datetime.utcnow() + timedelta(days=plan.period_months * 30)
	
	subscription.ends_at = new_ends_at
	subscription.grace_period_ends_at = new_ends_at + timedelta(days=plan.grace_period_days)
	subscription.status = "active"
	subscription.updated_at = datetime.utcnow()
	
	db.commit()
	db.refresh(subscription)
	
	return get_subscription(db, business_id, subscription.id)


def cancel_subscription(
	db: Session,
	business_id: int,
	subscription_id: int,
) -> Dict[str, Any]:
	"""لغو اشتراک"""
	subscription = db.query(BusinessStorageSubscription).filter(
		and_(
			BusinessStorageSubscription.id == subscription_id,
			BusinessStorageSubscription.business_id == business_id
		)
	).first()
	
	if not subscription:
		raise ApiError("SUBSCRIPTION_NOT_FOUND", "اشتراک یافت نشد", http_status=404)
	
	subscription.status = "cancelled"
	subscription.auto_renew = False
	subscription.updated_at = datetime.utcnow()
	
	db.commit()
	db.refresh(subscription)
	
	return get_subscription(db, business_id, subscription.id)


def check_expired_subscriptions(db: Session) -> List[Dict[str, Any]]:
	"""بررسی اشتراک‌های منقضی شده و شروع grace period"""
	now = datetime.utcnow()
	
	# اشتراک‌های فعال که تاریخ پایان آن‌ها گذشته
	expired = db.query(BusinessStorageSubscription).filter(
		and_(
			BusinessStorageSubscription.status == "active",
			BusinessStorageSubscription.ends_at.isnot(None),
			BusinessStorageSubscription.ends_at < now
		)
	).all()
	
	expired_list = []
	for sub in expired:
		sub.status = "expired"
		if not sub.grace_period_ends_at and sub.ends_at:
			plan = sub.plan
			if plan:
				sub.grace_period_ends_at = sub.ends_at + timedelta(days=plan.grace_period_days)
		sub.updated_at = datetime.utcnow()
		expired_list.append({
			"id": sub.id,
			"business_id": sub.business_id,
			"plan_id": sub.plan_id,
			"ends_at": sub.ends_at.isoformat() if sub.ends_at else None,
		})
	
	db.commit()
	return expired_list


def get_storage_usage_info(
	db: Session,
	business_id: int,
) -> Dict[str, Any]:
	"""دریافت اطلاعات کامل استفاده و محدودیت"""
	active_subscriptions = get_active_subscriptions(db, business_id)
	total_limit = calculate_total_storage_limit(db, business_id)
	current_usage = calculate_storage_usage(db, business_id)
	available = total_limit - current_usage
	
	return {
		"total_limit_gb": total_limit,
		"current_usage_gb": current_usage,
		"available_gb": available,
		"usage_percent": (current_usage / total_limit * 100) if total_limit > 0 else 0,
		"active_subscriptions": active_subscriptions,
		"subscription_count": len(active_subscriptions),
	}

