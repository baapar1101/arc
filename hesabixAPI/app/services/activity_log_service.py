from __future__ import annotations

from typing import Optional, Dict, Any
from datetime import datetime
from sqlalchemy.orm import Session
from adapters.db.models.activity_log import ActivityLog
from fastapi import Request


def log_activity(
	db: Session,
	user_id: int,
	category: str,
	action: str,
	description: str,
	business_id: Optional[int] = None,
	entity_type: Optional[str] = None,
	entity_id: Optional[int] = None,
	before_data: Optional[Dict[str, Any]] = None,
	after_data: Optional[Dict[str, Any]] = None,
	extra_info: Optional[Dict[str, Any]] = None,
	request: Optional[Request] = None
) -> ActivityLog:
	"""
	ثبت یک فعالیت در لاگ
	
	Args:
		db: جلسه دیتابیس
		user_id: شناسه کاربر
		category: دسته فعالیت (accounting, warehouse, product, person, business, user, settings, other)
		action: نوع عمل (create, update, delete, post, cancel, etc.)
		description: توضیحات قابل خواندن
		business_id: شناسه کسب و کار (اختیاری برای فعالیت‌های شخصی)
		entity_type: نوع موجودیت (invoice, document, product, person, etc.)
		entity_id: شناسه موجودیت
		before_data: داده‌های قبل از تغییر (فقط فیلدهای تغییر یافته)
		after_data: داده‌های بعد از تغییر (فقط فیلدهای تغییر یافته)
		extra_info: اطلاعات اضافی
		request: درخواست HTTP (برای استخراج IP و User-Agent)
	
	Returns:
		ActivityLog: لاگ ایجاد شده
	"""
	# استخراج اطلاعات از request در صورت وجود
	if request and not extra_info:
		extra_info = {}
		client_ip = request.client.host if request.client else None
		if client_ip:
			extra_info["ip_address"] = client_ip
		user_agent = request.headers.get("User-Agent")
		if user_agent:
			extra_info["user_agent"] = user_agent
	
	log = ActivityLog(
		user_id=user_id,
		business_id=business_id,
		category=category,
		action=action,
		entity_type=entity_type,
		entity_id=entity_id,
		description=description,
		before_data=before_data,
		after_data=after_data,
		extra_info=extra_info,
		created_at=datetime.utcnow()
	)
	
	db.add(log)
	db.flush()
	return log


# توابع کمکی برای لاگ‌گیری انواع مختلف فعالیت‌ها

def log_invoice_activity(
	db: Session,
	user_id: int,
	business_id: int,
	action: str,
	invoice_id: int,
	description: str,
	before_data: Optional[Dict[str, Any]] = None,
	after_data: Optional[Dict[str, Any]] = None,
	request: Optional[Request] = None
) -> ActivityLog:
	"""لاگ‌گیری فعالیت‌های فاکتور"""
	return log_activity(
		db=db,
		user_id=user_id,
		business_id=business_id,
		category="accounting",
		action=action,
		entity_type="invoice",
		entity_id=invoice_id,
		description=description,
		before_data=before_data,
		after_data=after_data,
		extra_info=None,
		request=request
	)


def log_warehouse_activity(
	db: Session,
	user_id: int,
	business_id: int,
	action: str,
	warehouse_doc_id: int,
	description: str,
	before_data: Optional[Dict[str, Any]] = None,
	after_data: Optional[Dict[str, Any]] = None,
	request: Optional[Request] = None
) -> ActivityLog:
	"""لاگ‌گیری فعالیت‌های انبار"""
	return log_activity(
		db=db,
		user_id=user_id,
		business_id=business_id,
		category="warehouse",
		action=action,
		entity_type="warehouse_document",
		entity_id=warehouse_doc_id,
		description=description,
		before_data=before_data,
		after_data=after_data,
		extra_info=None,
		request=request
	)


def log_product_activity(
	db: Session,
	user_id: int,
	business_id: int,
	action: str,
	product_id: int,
	description: str,
	before_data: Optional[Dict[str, Any]] = None,
	after_data: Optional[Dict[str, Any]] = None,
	request: Optional[Request] = None
) -> ActivityLog:
	"""لاگ‌گیری فعالیت‌های محصول"""
	return log_activity(
		db=db,
		user_id=user_id,
		business_id=business_id,
		category="product",
		action=action,
		entity_type="product",
		entity_id=product_id,
		description=description,
		before_data=before_data,
		after_data=after_data,
		extra_info=None,
		request=request
	)


def log_person_activity(
	db: Session,
	user_id: int,
	business_id: int,
	action: str,
	person_id: int,
	description: str,
	before_data: Optional[Dict[str, Any]] = None,
	after_data: Optional[Dict[str, Any]] = None,
	request: Optional[Request] = None
) -> ActivityLog:
	"""لاگ‌گیری فعالیت‌های شخص"""
	return log_activity(
		db=db,
		user_id=user_id,
		business_id=business_id,
		category="person",
		action=action,
		entity_type="person",
		entity_id=person_id,
		description=description,
		before_data=before_data,
		after_data=after_data,
		extra_info=None,
		request=request
	)


def log_business_activity(
	db: Session,
	user_id: int,
	business_id: int,
	action: str,
	description: str,
	before_data: Optional[Dict[str, Any]] = None,
	after_data: Optional[Dict[str, Any]] = None,
	request: Optional[Request] = None
) -> ActivityLog:
	"""لاگ‌گیری فعالیت‌های کسب و کار"""
	return log_activity(
		db=db,
		user_id=user_id,
		business_id=business_id,
		category="business",
		action=action,
		entity_type="business",
		entity_id=business_id,
		description=description,
		before_data=before_data,
		after_data=after_data,
		extra_info=None,
		request=request
	)


def log_user_activity(
	db: Session,
	user_id: int,
	action: str,
	description: str,
	entity_id: Optional[int] = None,
	extra_info: Optional[Dict[str, Any]] = None,
	request: Optional[Request] = None
) -> ActivityLog:
	"""لاگ‌گیری فعالیت‌های شخصی کاربر"""
	return log_activity(
		db=db,
		user_id=user_id,
		business_id=None,  # فعالیت‌های شخصی به کسب و کار مرتبط نیستند
		category="user",
		action=action,
		entity_type="user",
		entity_id=entity_id or user_id,
		description=description,
		before_data=None,
		after_data=None,
		extra_info=extra_info,
		request=request
	)

