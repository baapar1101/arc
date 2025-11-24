from __future__ import annotations

from typing import Dict, Any
from urllib.parse import urlsplit, urlunsplit
import structlog

from fastapi import APIRouter, Depends, Body, Request
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.responses import success_response, ApiError
from pydantic import BaseModel
from app.services.system_settings_service import (
	get_wallet_settings,
	set_wallet_base_currency_code,
	get_notifications_settings,
	set_notifications_settings,
	get_share_link_settings,
	set_share_link_settings,
	get_effective_notifications_settings,
)
from app.services.providers.telegram_provider import TelegramProvider

logger = structlog.get_logger()


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
	telegram_proxy_enabled: bool | None = None
	telegram_proxy_base_url: str | None = None
	telegram_proxy_api_key: str | None = None


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
		raise ApiError("FORBIDDEN", "Missing permission: system_settings", http_status=403)
	data = get_notifications_settings(db)
	return success_response(data, request)


class ShareLinkSettingsPayload(BaseModel):
	public_app_url: str


@router.get(
	"/share-links",
	summary="دریافت تنظیمات لینک‌های اشتراک عمومی",
	description="بازگرداندن آدرس مقصدی که لینک کوتاه پس از کلیک به آن هدایت می‌شود (افزونه Flutter Web).",
)
def get_share_link_settings_endpoint(
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	if not ctx.has_any_permission("system_settings", "superadmin"):
		raise ApiError("FORBIDDEN", "Missing permission: system_settings", http_status=403)
	data = get_share_link_settings(db)
	return success_response(data, request)


@router.put(
	"/share-links",
	summary="تنظیم آدرس اپلیکیشن عمومی لینک اشتراک",
	description="ثبت آدرس مقصد برای نمایش کارت حساب (مثلاً https://app.hesabix.com/public).",
)
def set_share_link_settings_endpoint(
	payload: ShareLinkSettingsPayload,
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	if not ctx.has_any_permission("system_settings", "superadmin"):
		raise ApiError("FORBIDDEN", "Missing permission: system_settings", http_status=403)
	data = set_share_link_settings(db, public_app_url=payload.public_app_url)
	return success_response(data, request, message="SHARE_LINK_PUBLIC_APP_URL_UPDATED")


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
		telegram_proxy_enabled=payload.telegram_proxy_enabled,
		telegram_proxy_base_url=payload.telegram_proxy_base_url,
		telegram_proxy_api_key=payload.telegram_proxy_api_key,
	)
	return success_response(data, request)


@router.post(
	"/notifications/telegram/webhook",
	summary="ثبت وب‌هوک تلگرام از طریق API",
	description="با استفاده از کانفیگ فعلی، آدرس وب‌هوک به سرور تلگرام اعلام می‌شود و نتیجه برگردانده می‌شود.",
)
def register_telegram_webhook_endpoint(
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	if not ctx.has_any_permission("system_settings", "superadmin"):
		raise ApiError("FORBIDDEN", "Missing permission: system_settings", http_status=403)

	logger.info("telegram_webhook_register_start", user_id=ctx.get_user_id())
	
	cfg = get_effective_notifications_settings(db)
	bot_token = cfg.get("telegram_bot_token")
	webhook_secret = cfg.get("telegram_webhook_secret")

	if not bot_token:
		logger.error("telegram_webhook_register_failed", reason="bot_token_missing")
		raise ApiError("TELEGRAM_BOT_TOKEN_MISSING", "توکن ربات تلگرام تنظیم نشده است.", http_status=400)
	if not webhook_secret:
		logger.error("telegram_webhook_register_failed", reason="webhook_secret_missing")
		raise ApiError("TELEGRAM_WEBHOOK_SECRET_MISSING", "رمز وب‌هوک تلگرام تنظیم نشده است.", http_status=400)

	proxy_cfg = cfg.get("telegram_proxy") or {}
	proxy_enabled = bool(proxy_cfg.get("enabled") and proxy_cfg.get("base_url"))
	
	logger.info("telegram_webhook_register_config", 
		proxy_enabled=proxy_enabled,
		proxy_base_url=proxy_cfg.get("base_url"),
		has_secret_header=bool(cfg.get("telegram_secret_header"))
	)

	if proxy_enabled:
		base_url = str(proxy_cfg.get("base_url")).rstrip("/")
		webhook_url = f"{base_url}/telegram/webhook"
		logger.info("telegram_webhook_url_proxy_mode", webhook_url=webhook_url, proxy_base_url=base_url)
	else:
		webhook_url = str(request.url_for("telegram_webhook", secret=webhook_secret))
		forwarded_proto = request.headers.get("X-Forwarded-Proto")
		if forwarded_proto:
			normalized_proto = forwarded_proto.lower()
			if normalized_proto in {"http", "https"}:
				parts = urlsplit(webhook_url)
				webhook_url = urlunsplit(
					(normalized_proto, parts.netloc, parts.path, parts.query, parts.fragment)
				)
		logger.info("telegram_webhook_url_direct_mode", webhook_url=webhook_url)

	logger.info("telegram_webhook_register_calling", webhook_url=webhook_url, proxy_enabled=proxy_enabled)
	
	provider = TelegramProvider(bot_token=bot_token, proxy_config=proxy_cfg if proxy_enabled else None)
	ok, description = provider.set_webhook(
		url=webhook_url,
		secret_token=cfg.get("telegram_secret_header"),
	)
	
	if ok:
		logger.info("telegram_webhook_register_success", webhook_url=webhook_url)
	else:
		logger.error("telegram_webhook_register_failed", 
			webhook_url=webhook_url,
			error=description,
			proxy_enabled=proxy_enabled
		)
	
	data = {
		"ok": ok,
		"webhook_url": webhook_url,
		"description": description,
	}
	message = "TELEGRAM_WEBHOOK_REGISTERED" if ok else "TELEGRAM_WEBHOOK_FAILED"
	return success_response(data, request, message=message)
