from __future__ import annotations

from typing import Any, Dict, Optional
from fastapi import APIRouter, Depends, Request, Body, HTTPException, Query
from pydantic import BaseModel
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.responses import success_response, format_datetime_fields
from adapters.db.repositories.notification_repo import UserNotificationSettingRepository
from adapters.db.repositories.notification_outbox_repository import NotificationOutboxRepository
from app.services.notification_service import NotificationService
from adapters.api.v1.schemas import QueryInfo

router = APIRouter(prefix="/notifications", tags=["اطلاع‌رسانی"])


class SettingsPayload(BaseModel):
	telegram_enabled: Optional[bool] = None
	email_enabled: Optional[bool] = None
	sms_enabled: Optional[bool] = None
	inapp_enabled: Optional[bool] = None


@router.get("/settings", summary="دریافت تنظیمات نوتیفیکیشن کاربر")
def get_settings(
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
	user_id = ctx.get_user_id()
	user = ctx.user
	
	# بررسی وضعیت احراز هویت
	email_verified = getattr(user, "email_verified", False)
	mobile_verified = getattr(user, "mobile_verified", False)
	
	repo = UserNotificationSettingRepository(db)
	rows = repo.list_for_user(user_id=user_id)
	
	# Defaults: بر اساس وضعیت احراز هویت
	# اگر موبایل تایید نشده باشد، SMS غیرفعال
	# اگر ایمیل تایید نشده باشد، Email غیرفعال
	# Telegram و InApp همیشه فعال هستند (نیازی به احراز هویت ندارند)
	res = {
		"telegram_enabled": True,  # Telegram همیشه فعال است
		"email_enabled": email_verified,  # Email نیاز به ایمیل تایید شده دارد
		"sms_enabled": mobile_verified,  # SMS نیاز به موبایل تایید شده دارد
		"inapp_enabled": True,  # InApp همیشه فعال است
	}
	
	# اعمال تنظیمات ذخیره شده کاربر
	for r in rows:
		if r.event_key is None:
			if r.channel == "telegram":
				# Telegram همیشه قابل تنظیم است
				res["telegram_enabled"] = r.enabled
			elif r.channel == "email":
				# فقط اگر ایمیل تایید شده باشد، تنظیمات کاربر اعمال می‌شود
				if email_verified:
					res["email_enabled"] = r.enabled
				else:
					res["email_enabled"] = False
			elif r.channel == "sms":
				# فقط اگر موبایل تایید شده باشد، تنظیمات کاربر اعمال می‌شود
				if mobile_verified:
					res["sms_enabled"] = r.enabled
				else:
					res["sms_enabled"] = False
			elif r.channel == "inapp":
				# InApp همیشه قابل تنظیم است
				res["inapp_enabled"] = r.enabled
	
	# افزودن اطلاعات وضعیت احراز هویت به پاسخ
	res["email_verified"] = email_verified
	res["mobile_verified"] = mobile_verified
	
	return success_response(res, request)


@router.put("/settings", summary="به‌روزرسانی تنظیمات نوتیفیکیشن کاربر")
def put_settings(
	payload: SettingsPayload,
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
	from app.core.responses import ApiError
	
	user_id = ctx.get_user_id()
	user = ctx.user
	
	# بررسی وضعیت احراز هویت
	email_verified = getattr(user, "email_verified", False)
	mobile_verified = getattr(user, "mobile_verified", False)
	
	repo = UserNotificationSettingRepository(db)
	
	# بررسی و اعمال محدودیت‌ها
	if payload.telegram_enabled is not None:
		# Telegram همیشه قابل تنظیم است (نیازی به احراز هویت ندارد)
		repo.upsert(user_id=user_id, channel="telegram", event_key=None, enabled=payload.telegram_enabled)
	
	if payload.email_enabled is not None:
		# اگر کاربر می‌خواهد Email را فعال کند اما ایمیل تایید نشده
		if payload.email_enabled and not email_verified:
			raise ApiError(
				"VERIFICATION_REQUIRED",
				"برای فعال کردن نوتیفیکیشن ایمیل، ابتدا باید ایمیل خود را تایید کنید",
				http_status=400
			)
		repo.upsert(user_id=user_id, channel="email", event_key=None, enabled=payload.email_enabled)
	
	if payload.sms_enabled is not None:
		# اگر کاربر می‌خواهد SMS را فعال کند اما موبایل تایید نشده
		if payload.sms_enabled and not mobile_verified:
			raise ApiError(
				"VERIFICATION_REQUIRED",
				"برای فعال کردن نوتیفیکیشن پیامک، ابتدا باید شماره موبایل خود را تایید کنید",
				http_status=400
			)
		repo.upsert(user_id=user_id, channel="sms", event_key=None, enabled=payload.sms_enabled)
	
	if payload.inapp_enabled is not None:
		# InApp همیشه قابل تنظیم است (نیازی به احراز هویت ندارد)
		repo.upsert(user_id=user_id, channel="inapp", event_key=None, enabled=payload.inapp_enabled)
	
	return success_response({"ok": True}, request)


@router.post("/test", summary="ارسال تست نوتیفیکیشن")
def test_notification(
	channel: str = Query(..., pattern="^(telegram|email|sms|inapp)$"),
	request: Request = None,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
	user_id = ctx.get_user_id()
	svc = NotificationService(db)
	svc.send(user_id=user_id, event_key="system.test", context={"subject": "تست نوتیفیکیشن", "message": "این یک پیام تست است"}, preferred_channels=[channel])
	return success_response({"sent": True, "channel": channel}, request)


# Mapping event keys to Persian titles
EVENT_KEY_TITLES = {
	"auth.otp_login": "ورود با OTP",
	"auth.password_reset": "فراموشی کلمه عبور",
	"support.ticket_created": "ایجاد تیکت",
	"support.user_reply": "پاسخ کاربر به تیکت",
	"support.operator_reply": "پاسخ اپراتور به تیکت",
	"system.test": "تست سیستم",
	"email.verification": "تایید ایمیل",
	"business.deleted": "حذف کسب‌وکار",
}


@router.post("/history", summary="دریافت تاریخچه ناتیفیکیشن‌های کاربر")
def get_notification_history(
	request: Request,
	query_info: QueryInfo,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
	"""
	دریافت لیست ناتیفیکیشن‌های ارسال شده به کاربر با قابلیت فیلتر، جستجو، مرتب‌سازی و صفحه‌بندی
	
	پارامترهای QueryInfo:
	- sort_by: فیلد مرتب‌سازی (مثال: created_at, channel, event_key, status)
	- sort_desc: ترتیب نزولی (true/false)
	- take: تعداد رکورد در هر صفحه (پیش‌فرض: 10)
	- skip: تعداد رکورد صرف‌نظر شده (پیش‌فرض: 0)
	- search: عبارت جستجو (جستجو در event_key و payload)
	- search_fields: فیلدهای جستجو (اختیاری)
	- filters: آرایه فیلترها با ساختار:
	  [
		{
		  "property": "channel",
		  "operator": "=",
		  "value": "email"
		},
		{
		  "property": "event_key",
		  "operator": "=",
		  "value": "auth.otp_login"
		},
		{
		  "property": "status",
		  "operator": "=",
		  "value": "sent"
		}
	  ]
	"""
	# دریافت user_id از AuthContext (از API key استخراج شده)
	user_id = ctx.get_user_id()
	
	# امنیت: اطمینان از اینکه user_id معتبر است
	if not user_id or user_id <= 0:
		from app.core.responses import ApiError
		raise ApiError("UNAUTHORIZED", "Invalid user context", http_status=401)
	
	repo = NotificationOutboxRepository(db)
	
	# دریافت لیست ناتیفیکیشن‌ها
	# Repository به صورت خودکار فیلتر user_id را اعمال می‌کند
	# و هرگونه فیلتر user_id که کاربر ارسال کرده را نادیده می‌گیرد
	notifications, total = repo.list_for_user(user_id, query_info)
	
	# تبدیل به dictionary و افزودن عنوان فارسی event_key
	items = []
	for notif in notifications:
		item = {
			"id": notif.id,
			"channel": notif.channel,
			"event_key": notif.event_key,
			"event_title": EVENT_KEY_TITLES.get(notif.event_key, notif.event_key),
			"status": notif.status,
			"created_at": notif.created_at.isoformat() if notif.created_at else None,
			"updated_at": notif.updated_at.isoformat() if notif.updated_at else None,
			"payload": notif.payload,
			"error_message": notif.error_message,
			"retry_count": notif.retry_count,
		}
		items.append(item)
	
	# محاسبه pagination
	page = (query_info.skip // query_info.take) + 1 if query_info.take > 0 else 1
	total_pages = (total + query_info.take - 1) // query_info.take if query_info.take > 0 else 1
	
	# فرمت کردن تاریخ‌ها
	formatted_items = [format_datetime_fields(item, request) for item in items]
	
	response_data = {
		"items": formatted_items,
		"pagination": {
			"total": total,
			"page": page,
			"per_page": query_info.take,
			"total_pages": total_pages,
			"has_next": page < total_pages,
			"has_prev": page > 1,
		},
	}
	
	return success_response(response_data, request)


