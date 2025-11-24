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


WALLET_BASE_CURRENCY_KEY = "wallet_base_currency_code"
DEFAULT_WALLET_CURRENCY_CODE = "IRR"
NOTIFY_TG_BOT_TOKEN = "telegram_bot_token"
NOTIFY_TG_BOT_USERNAME = "telegram_bot_username"
NOTIFY_TG_WEBHOOK_SECRET = "telegram_webhook_secret"
NOTIFY_TG_SECRET_HEADER = "telegram_secret_header"
NOTIFY_SMS_PROVIDER = "sms_provider_name"
NOTIFY_SMS_API_KEY = "sms_api_key"
NOTIFY_SMS_SENDER = "sms_sender"
NOTIFY_TG_PROXY_ENABLED = "telegram_proxy_enabled"
NOTIFY_TG_PROXY_BASE_URL = "telegram_proxy_base_url"
NOTIFY_TG_PROXY_API_KEY = "telegram_proxy_api_key"
DEFAULT_DOCUMENT_POLICIES_KEY = "default_document_monetization_policies"
SHARE_LINK_PUBLIC_APP_URL_KEY = "share_link_public_app_url"


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
