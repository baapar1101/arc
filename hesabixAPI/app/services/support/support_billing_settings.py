"""تنظیمات صورتحساب پشتیبانی (سطح سیستم)."""

from __future__ import annotations

import json
from typing import Any, Dict, List, Optional

from sqlalchemy.orm import Session

from app.core.responses import ApiError
from app.services.system_settings_service import (
	_get_setting,
	_get_setting_bool,
	_get_setting_int,
	_upsert_setting_bool,
	_upsert_setting_int,
	_upsert_setting_string,
)

SYSTEM_CONFIG_SUPPORT_BILLING_MODE = "system_config_support_billing_mode"
SYSTEM_CONFIG_SUPPORT_FREE_QUOTA_PER_MONTH = "system_config_support_free_quota_per_month"
SYSTEM_CONFIG_SUPPORT_GRACE_PERIOD_DAYS = "system_config_support_grace_period_days"
SYSTEM_CONFIG_SUPPORT_ALLOW_READ_WITHOUT_SUB = "system_config_support_allow_read_without_subscription"
SYSTEM_CONFIG_SUPPORT_REQUIRE_SUB_TO_REPLY = "system_config_support_require_subscription_to_reply"
SYSTEM_CONFIG_SUPPORT_DEFAULT_GATEWAY_ID = "system_config_support_default_gateway_id"
SYSTEM_CONFIG_SUPPORT_INVOICE_PREFIX = "system_config_support_invoice_prefix"
SYSTEM_CONFIG_SUPPORT_EXPIRY_NOTIFY_DAYS = "system_config_support_expiry_notify_days"
SYSTEM_CONFIG_SUPPORT_PAID_PRIORITY_BOOST = "system_config_support_paid_priority_boost"

ALLOWED_BILLING_MODES = ("free", "paid", "hybrid")


def get_support_billing_mode(db: Session) -> str:
	obj = _get_setting(db, SYSTEM_CONFIG_SUPPORT_BILLING_MODE)
	raw = (obj.value_string if obj and obj.value_string else "free").strip().lower()
	return raw if raw in ALLOWED_BILLING_MODES else "free"


def get_support_free_quota_per_month(db: Session) -> int:
	val = _get_setting_int(db, SYSTEM_CONFIG_SUPPORT_FREE_QUOTA_PER_MONTH)
	if val is None:
		return 2
	return max(0, int(val))


def get_support_grace_period_days(db: Session) -> int:
	val = _get_setting_int(db, SYSTEM_CONFIG_SUPPORT_GRACE_PERIOD_DAYS)
	if val is None:
		return 3
	return max(0, int(val))


def get_support_allow_read_without_subscription(db: Session) -> bool:
	raw = _get_setting_bool(db, SYSTEM_CONFIG_SUPPORT_ALLOW_READ_WITHOUT_SUB)
	return True if raw is None else bool(raw)


def get_support_require_subscription_to_reply(db: Session) -> bool:
	raw = _get_setting_bool(db, SYSTEM_CONFIG_SUPPORT_REQUIRE_SUB_TO_REPLY)
	return True if raw is None else bool(raw)


def get_support_default_gateway_id(db: Session) -> Optional[int]:
	val = _get_setting_int(db, SYSTEM_CONFIG_SUPPORT_DEFAULT_GATEWAY_ID)
	if val is None or int(val) <= 0:
		return None
	return int(val)


def get_support_invoice_prefix(db: Session) -> str:
	obj = _get_setting(db, SYSTEM_CONFIG_SUPPORT_INVOICE_PREFIX)
	prefix = (obj.value_string if obj and obj.value_string else "SUP").strip().upper()
	return (prefix or "SUP")[:10]


def get_support_expiry_notify_days(db: Session) -> List[int]:
	obj = _get_setting(db, SYSTEM_CONFIG_SUPPORT_EXPIRY_NOTIFY_DAYS)
	if obj and obj.value_string:
		try:
			data = json.loads(obj.value_string)
			if isinstance(data, list):
				return sorted({int(x) for x in data if int(x) > 0}, reverse=True)
		except Exception:
			pass
	return [7, 3, 1]


def get_support_paid_priority_boost(db: Session) -> bool:
	raw = _get_setting_bool(db, SYSTEM_CONFIG_SUPPORT_PAID_PRIORITY_BOOST)
	return True if raw is None else bool(raw)


def support_billing_settings_dict(db: Session) -> Dict[str, Any]:
	return {
		"support_billing_mode": get_support_billing_mode(db),
		"support_free_quota_per_month": get_support_free_quota_per_month(db),
		"support_grace_period_days": get_support_grace_period_days(db),
		"support_allow_read_without_subscription": get_support_allow_read_without_subscription(db),
		"support_require_subscription_to_reply": get_support_require_subscription_to_reply(db),
		"support_default_gateway_id": get_support_default_gateway_id(db),
		"support_invoice_prefix": get_support_invoice_prefix(db),
		"support_expiry_notify_days": get_support_expiry_notify_days(db),
		"support_paid_priority_boost": get_support_paid_priority_boost(db),
	}


def apply_support_billing_settings(
	db: Session,
	*,
	support_billing_mode: str | None = None,
	support_free_quota_per_month: int | None = None,
	support_grace_period_days: int | None = None,
	support_allow_read_without_subscription: bool | None = None,
	support_require_subscription_to_reply: bool | None = None,
	support_default_gateway_id: int | None = None,
	support_invoice_prefix: str | None = None,
	support_expiry_notify_days: list | None = None,
	support_paid_priority_boost: bool | None = None,
	clear_default_gateway: bool = False,
) -> None:
	if support_billing_mode is not None:
		mode = str(support_billing_mode).strip().lower()
		if mode not in ALLOWED_BILLING_MODES:
			raise ApiError(
				"INVALID_SUPPORT_BILLING_MODE",
				"حالت صورتحساب پشتیبانی باید free، paid یا hybrid باشد",
				http_status=400,
			)
		_upsert_setting_string(db, SYSTEM_CONFIG_SUPPORT_BILLING_MODE, mode)

	if support_free_quota_per_month is not None:
		_upsert_setting_int(
			db,
			SYSTEM_CONFIG_SUPPORT_FREE_QUOTA_PER_MONTH,
			max(0, int(support_free_quota_per_month)),
		)

	if support_grace_period_days is not None:
		_upsert_setting_int(
			db,
			SYSTEM_CONFIG_SUPPORT_GRACE_PERIOD_DAYS,
			max(0, int(support_grace_period_days)),
		)

	if support_allow_read_without_subscription is not None:
		_upsert_setting_bool(
			db,
			SYSTEM_CONFIG_SUPPORT_ALLOW_READ_WITHOUT_SUB,
			bool(support_allow_read_without_subscription),
		)

	if support_require_subscription_to_reply is not None:
		_upsert_setting_bool(
			db,
			SYSTEM_CONFIG_SUPPORT_REQUIRE_SUB_TO_REPLY,
			bool(support_require_subscription_to_reply),
		)

	if clear_default_gateway:
		_upsert_setting_int(db, SYSTEM_CONFIG_SUPPORT_DEFAULT_GATEWAY_ID, 0)
	elif support_default_gateway_id is not None:
		gid = int(support_default_gateway_id)
		if gid < 0:
			raise ApiError("INVALID_GATEWAY", "شناسه درگاه نامعتبر است", http_status=400)
		if gid > 0:
			from adapters.db.models.payment_gateway import PaymentGateway

			gw = db.query(PaymentGateway).filter(PaymentGateway.id == gid).first()
			if not gw:
				raise ApiError("GATEWAY_NOT_FOUND", "درگاه پرداخت یافت نشد", http_status=404)
		_upsert_setting_int(db, SYSTEM_CONFIG_SUPPORT_DEFAULT_GATEWAY_ID, gid)

	if support_invoice_prefix is not None:
		prefix = str(support_invoice_prefix).strip().upper()[:10] or "SUP"
		_upsert_setting_string(db, SYSTEM_CONFIG_SUPPORT_INVOICE_PREFIX, prefix)

	if support_expiry_notify_days is not None:
		days = sorted({int(x) for x in support_expiry_notify_days if int(x) > 0}, reverse=True)
		_upsert_setting_string(
			db,
			SYSTEM_CONFIG_SUPPORT_EXPIRY_NOTIFY_DAYS,
			json.dumps(days or [7, 3, 1], ensure_ascii=False),
		)

	if support_paid_priority_boost is not None:
		_upsert_setting_bool(
			db,
			SYSTEM_CONFIG_SUPPORT_PAID_PRIORITY_BOOST,
			bool(support_paid_priority_boost),
		)
