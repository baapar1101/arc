from __future__ import annotations

from typing import Dict, Any

from fastapi import APIRouter, Depends, Body, Request
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.responses import success_response
from pydantic import BaseModel
from app.services.system_settings_service import (
	get_wallet_settings,
	set_wallet_base_currency_code,
	get_notifications_settings,
	set_notifications_settings,
)


router = APIRouter(prefix="/admin/system-settings", tags=["admin-system-settings"])


@router.get(
	"/wallet",
	summary="دریافت تنظیمات کیف‌پول (ارز پایه)",
	description="خواندن ارز پایه کیف‌پول. اگر تنظیم نشده باشد IRR بازگردانده می‌شود.",
)
def get_wallet_settings_endpoint(
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	if not ctx.has_any_permission("system_settings", "superadmin"):
		from app.core.responses import ApiError
		raise ApiError("FORBIDDEN", "Missing permission: system_settings", http_status=403)
	data = get_wallet_settings(db)
	return success_response(data, request)


@router.put(
	"/wallet",
	summary="تنظیم ارز پایه کیف‌پول",
	description="تنظیم کد ارز پایه کیف‌پول (مثلاً IRR). تنها برای مدیر سیستم.",
)
def set_wallet_settings_endpoint(
	request: Request,
	payload: Dict[str, Any] = Body(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	if not ctx.has_any_permission("system_settings", "superadmin"):
		from app.core.responses import ApiError
		raise ApiError("FORBIDDEN", "Missing permission: system_settings", http_status=403)
	code = str(payload.get("wallet_base_currency_code") or "").strip().upper()
	data = set_wallet_base_currency_code(db, code)
	return success_response(data, request, message="WALLET_BASE_CURRENCY_UPDATED")

class NotificationsConfigPayload(BaseModel):
	telegram_bot_token: str | None = None
	telegram_bot_username: str | None = None
	telegram_webhook_secret: str | None = None
	telegram_secret_header: str | None = None
	sms_provider_name: str | None = None
	sms_api_key: str | None = None
	sms_sender: str | None = None


@router.get(
	"/notifications",
	summary="دریافت تنظیمات یکپارچه‌سازی نوتیفیکیشن‌ها (تلگرام/SMS)",
	description="خواندن کانفیگ‌های ربات تلگرام و SMS از تنظیمات سیستم",
)
def get_notifications_settings_endpoint(
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	if not ctx.has_any_permission("system_settings", "superadmin"):
		from app.core.responses import ApiError
		raise ApiError("FORBIDDEN", "Missing permission: system_settings", http_status=403)
	data = get_notifications_settings(db)
	return success_response(data, request)


@router.put(
	"/notifications",
	summary="تنظیم کانفیگ‌های ربات تلگرام و SMS",
	description="ذخیره تنظیمات یکپارچه‌سازی نوتیفیکیشن‌ها. توجه: تغییرات ممکن است نیاز به راه‌اندازی مجدد سرویس داشته باشد.",
)
def put_notifications_settings_endpoint(
	payload: NotificationsConfigPayload,
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	if not ctx.has_any_permission("system_settings", "superadmin"):
		from app.core.responses import ApiError
		raise ApiError("FORBIDDEN", "Missing permission: system_settings", http_status=403)
	data = set_notifications_settings(
		db,
		telegram_bot_token=payload.telegram_bot_token,
		telegram_bot_username=payload.telegram_bot_username,
		telegram_webhook_secret=payload.telegram_webhook_secret,
		telegram_secret_header=payload.telegram_secret_header,
		sms_provider_name=payload.sms_provider_name,
		sms_api_key=payload.sms_api_key,
		sms_sender=payload.sms_sender,
	)
	return success_response(data, request)
