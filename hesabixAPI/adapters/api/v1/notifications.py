from __future__ import annotations

from typing import Any, Dict, Optional
from fastapi import APIRouter, Depends, Request, Body, HTTPException, Query
from pydantic import BaseModel
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.responses import success_response, format_datetime_fields
from adapters.db.repositories.notification_repo import (
	UserNotificationSettingRepository,
	UserInappAlertPreferenceRepository,
)
from adapters.db.repositories.notification_outbox_repository import NotificationOutboxRepository
from app.services.notification_service import NotificationService
from adapters.api.v1.schemas import QueryInfo

router = APIRouter(prefix="/notifications", tags=["اطلاع‌رسانی"])


def _valid_inapp_sound_id(s: str) -> bool:
	if s == "default":
		return True
	if s.startswith("s_") and s[2:].isdigit():
		n = int(s[2:])
		return 1 <= n <= 27
	return False


class SettingsPayload(BaseModel):
	telegram_enabled: Optional[bool] = None
	bale_enabled: Optional[bool] = None
	email_enabled: Optional[bool] = None
	sms_enabled: Optional[bool] = None
	inapp_enabled: Optional[bool] = None
	inapp_alert_mode: Optional[str] = None  # normal | silent | do_not_disturb
	inapp_sound_enabled: Optional[bool] = None
	inapp_sound_asset_id: Optional[str] = None  # default یا s_1 … s_27


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
	inapp_prefs_repo = UserInappAlertPreferenceRepository(db)
	mode, sound_on, sound_id = inapp_prefs_repo.get_or_defaults(user_id=user_id)
	rows = repo.list_for_user(user_id=user_id)
	
	# Defaults: بر اساس وضعیت احراز هویت
	# اگر موبایل تایید نشده باشد، SMS غیرفعال
	# اگر ایمیل تایید نشده باشد، Email غیرفعال
	# Telegram و InApp همیشه فعال هستند (نیازی به احراز هویت ندارند)
	res = {
		"telegram_enabled": True,
		"bale_enabled": True,
		"email_enabled": email_verified,
		"sms_enabled": mobile_verified,
		"inapp_enabled": True,
	}
	
	# اعمال تنظیمات ذخیره شده کاربر
	for r in rows:
		if r.event_key is None:
			if r.channel == "telegram":
				res["telegram_enabled"] = r.enabled
			elif r.channel == "bale":
				res["bale_enabled"] = r.enabled
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
	res["inapp_alert_mode"] = mode
	res["inapp_sound_enabled"] = sound_on
	res["inapp_sound_asset_id"] = sound_id
	
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
	inapp_prefs_repo = UserInappAlertPreferenceRepository(db)
	
	# بررسی و اعمال محدودیت‌ها
	if payload.telegram_enabled is not None:
		repo.upsert(user_id=user_id, channel="telegram", event_key=None, enabled=payload.telegram_enabled)
	if payload.bale_enabled is not None:
		repo.upsert(user_id=user_id, channel="bale", event_key=None, enabled=payload.bale_enabled)
	
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
	
	if any(
		x is not None
		for x in (
			payload.inapp_alert_mode,
			payload.inapp_sound_enabled,
			payload.inapp_sound_asset_id,
		)
	):
		cur_mode, cur_sound_on, cur_sound_id = inapp_prefs_repo.get_or_defaults(user_id=user_id)
		next_mode = payload.inapp_alert_mode if payload.inapp_alert_mode is not None else cur_mode
		next_sound_on = payload.inapp_sound_enabled if payload.inapp_sound_enabled is not None else cur_sound_on
		next_sound_id = payload.inapp_sound_asset_id if payload.inapp_sound_asset_id is not None else cur_sound_id
		if next_mode not in ("normal", "silent", "do_not_disturb"):
			raise ApiError(
				"INVALID_INAPP_ALERT_MODE",
				"حالت هشدار درون‌برنامه‌ای نامعتبر است",
				http_status=400,
			)
		if not _valid_inapp_sound_id(next_sound_id):
			raise ApiError(
				"INVALID_INAPP_SOUND_ID",
				"شناسه صدای هشدار نامعتبر است",
				http_status=400,
			)
		inapp_prefs_repo.upsert(
			user_id=user_id,
			alert_mode=next_mode,
			sound_enabled=next_sound_on,
			sound_asset_id=next_sound_id,
		)
	
	return success_response({"ok": True}, request)


@router.post("/test", summary="ارسال تست نوتیفیکیشن")
def test_notification(
	channel: str = Query(..., pattern="^(telegram|bale|email|sms|inapp)$"),
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


