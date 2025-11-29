from __future__ import annotations

from typing import Optional, Dict, Any, List
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
DEFAULT_DOCUMENT_POLICIES_KEY = "default_document_monetization_policies"
SHARE_LINK_PUBLIC_APP_URL_KEY = "share_link_public_app_url"

# Zohal Service Configuration Keys
ZOHAL_API_KEY = "zohal_api_key"
ZOHAL_BASE_URL = "zohal_base_url"
ZOHAL_LOW_BALANCE_THRESHOLD = "zohal_low_balance_threshold"

# System Configuration Keys
SYSTEM_CONFIG_APP_NAME = "system_config_app_name"
SYSTEM_CONFIG_APP_VERSION = "system_config_app_version"
SYSTEM_CONFIG_DEFAULT_LANGUAGE = "system_config_default_language"
SYSTEM_CONFIG_DEFAULT_THEME = "system_config_default_theme"
SYSTEM_CONFIG_ENABLE_REGISTRATION = "system_config_enable_registration"
SYSTEM_CONFIG_ENABLE_EMAIL_VERIFICATION = "system_config_enable_email_verification"
SYSTEM_CONFIG_ENABLE_MAINTENANCE_MODE = "system_config_enable_maintenance_mode"
SYSTEM_CONFIG_SESSION_TIMEOUT = "system_config_session_timeout"
SYSTEM_CONFIG_MAX_FILE_SIZE = "system_config_max_file_size"
SYSTEM_CONFIG_MAX_USERS = "system_config_max_users"

# Redis Cache Configuration Keys
REDIS_CONFIG_ENABLED = "redis_config_enabled"
REDIS_CONFIG_HOST = "redis_config_host"
REDIS_CONFIG_PORT = "redis_config_port"
REDIS_CONFIG_DB = "redis_config_db"
REDIS_CONFIG_PASSWORD = "redis_config_password"


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
		"sms_provider_username": db_values.get("sms_provider_username"),
		"sms_provider_password": db_values.get("sms_provider_password"),
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
	}

def set_notifications_settings(
	db: Session,
	*, telegram_bot_token: str | None = None,
	telegram_bot_username: str | None = None,
	telegram_webhook_secret: str | None = None,
	telegram_secret_header: str | None = None,
	sms_provider_name: str | None = None,
	sms_api_key: str | None = None,
	sms_sender: str | None = None,
	sms_provider_username: str | None = None,
	sms_provider_password: str | None = None,
	sms_is_flash: bool | None = None,
	telegram_proxy_enabled: bool | None = None,
	telegram_proxy_base_url: str | None = None,
	telegram_proxy_api_key: str | None = None,
) -> Dict[str, Any]:
	if telegram_bot_token is not None:
		_upsert_setting_string(db, NOTIFY_TG_BOT_TOKEN, telegram_bot_token)
	if telegram_bot_username is not None:
		_upsert_setting_string(db, NOTIFY_TG_BOT_USERNAME, telegram_bot_username)
	if telegram_webhook_secret is not None:
		_upsert_setting_string(db, NOTIFY_TG_WEBHOOK_SECRET, telegram_webhook_secret)
	if telegram_secret_header is not None:
		_upsert_setting_string(db, NOTIFY_TG_SECRET_HEADER, telegram_secret_header)
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
	db.commit()
	return get_notifications_settings(db)


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
	return (max_users if max_users is not None else 1000)


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
	
	return {
		"app_name": (app_name.value_string if app_name and app_name.value_string else env.app_name),
		"app_version": (app_version.value_string if app_version and app_version.value_string else env.app_version),
		"default_language": (default_language.value_string if default_language and default_language.value_string else "fa"),
		"default_theme": (default_theme.value_string if default_theme and default_theme.value_string else "system"),
		"enable_registration": (enable_registration if enable_registration is not None else True),
		"enable_email_verification": (enable_email_verification if enable_email_verification is not None else True),
		"enable_maintenance_mode": (enable_maintenance_mode if enable_maintenance_mode is not None else False),
		"session_timeout": (session_timeout if session_timeout is not None else 30),
		"max_file_size": (max_file_size if max_file_size is not None else 10),
		"max_users": (max_users if max_users is not None else 1000),
	}


def set_system_configuration(
	db: Session,
	*,
	app_name: str | None = None,
	app_version: str | None = None,
	default_language: str | None = None,
	default_theme: str | None = None,
	enable_registration: bool | None = None,
	enable_email_verification: bool | None = None,
	enable_maintenance_mode: bool | None = None,
	session_timeout: int | None = None,
	max_file_size: int | None = None,
	max_users: int | None = None,
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
	
	if enable_registration is not None:
		_upsert_setting_bool(db, SYSTEM_CONFIG_ENABLE_REGISTRATION, enable_registration)
	
	if enable_email_verification is not None:
		_upsert_setting_bool(db, SYSTEM_CONFIG_ENABLE_EMAIL_VERIFICATION, enable_email_verification)
	
	if enable_maintenance_mode is not None:
		_upsert_setting_bool(db, SYSTEM_CONFIG_ENABLE_MAINTENANCE_MODE, enable_maintenance_mode)
		cache.delete("system:maintenance_mode")  # Invalidate cache
	
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
