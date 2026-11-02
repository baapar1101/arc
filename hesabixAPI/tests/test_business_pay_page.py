from decimal import Decimal
from unittest.mock import MagicMock, patch

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from adapters.api.v1.public_pay_pages import router as public_pay_pages_router
from adapters.db.session import get_db
from adapters.db.models.wallet import WalletTransaction
from adapters.db.seed_data.notification_event_types_seed import (
	NOTIFICATION_EVENT_TYPES_ROWS,
	PAY_LINK_RECEIVED_EVENT_CODES,
)
from app.core.payment_response import render_public_business_pay_page
from app.core.responses import ApiError
from app.services.business_pay_page_service import (
	GATEWAY_MIN_AMOUNT,
	RESERVED_USERNAMES,
	parse_pay_amount,
	validate_payer_mobile,
	validate_payer_name,
	validate_payer_note,
	validate_username_format,
)
from app.services.public_pay_page_payment_service import maybe_redirect_public_pay_page_payment_return


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


def _public_pay_html_client() -> TestClient:
	app = FastAPI()
	app.include_router(public_pay_pages_router)

	def _db():
		yield MagicMock()

	app.dependency_overrides[get_db] = _db
	return TestClient(app)


def _enabled_page_payload(**overrides):
	data = {
		"username": "shop-ali",
		"redirect_to": None,
		"is_enabled": True,
		"display_title": "فروشگاه علی",
		"business_name": "فروشگاه علی",
		"show_logo": False,
		"intro_text": "خوش آمدید",
		"min_amount": 50000,
		"currency_title": "ریال",
		"phone": "02112345678",
		"mobile": "09121234567",
		"postal_code": "1234567890",
	}
	data.update(overrides)
	return data


def test_public_pay_html_template_renders_title():
	html = render_public_business_pay_page(
		{
			"app_name": "حسابیکس",
			"username": "shop-ali",
			"page_title": "فروشگاه علی",
			"heading": "پرداخت به فروشگاه علی",
			"display_title": "فروشگاه علی",
			"intro_text": "متن راهنما",
			"show_logo": False,
			"logo_url": "",
			"is_enabled": True,
			"not_found": False,
			"not_found_message": "یافت نشد",
			"disabled_message": "غیرفعال",
			"error_message": "",
			"payment_status": "",
			"receipt_title": "رسید",
			"receipt_success": "موفق",
			"receipt_failed": "ناموفق",
			"tracking_label": "پیگیری",
			"receipt_ref": "",
			"receipt_tx": "",
			"amount_label": "مبلغ",
			"name_label": "نام",
			"mobile_label": "موبایل",
			"note_label": "توضیح",
			"pay_button": "پرداخت",
			"currency_hint": "مبلغ به ریال است",
			"min_amount_hint": "حداقل 50,000",
			"form_amount": "",
			"form_name": "",
			"form_mobile": "",
			"form_note": "",
		}
	)
	assert html.status_code == 200
	body = html.body.decode("utf-8")
	assert "پرداخت به فروشگاه علی" in body
	assert 'name="amount"' in body
	assert "YekanBakhFaNum" in body


def test_short_pay_page_serves_backend_html_not_flutter_redirect():
	client = _public_pay_html_client()
	with patch(
		"adapters.api.v1.public_pay_pages.get_public_pay_page",
		return_value=_enabled_page_payload(),
	), patch(
		"adapters.api.v1.public_pay_pages.resolve_payment_display_name",
		return_value="حسابیکس",
	):
		res = client.get("/u/shop-ali", follow_redirects=False)
	assert res.status_code == 200
	assert "text/html" in res.headers.get("content-type", "")
	assert "پرداخت به فروشگاه علی" in res.text
	assert "/public/pay/" not in (res.headers.get("location") or "")
	assert 'action="/u/shop-ali"' in res.text
	assert "02112345678" in res.text
	assert "09121234567" in res.text
	assert "1234567890" in res.text
	assert "فیشینگ" in res.text
	assert "گزارش تخلف" in res.text
	assert "قبل از واریز" in res.text


def test_short_pay_page_unknown_username_is_html_404():
	client = _public_pay_html_client()
	with patch(
		"adapters.api.v1.public_pay_pages.get_public_pay_page",
		side_effect=ApiError("PAY_PAGE_NOT_FOUND", "صفحه پرداخت یافت نشد", http_status=404),
	), patch(
		"adapters.api.v1.public_pay_pages.resolve_payment_display_name",
		return_value="حسابیکس",
	):
		res = client.get("/u/nobody-here")
	assert res.status_code == 404
	assert "این صفحه پرداخت یافت نشد" in res.text


def test_short_pay_page_former_username_redirects_to_canonical():
	client = _public_pay_html_client()
	with patch(
		"adapters.api.v1.public_pay_pages.get_public_pay_page",
		return_value=_enabled_page_payload(username="shop-ali", redirect_to="shop-ali"),
	):
		res = client.get("/u/old-shop", follow_redirects=False)
	assert res.status_code == 302
	assert res.headers["location"] == "/u/shop-ali"


def test_short_pay_page_form_post_redirects_to_gateway():
	client = _public_pay_html_client()
	with patch(
		"adapters.api.v1.public_pay_pages.get_public_pay_page",
		return_value=_enabled_page_payload(),
	), patch(
		"adapters.api.v1.public_pay_pages.start_public_pay_page_payment",
		return_value={"payment_url": "https://bank.example/pay"},
	), patch(
		"adapters.api.v1.public_pay_pages.resolve_payment_display_name",
		return_value="حسابیکس",
	):
		res = client.post(
			"/u/shop-ali",
			data={"amount": "100000", "confirm_business": "1"},
			follow_redirects=False,
		)
	assert res.status_code == 303
	assert res.headers["location"] == "https://bank.example/pay"


def test_gateway_return_redirects_to_backend_short_url():
	db = MagicMock()
	tx = WalletTransaction(
		business_id=1,
		type="public_pay_link",
		status="pending",
		amount=100000,
	)
	tx.extra_info = '{"username": "ali", "receipt_token": "tok123"}'
	db.query.return_value.filter.return_value.first.return_value = tx
	with patch(
		"app.services.public_pay_page_payment_service.resolve_public_app_base_url_for_public_links",
		return_value="https://app.example",
	):
		resp = maybe_redirect_public_pay_page_payment_return(
			db,
			tx_id=9,
			verify_data={"success": True, "external_ref": "R1"},
		)
	assert resp is not None
	assert resp.status_code == 302
	location = resp.headers["location"]
	assert location == "https://app.example/u/ali/r/tok123"
	assert "/public/pay/" not in location


def test_public_business_contact_rows_skip_empty():
	from app.services.business_pay_page_service import public_business_contact_rows

	rows = public_business_contact_rows(
		{
			"business_name": "فروشگاه علی",
			"phone": "0211",
			"mobile": None,
			"postal_code": "  ",
		}
	)
	labels = {r["label"] for r in rows}
	assert "نام کسب‌وکار" in labels
	assert "تلفن" in labels
	assert "موبایل" not in labels
	assert "کد پستی" not in labels


def test_short_pay_page_requires_business_confirm():
	client = _public_pay_html_client()
	with patch(
		"adapters.api.v1.public_pay_pages.get_public_pay_page",
		return_value=_enabled_page_payload(),
	), patch(
		"adapters.api.v1.public_pay_pages.resolve_payment_display_name",
		return_value="حسابیکس",
	):
		res = client.post("/u/shop-ali", data={"amount": "100000"}, follow_redirects=False)
	assert res.status_code == 400
	assert "بررسی" in res.text


def test_short_pay_page_abuse_report_is_recorded():
	client = _public_pay_html_client()
	with patch(
		"adapters.api.v1.public_pay_pages.get_public_pay_page",
		return_value=_enabled_page_payload(),
	), patch(
		"adapters.api.v1.public_pay_pages.submit_pay_page_abuse_report",
		return_value={"id": 1},
	) as submit, patch(
		"adapters.api.v1.public_pay_pages.resolve_payment_display_name",
		return_value="حسابیکس",
	):
		res = client.post(
			"/u/shop-ali/report",
			data={
				"reason": "phishing",
				"details": "این صفحه با کسب‌وکار واقعی همخوانی ندارد و مشکوک است",
			},
		)
	assert res.status_code == 200
	assert "گزارش شما ثبت شد" in res.text
	assert submit.called


def test_gateway_tracking_reads_legacy_and_unified_fields():
	from app.services.business_pay_page_service import gateway_tracking_from_extra

	legacy = gateway_tracking_from_extra(
		{"parsian_card": "6037-****-1234", "parsian_rrn": "998877", "receipt_token": "tok"}
	)
	assert legacy["card_num"] == "6037-****-1234"
	assert legacy["gateway_ref_id"] == "998877"
	assert legacy["receipt_token"] == "tok"

	unified = gateway_tracking_from_extra(
		{
			"card_num": "5022****8899",
			"gateway_ref_id": "ref-1",
			"factor_id": "44",
			"gateway_verify": {"card_num": "ignored", "trans_id": "t9"},
		}
	)
	assert unified["card_num"] == "5022****8899"
	assert unified["gateway_ref_id"] == "ref-1"
	assert unified["factor_id"] == "44"
	assert unified["gateway_verify"]["trans_id"] == "t9"


def test_persist_gateway_verify_keeps_payer_fields():
	import json

	from app.services.payment_service import persist_gateway_verify_on_tx

	tx = WalletTransaction()
	extra = {"payer_name": "علی", "payer_mobile": "09121234567"}
	persist_gateway_verify_on_tx(
		tx,
		extra,
		card_num=" 603799******1234 ",
		ref_id=987654,
		factor_id="12",
		extra_fields={"trans_id": "bit-1", "status": 1},
	)
	assert extra["payer_name"] == "علی"
	assert extra["card_num"] == "603799******1234"
	assert extra["gateway_ref_id"] == "987654"
	assert extra["factor_id"] == "12"
	stored = json.loads(tx.extra_info or "{}")
	assert stored["gateway_verify"]["card_num"] == "603799******1234"
	assert stored["gateway_verify"]["trans_id"] == "bit-1"


def test_pay_page_html_loads_persian_font_and_brand_name():
	html = render_public_business_pay_page(
		{
			"app_name": "آرک حسابداری",
			"username": "shop-ali",
			"page_title": "فروشگاه علی",
			"heading": "پرداخت به فروشگاه علی",
			"display_title": "فروشگاه علی",
			"intro_text": "",
			"show_logo": False,
			"logo_url": "",
			"is_enabled": True,
			"not_found": False,
			"not_found_message": "",
			"disabled_message": "",
			"error_message": "",
			"payment_status": "",
			"receipt_title": "",
			"receipt_success": "",
			"receipt_failed": "",
			"tracking_label": "",
			"receipt_ref": "",
			"receipt_tx": "",
			"amount_label": "مبلغ",
			"name_label": "نام",
			"mobile_label": "موبایل",
			"note_label": "توضیح",
			"pay_button": "پرداخت",
			"currency_hint": "",
			"min_amount_hint": "",
			"form_amount": "",
			"form_name": "",
			"form_mobile": "",
			"form_note": "",
			"business_rows": [],
		}
	)
	body = html.body.decode("utf-8")
	assert "YekanBakhFaNum" in body
	assert "/api/v1/public/pay-fonts/YekanBakhFaNum-Regular.woff2" in body
	assert "آرک حسابداری مبلغ را برای این کسب‌وکار دریافت می‌کند" in body
	assert "حسابیکس مبلغ" not in body


def test_pay_page_font_endpoint_serves_yekan():
	client = _public_pay_html_client()
	res = client.get("/api/v1/public/pay-fonts/YekanBakhFaNum-Regular.woff2")
	assert res.status_code == 200
	assert "font" in (res.headers.get("content-type") or "")
	assert len(res.content) > 1000
	missing = client.get("/api/v1/public/pay-fonts/not-a-font.woff2")
	assert missing.status_code == 404


def test_resolve_payment_display_name_uses_rebrand_fa(monkeypatch, tmp_path):
	from app.core.payment_response import resolve_payment_display_name, rebrand_product_text

	env_file = tmp_path / "deploy.env"
	env_file.write_text(
		"BRANDING_MODE=custom\nAPP_NAME_FA=فروشگاه آرک\nAPP_NAME_EN=Arc Shop\n",
		encoding="utf-8",
	)
	monkeypatch.setenv("HESABIX_DEPLOY_ENV", str(env_file))
	monkeypatch.delenv("APP_NAME_FA", raising=False)
	monkeypatch.delenv("APP_NAME_EN", raising=False)
	monkeypatch.delenv("BRANDING_MODE", raising=False)
	with patch("app.services.system_settings_service.get_app_name", return_value="Hesabix API"):
		assert resolve_payment_display_name(MagicMock()) == "فروشگاه آرک"
	assert rebrand_product_text("پرداخت با حسابیکس", "فروشگاه آرک") == "پرداخت با فروشگاه آرک"
