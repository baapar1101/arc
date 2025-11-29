"""
سرویس مدیریت سرویس‌های استعلامات زحل
"""
from __future__ import annotations

from typing import Optional, Dict, Any, List
from decimal import Decimal
import json
import structlog
from pathlib import Path

from sqlalchemy.orm import Session, selectinload
from sqlalchemy import select, and_, or_, func

from adapters.db.models.zohal import ZohalService, ZohalServiceLog
from decimal import Decimal
from adapters.db.models.currency import Currency
from adapters.db.models.business import Business
from app.core.responses import ApiError

logger = structlog.get_logger()


def list_zohal_services(
	db: Session,
	category: Optional[str] = None,
	only_active: Optional[bool] = None,
) -> List[Dict[str, Any]]:
	"""
	لیست تمام سرویس‌های زحل
	"""
	query = select(ZohalService).options(selectinload(ZohalService.currency))
	
	if category:
		query = query.where(ZohalService.service_category == category)
	
	if only_active is not None:
		query = query.where(ZohalService.is_active == only_active)
	
	query = query.order_by(ZohalService.service_category, ZohalService.service_name)
	
	services = db.execute(query).scalars().all()
	
	result = []
	for service in services:
		result.append({
			"id": service.id,
			"service_code": service.service_code,
			"service_path": service.service_path,
			"service_name": service.service_name,
			"service_category": service.service_category,
			"description": service.description,
			"is_active": service.is_active,
			"base_price": float(service.base_price),
			"currency_id": service.currency_id,
			"currency_code": service.currency.code if service.currency else None,
			"request_schema": service.request_schema,
			"response_schema": service.response_schema,
			"created_at": service.created_at.isoformat() if service.created_at else None,
			"updated_at": service.updated_at.isoformat() if service.updated_at else None,
		})
	
	return result


def get_zohal_service(db: Session, service_id: int) -> Dict[str, Any]:
	"""
	دریافت اطلاعات یک سرویس
	"""
	service = db.execute(
		select(ZohalService).options(selectinload(ZohalService.currency)).where(ZohalService.id == service_id)
	).scalars().first()
	
	if not service:
		raise ApiError("SERVICE_NOT_FOUND", "سرویس یافت نشد", http_status=404)
	
	return {
		"id": service.id,
		"service_code": service.service_code,
		"service_path": service.service_path,
		"service_name": service.service_name,
		"service_category": service.service_category,
		"description": service.description,
		"is_active": service.is_active,
		"base_price": float(service.base_price),
		"currency_id": service.currency_id,
		"currency_code": service.currency.code if service.currency else None,
		"request_schema": service.request_schema,
		"response_schema": service.response_schema,
		"created_at": service.created_at.isoformat() if service.created_at else None,
		"updated_at": service.updated_at.isoformat() if service.updated_at else None,
	}


def get_zohal_service_by_code(db: Session, service_code: str) -> Optional[ZohalService]:
	"""
	دریافت سرویس بر اساس کد
	"""
	return db.execute(
		select(ZohalService).options(selectinload(ZohalService.currency)).where(ZohalService.service_code == service_code)
	).scalars().first()


def toggle_zohal_service(db: Session, service_id: int, is_active: bool) -> Dict[str, Any]:
	"""
	فعال/غیرفعال کردن یک سرویس
	"""
	service = db.execute(
		select(ZohalService).options(selectinload(ZohalService.currency)).where(ZohalService.id == service_id)
	).scalars().first()
	
	if not service:
		raise ApiError("SERVICE_NOT_FOUND", "سرویس یافت نشد", http_status=404)
	
	service.is_active = is_active
	db.commit()
	db.refresh(service)
	
	return get_zohal_service(db, service_id)


def update_zohal_service_price(
	db: Session,
	service_id: int,
	base_price: Decimal,
	currency_id: int,
) -> Dict[str, Any]:
	"""
	به‌روزرسانی قیمت یک سرویس
	"""
	service = db.execute(
		select(ZohalService).options(selectinload(ZohalService.currency)).where(ZohalService.id == service_id)
	).scalars().first()
	
	if not service:
		raise ApiError("SERVICE_NOT_FOUND", "سرویس یافت نشد", http_status=404)
	
	# بررسی وجود ارز
	currency = db.execute(
		select(Currency).where(Currency.id == currency_id)
	).scalars().first()
	
	if not currency:
		raise ApiError("CURRENCY_NOT_FOUND", "ارز یافت نشد", http_status=404)
	
	if base_price < 0:
		raise ApiError("INVALID_PRICE", "قیمت نمی‌تواند منفی باشد", http_status=400)
	
	service.base_price = base_price
	service.currency_id = currency_id
	db.commit()
	db.refresh(service, ["currency"])
	
	return get_zohal_service(db, service_id)


def load_services_from_json(db: Session, json_file_path: str, default_currency_id: int) -> Dict[str, Any]:
	"""
	بارگذاری سرویس‌ها از فایل JSON OpenAPI
	"""
	json_path = Path(json_file_path)
	if not json_path.exists():
		raise ApiError("FILE_NOT_FOUND", f"فایل {json_file_path} یافت نشد", http_status=404)
	
	with open(json_path, 'r', encoding='utf-8') as f:
		openapi_spec = json.load(f)
	
	paths = openapi_spec.get("paths", {})
	created = 0
	updated = 0
	skipped = 0
	
	for path, path_item in paths.items():
		if not path.startswith("/services/"):
			continue
		
		# استخراج service_code از path
		# مثال: "/services/inquiry/card_inquiry" -> "card_inquiry"
		path_parts = path.strip("/").split("/")
		if len(path_parts) < 3:
			continue
		
		service_code = path_parts[-1]  # آخرین بخش
		
		# بررسی POST method
		post_method = path_item.get("post")
		if not post_method:
			continue
		
		# استخراج اطلاعات
		summary = post_method.get("summary", "")
		description = post_method.get("description", "")
		tags = post_method.get("tags", [])
		service_category = tags[0] if tags else "سایر"
		
		# استخراج request schema
		request_body = post_method.get("requestBody", {})
		request_schema = None
		if request_body:
			content = request_body.get("content", {})
			json_content = content.get("application/json", {})
			request_schema = json_content.get("schema", {})
		
		# استخراج response schema
		responses = post_method.get("responses", {})
		response_schema = None
		if responses:
			success_response = responses.get("200", {})
			if success_response:
				content = success_response.get("content", {})
				json_content = content.get("application/json", {})
				response_schema = json_content.get("schema", {})
		
		# بررسی وجود سرویس
		existing = get_zohal_service_by_code(db, service_code)
		
		if existing:
			# به‌روزرسانی
			existing.service_path = path
			existing.service_name = summary or service_code
			existing.service_category = service_category
			existing.description = description
			existing.request_schema = request_schema
			existing.response_schema = response_schema
			updated += 1
		else:
			# ایجاد جدید
			new_service = ZohalService(
				service_code=service_code,
				service_path=path,
				service_name=summary or service_code,
				service_category=service_category,
				description=description,
				is_active=True,
				base_price=Decimal("1000"),  # قیمت پیش‌فرض
				currency_id=default_currency_id,
				request_schema=request_schema,
				response_schema=response_schema,
			)
			db.add(new_service)
			created += 1
	
	db.commit()
	
	return {
		"created": created,
		"updated": updated,
		"skipped": skipped,
		"total": created + updated + skipped,
	}


def call_zohal_api(
	base_url: str,
	api_key: str,
	service_path: str,
	request_data: Dict[str, Any],
) -> Dict[str, Any]:
	"""
	فراخوانی API زحل
	"""
	import httpx
	
	url = f"{base_url.rstrip('/')}{service_path}"
	headers = {
		"Authorization": f"Bearer {api_key}",
		"Content-Type": "application/json",
	}
	
	try:
		with httpx.Client(timeout=30.0) as client:
			response = client.post(url, json=request_data, headers=headers)
			response.raise_for_status()
			return response.json()
	except httpx.HTTPError as e:
		logger.error(f"خطا در فراخوانی API زحل: {e}")
		raise ApiError("ZOHAL_API_ERROR", f"خطا در فراخوانی API زحل: {str(e)}", http_status=500)


def execute_zohal_inquiry(
	db: Session,
	business_id: int,
	user_id: int,
	service_code: str,
	request_data: Dict[str, Any],
) -> Dict[str, Any]:
	"""
	اجرای یک استعلام زحل
	این تابع:
	1. بررسی می‌کند سرویس فعال است
	2. بررسی می‌کند موجودی کیف پول کافی است
	3. فراخوانی API زحل
	4. کسر از کیف پول و ایجاد سند حسابداری
	5. ثبت لاگ
	"""
	from app.services.system_settings_service import get_zohal_settings
	from app.services.wallet_service import get_wallet_overview, charge_wallet_for_zohal_service
	
	# دریافت سرویس
	service = get_zohal_service_by_code(db, service_code)
	if not service:
		raise ApiError("SERVICE_NOT_FOUND", "سرویس یافت نشد", http_status=404)
	
	if not service.is_active:
		raise ApiError("SERVICE_DISABLED", "این سرویس در حال حاضر غیرفعال است", http_status=400)
	
	# دریافت تنظیمات زحل
	zohal_settings = get_zohal_settings(db)
	api_key = zohal_settings.get("api_key")
	base_url = zohal_settings.get("base_url")
	
	if not api_key:
		raise ApiError("ZOHAL_API_KEY_NOT_SET", "کلید API زحل تنظیم نشده است", http_status=500)
	
	# بررسی موجودی کیف پول
	wallet = get_wallet_overview(db, business_id)
	wallet_balance = Decimal(str(wallet.get("available_balance", 0)))
	service_price = service.base_price
	
	# تبدیل قیمت به ارز کیف پول (در صورت نیاز)
	wallet_currency_id = wallet.get("base_currency_id")
	if service.currency_id != wallet_currency_id:
		# TODO: تبدیل ارز
		charge_amount = service_price
	else:
		charge_amount = service_price
	
	if wallet_balance < charge_amount:
		raise ApiError(
			"INSUFFICIENT_BALANCE",
			f"موجودی کیف پول کافی نیست. موجودی: {wallet_balance}, هزینه: {charge_amount}",
			http_status=400
		)
	
	# فراخوانی API زحل
	try:
		zohal_response = call_zohal_api(
			base_url=base_url,
			api_key=api_key,
			service_path=service.service_path,
			request_data=request_data,
		)
	except Exception as e:
		# ثبت لاگ خطا
		log = ZohalServiceLog(
			business_id=business_id,
			service_id=service.id,
			user_id=user_id,
			request_data=request_data,
			response_data={"error": str(e)},
			status="error",
			error_message=str(e),
			amount_charged=Decimal("0"),
			currency_id=wallet_currency_id,
		)
		db.add(log)
		db.commit()
		raise
	
	# بررسی موفقیت پاسخ
	result = zohal_response.get("result")
	response_body = zohal_response.get("response_body", {})
	
	if result != 1:
		# استعلام ناموفق بود اما هزینه کسر نمی‌شود
		error_code = response_body.get("error_code")
		message = response_body.get("message", "خطا در استعلام")
		
		log = ZohalServiceLog(
			business_id=business_id,
			service_id=service.id,
			user_id=user_id,
			request_data=request_data,
			response_data=zohal_response,
			status="failed",
			error_message=message,
			amount_charged=Decimal("0"),
			currency_id=wallet_currency_id,
		)
		db.add(log)
		db.commit()
		
		return {
			"success": False,
			"service_name": service.service_name,
			"result": zohal_response,
			"amount_charged": 0,
			"log_id": log.id,
		}
	
	# استعلام موفق - کسر از کیف پول و ایجاد سند
	charge_result = charge_wallet_for_zohal_service(
		db=db,
		business_id=business_id,
		user_id=user_id,
		amount=charge_amount,
		service_id=service.id,
		service_name=service.service_name,
		description=f"هزینه سرویس {service.service_name}",
	)
	
	# ثبت لاگ موفق
	log = ZohalServiceLog(
		business_id=business_id,
		service_id=service.id,
		user_id=user_id,
		request_data=request_data,
		response_data=zohal_response,
		status="success",
		error_message=None,
		amount_charged=charge_amount,
		currency_id=wallet_currency_id,
		wallet_transaction_id=charge_result.get("wallet_transaction_id"),
		document_id=charge_result.get("document_id"),
	)
	db.add(log)
	db.commit()
	
	# بررسی موجودی کم
	wallet_after = get_wallet_overview(db, business_id)
	low_balance_threshold = Decimal(str(zohal_settings.get("low_balance_threshold", 10000)))
	low_balance_warning = wallet_after.get("available_balance", 0) < low_balance_threshold
	
	return {
		"success": True,
		"service_name": service.service_name,
		"result": zohal_response,
		"amount_charged": float(charge_amount),
		"remaining_balance": float(wallet_after.get("available_balance", 0)),
		"low_balance_warning": low_balance_warning,
		"log_id": log.id,
	}


def list_zohal_service_logs(
	db: Session,
	business_id: int,
	service_id: Optional[int] = None,
	start_date: Optional[str] = None,
	end_date: Optional[str] = None,
	limit: int = 50,
	skip: int = 0,
) -> Dict[str, Any]:
	"""
	لیست لاگ‌های استفاده از سرویس‌های زحل
	"""
	from datetime import datetime
	
	query = select(ZohalServiceLog).options(
		selectinload(ZohalServiceLog.service),
		selectinload(ZohalServiceLog.currency)
	).where(ZohalServiceLog.business_id == business_id)
	
	if service_id:
		query = query.where(ZohalServiceLog.service_id == service_id)
	
	if start_date:
		try:
			start_dt = datetime.fromisoformat(start_date.replace('Z', '+00:00'))
			query = query.where(ZohalServiceLog.created_at >= start_dt)
		except Exception:
			pass
	
	if end_date:
		try:
			end_dt = datetime.fromisoformat(end_date.replace('Z', '+00:00'))
			query = query.where(ZohalServiceLog.created_at <= end_dt)
		except Exception:
			pass
	
	query = query.order_by(ZohalServiceLog.created_at.desc())
	
	total = db.execute(select(func.count()).select_from(query.subquery())).scalar() or 0
	
	logs = db.execute(query.limit(limit).offset(skip)).scalars().all()
	
	result = []
	for log in logs:
		result.append({
			"id": log.id,
			"service_id": log.service_id,
			"service_name": log.service.service_name if log.service else None,
			"service_code": log.service.service_code if log.service else None,
			"status": log.status,
			"error_message": log.error_message,
			"amount_charged": float(log.amount_charged),
			"currency_code": log.currency.code if log.currency else None,
			"request_data": log.request_data,
			"response_data": log.response_data,
			"wallet_transaction_id": log.wallet_transaction_id,
			"document_id": log.document_id,
			"created_at": log.created_at.isoformat() if log.created_at else None,
		})
	
	return {
		"items": result,
		"total": total,
		"limit": limit,
		"skip": skip,
	}


def get_zohal_statistics(
	db: Session,
	start_date: Optional[str] = None,
	end_date: Optional[str] = None,
	business_id: Optional[int] = None,
	service_id: Optional[int] = None,
) -> Dict[str, Any]:
	"""
	آمار استفاده از سرویس‌های زحل
	"""
	from datetime import datetime
	
	query = select(ZohalServiceLog).options(
		selectinload(ZohalServiceLog.service),
		selectinload(ZohalServiceLog.business)
	)
	
	if business_id:
		query = query.where(ZohalServiceLog.business_id == business_id)
	
	if service_id:
		query = query.where(ZohalServiceLog.service_id == service_id)
	
	if start_date:
		try:
			start_dt = datetime.fromisoformat(start_date.replace('Z', '+00:00'))
			query = query.where(ZohalServiceLog.created_at >= start_dt)
		except Exception:
			pass
	
	if end_date:
		try:
			end_dt = datetime.fromisoformat(end_date.replace('Z', '+00:00'))
			query = query.where(ZohalServiceLog.created_at <= end_dt)
		except Exception:
			pass
	
	logs = db.execute(query).scalars().all()
	
	# محاسبه آمار
	total_requests = len(logs)
	successful_requests = len([l for l in logs if l.status == "success"])
	failed_requests = len([l for l in logs if l.status in ["failed", "error"]])
	total_revenue = sum([float(l.amount_charged) for l in logs if l.status == "success"])
	
	# آمار به تفکیک سرویس
	by_service = {}
	for log in logs:
		if log.status == "success":
			service_name = log.service.service_name if log.service else "نامشخص"
			if service_name not in by_service:
				by_service[service_name] = {
					"service_id": log.service_id,
					"service_name": service_name,
					"request_count": 0,
					"revenue": 0.0,
				}
			by_service[service_name]["request_count"] += 1
			by_service[service_name]["revenue"] += float(log.amount_charged)
	
	# آمار به تفکیک کسب‌وکار
	by_business = {}
	for log in logs:
		if log.status == "success":
			business_name = log.business.name if log.business else "نامشخص"
			if business_name not in by_business:
				by_business[business_name] = {
					"business_id": log.business_id,
					"business_name": business_name,
					"request_count": 0,
					"revenue": 0.0,
				}
			by_business[business_name]["request_count"] += 1
			by_business[business_name]["revenue"] += float(log.amount_charged)
	
	# آمار روزانه
	daily_usage = {}
	for log in logs:
		if log.status == "success":
			date_key = log.created_at.date().isoformat() if log.created_at else None
			if date_key:
				if date_key not in daily_usage:
					daily_usage[date_key] = {
						"date": date_key,
						"count": 0,
						"revenue": 0.0,
					}
				daily_usage[date_key]["count"] += 1
				daily_usage[date_key]["revenue"] += float(log.amount_charged)
	
	return {
		"total_requests": total_requests,
		"successful_requests": successful_requests,
		"failed_requests": failed_requests,
		"total_revenue": total_revenue,
		"by_service": list(by_service.values()),
		"by_business": list(by_business.values()),
		"daily_usage": list(daily_usage.values()),
	}


def get_zohal_service_log(db: Session, log_id: int, business_id: int) -> Dict[str, Any]:
	"""
	دریافت اطلاعات یک لاگ
	"""
	log = db.execute(
		select(ZohalServiceLog).options(
			selectinload(ZohalServiceLog.service),
			selectinload(ZohalServiceLog.currency)
		).where(
			and_(
				ZohalServiceLog.id == log_id,
				ZohalServiceLog.business_id == business_id,
			)
		)
	).scalars().first()
	
	if not log:
		raise ApiError("LOG_NOT_FOUND", "لاگ یافت نشد", http_status=404)
	
	return {
		"id": log.id,
		"service_id": log.service_id,
		"service_name": log.service.service_name if log.service else None,
		"service_code": log.service.service_code if log.service else None,
		"status": log.status,
		"error_message": log.error_message,
		"amount_charged": float(log.amount_charged),
		"currency_code": log.currency.code if log.currency else None,
		"request_data": log.request_data,
		"response_data": log.response_data,
		"wallet_transaction_id": log.wallet_transaction_id,
		"document_id": log.document_id,
		"created_at": log.created_at.isoformat() if log.created_at else None,
	}

