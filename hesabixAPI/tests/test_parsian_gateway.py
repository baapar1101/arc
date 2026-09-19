from unittest.mock import MagicMock, patch

import pytest

from app.core.responses import ApiError
from app.services.parsian_gateway import (
	SALE_NS,
	SALE_SOAP_ACTION,
	SUPPORT_ORDER_BASE,
	WALLET_ORDER_BASE,
	build_sale_envelope,
	build_startpay_url,
	callback_paid,
	confirm_payment,
	decode_order_id,
	make_order_id,
	parse_amount,
	parse_confirm_response,
	parse_sale_response,
	resolve_login_account,
	resolve_sale_url,
	sale_payment_request,
)
from app.services.payment_service import _initiate_parsian, _verify_parsian
from app.services.support.support_payment_gateway import (
	_initiate_parsian as _initiate_support_parsian,
	_verify_parsian as _verify_support_parsian,
)


SALE_OK_XML = """<?xml version="1.0" encoding="utf-8"?>
<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
  <soap:Body>
    <SalePaymentRequestResponse xmlns="https://pec.Shaparak.ir/NewIPGServices/Sale/SaleService">
      <SalePaymentRequestResult>
        <Status>0</Status>
        <Token>9876543210</Token>
        <Message>موفق</Message>
      </SalePaymentRequestResult>
    </SalePaymentRequestResponse>
  </soap:Body>
</soap:Envelope>
"""

SALE_FAIL_XML = """<?xml version="1.0" encoding="utf-8"?>
<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
  <soap:Body>
    <SalePaymentRequestResponse xmlns="https://pec.Shaparak.ir/NewIPGServices/Sale/SaleService">
      <SalePaymentRequestResult>
        <Status>-1533</Status>
        <Token>0</Token>
        <Message>PIN نامعتبر است</Message>
      </SalePaymentRequestResult>
    </SalePaymentRequestResponse>
  </soap:Body>
</soap:Envelope>
"""

CONFIRM_OK_XML = """<?xml version="1.0" encoding="utf-8"?>
<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
  <soap:Body>
    <ConfirmPaymentWithAmountResponse xmlns="https://pec.Shaparak.ir/NewIPGServices/Confirm/ConfirmService">
      <ConfirmPaymentWithAmountResult>
        <Status>0</Status>
        <Token>9876543210</Token>
        <RRN>123456789012</RRN>
        <CardNumberMasked>6037-****-****-1234</CardNumberMasked>
      </ConfirmPaymentWithAmountResult>
    </ConfirmPaymentWithAmountResponse>
  </soap:Body>
</soap:Envelope>
"""

CONFIRM_FAIL_XML = """<?xml version="1.0" encoding="utf-8"?>
<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
  <soap:Body>
    <ConfirmPaymentWithAmountResponse xmlns="https://pec.Shaparak.ir/NewIPGServices/Confirm/ConfirmService">
      <ConfirmPaymentWithAmountResult>
        <Status>-1532</Status>
      </ConfirmPaymentWithAmountResult>
    </ConfirmPaymentWithAmountResponse>
  </soap:Body>
</soap:Envelope>
"""


def test_resolve_login_account_prefers_pin_then_merchant_id() -> None:
	assert resolve_login_account({"pin": "PIN-1", "merchant_id": "M", "terminal_id": "9"}) == "PIN-1"
	assert resolve_login_account({"merchant_id": "ACCEPTOR-PIN", "terminal_id": "12345"}) == "ACCEPTOR-PIN"
	assert resolve_login_account({"terminal_id": "12345"}) == "12345"
	assert resolve_login_account({}) == ""


def test_order_id_namespaces_wallet_and_support() -> None:
	wid = make_order_id("wallet", 42)
	sid = make_order_id("support", 42)
	assert wid == WALLET_ORDER_BASE + 42
	assert sid == SUPPORT_ORDER_BASE + 42
	assert decode_order_id(wid) == ("wallet", 42)
	assert decode_order_id(sid) == ("support", 42)


def test_callback_paid_only_zero() -> None:
	assert callback_paid("0") is True
	assert callback_paid(0) is True
	assert callback_paid("100") is False
	assert callback_paid("ok") is False
	assert callback_paid(None) is False


def test_parse_amount_strips_commas() -> None:
	assert parse_amount("1,450,000") == 1_450_000
	assert parse_amount("1450000") == 1_450_000


def test_build_startpay_url_uses_lowercase_token() -> None:
	assert build_startpay_url("https://pec.shaparak.ir/NewIPG/?token=", "abc") == "https://pec.shaparak.ir/NewIPG/?token=abc"
	assert build_startpay_url("https://pec.shaparak.ir/NewIPG/?Token", "abc") == "https://pec.shaparak.ir/NewIPG/?Token=abc"
	assert build_startpay_url("https://pec.shaparak.ir/NewIPG/", "abc") == "https://pec.shaparak.ir/NewIPG/?token=abc"


def test_sale_envelope_is_soap_with_login_account() -> None:
	xml = build_sale_envelope(
		login_account="PIN&X",
		order_id=1000000042,
		amount=1450000,
		callback_url="https://example.com/cb?tx_id=42&source=app",
	)
	assert "soap:Envelope" in xml
	assert f'xmlns="{SALE_NS}"' in xml
	assert "<LoginAccount>PIN&amp;X</LoginAccount>" in xml
	assert "<Amount>1450000</Amount>" in xml
	assert "<CallBackUrl>https://example.com/cb?tx_id=42&amp;source=app</CallBackUrl>" in xml
	assert SALE_SOAP_ACTION.startswith("https://pec.Shaparak.ir/")


def test_parse_sale_success_and_failure() -> None:
	ok = parse_sale_response(SALE_OK_XML)
	assert ok.ok is True
	assert ok.token == "9876543210"
	assert ok.status == "0"
	fail = parse_sale_response(SALE_FAIL_XML)
	assert fail.ok is False
	assert fail.token is None
	assert fail.status == "-1533"
	assert "نامعتبر" in (fail.message or "")


def test_parse_confirm_success_and_failure() -> None:
	ok = parse_confirm_response(CONFIRM_OK_XML)
	assert ok.ok is True
	assert ok.rrn == "123456789012"
	assert ok.card_number == "6037-****-****-1234"
	fail = parse_confirm_response(CONFIRM_FAIL_XML)
	assert fail.ok is False
	assert fail.status == "-1532"


def test_resolve_sale_url_production() -> None:
	url = resolve_sale_url({}, is_sandbox=False)
	assert url == "https://pec.shaparak.ir/NewIPGServices/Sale/SaleService.asmx"


@patch("app.services.parsian_gateway._soap_post")
def test_sale_payment_request_posts_xml_not_json(mock_post: MagicMock) -> None:
	mock_post.return_value = SALE_OK_XML
	result = sale_payment_request(
		{"pin": "SECRET-PIN"},
		is_sandbox=False,
		order_id=1000000007,
		amount=50000,
		callback_url="https://shop.example/cb",
	)
	assert result.ok is True
	assert result.token == "9876543210"
	url, envelope, action = mock_post.call_args.args
	assert url.endswith("/NewIPGServices/Sale/SaleService.asmx")
	assert envelope.lstrip().startswith("<?xml")
	assert "<LoginAccount>SECRET-PIN</LoginAccount>" in envelope
	assert action == SALE_SOAP_ACTION


@patch("app.services.payment_service.sale_payment_request")
def test_wallet_initiate_production_raises_without_fake_token(mock_sale: MagicMock) -> None:
	mock_sale.return_value = parse_sale_response(SALE_FAIL_XML)
	gw = MagicMock(is_sandbox=False, id=1)
	cfg = {"pin": "P", "callback_url": "https://x/cb"}
	db = MagicMock()
	with pytest.raises(ApiError) as ei:
		_initiate_parsian(db, gw, cfg, business_id=1, tx_id=9, amount=100000)
	assert ei.value.status_code == 502
	assert "TEST-TOKEN" not in str(ei.value.detail)


@patch("app.services.payment_service.sale_payment_request")
def test_wallet_initiate_success_stores_order_id_and_startpay(mock_sale: MagicMock) -> None:
	mock_sale.return_value = parse_sale_response(SALE_OK_XML)
	gw = MagicMock(is_sandbox=False, id=3)
	cfg = {"pin": "P", "callback_url": "https://x/api/v1/wallet/payments/callback/parsian"}
	tx = MagicMock(extra_info="{}")
	db = MagicMock()
	db.query.return_value.filter.return_value.first.return_value = tx
	result = _initiate_parsian(db, gw, cfg, business_id=1, tx_id=9, amount=1450000)
	assert result.external_ref == "9876543210"
	assert "token=9876543210" in result.payment_url.lower()
	assert "NewIPG" in result.payment_url
	sale_kwargs = mock_sale.call_args.kwargs
	assert sale_kwargs["order_id"] == make_order_id("wallet", 9)
	assert sale_kwargs["amount"] == 1450000
	assert "tx_id=9" in sale_kwargs["callback_url"]
	assert tx.external_ref == "9876543210"


@patch("app.services.payment_service.confirm_top_up")
@patch("app.services.payment_service.confirm_payment")
def test_wallet_verify_requires_confirm_soap(mock_confirm: MagicMock, mock_top_up: MagicMock) -> None:
	mock_confirm.return_value = parse_confirm_response(CONFIRM_OK_XML)
	tx = MagicMock()
	tx.amount = 1450000
	tx.extra_info = '{"gateway_id": 3, "parsian_order_id": 1000000009, "created_by_user_id": 4}'
	gw = MagicMock(is_sandbox=False, id=3, config_json='{"pin":"P"}')
	db = MagicMock()
	db.query.return_value.filter.return_value.first.side_effect = [tx, gw]
	out = _verify_parsian(db, {"tx_id": 9, "Token": "9876543210", "status": "0", "Amount": "1,450,000", "OrderId": "1000000009", "RRN": "123456789012"})
	assert out["success"] is True
	assert out["ref_id"] == "123456789012"
	mock_confirm.assert_called_once()
	assert mock_confirm.call_args.kwargs["token"] == "9876543210"
	assert mock_confirm.call_args.kwargs["amount"] == 1_450_000
	mock_top_up.assert_called_once()
	assert mock_top_up.call_args.kwargs["success"] is True


@patch("app.services.payment_service.confirm_top_up")
@patch("app.services.payment_service.confirm_payment")
def test_wallet_verify_does_not_confirm_when_status_not_zero(mock_confirm: MagicMock, mock_top_up: MagicMock) -> None:
	tx = MagicMock()
	tx.extra_info = '{"gateway_id": 3}'
	gw = MagicMock(is_sandbox=False, config_json='{"pin":"P"}')
	db = MagicMock()
	db.query.return_value.filter.return_value.first.side_effect = [tx, gw]
	out = _verify_parsian(db, {"tx_id": 9, "Token": "t", "status": "1"})
	assert out["success"] is False
	mock_confirm.assert_not_called()
	assert mock_top_up.call_args.kwargs["success"] is False


@patch("app.services.support.support_payment_gateway.sale_payment_request")
def test_support_initiate_uses_soap_in_production(mock_sale: MagicMock) -> None:
	mock_sale.return_value = parse_sale_response(SALE_OK_XML)
	gw = MagicMock(is_sandbox=False, id=1)
	session = MagicMock(id=8)
	result = _initiate_support_parsian(
		MagicMock(),
		gw,
		{"pin": "P", "callback_url": "https://x/api/v1/wallet/payments/callback/parsian"},
		session,
		200000,
		"app",
	)
	assert result.external_ref == "9876543210"
	assert mock_sale.call_args.kwargs["order_id"] == make_order_id("support", 8)
	assert "token=" in result.payment_url.lower()


@patch("app.services.support.support_payment_gateway.sale_payment_request")
def test_support_initiate_production_failure(mock_sale: MagicMock) -> None:
	mock_sale.return_value = parse_sale_response(SALE_FAIL_XML)
	gw = MagicMock(is_sandbox=False)
	session = MagicMock(id=8)
	with pytest.raises(ApiError):
		_initiate_support_parsian(
			MagicMock(),
			gw,
			{"pin": "P", "callback_url": "https://x/api/v1/wallet/payments/callback/parsian"},
			session,
			200000,
			"app",
		)


@patch("app.services.support.support_payment_gateway.confirm_payment")
def test_support_verify_confirms_when_status_zero(mock_confirm: MagicMock) -> None:
	mock_confirm.return_value = parse_confirm_response(CONFIRM_OK_XML)
	session = MagicMock(id=8, amount=200000, external_ref="9876543210", provider_payload={"parsian_order_id": make_order_id("support", 8)})
	gw = MagicMock(is_sandbox=False)
	ok, token, ref, payload = _verify_support_parsian(
		session, gw, {"pin": "P"}, {"Token": "9876543210", "status": "0", "Amount": "200000"}
	)
	assert ok is True
	assert ref == "123456789012"
	assert payload["confirm"]["status"] == "0"
	mock_confirm.assert_called_once()


@patch("app.services.parsian_gateway._soap_post")
def test_confirm_payment_posts_confirm_service(mock_post: MagicMock) -> None:
	mock_post.return_value = CONFIRM_OK_XML
	result = confirm_payment({"pin": "P"}, is_sandbox=False, token="9876543210", order_id=1000000009, amount=1450000)
	assert result.ok is True
	url, envelope, action = mock_post.call_args.args
	assert url.endswith("/NewIPGServices/Confirm/ConfirmService.asmx")
	assert "<ConfirmPayment" in envelope
	assert "<LoginAccount>P</LoginAccount>" in envelope
	assert "<Token>9876543210</Token>" in envelope
	assert "<Amount>" not in envelope
	assert action.endswith("/ConfirmPayment")
