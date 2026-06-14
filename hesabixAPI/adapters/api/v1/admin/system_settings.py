from __future__ import annotations

from typing import Dict, Any, Optional
from urllib.parse import urlsplit, urlunsplit
import structlog

from fastapi import APIRouter, Depends, Body, Request, Query, UploadFile, File, BackgroundTasks
from fastapi.responses import Response
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.responses import success_response, ApiError
from app.services.database_backup_service import DatabaseBackupService, DatabaseBackupError
from app.services.database_restore_service import (
	DatabaseRestoreService,
	DatabaseRestoreError,
	CONFIRMATION_TOKEN,
	CONFIRMATION_TOKEN_EN,
)
from app.services.job_manager import JobManager
from pydantic import BaseModel, Field
from app.services.auth_security_event_service import get_auth_security_report
from app.services.system_settings_service import (
	get_wallet_settings,
	set_wallet_base_currency_code,
	get_notifications_settings,
	set_notifications_settings,
	get_share_link_settings,
	set_share_link_settings,
	get_marketplace_settings,
	set_marketplace_settings,
	get_effective_notifications_settings,
	get_system_configuration,
	set_system_configuration,
	get_redis_configuration,
	set_redis_configuration,
	get_zohal_settings,
	set_zohal_settings,
	get_notification_sms_pricing,
	set_notification_sms_pricing,
)
from app.services.providers.telegram_provider import TelegramProvider
from app.services.providers.bale_provider import BaleProvider

logger = structlog.get_logger()


router = APIRouter(prefix="/admin/system-settings", tags=["مدیریت سیستم"])


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
	bale_bot_token: str | None = None
	bale_bot_username: str | None = None
	bale_webhook_secret: str | None = None
	sms_provider_name: str | None = None
	sms_api_key: str | None = None
	sms_sender: str | None = None
	sms_provider_username: str | None = None
	sms_provider_password: str | None = None
	sms_is_flash: bool | None = None
	telegram_proxy_enabled: bool | None = None
	telegram_proxy_base_url: str | None = None
	telegram_proxy_api_key: str | None = None
	inapp_read_retention_enabled: bool | None = None
	inapp_read_retention_days: int | None = None


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
	invoice_gateway_fee_percent: Optional[float] = Field(
		default=None,
		ge=0,
		le=100,
		description="درصد کارمزد درگاه برای پرداخت آنلاین از لینک فاکتور (۰ تا ۱۰۰). خالی = بدون تغییر",
	)


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
	data = set_share_link_settings(
		db,
		public_app_url=payload.public_app_url,
		invoice_gateway_fee_percent=payload.invoice_gateway_fee_percent,
	)
	return success_response(data, request, message="SHARE_LINK_PUBLIC_APP_URL_UPDATED")


class MarketplaceSettingsPayload(BaseModel):
	publisher_share_percent: float = Field(
		ge=0,
		le=100,
		description="درصد سهم ناشر از فروش مهارت AI (۰ تا ۱۰۰)",
	)


@router.get(
	"/marketplace",
	summary="تنظیمات مارکت‌پلیس",
	description="درصد سهم ناشر از فروش مهارت‌های AI و سایر تنظیمات مارکت‌پلیس",
)
def get_marketplace_settings_endpoint(
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	if not ctx.has_any_permission("system_settings", "superadmin"):
		raise ApiError("FORBIDDEN", "Missing permission: system_settings", http_status=403)
	data = get_marketplace_settings(db)
	return success_response(data, request)


@router.put(
	"/marketplace",
	summary="به‌روزرسانی تنظیمات مارکت‌پلیس",
)
def set_marketplace_settings_endpoint(
	payload: MarketplaceSettingsPayload,
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	if not ctx.has_any_permission("system_settings", "superadmin"):
		raise ApiError("FORBIDDEN", "Missing permission: system_settings", http_status=403)
	data = set_marketplace_settings(
		db,
		publisher_share_percent=payload.publisher_share_percent,
	)
	return success_response(data, request, message="MARKETPLACE_SETTINGS_UPDATED")


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
		bale_bot_token=payload.bale_bot_token,
		bale_bot_username=payload.bale_bot_username,
		bale_webhook_secret=payload.bale_webhook_secret,
		sms_provider_name=payload.sms_provider_name,
		sms_api_key=payload.sms_api_key,
		sms_sender=payload.sms_sender,
		sms_provider_username=payload.sms_provider_username,
		sms_provider_password=payload.sms_provider_password,
		sms_is_flash=payload.sms_is_flash,
		telegram_proxy_enabled=payload.telegram_proxy_enabled,
		telegram_proxy_base_url=payload.telegram_proxy_base_url,
		telegram_proxy_api_key=payload.telegram_proxy_api_key,
		inapp_read_retention_enabled=payload.inapp_read_retention_enabled,
		inapp_read_retention_days=payload.inapp_read_retention_days,
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
		else:
			# اگر X-Forwarded-Proto وجود ندارد، از scheme فعلی request استفاده می‌کنیم
			# و اگر http است، به https تبدیل می‌کنیم (برای امنیت)
			parts = urlsplit(webhook_url)
			current_scheme = parts.scheme or (request.url.scheme if request.url else "https")
			# اگر http است، به https تبدیل می‌کنیم
			if current_scheme == "http":
				current_scheme = "https"
			webhook_url = urlunsplit(
				(current_scheme, parts.netloc, parts.path, parts.query, parts.fragment)
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
		cmd_ok = provider.set_my_commands(
			[
				{"command": "menu", "description": "منوی اصلی"},
				{"command": "crmchat", "description": "چت وب CRM (اپراتور ویجت)"},
				{"command": "bizpick", "description": "فهرست انتخاب کسب‌وکار"},
				{"command": "crmhelp", "description": "راهنما و دکمه\u200cهای چت وب"},
				{"command": "help", "description": "راهنمای ربات"},
			]
		)
		logger.info("telegram_bot_commands_registered", ok=cmd_ok)
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


@router.post(
	"/notifications/bale/webhook",
	summary="ثبت وب‌هوک بله",
	description="با استفاده از کانفیگ فعلی، آدرس وب‌هوک به سرور بله اعلام می‌شود. پورت‌های مجاز: 443، 88",
)
def register_bale_webhook_endpoint(
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	if not ctx.has_any_permission("system_settings", "superadmin"):
		raise ApiError("FORBIDDEN", "Missing permission: system_settings", http_status=403)

	cfg = get_effective_notifications_settings(db)
	bot_token = cfg.get("bale_bot_token")
	webhook_secret = cfg.get("bale_webhook_secret")

	if not bot_token:
		raise ApiError("BALE_BOT_TOKEN_MISSING", "توکن ربات بله تنظیم نشده است.", http_status=400)
	if not webhook_secret:
		raise ApiError("BALE_WEBHOOK_SECRET_MISSING", "رمز وب‌هوک بله تنظیم نشده است.", http_status=400)

	webhook_url = str(request.url_for("bale_webhook", secret=webhook_secret))
	forwarded_proto = request.headers.get("X-Forwarded-Proto")
	if forwarded_proto and forwarded_proto.lower() in ("http", "https"):
		parts = urlsplit(webhook_url)
		webhook_url = urlunsplit(
			(forwarded_proto.lower(), parts.netloc, parts.path, parts.query, parts.fragment)
		)
	else:
		parts = urlsplit(webhook_url)
		scheme = parts.scheme or (getattr(request.url, "scheme", None) or "https")
		if scheme == "http":
			scheme = "https"
		webhook_url = urlunsplit((scheme, parts.netloc, parts.path, parts.query, parts.fragment))

	provider = BaleProvider(bot_token=bot_token)
	ok, description = provider.set_webhook(url=webhook_url)

	data = {
		"ok": ok,
		"webhook_url": webhook_url,
		"description": description,
	}
	message = "BALE_WEBHOOK_REGISTERED" if ok else "BALE_WEBHOOK_FAILED"
	return success_response(data, request, message=message)


class SystemConfigurationPayload(BaseModel):
	app_name: str | None = None
	app_version: str | None = None
	default_language: str | None = None
	default_theme: str | None = None
	default_timezone: str | None = Field(
		default=None,
		description="نام منطقهٔ زمانی IANA برای نمایش تاریخ/زمان در کل سیستم (مثال Asia/Tehran)",
		max_length=80,
	)
	enable_registration: bool | None = None
	enable_email_verification: bool | None = None
	enable_maintenance_mode: bool | None = None
	support_tickets_enabled: bool | None = Field(
		default=None,
		description="اگر False باشد ثبت/view تیکت برای کاربران عادی قطع می‌شود؛ اپراتور همچنان دسترسی دارد",
	)
	support_tickets_disabled_message: str | None = Field(
		default=None,
		description="متن دلخواه مدیر؛ در صورت خالی نمایش پیش‌فرض در خطا و عمومی برای کاربر",
		max_length=8192,
	)
	session_timeout: int | None = None
	max_file_size: int | None = None
	max_users: int | None = None
	business_creation_verification_requirement: str | None = Field(
		default=None,
		description="کنترل دسترسی ایجاد کسب و کار: none, email_only, mobile_only, both, either"
	)
	sms_destination_rate_enabled: bool | None = None
	sms_destination_rate_max_sends: int | None = None
	sms_destination_rate_window_minutes: int | None = None
	captcha_max_attempts: int | None = None
	captcha_length: int | None = None
	captcha_ttl_seconds: int | None = None
	captcha_mode: str | None = None
	captcha_bind_ip: bool | None = None
	captcha_strong_image: bool | None = None
	captcha_rate_max: int | None = None
	captcha_rate_window_sec: int | None = None
	login_rate_max_short: int | None = None
	login_rate_window_short_sec: int | None = None
	login_rate_max_long: int | None = None
	login_rate_window_long_sec: int | None = None
	register_rate_max: int | None = None
	register_rate_window_sec: int | None = None
	forgot_password_rate_max: int | None = None
	forgot_password_rate_window_sec: int | None = None
	reset_password_rate_max: int | None = None
	reset_password_rate_window_sec: int | None = None
	password_reset_otp_rate_max: int | None = None
	password_reset_otp_rate_window_sec: int | None = None
	login_backoff_max_fails: int | None = None
	login_backoff_window_minutes: int | None = None
	login_backoff_seconds: int | None = None
	firewall_auto_ban_on_login_fail: bool | None = None
	firewall_auto_ban_duration_sec: int | None = Field(None, ge=60, le=86400)


@router.get(
	"/configuration",
	summary="دریافت تنظیمات پیکربندی سیستم",
	description="خواندن تنظیمات عمومی سیستم شامل نام اپلیکیشن، نسخه، زبان پیش‌فرض، تم و سایر تنظیمات.",
)
def get_system_configuration_endpoint(
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	if not ctx.has_any_permission("system_settings", "superadmin"):
		raise ApiError("FORBIDDEN", "Missing permission: system_settings", http_status=403)
	data = get_system_configuration(db)
	return success_response(data, request)


@router.put(
	"/configuration",
	summary="به‌روزرسانی تنظیمات پیکربندی سیستم",
	description="ذخیره تنظیمات عمومی سیستم. تنها برای مدیر سیستم.",
)
def set_system_configuration_endpoint(
	payload: SystemConfigurationPayload,
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	if not ctx.has_any_permission("system_settings", "superadmin"):
		raise ApiError("FORBIDDEN", "Missing permission: system_settings", http_status=403)
	data = set_system_configuration(
		db,
		app_name=payload.app_name,
		app_version=payload.app_version,
		default_language=payload.default_language,
		default_theme=payload.default_theme,
		default_timezone=payload.default_timezone,
		enable_registration=payload.enable_registration,
		enable_email_verification=payload.enable_email_verification,
		enable_maintenance_mode=payload.enable_maintenance_mode,
		support_tickets_enabled=payload.support_tickets_enabled,
		support_tickets_disabled_message=payload.support_tickets_disabled_message,
		session_timeout=payload.session_timeout,
		max_file_size=payload.max_file_size,
		max_users=payload.max_users,
		business_creation_verification_requirement=payload.business_creation_verification_requirement,
		sms_destination_rate_enabled=payload.sms_destination_rate_enabled,
		sms_destination_rate_max_sends=payload.sms_destination_rate_max_sends,
		sms_destination_rate_window_minutes=payload.sms_destination_rate_window_minutes,
		captcha_max_attempts=payload.captcha_max_attempts,
		captcha_length=payload.captcha_length,
		captcha_ttl_seconds=payload.captcha_ttl_seconds,
		captcha_mode=payload.captcha_mode,
		captcha_bind_ip=payload.captcha_bind_ip,
		captcha_strong_image=payload.captcha_strong_image,
		captcha_rate_max=payload.captcha_rate_max,
		captcha_rate_window_sec=payload.captcha_rate_window_sec,
		login_rate_max_short=payload.login_rate_max_short,
		login_rate_window_short_sec=payload.login_rate_window_short_sec,
		login_rate_max_long=payload.login_rate_max_long,
		login_rate_window_long_sec=payload.login_rate_window_long_sec,
		register_rate_max=payload.register_rate_max,
		register_rate_window_sec=payload.register_rate_window_sec,
		forgot_password_rate_max=payload.forgot_password_rate_max,
		forgot_password_rate_window_sec=payload.forgot_password_rate_window_sec,
		reset_password_rate_max=payload.reset_password_rate_max,
		reset_password_rate_window_sec=payload.reset_password_rate_window_sec,
		password_reset_otp_rate_max=payload.password_reset_otp_rate_max,
		password_reset_otp_rate_window_sec=payload.password_reset_otp_rate_window_sec,
		login_backoff_max_fails=payload.login_backoff_max_fails,
		login_backoff_window_minutes=payload.login_backoff_window_minutes,
		login_backoff_seconds=payload.login_backoff_seconds,
		firewall_auto_ban_on_login_fail=payload.firewall_auto_ban_on_login_fail,
		firewall_auto_ban_duration_sec=payload.firewall_auto_ban_duration_sec,
	)
	return success_response(data, request, message="SYSTEM_CONFIGURATION_UPDATED")


@router.get(
	"/auth-security-report",
	summary="گزارش رویدادهای امنیت احراز هویت و کپچا",
	description="آمار و آخرین رویدادها (محدود به مدیر سیستم).",
)
def get_auth_security_report_endpoint(
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	hours: int = Query(24, ge=1, le=2160),
	limit: int = Query(80, ge=1, le=500),
) -> dict:
	if not ctx.has_any_permission("system_settings", "superadmin"):
		raise ApiError("FORBIDDEN", "Missing permission: system_settings", http_status=403)
	data = get_auth_security_report(db, hours=hours, limit=limit)
	return success_response(data, request)


class RedisConfigurationPayload(BaseModel):
	"""Payload برای تنظیمات Redis"""
	enabled: bool | None = None
	host: str | None = None
	port: int | None = None
	db: int | None = None
	password: str | None = None


@router.get(
	"/redis",
	summary="دریافت تنظیمات Redis Cache",
	description="خواندن تنظیمات Redis شامل فعال/غیرفعال بودن، آدرس، پورت، شماره دیتابیس و رمز عبور.",
)
def get_redis_configuration_endpoint(
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	if not ctx.has_any_permission("system_settings", "superadmin"):
		raise ApiError("FORBIDDEN", "Missing permission: system_settings", http_status=403)
	
	data = get_redis_configuration(db)
	# برای امنیت، password را نشان نمی‌دهیم (فقط وجود یا عدم وجود)
	if data.get("password"):
		data["password"] = "***"  # نشان دادن وجود password بدون نمایش آن
	
	return success_response(data, request)


@router.put(
	"/redis",
	summary="به‌روزرسانی تنظیمات Redis Cache",
	description="ذخیره تنظیمات Redis. توجه: تغییرات نیاز به راه‌اندازی مجدد سرویس ندارد و به صورت خودکار اعمال می‌شود.",
)
def set_redis_configuration_endpoint(
	payload: RedisConfigurationPayload,
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	if not ctx.has_any_permission("system_settings", "superadmin"):
		raise ApiError("FORBIDDEN", "Missing permission: system_settings", http_status=403)
	
	# اگر password خالی ارسال شده (برای حذف password)
	password_value = payload.password if payload.password is not None else None
	if password_value == "":
		password_value = None
	
	data = set_redis_configuration(
		db,
		enabled=payload.enabled,
		host=payload.host,
		port=payload.port,
		db_num=payload.db,
		password=password_value,
	)
	
	# تست اتصال Redis بعد از تغییرات
	from app.core.cache import get_redis_client
	redis_client = get_redis_client(force_reconnect=True)
	
	connection_status = "connected" if redis_client else "disconnected"
	if redis_client:
		try:
			redis_client.ping()
			connection_status = "connected"
		except Exception:
			connection_status = "connection_failed"
	
	# برای امنیت، password را نشان نمی‌دهیم
	if data.get("password"):
		data["password"] = "***"
	
	data["connection_status"] = connection_status
	
	return success_response(data, request, message="REDIS_CONFIGURATION_UPDATED")


@router.post(
	"/redis/test",
	summary="تست اتصال Redis",
	description="تست اتصال به Redis با تنظیمات فعلی و برگرداندن وضعیت اتصال.",
)
def test_redis_connection_endpoint(
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	if not ctx.has_any_permission("system_settings", "superadmin"):
		raise ApiError("FORBIDDEN", "Missing permission: system_settings", http_status=403)
	
	from app.core.cache import get_redis_client
	redis_client = get_redis_client(force_reconnect=True)
	
	if not redis_client:
		return success_response({
			"connected": False,
			"message": "Redis is disabled or connection failed"
		}, request)
	
	try:
		# تست ping
		redis_client.ping()
		
		# تست set/get
		test_key = "hesabix:test:connection"
		test_value = "test_value"
		redis_client.setex(test_key, 10, test_value)
		retrieved_value = redis_client.get(test_key)
		redis_client.delete(test_key)
		
		# دریافت اطلاعات سرور
		info = redis_client.info("server")
		redis_version = info.get("redis_version", "unknown")
		
		# دریافت اطلاعات حافظه
		memory_info = redis_client.info("memory")
		used_memory = memory_info.get("used_memory_human", "unknown")
		
		return success_response({
			"connected": True,
			"message": "Redis connection successful",
			"redis_version": redis_version,
			"used_memory": used_memory,
			"test_passed": retrieved_value == test_value
		}, request)
	except Exception as e:
		return success_response({
			"connected": False,
			"message": f"Redis connection test failed: {str(e)}"
		}, request)


class ZohalSettingsPayload(BaseModel):
	api_key: str | None = None
	base_url: str | None = None
	low_balance_threshold: float | None = None


@router.get(
	"/zohal",
	summary="دریافت تنظیمات سرویس زحل",
	description="خواندن تنظیمات API Key و پیکربندی سرویس زحل",
)
def get_zohal_settings_endpoint(
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	if not ctx.has_any_permission("system_settings", "superadmin"):
		raise ApiError("FORBIDDEN", "Missing permission: system_settings", http_status=403)
	data = get_zohal_settings(db)
	return success_response(data, request)


@router.put(
	"/zohal",
	summary="تنظیم پیکربندی سرویس زحل",
	description="تنظیم API Key، آدرس پایه و آستانه موجودی کم برای سرویس زحل",
)
def set_zohal_settings_endpoint(
	request: Request,
	payload: ZohalSettingsPayload,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	if not ctx.has_any_permission("system_settings", "superadmin"):
		raise ApiError("FORBIDDEN", "Missing permission: system_settings", http_status=403)
	data = set_zohal_settings(
		db,
		api_key=payload.api_key,
		base_url=payload.base_url,
		low_balance_threshold=payload.low_balance_threshold,
	)
	return success_response(data, request, message="ZOHAL_SETTINGS_UPDATED")


class NotificationSmsPricingPayload(BaseModel):
	price_per_sms: float | None = Field(None, gt=0, description="قیمت پیش‌فرض هر پیامک")
	event_type_prices: Dict[str, float] | None = Field(None, description="قیمت‌های خاص برای event_type ها")


@router.get(
	"/notification-sms-pricing",
	summary="دریافت تنظیمات قیمت‌گذاری پیامک ناتیفیکیشن",
	description="خواندن قیمت‌گذاری پیامک‌های ناتیفیکیشن کسب‌وکارها",
)
def get_notification_sms_pricing_endpoint(
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	if not ctx.has_any_permission("system_settings", "superadmin"):
		raise ApiError("FORBIDDEN", "Missing permission: system_settings", http_status=403)
	data = get_notification_sms_pricing(db)
	return success_response(data, request)


@router.put(
	"/notification-sms-pricing",
	summary="تنظیم قیمت‌گذاری پیامک ناتیفیکیشن",
	description="تنظیم قیمت هر پیامک برای ناتیفیکیشن‌های کسب‌وکارها. قیمت‌ها بر اساس ارز کیف پول هستند.",
)
def set_notification_sms_pricing_endpoint(
	payload: NotificationSmsPricingPayload,
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	if not ctx.has_any_permission("system_settings", "superadmin"):
		raise ApiError("FORBIDDEN", "Missing permission: system_settings", http_status=403)
	data = set_notification_sms_pricing(
		db,
		price_per_sms=payload.price_per_sms,
		event_type_prices=payload.event_type_prices,
	)
	return success_response(data, request, message="NOTIFICATION_SMS_PRICING_UPDATED")


# --- Database Backup ---


class DatabaseBackupPayload(BaseModel):
	"""Payload اختیاری برای بکاپ. برای email نیاز به email، برای ftp نیاز به storage_config_id."""
	email: Optional[str] = Field(None, description="آدرس ایمیل گیرنده (برای delivery=email)")
	storage_config_id: Optional[str] = Field(None, description="شناسه StorageConfig با نوع ftp (برای delivery=ftp)")


@router.post(
	"/database-backup",
	summary="بکاپ دیتابیس",
	description="ایجاد بکاپ کامل دیتابیس و تحویل به روش download، email یا ftp. تنها برای مدیر سیستم.",
)
def create_database_backup_endpoint(
	request: Request,
	delivery: str = Query(..., description="download | email | ftp"),
	compress: bool = Query(True, description="فشرده‌سازی با gzip"),
	payload: Optional[DatabaseBackupPayload] = Body(None),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
):
	if not ctx.has_any_permission("system_settings", "superadmin"):
		raise ApiError("FORBIDDEN", "Missing permission: system_settings", http_status=403)

	service = DatabaseBackupService(db)
	delivery_lower = (delivery or "").lower().strip()

	try:
		if delivery_lower == "download":
			content, filename = service.deliver_download(compress=compress)
			return Response(
				content=content,
				media_type="application/octet-stream",
				headers={
					"Content-Disposition": f'attachment; filename="{filename}"',
				},
			)

		elif delivery_lower == "email":
			email_val = (payload and payload.email or "").strip()
			if not email_val:
				raise ApiError("EMAIL_REQUIRED", "آدرس ایمیل برای تحویل به ایمیل الزامی است.", http_status=400)
			ok = service.deliver_email(to_email=email_val, compress=compress)
			if not ok:
				raise ApiError("EMAIL_SEND_FAILED", "ارسال ایمیل ناموفق بود.", http_status=500)
			return success_response(
				{"sent": True, "to": email_val},
				request,
				message="DATABASE_BACKUP_EMAIL_SENT",
			)

		elif delivery_lower == "ftp":
			config_id = (payload and payload.storage_config_id or "").strip()
			if not config_id:
				raise ApiError("STORAGE_CONFIG_REQUIRED", "شناسه تنظیمات FTP الزامی است.", http_status=400)
			result = service.deliver_ftp(storage_config_id=config_id, compress=compress)
			return success_response(result, request, message="DATABASE_BACKUP_FTP_UPLOADED")

		else:
			raise ApiError(
				"INVALID_DELIVERY",
				"مقدار delivery باید یکی از download، email یا ftp باشد.",
				http_status=400,
			)

	except DatabaseBackupError as e:
		logger.error("database_backup_endpoint_failed", error=str(e), delivery=delivery_lower)
		raise ApiError("BACKUP_FAILED", str(e), http_status=500)
	except Exception as e:
		logger.exception("database_backup_endpoint_unexpected_error", error=str(e), delivery=delivery_lower)
		raise


@router.post(
	"/database-restore",
	summary="ریستور دیتابیس",
	description="بازیابی کامل دیتابیس از فایل بکاپ .sql یا .sql.gz. نیاز به تأیید. به صورت Job پس‌زمینه اجرا می‌شود. تنها برای superadmin.",
)
async def create_database_restore_endpoint(
	request: Request,
	file: UploadFile = File(..., description="فایل بکاپ .sql یا .sql.gz"),
	confirmation: str = Query(..., description="برای تأیید عبارت 'بازیابی' یا 'RESTORE' را وارد کنید"),
	background_tasks: BackgroundTasks = None,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
):
	if not ctx.is_superadmin():
		raise ApiError("FORBIDDEN", "فقط superadmin می‌تواند ریستور دیتابیس انجام دهد.", http_status=403)

	confirmation_clean = (confirmation or "").strip()
	if confirmation_clean not in (CONFIRMATION_TOKEN, CONFIRMATION_TOKEN_EN):
		raise ApiError(
			"CONFIRMATION_REQUIRED",
			f"برای تأیید ریستور، عبارت '{CONFIRMATION_TOKEN}' یا '{CONFIRMATION_TOKEN_EN}' را وارد کنید.",
			http_status=400,
		)

	filename = (file.filename or "").strip()
	if not filename:
		raise ApiError("FILE_REQUIRED", "فایل بکاپ الزامی است.", http_status=400)

	basename = filename.lower()
	if not (basename.endswith(".sql") or basename.endswith(".sql.gz") or basename.endswith(".gz")):
		raise ApiError(
			"INVALID_FILE_TYPE",
			"فرمت فایل باید .sql یا .sql.gz باشد.",
			http_status=400,
		)

	try:
		content = await file.read()
	except Exception as e:
		raise ApiError("FILE_READ_ERROR", f"خواندن فایل ناموفق بود: {str(e)}", http_status=400) from e

	if len(content) < 100:
		raise ApiError("INVALID_FILE", "فایل بکاپ خیلی کوچک است یا نامعتبر است.", http_status=400)

	# ذخیره در فایل موقت
	import tempfile
	import os
	suffix = ".sql.gz" if basename.endswith(".gz") else ".sql"
	fd, temp_path = tempfile.mkstemp(suffix=suffix)
	try:
		os.write(fd, content)
		os.close(fd)
	except Exception as e:
		try:
			os.close(fd)
		except Exception:
			pass
		raise ApiError("TEMP_FILE_ERROR", f"ذخیره موقت فایل ناموفق بود: {str(e)}", http_status=500) from e

	jm = JobManager.instance()
	job_id = jm.create("ریستور دیتابیس در صف")

	def task():
		try:
			jm.start(job_id, "شروع ریستور دیتابیس")

			def on_progress(percent: int, message: str):
				jm.update(job_id, percent, message)

			service = DatabaseRestoreService(on_progress=on_progress)
			service.restore(temp_path)
			jm.succeed(job_id, {"message": "ریستور با موفقیت انجام شد"})
		except DatabaseRestoreError as e:
			jm.fail(job_id, str(e))
		except Exception as e:
			jm.fail(job_id, str(e))
		finally:
			try:
				os.unlink(temp_path)
			except Exception:
				pass

	background_tasks.add_task(task)

	return success_response(
		{"job_id": job_id, "message": "ریستور در پس‌زمینه شروع شد"},
		request,
		message="DATABASE_RESTORE_STARTED",
	)
