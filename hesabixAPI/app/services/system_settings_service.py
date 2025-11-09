from __future__ import annotations

from typing import Optional, Dict, Any

from sqlalchemy.orm import Session
from sqlalchemy import select

from adapters.db.models.system_setting import SystemSetting
from adapters.db.models.currency import Currency
from app.core.responses import ApiError


WALLET_BASE_CURRENCY_KEY = "wallet_base_currency_code"
DEFAULT_WALLET_CURRENCY_CODE = "IRR"


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


