from __future__ import annotations

from typing import Optional, Dict, Any, List
from datetime import datetime
import json
from urllib.parse import urlparse

from sqlalchemy.orm import Session
from sqlalchemy import select

from adapters.db.models.system_setting import SystemSetting
from adapters.db.models.currency import Currency
from app.core.responses import ApiError
from app.core.settings import get_settings
from app.core.cache import get_cache


WALLET_BASE_CURRENCY_KEY = "wallet_base_currency_code"
DEFAULT_WALLET_CURRENCY_CODE = "IRR"
NOTIFY_TG_BOT_TOKEN = "telegram_bot_token"
NOTIFY_TG_BOT_USERNAME = "telegram_bot_username"
NOTIFY_TG_WEBHOOK_SECRET = "telegram_webhook_secret"
NOTIFY_TG_SECRET_HEADER = "telegram_secret_header"
NOTIFY_SMS_PROVIDER = "sms_provider_name"
NOTIFY_SMS_API_KEY = "sms_api_key"
NOTIFY_SMS_SENDER = "sms_sender"
NOTIFY_SMS_PROVIDER_USERNAME = "sms_provider_username"
NOTIFY_SMS_PROVIDER_PASSWORD = "sms_provider_password"
NOTIFY_SMS_IS_FLASH = "sms_is_flash"
NOTIFY_TG_PROXY_ENABLED = "telegram_proxy_enabled"
NOTIFY_TG_PROXY_BASE_URL = "telegram_proxy_base_url"
NOTIFY_TG_PROXY_API_KEY = "telegram_proxy_api_key"
NOTIFY_BALE_BOT_TOKEN = "bale_bot_token"
NOTIFY_BALE_BOT_USERNAME = "bale_bot_username"
NOTIFY_BALE_WEBHOOK_SECRET = "bale_webhook_secret"
NOTIFY_INAPP_READ_RETENTION_ENABLED = "inapp_read_retention_enabled"
NOTIFY_INAPP_READ_RETENTION_DAYS = "inapp_read_retention_days"
DEFAULT_DOCUMENT_POLICIES_KEY = "default_document_monetization_policies"
SHARE_LINK_PUBLIC_APP_URL_KEY = "share_link_public_app_url"

# SMS destination rate limit (optional DB overrides; base values from Settings / env)
SMS_DESTINATION_RATE_ENABLED_KEY = "sms_destination_rate_enabled"
SMS_DESTINATION_RATE_MAX_SENDS_KEY = "sms_destination_rate_max_sends"
SMS_DESTINATION_RATE_WINDOW_MINUTES_KEY = "sms_destination_rate_window_minutes"

# Zohal Service Configuration Keys
ZOHAL_API_KEY = "zohal_api_key"
ZOHAL_BASE_URL = "zohal_base_url"
ZOHAL_LOW_BALANCE_THRESHOLD = "zohal_low_balance_threshold"

# Notification SMS Pricing Configuration Key
NOTIFICATION_SMS_PRICING_KEY = "notification_sms_pricing"

# System Configuration Keys
SYSTEM_CONFIG_APP_NAME = "system_config_app_name"
SYSTEM_CONFIG_APP_VERSION = "system_config_app_version"
SYSTEM_CONFIG_DEFAULT_LANGUAGE = "system_config_default_language"
SYSTEM_CONFIG_DEFAULT_THEME = "system_config_default_theme"
# منطقهٔ زمانی IANA برای نمایش تاریخ/زمان در API (قرارداد: مقادیر naive در DB = UTC)
SYSTEM_CONFIG_DEFAULT_TIMEZONE = "system_config_default_timezone"
SYSTEM_CONFIG_ENABLE_REGISTRATION = "system_config_enable_registration"
SYSTEM_CONFIG_ENABLE_EMAIL_VERIFICATION = "system_config_enable_email_verification"
SYSTEM_CONFIG_ENABLE_MAINTENANCE_MODE = "system_config_enable_maintenance_mode"
SYSTEM_CONFIG_SUPPORT_TICKETS_ENABLED = "system_config_support_tickets_enabled"
SYSTEM_CONFIG_SUPPORT_TICKETS_DISABLED_MESSAGE = "system_config_support_tickets_disabled_message"
SYSTEM_CONFIG_SESSION_TIMEOUT = "system_config_session_timeout"
SYSTEM_CONFIG_MAX_FILE_SIZE = "system_config_max_file_size"
SYSTEM_CONFIG_MAX_USERS = "system_config_max_users"
SYSTEM_CONFIG_BUSINESS_CREATION_VERIFICATION_REQUIREMENT = "system_config_business_creation_verification_requirement"

# کپچا و محدودیت نرخ احراز هویت (قابل تنظیم توسط مدیر)
SYSTEM_CONFIG_CAPTCHA_MAX_ATTEMPTS = "system_config_captcha_max_attempts"
SYSTEM_CONFIG_CAPTCHA_LENGTH = "system_config_captcha_length"
SYSTEM_CONFIG_CAPTCHA_TTL_SECONDS = "system_config_captcha_ttl_seconds"
SYSTEM_CONFIG_CAPTCHA_MODE = "system_config_captcha_mode"
SYSTEM_CONFIG_CAPTCHA_BIND_IP = "system_config_captcha_bind_ip"
SYSTEM_CONFIG_CAPTCHA_STRONG_IMAGE = "system_config_captcha_strong_image"
SYSTEM_CONFIG_CAPTCHA_RATE_MAX = "system_config_captcha_rate_max"
SYSTEM_CONFIG_CAPTCHA_RATE_WINDOW_SEC = "system_config_captcha_rate_window_sec"
SYSTEM_CONFIG_LOGIN_RATE_MAX_SHORT = "system_config_login_rate_max_short"
SYSTEM_CONFIG_LOGIN_RATE_WINDOW_SHORT_SEC = "system_config_login_rate_window_short_sec"
SYSTEM_CONFIG_LOGIN_RATE_MAX_LONG = "system_config_login_rate_max_long"
SYSTEM_CONFIG_LOGIN_RATE_WINDOW_LONG_SEC = "system_config_login_rate_window_long_sec"
SYSTEM_CONFIG_REGISTER_RATE_MAX = "system_config_register_rate_max"
SYSTEM_CONFIG_REGISTER_RATE_WINDOW_SEC = "system_config_register_rate_window_sec"
SYSTEM_CONFIG_FORGOT_RATE_MAX = "system_config_forgot_password_rate_max"
SYSTEM_CONFIG_FORGOT_RATE_WINDOW_SEC = "system_config_forgot_password_rate_window_sec"
SYSTEM_CONFIG_RESET_RATE_MAX = "system_config_reset_password_rate_max"
SYSTEM_CONFIG_RESET_RATE_WINDOW_SEC = "system_config_reset_password_rate_window_sec"
SYSTEM_CONFIG_PR_OTP_RATE_MAX = "system_config_password_reset_otp_rate_max"
SYSTEM_CONFIG_PR_OTP_RATE_WINDOW_SEC = "system_config_password_reset_otp_rate_window_sec"
SYSTEM_CONFIG_LOGIN_BACKOFF_MAX_FAILS = "system_config_login_backoff_max_fails"
SYSTEM_CONFIG_LOGIN_BACKOFF_WINDOW_MINUTES = "system_config_login_backoff_window_minutes"
SYSTEM_CONFIG_LOGIN_BACKOFF_SECONDS = "system_config_login_backoff_seconds"
SYSTEM_CONFIG_FIREWALL_AUTO_BAN_ON_LOGIN_FAIL = "system_config_firewall_auto_ban_on_login_fail"
SYSTEM_CONFIG_FIREWALL_AUTO_BAN_DURATION_SEC = "system_config_firewall_auto_ban_duration_sec"

# Redis Cache Configuration Keys
REDIS_CONFIG_ENABLED = "redis_config_enabled"
REDIS_CONFIG_HOST = "redis_config_host"
REDIS_CONFIG_PORT = "redis_config_port"
REDIS_CONFIG_DB = "redis_config_db"
REDIS_CONFIG_PASSWORD = "redis_config_password"

_SUPPORT_TICKETS_DISABLED_FALLBACK_MESSAGE_FA = "سیستم تیکت‌های پشتیبانی موقتاً غیرفعال است."
MAX_SUPPORT_TICKETS_DISABLED_MESSAGE_LEN = 8192


def is_support_tickets_enabled_for_users(db: Session) -> bool:
	raw = _get_setting_bool(db, SYSTEM_CONFIG_SUPPORT_TICKETS_ENABLED)
	return True if raw is None else raw


def get_support_tickets_disabled_user_message(db: Session) -> str:
	obj = _get_setting(db, SYSTEM_CONFIG_SUPPORT_TICKETS_DISABLED_MESSAGE)
	if obj and obj.value_string and obj.value_string.strip():
		text = obj.value_string.strip()
		return text[:MAX_SUPPORT_TICKETS_DISABLED_MESSAGE_LEN]
	return _SUPPORT_TICKETS_DISABLED_FALLBACK_MESSAGE_FA


def assert_end_user_support_tickets_allowed(db: Session) -> None:
	if is_support_tickets_enabled_for_users(db):
		return
	msg = get_support_tickets_disabled_user_message(db)
	raise ApiError(
		"SUPPORT_TICKETS_DISABLED",
		msg,
		http_status=403,
		details={"user_message": msg},
	)


def support_tickets_public_config_dict(db: Session) -> Dict[str, Any]:
	enabled = is_support_tickets_enabled_for_users(db)
	return {
		"support_tickets_enabled": enabled,
		"support_tickets_disabled_message": "" if enabled else get_support_tickets_disabled_user_message(db),
	}


def _default_share_link_base_url() -> str:
	full = (get_settings().share_link_public_app_url or "").strip().rstrip("/")
	if full.lower().endswith("/public"):
		return full[:-len("/public")].rstrip("/") or full
	return full


def _get_setting(db: Session, key: str) -> Optional[SystemSetting]:
	return db.execute(
		select(SystemSetting).where(SystemSetting.key == key)
	).scalars().first()


def _upsert_setting_string(db: Session, key: str, value: str) -> SystemSetting:
	obj = _get_setting(db, key)
	if obj:
		obj.value_string = value
		obj.value_json = None  # clear json if setting string
	else:
		obj = SystemSetting(key=key, value_string=value)
		db.add(obj)
	db.flush()
	return obj


def _upsert_setting_json(db: Session, key: str, value: Dict[str, Any]) -> SystemSetting:
	obj = _get_setting(db, key)
	json_str = json.dumps(value, ensure_ascii=False)
	if obj:
		obj.value_json = json_str
		obj.value_string = None  # clear string if setting json
	else:
		obj = SystemSetting(key=key, value_json=json_str)
		db.add(obj)
	db.flush()
	return obj


def _get_setting_bool(db: Session, key: str) -> Optional[bool]:
	obj = _get_setting(db, key)
	if obj and obj.value_string is not None:
		val = obj.value_string.strip().lower()
		return val in {"1", "true", "yes", "on"}
	return None


def _upsert_setting_bool(db: Session, key: str, value: bool) -> SystemSetting:
	return _upsert_setting_string(db, key, "true" if value else "false")


def _get_setting_json(db: Session, key: str) -> Optional[Dict[str, Any]]:
	obj = _get_setting(db, key)
	if obj and obj.value_json:
		try:
			return json.loads(obj.value_json)
		except (json.JSONDecodeError, TypeError):
			return None
	return None


def _get_setting_int(db: Session, key: str) -> Optional[int]:
	obj = _get_setting(db, key)
	if obj and obj.value_int is not None:
		return obj.value_int
	if obj and obj.value_string is not None:
		try:
			return int(obj.value_string.strip())
		except (ValueError, TypeError):
			return None
	return None


def _upsert_setting_int(db: Session, key: str, value: int) -> SystemSetting:
	obj = _get_setting(db, key)
	if obj:
		obj.value_int = value
		obj.value_string = None
		obj.value_json = None
	else:
		obj = SystemSetting(key=key, value_int=value)
		db.add(obj)
	db.flush()
	return obj


def get_wallet_settings(db: Session) -> Dict[str, Any]:
	"""
	خواندن تنظیمات کیف‌پول (تنها ارز پایه در این فاز)
	"""
	obj = _get_setting(db, WALLET_BASE_CURRENCY_KEY)
	code = (obj.value_string if obj and obj.value_string else DEFAULT_WALLET_CURRENCY_CODE)
	# resolve currency id (optional)
	currency = db.query(Currency).filter(Currency.code == code).first()
	return {
		"wallet_base_currency_code": code,
		"wallet_base_currency_id": currency.id if currency else None,
		"wallet_base_currency_title": currency.title if currency else None,
		"wallet_base_currency_symbol": currency.symbol if currency else None,
	}


def set_wallet_base_currency_code(db: Session, code: str) -> Dict[str, Any]:
	"""
	تنظیم ارز پایه کیف‌پول با اعتبارسنجی وجود ارز
	"""
	code = str(code or "").strip().upper()
	if not code:
		raise ApiError("CURRENCY_CODE_REQUIRED", "کد ارز الزامی است", http_status=400)
	currency = db.query(Currency).filter(Currency.code == code).first()
	if not currency:
		raise ApiError("CURRENCY_NOT_FOUND", f"ارز با کد {code} یافت نشد", http_status=404)
	_upsert_setting_string(db, WALLET_BASE_CURRENCY_KEY, code)
	db.commit()
	return {
		"wallet_base_currency_code": code,
		"wallet_base_currency_id": currency.id,
	}

def get_notifications_settings(db: Session) -> Dict[str, Any]:
	tg_token = _get_setting(db, NOTIFY_TG_BOT_TOKEN)
	tg_username = _get_setting(db, NOTIFY_TG_BOT_USERNAME)
	tg_webhook = _get_setting(db, NOTIFY_TG_WEBHOOK_SECRET)
	tg_header = _get_setting(db, NOTIFY_TG_SECRET_HEADER)
	sms_provider = _get_setting(db, NOTIFY_SMS_PROVIDER)
	sms_api_key = _get_setting(db, NOTIFY_SMS_API_KEY)
	sms_sender = _get_setting(db, NOTIFY_SMS_SENDER)
	sms_username = _get_setting(db, NOTIFY_SMS_PROVIDER_USERNAME)
	sms_password = _get_setting(db, NOTIFY_SMS_PROVIDER_PASSWORD)
	sms_is_flash = _get_setting_bool(db, NOTIFY_SMS_IS_FLASH)
	tg_proxy_enabled = _get_setting_bool(db, NOTIFY_TG_PROXY_ENABLED)
	tg_proxy_base = _get_setting(db, NOTIFY_TG_PROXY_BASE_URL)
	tg_proxy_api_key = _get_setting(db, NOTIFY_TG_PROXY_API_KEY)
	bale_token = _get_setting(db, NOTIFY_BALE_BOT_TOKEN)
	bale_username = _get_setting(db, NOTIFY_BALE_BOT_USERNAME)
	bale_webhook = _get_setting(db, NOTIFY_BALE_WEBHOOK_SECRET)
	inapp_retention_enabled = _get_setting_bool(db, NOTIFY_INAPP_READ_RETENTION_ENABLED)
	inapp_retention_days = _get_setting_int(db, NOTIFY_INAPP_READ_RETENTION_DAYS)
	return {
		"telegram_bot_token": (tg_token.value_string if tg_token and tg_token.value_string else None),
		"telegram_bot_username": (tg_username.value_string if tg_username and tg_username.value_string else None),
		"telegram_webhook_secret": (tg_webhook.value_string if tg_webhook and tg_webhook.value_string else None),
		"telegram_secret_header": (tg_header.value_string if tg_header and tg_header.value_string else None),
		"sms_provider_name": (sms_provider.value_string if sms_provider and sms_provider.value_string else None),
		"sms_api_key": (sms_api_key.value_string if sms_api_key and sms_api_key.value_string else None),
		"sms_sender": (sms_sender.value_string if sms_sender and sms_sender.value_string else None),
		"sms_provider_username": (sms_username.value_string if sms_username and sms_username.value_string else None),
		"sms_provider_password": (sms_password.value_string if sms_password and sms_password.value_string else None),
		"sms_is_flash": sms_is_flash if sms_is_flash is not None else False,
		"telegram_proxy_enabled": tg_proxy_enabled,
		"telegram_proxy_base_url": (tg_proxy_base.value_string if tg_proxy_base and tg_proxy_base.value_string else None),
		"telegram_proxy_api_key": (tg_proxy_api_key.value_string if tg_proxy_api_key and tg_proxy_api_key.value_string else None),
		"bale_bot_token": (bale_token.value_string if bale_token and bale_token.value_string else None),
		"bale_bot_username": (bale_username.value_string if bale_username and bale_username.value_string else None),
		"bale_webhook_secret": (bale_webhook.value_string if bale_webhook and bale_webhook.value_string else None),
		"inapp_read_retention_enabled": bool(inapp_retention_enabled) if inapp_retention_enabled is not None else False,
		"inapp_read_retention_days": int(inapp_retention_days) if inapp_retention_days is not None else 0,
	}


def get_effective_notifications_settings(db: Session) -> Dict[str, Any]:
	"""
	مقادیر ذخیره‌شده در DB را می‌خواند و در صورت نبود مقدار، به تنظیمات محیطی برمی‌گردد.
	"""
	env = get_settings()
	db_values = get_notifications_settings(db)
	return {
		"telegram_bot_token": db_values.get("telegram_bot_token") or env.telegram_bot_token,
		"telegram_bot_username": db_values.get("telegram_bot_username") or env.telegram_bot_username,
		"telegram_webhook_secret": db_values.get("telegram_webhook_secret") or env.telegram_webhook_secret,
		"telegram_secret_header": db_values.get("telegram_secret_header") or env.telegram_secret_header,
		"sms_provider_name": db_values.get("sms_provider_name") or env.sms_provider_name,
		"sms_api_key": db_values.get("sms_api_key") or env.sms_api_key,
		"sms_sender": db_values.get("sms_sender") or env.sms_sender,
		"sms_provider_username": db_values.get("sms_provider_username") or getattr(env, 'sms_provider_username', None),
		"sms_provider_password": db_values.get("sms_provider_password") or getattr(env, 'sms_provider_password', None),
		"sms_is_flash": db_values.get("sms_is_flash", False),
		"telegram_proxy": {
			"enabled": (
				db_values.get("telegram_proxy_enabled")
				if db_values.get("telegram_proxy_enabled") is not None
				else env.telegram_proxy_enabled
			),
			"base_url": db_values.get("telegram_proxy_base_url") or env.telegram_proxy_base_url,
			"api_key": db_values.get("telegram_proxy_api_key") or env.telegram_proxy_api_key,
		},
		"bale_bot_token": db_values.get("bale_bot_token") or getattr(env, "bale_bot_token", None),
		"bale_bot_username": db_values.get("bale_bot_username") or getattr(env, "bale_bot_username", None),
		"bale_webhook_secret": db_values.get("bale_webhook_secret") or getattr(env, "bale_webhook_secret", None),
	}

def set_notifications_settings(
	db: Session,
	*, telegram_bot_token: str | None = None,
	telegram_bot_username: str | None = None,
	telegram_webhook_secret: str | None = None,
	telegram_secret_header: str | None = None,
	bale_bot_token: str | None = None,
	bale_bot_username: str | None = None,
	bale_webhook_secret: str | None = None,
	sms_provider_name: str | None = None,
	sms_api_key: str | None = None,
	sms_sender: str | None = None,
	sms_provider_username: str | None = None,
	sms_provider_password: str | None = None,
	sms_is_flash: bool | None = None,
	telegram_proxy_enabled: bool | None = None,
	telegram_proxy_base_url: str | None = None,
	telegram_proxy_api_key: str | None = None,
	inapp_read_retention_enabled: bool | None = None,
	inapp_read_retention_days: int | None = None,
) -> Dict[str, Any]:
	if telegram_bot_token is not None:
		_upsert_setting_string(db, NOTIFY_TG_BOT_TOKEN, telegram_bot_token)
	if telegram_bot_username is not None:
		_upsert_setting_string(db, NOTIFY_TG_BOT_USERNAME, telegram_bot_username)
	if telegram_webhook_secret is not None:
		_upsert_setting_string(db, NOTIFY_TG_WEBHOOK_SECRET, telegram_webhook_secret)
	if telegram_secret_header is not None:
		_upsert_setting_string(db, NOTIFY_TG_SECRET_HEADER, telegram_secret_header)
	if bale_bot_token is not None:
		_upsert_setting_string(db, NOTIFY_BALE_BOT_TOKEN, bale_bot_token)
	if bale_bot_username is not None:
		_upsert_setting_string(db, NOTIFY_BALE_BOT_USERNAME, bale_bot_username)
	if bale_webhook_secret is not None:
		_upsert_setting_string(db, NOTIFY_BALE_WEBHOOK_SECRET, bale_webhook_secret)
	if sms_provider_name is not None:
		_upsert_setting_string(db, NOTIFY_SMS_PROVIDER, sms_provider_name)
	if sms_api_key is not None:
		_upsert_setting_string(db, NOTIFY_SMS_API_KEY, sms_api_key)
	if sms_sender is not None:
		_upsert_setting_string(db, NOTIFY_SMS_SENDER, sms_sender)
	if sms_provider_username is not None:
		_upsert_setting_string(db, NOTIFY_SMS_PROVIDER_USERNAME, sms_provider_username)
	if sms_provider_password is not None:
		_upsert_setting_string(db, NOTIFY_SMS_PROVIDER_PASSWORD, sms_provider_password)
	if sms_is_flash is not None:
		_upsert_setting_bool(db, NOTIFY_SMS_IS_FLASH, sms_is_flash)
	if telegram_proxy_enabled is not None:
		_upsert_setting_bool(db, NOTIFY_TG_PROXY_ENABLED, telegram_proxy_enabled)
	if telegram_proxy_base_url is not None:
		_upsert_setting_string(db, NOTIFY_TG_PROXY_BASE_URL, telegram_proxy_base_url)
	if telegram_proxy_api_key is not None:
		_upsert_setting_string(db, NOTIFY_TG_PROXY_API_KEY, telegram_proxy_api_key)
	if inapp_read_retention_enabled is not None:
		_upsert_setting_bool(db, NOTIFY_INAPP_READ_RETENTION_ENABLED, inapp_read_retention_enabled)
	if inapp_read_retention_days is not None:
		d = int(inapp_read_retention_days)
		if d < 0:
			raise ApiError("INVALID_RETENTION_DAYS", "تعداد روز باید غیرمنفی باشد", http_status=400)
		if d > 3650:
			raise ApiError("INVALID_RETENTION_DAYS", "تعداد روز بیش از حد مجاز است", http_status=400)
		_upsert_setting_int(db, NOTIFY_INAPP_READ_RETENTION_DAYS, d)
	db.commit()
	return get_notifications_settings(db)


def get_sms_destination_rate_effective(db: Session) -> tuple[bool, int, int]:
	"""
	مقادیر مؤثر سقف نرخ ارسال SMS به یک شماره مقصد.
	پایه از تنظیمات محیط؛ در صورت وجود در system_settings اولویت با DB است.
	"""
	env = get_settings()
	enabled = bool(env.sms_destination_rate_enabled)
	max_sends = int(env.sms_destination_rate_max_sends)
	window_minutes = int(env.sms_destination_rate_window_minutes)

	db_enabled = _get_setting_bool(db, SMS_DESTINATION_RATE_ENABLED_KEY)
	if db_enabled is not None:
		enabled = db_enabled
	db_max = _get_setting_int(db, SMS_DESTINATION_RATE_MAX_SENDS_KEY)
	if db_max is not None and db_max >= 0:
		max_sends = db_max
	db_win = _get_setting_int(db, SMS_DESTINATION_RATE_WINDOW_MINUTES_KEY)
	if db_win is not None and db_win > 0:
		window_minutes = db_win

	return enabled, max_sends, window_minutes


def get_share_link_settings(db: Session) -> Dict[str, Any]:
	default_url = _default_share_link_base_url()
	obj = _get_setting(db, SHARE_LINK_PUBLIC_APP_URL_KEY)
	value = (obj.value_string or "").strip() if obj and obj.value_string else default_url
	return {
		"public_app_url": value or default_url,
	}


def set_share_link_settings(db: Session, *, public_app_url: str) -> Dict[str, Any]:
	url = (public_app_url or "").strip()
	if not url:
		raise ApiError("PUBLIC_APP_URL_REQUIRED", "آدرس مقصد لینک اشتراک الزامی است", http_status=400)
	parsed = urlparse(url)
	if parsed.scheme not in ("http", "https"):
		raise ApiError("INVALID_PUBLIC_APP_URL", "آدرس باید با http یا https شروع شود", http_status=400)
	normalized = url.rstrip("/")
	if normalized.lower().endswith("/public"):
		normalized = normalized[:-len("/public")].rstrip("/")
	_upsert_setting_string(db, SHARE_LINK_PUBLIC_APP_URL_KEY, normalized or url)
	db.commit()
	return get_share_link_settings(db)


def resolve_public_app_base_url_for_public_links(db: Session) -> str:
	"""
	پایهٔ دامنهٔ اپ وب برای لینک‌های عمومی (کارت حساب، اشتراک فایل و غیره).
	اولویت با مقدار ذخیره‌شده در DB است؛ در نبود مؤثر، مقدار env استفاده می‌شود.
	خروجی بدون پسوند /public است (مسیرهایی مثل /public/... هنگام ساخت URL کامل اضافه می‌شوند).
	"""
	data = get_share_link_settings(db)
	base = (data.get("public_app_url") or "").strip().rstrip("/")
	if base.lower().endswith("/public"):
		base = base[: -len("/public")].rstrip("/")
	if base:
		return base
	env_base = (get_settings().share_link_public_app_url or "").strip().rstrip("/")
	if env_base.lower().endswith("/public"):
		env_base = env_base[: -len("/public")].rstrip("/")
	return env_base


def _normalize_http_origin_for_share_path(base: str) -> str:
	"""حذف پسوندهای /public و /p و /i از انتهای پایه تا بتوان {origin}/p/... و {origin}/i/... ساخت."""
	if not base:
		return ""
	s = base.strip().rstrip("/")
	changed = True
	while changed:
		changed = False
		low = s.lower()
		for suffix in ("/public", "/p", "/i"):
			if low.endswith(suffix):
				s = s[: -len(suffix)].rstrip("/")
				low = s.lower()
				changed = True
				break
	return s


def resolve_share_url_http_origin(
	db: Optional[Session] = None,
	request_base_url: Optional[str] = None,
) -> str:
	"""
	پایهٔ دامنهٔ مطلق برای لینک کوتاه /p/ و /i/:
	1) مقدار DB + env از طریق resolve_public_app_base_url_for_public_links
	2) متغیر env قدیمی share_link_public_base_url
	3) host درخواست (فقط اگر ۱ و ۲ خالی باشد)
	"""
	if db is not None:
		b = (resolve_public_app_base_url_for_public_links(db) or "").strip()
		b = _normalize_http_origin_for_share_path(b)
		if b:
			return b
	b = (get_settings().share_link_public_base_url or "").strip()
	b = _normalize_http_origin_for_share_path(b)
	if b:
		return b
	if request_base_url:
		return _normalize_http_origin_for_share_path(request_base_url)
	return ""


def get_default_document_policies(db: Session) -> List[Dict[str, Any]]:
	"""
	خواندن سیاست‌های پیش‌فرض درآمدزایی اسناد برای کسب‌وکارهای جدید
	"""
	data = _get_setting_json(db, DEFAULT_DOCUMENT_POLICIES_KEY)
	if data and isinstance(data, dict) and "default_policies" in data:
		return data["default_policies"]
	# مقادیر پیش‌فرض
	return [
		{
			"policy_type": "free",
			"title": "ثبت رایگان اسناد",
			"priority": 10,
			"is_active": True,
			"config": {}
		},
		{
			"policy_type": "subscription",
			"title": "پکیج نامحدود",
			"priority": 20,
			"is_active": True,
			"config": {
				"cascade": True
			}
		},
		{
			"policy_type": "volume",
			"title": "هزینه بر اساس حجم",
			"priority": 30,
			"is_active": True,
			"config": {
				"cycle": "monthly",
				"tier_amount": 10000000,
				"price_per_tier": 50000,
				"free_threshold_amount": 5000000,
				"cascade": True
			}
		},
		{
			"policy_type": "per_document",
			"title": "هزینه ثبت تکی",
			"priority": 40,
			"is_active": True,
			"config": {
				"fee_amount": 1000,
				"auto_charge_wallet": True,
				"cascade": False
			}
		}
	]


def set_default_document_policies(db: Session, policies: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
	"""
	تنظیم سیاست‌های پیش‌فرض درآمدزایی اسناد برای کسب‌وکارهای جدید
	"""
	if not isinstance(policies, list):
		raise ApiError("INVALID_POLICIES", "سیاست‌ها باید به صورت لیست باشند", http_status=400)
	
	# اعتبارسنجی ساختار
	valid_types = {"free", "subscription", "per_document", "volume", "hybrid"}
	for idx, policy in enumerate(policies):
		if not isinstance(policy, dict):
			raise ApiError("INVALID_POLICY", f"سیاست در ایندکس {idx} نامعتبر است", http_status=400)
		policy_type = policy.get("policy_type")
		if policy_type not in valid_types:
			raise ApiError("INVALID_POLICY_TYPE", f"نوع سیاست '{policy_type}' نامعتبر است", http_status=400)
		if "priority" not in policy:
			raise ApiError("MISSING_PRIORITY", f"اولویت برای سیاست در ایندکس {idx} الزامی است", http_status=400)
		if "title" not in policy:
			raise ApiError("MISSING_TITLE", f"عنوان برای سیاست در ایندکس {idx} الزامی است", http_status=400)
	
	# ذخیره
	data = {"default_policies": policies}
	_upsert_setting_json(db, DEFAULT_DOCUMENT_POLICIES_KEY, data)
	return policies


def get_app_name(db: Session) -> str:
	"""خواندن نام اپلیکیشن از DB یا env"""
	cache = get_cache()
	cache_key = "system:app_name"
	cached_value = cache.get(cache_key)
	if cached_value is not None:
		return cached_value
	
	env = get_settings()
	app_name = _get_setting(db, SYSTEM_CONFIG_APP_NAME)
	result = (app_name.value_string if app_name and app_name.value_string else env.app_name)
	cache.set(cache_key, result, ttl=300)  # 5 دقیقه
	return result


def get_app_version(db: Session) -> str:
	"""خواندن نسخه اپلیکیشن از DB یا env"""
	cache = get_cache()
	cache_key = "system:app_version"
	cached_value = cache.get(cache_key)
	if cached_value is not None:
		return cached_value
	
	env = get_settings()
	app_version = _get_setting(db, SYSTEM_CONFIG_APP_VERSION)
	result = (app_version.value_string if app_version and app_version.value_string else env.app_version)
	cache.set(cache_key, result, ttl=300)  # 5 دقیقه
	return result


def is_registration_enabled(db: Session) -> bool:
	"""بررسی فعال بودن ثبت‌نام"""
	enable_registration = _get_setting_bool(db, SYSTEM_CONFIG_ENABLE_REGISTRATION)
	return (enable_registration if enable_registration is not None else True)


def is_email_verification_enabled(db: Session) -> bool:
	"""بررسی فعال بودن تایید ایمیل"""
	enable_email_verification = _get_setting_bool(db, SYSTEM_CONFIG_ENABLE_EMAIL_VERIFICATION)
	return (enable_email_verification if enable_email_verification is not None else True)


def get_business_creation_verification_requirement(db: Session) -> str:
	"""
	دریافت تنظیمات کنترل دسترسی ایجاد کسب و کار
	
	Returns:
		str: یکی از مقادیر: "none", "email_only", "mobile_only", "both", "either"
		پیش‌فرض: "none" (اگر هیچ مقداری تنظیم نشده باشد)
	"""
	requirement = _get_setting(db, SYSTEM_CONFIG_BUSINESS_CREATION_VERIFICATION_REQUIREMENT)
	if requirement and requirement.value_string:
		value = requirement.value_string.strip()
		if value:
			valid_values = ["none", "email_only", "mobile_only", "both", "either"]
			if value in valid_values:
				return value
	# اگر هیچ مقداری تنظیم نشده باشد یا مقدار نامعتبر باشد، "none" (بدون محدودیت) برمی‌گرداند
	return "none"


def set_business_creation_verification_requirement(db: Session, requirement: str) -> None:
	"""
	تنظیم کنترل دسترسی ایجاد کسب و کار
	
	Args:
		db: Database session
		requirement: یکی از مقادیر: "none", "email_only", "mobile_only", "both", "either"
	"""
	valid_values = ["none", "email_only", "mobile_only", "both", "either"]
	if requirement not in valid_values:
		raise ApiError("INVALID_REQUIREMENT", f"مقدار نامعتبر. باید یکی از این موارد باشد: {', '.join(valid_values)}", http_status=400)
	
	_upsert_setting_string(db, SYSTEM_CONFIG_BUSINESS_CREATION_VERIFICATION_REQUIREMENT, requirement)
	cache = get_cache()
	cache.delete("system:business_creation_verification_requirement")


def is_maintenance_mode_enabled(db: Session) -> bool:
	"""بررسی فعال بودن حالت تعمیرات"""
	cache = get_cache()
	cache_key = "system:maintenance_mode"
	cached_value = cache.get(cache_key)
	if cached_value is not None:
		return cached_value
	
	enable_maintenance_mode = _get_setting_bool(db, SYSTEM_CONFIG_ENABLE_MAINTENANCE_MODE)
	result = (enable_maintenance_mode if enable_maintenance_mode is not None else False)
	cache.set(cache_key, result, ttl=30)  # 30 ثانیه (برای پاسخ سریع‌تر)
	return result


def get_session_timeout(db: Session) -> int:
	"""خواندن زمان انقضای نشست (0 = نامحدود)"""
	session_timeout = _get_setting_int(db, SYSTEM_CONFIG_SESSION_TIMEOUT)
	return (session_timeout if session_timeout is not None else 30)


def get_max_file_size_mb(db: Session) -> int:
	"""خواندن حداکثر حجم فایل به مگابایت"""
	max_file_size = _get_setting_int(db, SYSTEM_CONFIG_MAX_FILE_SIZE)
	return (max_file_size if max_file_size is not None else 10)


def get_max_users(db: Session) -> int:
	"""خواندن حداکثر تعداد کاربران (0 = نامحدود)"""
	max_users = _get_setting_int(db, SYSTEM_CONFIG_MAX_USERS)
	return (max_users if max_users is not None else 0)


def get_default_language(db: Session) -> str:
	"""خواندن زبان پیش‌فرض"""
	cache = get_cache()
	cache_key = "system:default_language"
	cached_value = cache.get(cache_key)
	if cached_value is not None:
		return cached_value
	
	default_language = _get_setting(db, SYSTEM_CONFIG_DEFAULT_LANGUAGE)
	result = (default_language.value_string if default_language and default_language.value_string else "fa")
	cache.set(cache_key, result, ttl=300)  # 5 دقیقه
	return result


def get_default_theme(db: Session) -> str:
	"""خواندن تم پیش‌فرض"""
	default_theme = _get_setting(db, SYSTEM_CONFIG_DEFAULT_THEME)
	return (default_theme.value_string if default_theme and default_theme.value_string else "system")


def validate_iana_timezone_name(name: str) -> str:
	"""نام IANA را اعتبارسنجی می‌کند؛ در صورت نامعتبر بودن Asia/Tehran برمی‌گرداند."""
	from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

	n = (name or "").strip()
	if not n:
		return "Asia/Tehran"
	try:
		ZoneInfo(n)
		return n
	except ZoneInfoNotFoundError:
		return "Asia/Tehran"


def resolve_system_display_timezone_string(db: Session) -> str:
	"""مقدار ذخیره‌شده در DB را می‌خواند و به نام IANA معتبر نرمال می‌کند."""
	row = _get_setting(db, SYSTEM_CONFIG_DEFAULT_TIMEZONE)
	raw = (row.value_string if row and row.value_string else "").strip()
	if not raw:
		return "Asia/Tehran"
	return validate_iana_timezone_name(raw)


def get_system_display_timezone_cached() -> str:
	"""منطقهٔ زمانی نمایش برای سریالایزر پاسخ‌ها (با کش کوتاه)."""
	cache = get_cache()
	cache_key = "system:display_timezone"
	cached = cache.get(cache_key)
	if cached is not None:
		return str(cached)
	try:
		from adapters.db.session import get_db_session

		with get_db_session() as db:
			tz = resolve_system_display_timezone_string(db)
	except Exception:
		tz = "Asia/Tehran"
	cache.set(cache_key, tz, ttl=300)
	return tz


def datetime_to_system_tz_iso_string(dt: datetime) -> str:
	"""برای WebSocket/JSON: لحظهٔ naive UTC را به ISO با آفست منطقهٔ نمایش سیستم تبدیل می‌کند."""
	from datetime import timezone as dt_timezone
	from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

	tz_name = get_system_display_timezone_cached()
	try:
		tz = ZoneInfo(tz_name.strip() or "Asia/Tehran")
	except ZoneInfoNotFoundError:
		tz = ZoneInfo("Asia/Tehran")
	if dt.tzinfo is None:
		utc_dt = dt.replace(tzinfo=dt_timezone.utc)
	else:
		utc_dt = dt.astimezone(dt_timezone.utc)
	return utc_dt.astimezone(tz).isoformat()


def get_captcha_auth_security_effective(db: Session) -> Dict[str, Any]:
	"""
	مقادیر مؤثر امنیت کپچا و محدودیت نرخ (DB + env).
	برای استفاده در سرویس کپچا و rate limiter.
	"""
	env = get_settings()

	def _ii(key: str, default: int) -> int:
		v = _get_setting_int(db, key)
		return int(v) if v is not None else default

	def _bb(key: str, default: bool) -> bool:
		b = _get_setting_bool(db, key)
		return b if b is not None else default

	def _ss(key: str, default: str) -> str:
		o = _get_setting(db, key)
		if o and o.value_string:
			return o.value_string.strip()
		return default

	mode = _ss(SYSTEM_CONFIG_CAPTCHA_MODE, "numeric")
	if mode not in ("numeric", "alphanumeric"):
		mode = "numeric"

	return {
		"captcha_max_attempts": max(1, min(30, _ii(SYSTEM_CONFIG_CAPTCHA_MAX_ATTEMPTS, 5))),
		"captcha_length": max(4, min(8, _ii(SYSTEM_CONFIG_CAPTCHA_LENGTH, int(env.captcha_length)))),
		"captcha_ttl_seconds": max(60, min(600, _ii(SYSTEM_CONFIG_CAPTCHA_TTL_SECONDS, int(env.captcha_ttl_seconds)))),
		"captcha_mode": mode,
		"captcha_bind_ip": _bb(SYSTEM_CONFIG_CAPTCHA_BIND_IP, True),
		"captcha_strong_image": _bb(SYSTEM_CONFIG_CAPTCHA_STRONG_IMAGE, True),
		"captcha_rate_max": max(1, min(200, _ii(SYSTEM_CONFIG_CAPTCHA_RATE_MAX, 20))),
		"captcha_rate_window_sec": max(10, min(3600, _ii(SYSTEM_CONFIG_CAPTCHA_RATE_WINDOW_SEC, 60))),
		"login_rate_max_short": max(1, min(100, _ii(SYSTEM_CONFIG_LOGIN_RATE_MAX_SHORT, 10))),
		"login_rate_window_short_sec": max(10, min(3600, _ii(SYSTEM_CONFIG_LOGIN_RATE_WINDOW_SHORT_SEC, 60))),
		"login_rate_max_long": max(1, min(500, _ii(SYSTEM_CONFIG_LOGIN_RATE_MAX_LONG, 10))),
		"login_rate_window_long_sec": max(60, min(86400, _ii(SYSTEM_CONFIG_LOGIN_RATE_WINDOW_LONG_SEC, 300))),
		"register_rate_max": max(1, min(100, _ii(SYSTEM_CONFIG_REGISTER_RATE_MAX, 5))),
		"register_rate_window_sec": max(60, min(86400, _ii(SYSTEM_CONFIG_REGISTER_RATE_WINDOW_SEC, 3600))),
		"forgot_rate_max": max(1, min(100, _ii(SYSTEM_CONFIG_FORGOT_RATE_MAX, 5))),
		"forgot_rate_window_sec": max(60, min(86400, _ii(SYSTEM_CONFIG_FORGOT_RATE_WINDOW_SEC, 3600))),
		"reset_rate_max": max(1, min(200, _ii(SYSTEM_CONFIG_RESET_RATE_MAX, 10))),
		"reset_rate_window_sec": max(60, min(86400, _ii(SYSTEM_CONFIG_RESET_RATE_WINDOW_SEC, 3600))),
		"pr_otp_rate_max": max(1, min(100, _ii(SYSTEM_CONFIG_PR_OTP_RATE_MAX, 5))),
		"pr_otp_rate_window_sec": max(60, min(86400, _ii(SYSTEM_CONFIG_PR_OTP_RATE_WINDOW_SEC, 300))),
		"login_backoff_max_fails": max(0, min(50, _ii(SYSTEM_CONFIG_LOGIN_BACKOFF_MAX_FAILS, 5))),
		"login_backoff_window_minutes": max(1, min(1440, _ii(SYSTEM_CONFIG_LOGIN_BACKOFF_WINDOW_MINUTES, 15))),
		"login_backoff_seconds": max(0, min(3600, _ii(SYSTEM_CONFIG_LOGIN_BACKOFF_SECONDS, 90))),
		"firewall_auto_ban_on_login_fail": _bb(SYSTEM_CONFIG_FIREWALL_AUTO_BAN_ON_LOGIN_FAIL, False),
		"firewall_auto_ban_duration_sec": max(60, min(86400, _ii(SYSTEM_CONFIG_FIREWALL_AUTO_BAN_DURATION_SEC, 3600))),
	}


def get_system_configuration(db: Session) -> Dict[str, Any]:
	"""
	خواندن تنظیمات پیکربندی سیستم
	"""
	env = get_settings()
	
	app_name = _get_setting(db, SYSTEM_CONFIG_APP_NAME)
	app_version = _get_setting(db, SYSTEM_CONFIG_APP_VERSION)
	default_language = _get_setting(db, SYSTEM_CONFIG_DEFAULT_LANGUAGE)
	default_theme = _get_setting(db, SYSTEM_CONFIG_DEFAULT_THEME)
	enable_registration = _get_setting_bool(db, SYSTEM_CONFIG_ENABLE_REGISTRATION)
	enable_email_verification = _get_setting_bool(db, SYSTEM_CONFIG_ENABLE_EMAIL_VERIFICATION)
	enable_maintenance_mode = _get_setting_bool(db, SYSTEM_CONFIG_ENABLE_MAINTENANCE_MODE)
	session_timeout = _get_setting_int(db, SYSTEM_CONFIG_SESSION_TIMEOUT)
	max_file_size = _get_setting_int(db, SYSTEM_CONFIG_MAX_FILE_SIZE)
	max_users = _get_setting_int(db, SYSTEM_CONFIG_MAX_USERS)
	business_creation_requirement = get_business_creation_verification_requirement(db)
	sms_r = get_sms_destination_rate_effective(db)
	sec = get_captcha_auth_security_effective(db)
	support_disabled_msg_setting = _get_setting(db, SYSTEM_CONFIG_SUPPORT_TICKETS_DISABLED_MESSAGE)
	support_disabled_msg_storage = ""
	if support_disabled_msg_setting and support_disabled_msg_setting.value_string:
		support_disabled_msg_storage = support_disabled_msg_setting.value_string.strip()[
			:MAX_SUPPORT_TICKETS_DISABLED_MESSAGE_LEN
		]

	return {
		"app_name": (app_name.value_string if app_name and app_name.value_string else env.app_name),
		"app_version": (app_version.value_string if app_version and app_version.value_string else env.app_version),
		"default_language": (default_language.value_string if default_language and default_language.value_string else "fa"),
		"default_theme": (default_theme.value_string if default_theme and default_theme.value_string else "system"),
		"default_timezone": resolve_system_display_timezone_string(db),
		"enable_registration": (enable_registration if enable_registration is not None else True),
		"enable_email_verification": (enable_email_verification if enable_email_verification is not None else True),
		"enable_maintenance_mode": (enable_maintenance_mode if enable_maintenance_mode is not None else False),
		"session_timeout": (session_timeout if session_timeout is not None else 30),
		"max_file_size": (max_file_size if max_file_size is not None else 10),
		"max_users": (max_users if max_users is not None else 0),
		"business_creation_verification_requirement": business_creation_requirement,
		"sms_destination_rate_enabled": sms_r[0],
		"sms_destination_rate_max_sends": sms_r[1],
		"sms_destination_rate_window_minutes": sms_r[2],
		"captcha_max_attempts": sec["captcha_max_attempts"],
		"captcha_length": sec["captcha_length"],
		"captcha_ttl_seconds": sec["captcha_ttl_seconds"],
		"captcha_mode": sec["captcha_mode"],
		"captcha_bind_ip": sec["captcha_bind_ip"],
		"captcha_strong_image": sec["captcha_strong_image"],
		"captcha_rate_max": sec["captcha_rate_max"],
		"captcha_rate_window_sec": sec["captcha_rate_window_sec"],
		"login_rate_max_short": sec["login_rate_max_short"],
		"login_rate_window_short_sec": sec["login_rate_window_short_sec"],
		"login_rate_max_long": sec["login_rate_max_long"],
		"login_rate_window_long_sec": sec["login_rate_window_long_sec"],
		"register_rate_max": sec["register_rate_max"],
		"register_rate_window_sec": sec["register_rate_window_sec"],
		"forgot_password_rate_max": sec["forgot_rate_max"],
		"forgot_password_rate_window_sec": sec["forgot_rate_window_sec"],
		"reset_password_rate_max": sec["reset_rate_max"],
		"reset_password_rate_window_sec": sec["reset_rate_window_sec"],
		"password_reset_otp_rate_max": sec["pr_otp_rate_max"],
		"password_reset_otp_rate_window_sec": sec["pr_otp_rate_window_sec"],
		"login_backoff_max_fails": sec["login_backoff_max_fails"],
		"login_backoff_window_minutes": sec["login_backoff_window_minutes"],
		"login_backoff_seconds": sec["login_backoff_seconds"],
		"firewall_auto_ban_on_login_fail": sec["firewall_auto_ban_on_login_fail"],
		"firewall_auto_ban_duration_sec": sec["firewall_auto_ban_duration_sec"],
		"support_tickets_enabled": is_support_tickets_enabled_for_users(db),
		"support_tickets_disabled_message": support_disabled_msg_storage,
	}


def set_system_configuration(
	db: Session,
	*,
	app_name: str | None = None,
	app_version: str | None = None,
	default_language: str | None = None,
	default_theme: str | None = None,
	default_timezone: str | None = None,
	enable_registration: bool | None = None,
	enable_email_verification: bool | None = None,
	enable_maintenance_mode: bool | None = None,
	support_tickets_enabled: bool | None = None,
	support_tickets_disabled_message: str | None = None,
	session_timeout: int | None = None,
	max_file_size: int | None = None,
	max_users: int | None = None,
	business_creation_verification_requirement: str | None = None,
	sms_destination_rate_enabled: bool | None = None,
	sms_destination_rate_max_sends: int | None = None,
	sms_destination_rate_window_minutes: int | None = None,
	captcha_max_attempts: int | None = None,
	captcha_length: int | None = None,
	captcha_ttl_seconds: int | None = None,
	captcha_mode: str | None = None,
	captcha_bind_ip: bool | None = None,
	captcha_strong_image: bool | None = None,
	captcha_rate_max: int | None = None,
	captcha_rate_window_sec: int | None = None,
	login_rate_max_short: int | None = None,
	login_rate_window_short_sec: int | None = None,
	login_rate_max_long: int | None = None,
	login_rate_window_long_sec: int | None = None,
	register_rate_max: int | None = None,
	register_rate_window_sec: int | None = None,
	forgot_password_rate_max: int | None = None,
	forgot_password_rate_window_sec: int | None = None,
	reset_password_rate_max: int | None = None,
	reset_password_rate_window_sec: int | None = None,
	password_reset_otp_rate_max: int | None = None,
	password_reset_otp_rate_window_sec: int | None = None,
	login_backoff_max_fails: int | None = None,
	login_backoff_window_minutes: int | None = None,
	login_backoff_seconds: int | None = None,
	firewall_auto_ban_on_login_fail: bool | None = None,
	firewall_auto_ban_duration_sec: int | None = None,
) -> Dict[str, Any]:
	"""
	تنظیم پیکربندی سیستم با اعتبارسنجی
	"""
	cache = get_cache()
	if app_name is not None:
		app_name = str(app_name).strip()
		if not app_name:
			raise ApiError("APP_NAME_REQUIRED", "نام اپلیکیشن الزامی است", http_status=400)
		_upsert_setting_string(db, SYSTEM_CONFIG_APP_NAME, app_name)
		cache.delete("system:app_name")  # Invalidate cache
	
	if app_version is not None:
		app_version = str(app_version).strip()
		if not app_version:
			raise ApiError("APP_VERSION_REQUIRED", "نسخه اپلیکیشن الزامی است", http_status=400)
		_upsert_setting_string(db, SYSTEM_CONFIG_APP_VERSION, app_version)
		cache.delete("system:app_version")  # Invalidate cache
	
	if default_language is not None:
		default_language = str(default_language).strip().lower()
		if default_language not in {"fa", "en"}:
			raise ApiError("INVALID_LANGUAGE", "زبان باید fa یا en باشد", http_status=400)
		_upsert_setting_string(db, SYSTEM_CONFIG_DEFAULT_LANGUAGE, default_language)
		cache.delete("system:default_language")  # Invalidate cache
	
	if default_theme is not None:
		default_theme = str(default_theme).strip().lower()
		if default_theme not in {"system", "light", "dark"}:
			raise ApiError("INVALID_THEME", "تم باید system، light یا dark باشد", http_status=400)
		_upsert_setting_string(db, SYSTEM_CONFIG_DEFAULT_THEME, default_theme)

	if default_timezone is not None:
		from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

		raw_tz = str(default_timezone).strip()
		if not raw_tz:
			raise ApiError("INVALID_TIMEZONE", "نام منطقهٔ زمانی (IANA) نمی‌تواند خالی باشد", http_status=400)
		try:
			ZoneInfo(raw_tz)
		except ZoneInfoNotFoundError:
			raise ApiError(
				"INVALID_TIMEZONE",
				f"نام منطقهٔ زمانی معتبر نیست (مثال: Asia/Tehran): {raw_tz}",
				http_status=400,
			)
		_upsert_setting_string(db, SYSTEM_CONFIG_DEFAULT_TIMEZONE, raw_tz)
		cache.delete("system:display_timezone")
	
	if enable_registration is not None:
		_upsert_setting_bool(db, SYSTEM_CONFIG_ENABLE_REGISTRATION, enable_registration)
	
	if enable_email_verification is not None:
		_upsert_setting_bool(db, SYSTEM_CONFIG_ENABLE_EMAIL_VERIFICATION, enable_email_verification)
	
	if enable_maintenance_mode is not None:
		_upsert_setting_bool(db, SYSTEM_CONFIG_ENABLE_MAINTENANCE_MODE, enable_maintenance_mode)
		cache.delete("system:maintenance_mode")  # Invalidate cache

	if support_tickets_enabled is not None:
		_upsert_setting_bool(db, SYSTEM_CONFIG_SUPPORT_TICKETS_ENABLED, support_tickets_enabled)

	if support_tickets_disabled_message is not None:
		text = str(support_tickets_disabled_message).strip()
		if len(text) > MAX_SUPPORT_TICKETS_DISABLED_MESSAGE_LEN:
			raise ApiError(
				"SUPPORT_MESSAGE_TOO_LONG",
				f"پیام غیرفعال‌سازی تیکت‌ها حداکثر {MAX_SUPPORT_TICKETS_DISABLED_MESSAGE_LEN} کاراکتر است",
				http_status=400,
			)
		_upsert_setting_string(db, SYSTEM_CONFIG_SUPPORT_TICKETS_DISABLED_MESSAGE, text)
	
	if session_timeout is not None:
		# 0 به معنی نامحدود است
		if session_timeout < 0 or (session_timeout > 0 and (session_timeout < 5 or session_timeout > 1440)):
			raise ApiError("INVALID_SESSION_TIMEOUT", "زمان انقضای نشست باید 0 (نامحدود) یا بین 5 تا 1440 دقیقه باشد", http_status=400)
		_upsert_setting_int(db, SYSTEM_CONFIG_SESSION_TIMEOUT, session_timeout)
	
	if max_file_size is not None:
		if max_file_size < 1 or max_file_size > 1000:
			raise ApiError("INVALID_MAX_FILE_SIZE", "حداکثر حجم فایل باید بین 1 تا 1000 مگابایت باشد", http_status=400)
		_upsert_setting_int(db, SYSTEM_CONFIG_MAX_FILE_SIZE, max_file_size)
	
	if max_users is not None:
		# 0 به معنی نامحدود است
		if max_users < 0 or (max_users > 0 and max_users > 10000):
			raise ApiError("INVALID_MAX_USERS", "حداکثر تعداد کاربران باید 0 (نامحدود) یا بین 1 تا 10000 باشد", http_status=400)
		_upsert_setting_int(db, SYSTEM_CONFIG_MAX_USERS, max_users)
	
	if business_creation_verification_requirement is not None:
		# اگر مقدار خالی یا null باشد، به "none" تنظیم می‌شود
		req_value = business_creation_verification_requirement.strip() if isinstance(business_creation_verification_requirement, str) else "none"
		if not req_value:
			req_value = "none"
		set_business_creation_verification_requirement(db, req_value)

	if sms_destination_rate_enabled is not None:
		_upsert_setting_bool(db, SMS_DESTINATION_RATE_ENABLED_KEY, sms_destination_rate_enabled)
	if sms_destination_rate_max_sends is not None:
		if sms_destination_rate_max_sends < 0 or sms_destination_rate_max_sends > 1_000_000:
			raise ApiError("INVALID_SMS_DEST_RATE", "سقف ارسال به مقصد باید بین 0 تا 1000000 باشد", http_status=400)
		_upsert_setting_int(db, SMS_DESTINATION_RATE_MAX_SENDS_KEY, sms_destination_rate_max_sends)
	if sms_destination_rate_window_minutes is not None:
		if sms_destination_rate_window_minutes < 1 or sms_destination_rate_window_minutes > 10080:
			raise ApiError("INVALID_SMS_DEST_WINDOW", "پنجره زمانی باید بین 1 تا 10080 دقیقه باشد", http_status=400)
		_upsert_setting_int(db, SMS_DESTINATION_RATE_WINDOW_MINUTES_KEY, sms_destination_rate_window_minutes)

	if captcha_max_attempts is not None:
		if captcha_max_attempts < 1 or captcha_max_attempts > 30:
			raise ApiError("INVALID_CAPTCHA_MAX_ATTEMPTS", "حداکثر تلاش کپچا باید بین 1 تا 30 باشد", http_status=400)
		_upsert_setting_int(db, SYSTEM_CONFIG_CAPTCHA_MAX_ATTEMPTS, captcha_max_attempts)
	if captcha_length is not None:
		if captcha_length < 4 or captcha_length > 8:
			raise ApiError("INVALID_CAPTCHA_LENGTH", "طول کپچا باید بین 4 تا 8 باشد", http_status=400)
		_upsert_setting_int(db, SYSTEM_CONFIG_CAPTCHA_LENGTH, captcha_length)
	if captcha_ttl_seconds is not None:
		if captcha_ttl_seconds < 60 or captcha_ttl_seconds > 600:
			raise ApiError("INVALID_CAPTCHA_TTL", "زمان انقضای کپچا باید بین 60 تا 600 ثانیه باشد", http_status=400)
		_upsert_setting_int(db, SYSTEM_CONFIG_CAPTCHA_TTL_SECONDS, captcha_ttl_seconds)
	if captcha_mode is not None:
		cm = str(captcha_mode).strip().lower()
		if cm not in ("numeric", "alphanumeric"):
			raise ApiError("INVALID_CAPTCHA_MODE", "حالت کپچا باید numeric یا alphanumeric باشد", http_status=400)
		_upsert_setting_string(db, SYSTEM_CONFIG_CAPTCHA_MODE, cm)
	if captcha_bind_ip is not None:
		_upsert_setting_bool(db, SYSTEM_CONFIG_CAPTCHA_BIND_IP, captcha_bind_ip)
	if captcha_strong_image is not None:
		_upsert_setting_bool(db, SYSTEM_CONFIG_CAPTCHA_STRONG_IMAGE, captcha_strong_image)
	if captcha_rate_max is not None:
		if captcha_rate_max < 1 or captcha_rate_max > 200:
			raise ApiError("INVALID_CAPTCHA_RATE", "سقف درخواست کپچا باید بین 1 تا 200 باشد", http_status=400)
		_upsert_setting_int(db, SYSTEM_CONFIG_CAPTCHA_RATE_MAX, captcha_rate_max)
	if captcha_rate_window_sec is not None:
		if captcha_rate_window_sec < 10 or captcha_rate_window_sec > 3600:
			raise ApiError("INVALID_CAPTCHA_RATE_WINDOW", "پنجره نرخ کپچا باید بین 10 تا 3600 ثانیه باشد", http_status=400)
		_upsert_setting_int(db, SYSTEM_CONFIG_CAPTCHA_RATE_WINDOW_SEC, captcha_rate_window_sec)
	if login_rate_max_short is not None:
		if login_rate_max_short < 1 or login_rate_max_short > 100:
			raise ApiError("INVALID_LOGIN_RATE", "محدودیت کوتاه ورود نامعتبر است", http_status=400)
		_upsert_setting_int(db, SYSTEM_CONFIG_LOGIN_RATE_MAX_SHORT, login_rate_max_short)
	if login_rate_window_short_sec is not None:
		if login_rate_window_short_sec < 10 or login_rate_window_short_sec > 3600:
			raise ApiError("INVALID_LOGIN_RATE_WINDOW", "پنجره کوتاه ورود نامعتبر است", http_status=400)
		_upsert_setting_int(db, SYSTEM_CONFIG_LOGIN_RATE_WINDOW_SHORT_SEC, login_rate_window_short_sec)
	if login_rate_max_long is not None:
		if login_rate_max_long < 1 or login_rate_max_long > 500:
			raise ApiError("INVALID_LOGIN_RATE_LONG", "محدودیت بلند ورود نامعتبر است", http_status=400)
		_upsert_setting_int(db, SYSTEM_CONFIG_LOGIN_RATE_MAX_LONG, login_rate_max_long)
	if login_rate_window_long_sec is not None:
		if login_rate_window_long_sec < 60 or login_rate_window_long_sec > 86400:
			raise ApiError("INVALID_LOGIN_RATE_WINDOW_LONG", "پنجره بلند ورود نامعتبر است", http_status=400)
		_upsert_setting_int(db, SYSTEM_CONFIG_LOGIN_RATE_WINDOW_LONG_SEC, login_rate_window_long_sec)
	if register_rate_max is not None:
		if register_rate_max < 1 or register_rate_max > 100:
			raise ApiError("INVALID_REGISTER_RATE", "محدودیت ثبت‌نام نامعتبر است", http_status=400)
		_upsert_setting_int(db, SYSTEM_CONFIG_REGISTER_RATE_MAX, register_rate_max)
	if register_rate_window_sec is not None:
		if register_rate_window_sec < 60 or register_rate_window_sec > 86400:
			raise ApiError("INVALID_REGISTER_WINDOW", "پنجره ثبت‌نام نامعتبر است", http_status=400)
		_upsert_setting_int(db, SYSTEM_CONFIG_REGISTER_RATE_WINDOW_SEC, register_rate_window_sec)
	if forgot_password_rate_max is not None:
		if forgot_password_rate_max < 1 or forgot_password_rate_max > 100:
			raise ApiError("INVALID_FORGOT_RATE", "محدودیت فراموشی رمز نامعتبر است", http_status=400)
		_upsert_setting_int(db, SYSTEM_CONFIG_FORGOT_RATE_MAX, forgot_password_rate_max)
	if forgot_password_rate_window_sec is not None:
		if forgot_password_rate_window_sec < 60 or forgot_password_rate_window_sec > 86400:
			raise ApiError("INVALID_FORGOT_WINDOW", "پنجره فراموشی رمز نامعتبر است", http_status=400)
		_upsert_setting_int(db, SYSTEM_CONFIG_FORGOT_RATE_WINDOW_SEC, forgot_password_rate_window_sec)
	if reset_password_rate_max is not None:
		if reset_password_rate_max < 1 or reset_password_rate_max > 200:
			raise ApiError("INVALID_RESET_RATE", "محدودیت بازنشانی رمز نامعتبر است", http_status=400)
		_upsert_setting_int(db, SYSTEM_CONFIG_RESET_RATE_MAX, reset_password_rate_max)
	if reset_password_rate_window_sec is not None:
		if reset_password_rate_window_sec < 60 or reset_password_rate_window_sec > 86400:
			raise ApiError("INVALID_RESET_WINDOW", "پنجره بازنشانی رمز نامعتبر است", http_status=400)
		_upsert_setting_int(db, SYSTEM_CONFIG_RESET_RATE_WINDOW_SEC, reset_password_rate_window_sec)
	if password_reset_otp_rate_max is not None:
		if password_reset_otp_rate_max < 1 or password_reset_otp_rate_max > 100:
			raise ApiError("INVALID_PR_OTP_RATE", "محدودیت OTP بازیابی نامعتبر است", http_status=400)
		_upsert_setting_int(db, SYSTEM_CONFIG_PR_OTP_RATE_MAX, password_reset_otp_rate_max)
	if password_reset_otp_rate_window_sec is not None:
		if password_reset_otp_rate_window_sec < 60 or password_reset_otp_rate_window_sec > 86400:
			raise ApiError("INVALID_PR_OTP_WINDOW", "پنجره OTP بازیابی نامعتبر است", http_status=400)
		_upsert_setting_int(db, SYSTEM_CONFIG_PR_OTP_RATE_WINDOW_SEC, password_reset_otp_rate_window_sec)
	if login_backoff_max_fails is not None:
		if login_backoff_max_fails < 0 or login_backoff_max_fails > 50:
			raise ApiError("INVALID_LOGIN_BACKOFF_FAILS", "تعداد تلاش برای backoff باید بین 0 تا 50 باشد (0=غیرفعال)", http_status=400)
		_upsert_setting_int(db, SYSTEM_CONFIG_LOGIN_BACKOFF_MAX_FAILS, login_backoff_max_fails)
	if login_backoff_window_minutes is not None:
		if login_backoff_window_minutes < 1 or login_backoff_window_minutes > 1440:
			raise ApiError("INVALID_LOGIN_BACKOFF_WINDOW", "پنجره backoff باید بین 1 تا 1440 دقیقه باشد", http_status=400)
		_upsert_setting_int(db, SYSTEM_CONFIG_LOGIN_BACKOFF_WINDOW_MINUTES, login_backoff_window_minutes)
	if login_backoff_seconds is not None:
		if login_backoff_seconds < 0 or login_backoff_seconds > 3600:
			raise ApiError("INVALID_LOGIN_BACKOFF_SEC", "مدت انتظار backoff باید بین 0 تا 3600 ثانیه باشد", http_status=400)
		_upsert_setting_int(db, SYSTEM_CONFIG_LOGIN_BACKOFF_SECONDS, login_backoff_seconds)
	if firewall_auto_ban_on_login_fail is not None:
		_upsert_setting_bool(db, SYSTEM_CONFIG_FIREWALL_AUTO_BAN_ON_LOGIN_FAIL, firewall_auto_ban_on_login_fail)
	if firewall_auto_ban_duration_sec is not None:
		if firewall_auto_ban_duration_sec < 60 or firewall_auto_ban_duration_sec > 86400:
			raise ApiError(
				"INVALID_FIREWALL_AUTO_BAN_DURATION",
				"مدت بن خودکار پس از ورود ناموفق باید بین 60 تا 86400 ثانیه باشد",
				http_status=400,
			)
		_upsert_setting_int(db, SYSTEM_CONFIG_FIREWALL_AUTO_BAN_DURATION_SEC, firewall_auto_ban_duration_sec)
	
	db.commit()
	return get_system_configuration(db)


def get_redis_configuration(db: Session) -> Dict[str, Any]:
	"""
	خواندن تنظیمات Redis از DB یا env
	"""
	env = get_settings()
	
	redis_enabled = _get_setting_bool(db, REDIS_CONFIG_ENABLED)
	redis_host = _get_setting(db, REDIS_CONFIG_HOST)
	redis_port = _get_setting_int(db, REDIS_CONFIG_PORT)
	redis_db = _get_setting_int(db, REDIS_CONFIG_DB)
	redis_password = _get_setting(db, REDIS_CONFIG_PASSWORD)
	
	return {
		"enabled": (redis_enabled if redis_enabled is not None else getattr(env, 'redis_enabled', False)),
		"host": (redis_host.value_string if redis_host and redis_host.value_string else getattr(env, 'redis_host', 'localhost')),
		"port": (redis_port if redis_port is not None else getattr(env, 'redis_port', 6379)),
		"db": (redis_db if redis_db is not None else getattr(env, 'redis_db', 0)),
		"password": (redis_password.value_string if redis_password and redis_password.value_string else getattr(env, 'redis_password', None)),
	}


def set_redis_configuration(
	db: Session,
	*,
	enabled: bool | None = None,
	host: str | None = None,
	port: int | None = None,
	db_num: int | None = None,
	password: str | None = None,
) -> Dict[str, Any]:
	"""
	تنظیم پیکربندی Redis با اعتبارسنجی
	"""
	if enabled is not None:
		_upsert_setting_bool(db, REDIS_CONFIG_ENABLED, enabled)
	
	if host is not None:
		host = str(host).strip()
		if not host:
			raise ApiError("REDIS_HOST_REQUIRED", "آدرس سرور Redis الزامی است", http_status=400)
		_upsert_setting_string(db, REDIS_CONFIG_HOST, host)
	
	if port is not None:
		if port < 1 or port > 65535:
			raise ApiError("INVALID_REDIS_PORT", "پورت Redis باید بین 1 تا 65535 باشد", http_status=400)
		_upsert_setting_int(db, REDIS_CONFIG_PORT, port)
	
	if db_num is not None:
		if db_num < 0 or db_num > 15:
			raise ApiError("INVALID_REDIS_DB", "شماره دیتابیس Redis باید بین 0 تا 15 باشد", http_status=400)
		_upsert_setting_int(db, REDIS_CONFIG_DB, db_num)
	
	if password is not None:
		# اگر password خالی است، None ذخیره می‌کنیم
		password = password.strip() if password else None
		if password:
			_upsert_setting_string(db, REDIS_CONFIG_PASSWORD, password)
		else:
			# حذف password
			obj = _get_setting(db, REDIS_CONFIG_PASSWORD)
			if obj:
				obj.value_string = None
				db.add(obj)
	
	db.commit()
	
	# Invalidate cache و reconnect Redis client
	from app.core.cache import get_cache
	import app.core.cache as cache_module
	
	# Force reconnect Redis client
	cache_module._redis_client = None
	
	# Refresh cache service
	cache = get_cache()
	# حذف تمام cache برای reconnect
	if cache.enabled:
		cache.invalidate("system:*")
		cache.invalidate("api_key:*")
	
	return get_redis_configuration(db)


def get_zohal_settings(db: Session) -> Dict[str, Any]:
	"""
	خواندن تنظیمات سرویس زحل
	"""
	api_key = _get_setting(db, ZOHAL_API_KEY)
	base_url = _get_setting(db, ZOHAL_BASE_URL)
	low_balance_threshold = _get_setting(db, ZOHAL_LOW_BALANCE_THRESHOLD)
	
	return {
		"api_key": (api_key.value_string if api_key and api_key.value_string else None),
		"base_url": (base_url.value_string if base_url and base_url.value_string else "https://service.zohal.io/api/v0"),
		"low_balance_threshold": (
			float(low_balance_threshold.value_string) 
			if low_balance_threshold and low_balance_threshold.value_string 
			else 10000.0
		),
	}


def set_zohal_settings(
	db: Session,
	*,
	api_key: str | None = None,
	base_url: str | None = None,
	low_balance_threshold: float | None = None,
) -> Dict[str, Any]:
	"""
	تنظیم پیکربندی سرویس زحل
	"""
	if api_key is not None:
		api_key = str(api_key).strip()
		if not api_key:
			raise ApiError("ZOHAL_API_KEY_REQUIRED", "کلید API زحل الزامی است", http_status=400)
		_upsert_setting_string(db, ZOHAL_API_KEY, api_key)
	
	if base_url is not None:
		base_url = str(base_url).strip().rstrip("/")
		if not base_url:
			raise ApiError("ZOHAL_BASE_URL_REQUIRED", "آدرس پایه API زحل الزامی است", http_status=400)
		_upsert_setting_string(db, ZOHAL_BASE_URL, base_url)
	
	if low_balance_threshold is not None:
		if low_balance_threshold < 0:
			raise ApiError("INVALID_THRESHOLD", "آستانه موجودی نمی‌تواند منفی باشد", http_status=400)
		_upsert_setting_string(db, ZOHAL_LOW_BALANCE_THRESHOLD, str(low_balance_threshold))
	
	db.commit()
	
	# Invalidate cache
	cache = get_cache()
	if cache.enabled:
		cache.invalidate("zohal:*")
	
	return get_zohal_settings(db)


def get_notification_sms_pricing(db: Session) -> Dict[str, Any]:
	"""
	خواندن تنظیمات قیمت‌گذاری پیامک ناتیفیکیشن
	
	Returns:
		دیکشنری شامل:
		- price_per_sms: قیمت پیش‌فرض هر پیامک (حداقل 1)
		- event_type_prices: قیمت‌های خاص برای هر event_type
	"""
	data = _get_setting_json(db, NOTIFICATION_SMS_PRICING_KEY)
	if data and isinstance(data, dict):
		price_per_sms = data.get("price_per_sms")
		# اعتبارسنجی قیمت پیش‌فرض
		if price_per_sms is not None:
			try:
				price_per_sms = float(price_per_sms)
				if price_per_sms <= 0:
					# اگر قیمت نامعتبر باشد، از مقدار پیش‌فرض استفاده می‌کنیم
					price_per_sms = 500.0
			except (ValueError, TypeError):
				price_per_sms = 500.0
		else:
			price_per_sms = 500.0
		
		# اعتبارسنجی قیمت‌های event_type
		event_type_prices = data.get("event_type_prices", {})
		if isinstance(event_type_prices, dict):
			validated_prices = {}
			for event_type, price in event_type_prices.items():
				try:
					price_float = float(price)
					if price_float > 0:
						validated_prices[str(event_type)] = price_float
				except (ValueError, TypeError):
					# قیمت نامعتبر را نادیده می‌گیریم
					continue
			event_type_prices = validated_prices
		else:
			event_type_prices = {}
		
		return {
			"price_per_sms": price_per_sms,
			"event_type_prices": event_type_prices
		}
	# مقادیر پیش‌فرض
	return {
		"price_per_sms": 500.0,
		"event_type_prices": {}
	}


def set_notification_sms_pricing(
	db: Session,
	*,
	price_per_sms: float | None = None,
	event_type_prices: Dict[str, float] | None = None,
) -> Dict[str, Any]:
	"""
	تنظیم قیمت‌گذاری پیامک ناتیفیکیشن
	
	Args:
		price_per_sms: قیمت پیش‌فرض هر پیامک (باید بزرگتر از صفر باشد)
		event_type_prices: دیکشنری قیمت‌های خاص برای event_type ها
	"""
	current = get_notification_sms_pricing(db)
	
	if price_per_sms is not None:
		if price_per_sms <= 0:
			raise ApiError("INVALID_PRICE", "قیمت هر پیامک باید بزرگتر از صفر باشد", http_status=400)
		current["price_per_sms"] = float(price_per_sms)
	
	if event_type_prices is not None:
		# اعتبارسنجی قیمت‌ها
		for event_type, price in event_type_prices.items():
			if price <= 0:
				raise ApiError("INVALID_PRICE", f"قیمت برای {event_type} باید بزرگتر از صفر باشد", http_status=400)
		current["event_type_prices"] = event_type_prices
	
	_upsert_setting_json(db, NOTIFICATION_SMS_PRICING_KEY, current)
	db.commit()
	return current
