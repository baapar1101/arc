from decimal import Decimal

import pytest

from app.core.responses import ApiError
from adapters.db.seed_data.notification_event_types_seed import (
	NOTIFICATION_EVENT_TYPES_ROWS,
	PAY_LINK_RECEIVED_EVENT_CODES,
)
from app.services.business_pay_page_service import (
	GATEWAY_MIN_AMOUNT,
	RESERVED_USERNAMES,
	parse_pay_amount,
	validate_payer_mobile,
	validate_payer_name,
	validate_payer_note,
	validate_username_format,
)


def test_username_format_accepts_valid_handles():
	assert validate_username_format("mohammad") == "mohammad"
	assert validate_username_format("Shop-01") == "shop-01"


def test_username_rejects_reserved_and_invalid():
	with pytest.raises(ApiError) as exc:
		validate_username_format("admin")
	assert exc.value.code == "USERNAME_RESERVED"
	assert "admin" in RESERVED_USERNAMES
	with pytest.raises(ApiError) as exc:
		validate_username_format("ab")
	assert exc.value.code == "INVALID_USERNAME"
	with pytest.raises(ApiError):
		validate_username_format("Ali_Reza")
	with pytest.raises(ApiError):
		validate_username_format("-bad")
	with pytest.raises(ApiError):
		validate_username_format("bad--name")


def test_payer_name_letters_and_zwnj():
	assert validate_payer_name("محمد رضا") == "محمد رضا"
	assert validate_payer_name(None) is None
	assert validate_payer_name("  ") is None
	with pytest.raises(ApiError):
		validate_payer_name("ali123")
	with pytest.raises(ApiError):
		validate_payer_name("الف" * 20)


def test_payer_mobile_iranian_rule():
	assert validate_payer_mobile("09121234567") == "09121234567"
	assert validate_payer_mobile("۰۹۱۲۱۲۳۴۵۶۷") == "09121234567"
	assert validate_payer_mobile("") is None
	with pytest.raises(ApiError):
		validate_payer_mobile("091212345")
	with pytest.raises(ApiError):
		validate_payer_mobile("08121234567")


def test_amount_and_note():
	assert parse_pay_amount("1,250,000") == Decimal("1250000")
	assert parse_pay_amount("۵۰۰۰۰") == Decimal("50000")
	with pytest.raises(ApiError):
		parse_pay_amount("0")
	assert GATEWAY_MIN_AMOUNT == Decimal("50000")
	assert validate_payer_note("ok") == "ok"
	assert validate_payer_note(None) is None
	with pytest.raises(ApiError):
		validate_payer_note("x" * 1001)


def test_pay_link_received_event_is_in_seed_catalog():
	codes = {row["code"] for row in NOTIFICATION_EVENT_TYPES_ROWS}
	assert PAY_LINK_RECEIVED_EVENT_CODES <= codes
	row = next(r for r in NOTIFICATION_EVENT_TYPES_ROWS if r["code"] == "pay_link.received")
	assert "{{ payer_name }}" in row["default_sms_template"]
	assert "{{ amount }}" in row["default_sms_template"]
