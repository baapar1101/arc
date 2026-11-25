"""حسابداری تسویه دیجی‌پی، تاریخ شمسی/میلادی و کلاینت UPG."""

from __future__ import annotations

from decimal import Decimal
from types import SimpleNamespace

import pytest

from app.core.date_input import format_user_date, parse_user_date
from app.services.digipay_client import DIGIPAY_VERSION, DigipayClient, TICKET_TYPE_UPG
from app.services.digipay_service import (
	_callback_amount_rials,
	_normalize_mobile,
	_rials,
	_settlement_splits,
	_ticket_redirect_url,
)


def test_settlement_splits_balance_with_vat_on_commission():
	splits = _settlement_splits(Decimal("1000000"), Decimal("2"), Decimal("10"))
	assert splits["commission"] == Decimal("20000.00")
	assert splits["vat"] == Decimal("2000.00")
	assert splits["net"] == Decimal("978000.00")
	assert splits["gross"] == splits["net"] + splits["commission"] + splits["vat"]


def test_settlement_rejects_negative_net():
	from app.core.responses import ApiError

	with pytest.raises(ApiError) as exc:
		_settlement_splits(Decimal("100"), Decimal("90"), Decimal("50"))
	assert exc.value.code == "DIGIPAY_SETTLEMENT_NEGATIVE"


def test_rials_rounds_half_up():
	assert _rials(Decimal("10.4")) == 10
	assert _rials(Decimal("10.5")) == 11


def test_normalize_mobile_accepts_local_and_98():
	assert _normalize_mobile("09121234567", "fa") == "09121234567"
	assert _normalize_mobile("+989121234567", "en") == "09121234567"
	assert _normalize_mobile("9121234567", "fa") == "09121234567"


def test_normalize_mobile_rejects_invalid():
	from app.core.responses import ApiError

	with pytest.raises(ApiError) as exc:
		_normalize_mobile("123", "en")
	assert exc.value.code == "DIGIPAY_INVALID_MOBILE"


def test_jalali_and_gregorian_settlement_dates_roundtrip():
	jalali = parse_user_date("1404/08/10", calendar_type="jalali")
	assert jalali is not None
	assert format_user_date(jalali, calendar_type="jalali") == "1404/08/10"
	gregorian = parse_user_date(jalali.isoformat(), calendar_type="gregorian")
	assert gregorian == jalali
	assert format_user_date(gregorian, calendar_type="gregorian") == jalali.isoformat()


class _FakeResponse:
	def __init__(self, status_code: int, payload: dict):
		self.status_code = status_code
		self._payload = payload

	def json(self):
		return self._payload


def test_ticket_redirect_url_accepts_payurl_alias():
	assert _ticket_redirect_url({"redirectUrl": "https://pay.example/a"}) == "https://pay.example/a"
	assert _ticket_redirect_url({"payUrl": "https://pay.example/b"}) == "https://pay.example/b"
	assert _ticket_redirect_url({}) is None


def test_callback_amount_parses_form_strings():
	assert _callback_amount_rials("10000") == 10000
	assert _callback_amount_rials("10000.0") == 10000
	assert _callback_amount_rials(10000.4) == 10000
	assert _callback_amount_rials("") is None
	assert _callback_amount_rials(None) is None


def test_upg_client_login_sends_password_grant_form():
	calls = []

	def fake_post(url, json_body=None, form=None, headers=None):
		calls.append(SimpleNamespace(url=url, json_body=json_body, form=form, headers=headers or {}))
		return _FakeResponse(200, {"access_token": "tok", "expires_in": 3600})

	client = DigipayClient(
		username="u",
		password="p",
		client_id="id",
		client_secret="secret",
		environment="sandbox",
		http_post=fake_post,
	)
	assert client.login() == "tok"
	login = calls[0]
	assert "oauth/token" in login.url
	assert login.form == {"username": "u", "password": "p", "grant_type": "password"}
	assert str(login.headers.get("Authorization", "")).startswith("Basic ")


def test_upg_client_ticket_uses_type_11_and_version_header():
	calls = []

	def fake_post(url, json_body=None, form=None, headers=None):
		calls.append(SimpleNamespace(url=url, json_body=json_body, form=form, headers=headers or {}))
		if "oauth/token" in url:
			return _FakeResponse(200, {"access_token": "tok", "expires_in": 3600})
		return _FakeResponse(200, {"result": {"status": 0}, "ticket": "T1", "redirectUrl": "https://pay.example/x"})

	client = DigipayClient(
		username="u",
		password="p",
		client_id="id",
		client_secret="secret",
		environment="sandbox",
		http_post=fake_post,
	)
	data = client.create_ticket({"cellNumber": "09120000000", "amount": 1000, "providerId": "hx1"})
	assert data["ticket"] == "T1"
	assert any("oauth/token" in c.url for c in calls)
	ticket_call = next(c for c in calls if "tickets/business" in c.url)
	assert f"type={TICKET_TYPE_UPG}" in ticket_call.url
	assert ticket_call.headers.get("Digipay-Version") == DIGIPAY_VERSION
	assert ticket_call.headers.get("Authorization") == "Bearer tok"
