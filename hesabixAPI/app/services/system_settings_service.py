from __future__ import annotations

from typing import Optional, Dict, Any

from sqlalchemy.orm import Session
from sqlalchemy import select

from adapters.db.models.system_setting import SystemSetting
from adapters.db.models.currency import Currency
from app.core.responses import ApiError


WALLET_BASE_CURRENCY_KEY = "wallet_base_currency_code"
DEFAULT_WALLET_CURRENCY_CODE = "IRR"
NOTIFY_TG_BOT_TOKEN = "telegram_bot_token"
NOTIFY_TG_BOT_USERNAME = "telegram_bot_username"
NOTIFY_TG_WEBHOOK_SECRET = "telegram_webhook_secret"
NOTIFY_TG_SECRET_HEADER = "telegram_secret_header"
NOTIFY_SMS_PROVIDER = "sms_provider_name"
NOTIFY_SMS_API_KEY = "sms_api_key"
NOTIFY_SMS_SENDER = "sms_sender"


def _get_setting(db: Session, key: str) -> Optional[SystemSetting]:
	return db.execute(
		select(SystemSetting).where(SystemSetting.key == key)
	).scalars().first()


def _upsert_setting_string(db: Session, key: str, value: str) -> SystemSetting:
	obj = _get_setting(db, key)
	if obj:
		obj.value_string = value
	else:
		obj = SystemSetting(key=key, value_string=value)
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
	return {
		"wallet_base_currency_code": code,
		"wallet_base_currency_id": currency.id,
	}

def get_notifications_settings(db: Session) -> Dict[str, Any]:
	return {
		"telegram_bot_token": (_get_setting(db, NOTIFY_TG_BOT_TOKEN).value_string if _get_setting(db, NOTIFY_TG_BOT_TOKEN) else None),
		"telegram_bot_username": (_get_setting(db, NOTIFY_TG_BOT_USERNAME).value_string if _get_setting(db, NOTIFY_TG_BOT_USERNAME) else None),
		"telegram_webhook_secret": (_get_setting(db, NOTIFY_TG_WEBHOOK_SECRET).value_string if _get_setting(db, NOTIFY_TG_WEBHOOK_SECRET) else None),
		"telegram_secret_header": (_get_setting(db, NOTIFY_TG_SECRET_HEADER).value_string if _get_setting(db, NOTIFY_TG_SECRET_HEADER) else None),
		"sms_provider_name": (_get_setting(db, NOTIFY_SMS_PROVIDER).value_string if _get_setting(db, NOTIFY_SMS_PROVIDER) else None),
		"sms_api_key": (_get_setting(db, NOTIFY_SMS_API_KEY).value_string if _get_setting(db, NOTIFY_SMS_API_KEY) else None),
		"sms_sender": (_get_setting(db, NOTIFY_SMS_SENDER).value_string if _get_setting(db, NOTIFY_SMS_SENDER) else None),
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
	return get_notifications_settings(db)
