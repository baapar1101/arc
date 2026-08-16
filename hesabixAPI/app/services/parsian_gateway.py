"""اتصال SOAP رسمی درگاه پارسیان (PEC NewIPG).

مرجع: افزونه رسمی ووکامرس https://pgw.pec.ir/Content/Plugin/wc-pec-gateway.zip
"""

from __future__ import annotations

import logging
import re
from dataclasses import dataclass
from typing import Any, Dict, Optional, Tuple
from xml.etree import ElementTree as ET
from xml.sax.saxutils import escape as xml_escape

import httpx

logger = logging.getLogger(__name__)

PROD_HOST = "https://pec.shaparak.ir"
SANDBOX_HOST = "https://sandbox.banktest.ir/parsian"

SALE_PATH = "/NewIPGServices/Sale/SaleService.asmx"
CONFIRM_PATH = "/NewIPGServices/Confirm/ConfirmService.asmx"
REVERSE_PATH = "/NewIPGServices/Reverse/ReversalService.asmx"
STARTPAY_PATH = "/NewIPG/?token="

SALE_NS = "https://pec.Shaparak.ir/NewIPGServices/Sale/SaleService"
CONFIRM_NS = "https://pec.Shaparak.ir/NewIPGServices/Confirm/ConfirmService"
REVERSE_NS = "https://pec.Shaparak.ir/NewIPGServices/Reversal/ReversalService"

SALE_SOAP_ACTION = f"{SALE_NS}/SalePaymentRequest"
CONFIRM_SOAP_ACTION = f"{CONFIRM_NS}/ConfirmPaymentWithAmount"
REVERSE_SOAP_ACTION = f"{REVERSE_NS}/ReversalRequest"

WALLET_ORDER_BASE = 1_000_000_000
SUPPORT_ORDER_BASE = 2_000_000_000

_SOAP_TIMEOUT = 15.0


@dataclass
class ParsianSaleResult:
	ok: bool
	token: Optional[str]
	status: Optional[str]
	message: Optional[str]
	raw: str = ""


@dataclass
class ParsianConfirmResult:
	ok: bool
	status: Optional[str]
	token: Optional[str]
	rrn: Optional[str]
	card_number: Optional[str]
	message: Optional[str]
	raw: str = ""


def resolve_login_account(cfg: Dict[str, Any]) -> str:
	"""PIN پذیرنده برای LoginAccount.

	ترتیب: pin → login_account → merchant_id → terminal_id
	در UI قبلی PIN معمولاً در merchant_id («کد پذیرنده») ذخیره می‌شد.
	"""
	for key in ("pin", "login_account", "merchant_id", "terminal_id"):
		val = str(cfg.get(key) or "").strip()
		if val:
			return val
	return ""


def make_order_id(scope: str, internal_id: int) -> int:
	"""OrderId یکتا برای پارسیان؛ کیف‌پول و پشتیبانی را جدا می‌کند."""
	internal_id = int(internal_id)
	if scope == "support":
		return SUPPORT_ORDER_BASE + internal_id
	return WALLET_ORDER_BASE + internal_id


def decode_order_id(order_id: int) -> Tuple[str, int]:
	oid = int(order_id or 0)
	if oid >= SUPPORT_ORDER_BASE:
		return "support", oid - SUPPORT_ORDER_BASE
	if oid >= WALLET_ORDER_BASE:
		return "wallet", oid - WALLET_ORDER_BASE
	return "unknown", oid


def is_test_token(token: Optional[str]) -> bool:
	t = str(token or "")
	return t.startswith("TEST-TOKEN-") or t.startswith("TEST-PARSIAN-")


def callback_paid(status: Any) -> bool:
	"""موفقیت برگشت از درگاه: status === 0 مطابق افزونه رسمی."""
	if status is None:
		return False
	s = str(status).strip().lower()
	return s in ("0", "0.0")


def parse_amount(value: Any) -> int:
	s = str(value or "").replace(",", "").replace("،", "").strip()
	if not s:
		return 0
	try:
		return int(round(float(s)))
	except (TypeError, ValueError):
		return 0


def _host(is_sandbox: bool) -> str:
	return SANDBOX_HOST if is_sandbox else PROD_HOST


def resolve_sale_url(cfg: Dict[str, Any], *, is_sandbox: bool) -> str:
	explicit = str(cfg.get("sale_url") or cfg.get("token_url") or "").strip()
	if explicit:
		return explicit
	base = str(cfg.get("api_base") or _host(is_sandbox)).rstrip("/")
	return f"{base}{SALE_PATH}"


def resolve_confirm_url(cfg: Dict[str, Any], *, is_sandbox: bool) -> str:
	explicit = str(cfg.get("confirm_url") or "").strip()
	if explicit:
		return explicit
	base = str(cfg.get("api_base") or _host(is_sandbox)).rstrip("/")
	return f"{base}{CONFIRM_PATH}"


def resolve_startpay_base(cfg: Dict[str, Any], *, is_sandbox: bool) -> str:
	explicit = str(cfg.get("startpay_base") or "").strip()
	if explicit:
		return explicit
	return f"{_host(is_sandbox).rstrip('/')}{STARTPAY_PATH}"


def build_startpay_url(base: str, token: str) -> str:
	b = (base or "").strip() or f"{PROD_HOST}{STARTPAY_PATH}"
	if re.search(r"[?&][Tt]oken=?$", b):
		return b + ("" if b.endswith("=") else "=") + token
	if b.endswith("="):
		return b + token
	joiner = "&" if "?" in b else "?"
	return f"{b}{joiner}token={token}"


def build_sale_envelope(
	*,
	login_account: str,
	order_id: int,
	amount: int,
	callback_url: str,
	additional_data: str = "",
	originator: str = "",
) -> str:
	return (
		'<?xml version="1.0" encoding="utf-8"?>'
		'<soap:Envelope xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"'
		' xmlns:xsd="http://www.w3.org/2001/XMLSchema"'
		' xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">'
		"<soap:Body>"
		f'<SalePaymentRequest xmlns="{SALE_NS}">'
		"<requestData>"
		f"<LoginAccount>{xml_escape(login_account)}</LoginAccount>"
		f"<OrderId>{int(order_id)}</OrderId>"
		f"<Amount>{int(amount)}</Amount>"
		f"<CallBackUrl>{xml_escape(callback_url)}</CallBackUrl>"
		f"<AdditionalData>{xml_escape(additional_data)}</AdditionalData>"
		f"<Originator>{xml_escape(originator)}</Originator>"
		"</requestData>"
		"</SalePaymentRequest>"
		"</soap:Body>"
		"</soap:Envelope>"
	)


def build_confirm_envelope(
	*,
	login_account: str,
	token: str,
	order_id: int,
	amount: int,
) -> str:
	return (
		'<?xml version="1.0" encoding="utf-8"?>'
		'<soap:Envelope xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"'
		' xmlns:xsd="http://www.w3.org/2001/XMLSchema"'
		' xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">'
		"<soap:Body>"
		f'<ConfirmPaymentWithAmount xmlns="{CONFIRM_NS}">'
		"<requestData>"
		f"<LoginAccount>{xml_escape(login_account)}</LoginAccount>"
		f"<Token>{xml_escape(str(token))}</Token>"
		f"<OrderId>{int(order_id)}</OrderId>"
		f"<Amount>{int(amount)}</Amount>"
		"</requestData>"
		"</ConfirmPaymentWithAmount>"
		"</soap:Body>"
		"</soap:Envelope>"
	)


def _local_name(tag: str) -> str:
	if tag.startswith("{"):
		return tag.rsplit("}", 1)[-1]
	if ":" in tag:
		return tag.split(":")[-1]
	return tag


def _first_text(root: ET.Element, *names: str) -> Optional[str]:
	wanted = {n.lower() for n in names}
	for el in root.iter():
		if _local_name(el.tag).lower() in wanted:
			text = (el.text or "").strip()
			if text:
				return text
	return None


def _parse_xml(raw: str) -> Optional[ET.Element]:
	text = (raw or "").strip()
	if not text:
		return None
	# افزونه رسمی soap:Body را جدا می‌کند؛ ما کل سند را با local-name می‌خوانیم.
	try:
		return ET.fromstring(text)
	except ET.ParseError:
		try:
			start = text.find("<")
			if start > 0:
				return ET.fromstring(text[start:])
		except ET.ParseError:
			return None
	return None


def _token_ok(token: Optional[str]) -> bool:
	if not token:
		return False
	t = token.strip()
	if not t or t in ("0", "-1"):
		return False
	try:
		if int(t) <= 0:
			return False
	except ValueError:
		pass
	return True


def parse_sale_response(raw: str) -> ParsianSaleResult:
	root = _parse_xml(raw)
	if root is None:
		return ParsianSaleResult(ok=False, token=None, status="-138", message="پاسخ نامعتبر از درگاه پارسیان", raw=raw)
	fault = _first_text(root, "faultstring", "FaultString")
	status = _first_text(root, "Status")
	token = _first_text(root, "Token")
	message = _first_text(root, "Message") or fault
	ok = _token_ok(token) and str(status or "0").strip() in ("0", "0.0")
	return ParsianSaleResult(ok=ok, token=token if _token_ok(token) else None, status=status, message=message, raw=raw)


def parse_confirm_response(raw: str) -> ParsianConfirmResult:
	root = _parse_xml(raw)
	if root is None:
		return ParsianConfirmResult(
			ok=False, status="-138", token=None, rrn=None, card_number=None,
			message="پاسخ نامعتبر از درگاه پارسیان", raw=raw,
		)
	status = _first_text(root, "Status")
	ok = str(status or "").strip() == "0"
	return ParsianConfirmResult(
		ok=ok,
		status=status,
		token=_first_text(root, "Token"),
		rrn=_first_text(root, "RRN"),
		card_number=_first_text(root, "CardNumberMasked"),
		message=_first_text(root, "Message", "faultstring"),
		raw=raw,
	)


def _soap_post(url: str, envelope: str, soap_action: str) -> str:
	headers = {
		"Content-Type": "text/xml; charset=utf-8",
		"Accept": "text/xml",
		"SOAPAction": soap_action,
	}
	with httpx.Client(timeout=_SOAP_TIMEOUT) as client:
		resp = client.post(url, content=envelope.encode("utf-8"), headers=headers)
		return resp.text or ""


def sale_payment_request(
	cfg: Dict[str, Any],
	*,
	is_sandbox: bool,
	order_id: int,
	amount: int,
	callback_url: str,
) -> ParsianSaleResult:
	login = resolve_login_account(cfg)
	if not login:
		return ParsianSaleResult(ok=False, token=None, status=None, message="شناسه پذیرنده (PIN) تنظیم نشده است")
	url = resolve_sale_url(cfg, is_sandbox=is_sandbox)
	envelope = build_sale_envelope(
		login_account=login,
		order_id=order_id,
		amount=amount,
		callback_url=callback_url,
	)
	try:
		raw = _soap_post(url, envelope, SALE_SOAP_ACTION)
	except Exception as ex:
		logger.warning("parsian_sale_http_failed url=%s err=%s", url, ex)
		return ParsianSaleResult(ok=False, token=None, status="-138", message="ارتباط با درگاه پارسیان برقرار نشد")
	result = parse_sale_response(raw)
	if not result.ok:
		logger.warning(
			"parsian_sale_rejected status=%s message=%s",
			result.status,
			(result.message or "")[:200],
		)
	return result


def confirm_payment(
	cfg: Dict[str, Any],
	*,
	is_sandbox: bool,
	token: str,
	order_id: int,
	amount: int,
) -> ParsianConfirmResult:
	login = resolve_login_account(cfg)
	if not login or not token:
		return ParsianConfirmResult(
			ok=False, status=None, token=None, rrn=None, card_number=None,
			message="PIN یا توکن برای تأیید پارسیان موجود نیست",
		)
	url = resolve_confirm_url(cfg, is_sandbox=is_sandbox)
	envelope = build_confirm_envelope(
		login_account=login,
		token=token,
		order_id=order_id,
		amount=amount,
	)
	try:
		raw = _soap_post(url, envelope, CONFIRM_SOAP_ACTION)
	except Exception as ex:
		logger.warning("parsian_confirm_http_failed url=%s err=%s", url, ex)
		return ParsianConfirmResult(
			ok=False, status="-138", token=None, rrn=None, card_number=None,
			message="ارتباط با درگاه پارسیان برای تأیید برقرار نشد",
		)
	result = parse_confirm_response(raw)
	if not result.ok:
		logger.warning(
			"parsian_confirm_rejected status=%s message=%s",
			result.status,
			(result.message or "")[:200],
		)
	return result


def sale_error_message(result: ParsianSaleResult) -> str:
	msg = (result.message or "").strip()
	if result.status and msg:
		return f"خطای پارسیان (کد {result.status}): {msg}"
	if msg:
		return msg
	if result.status:
		return f"ایجاد تراکنش پارسیان ناموفق بود (کد {result.status})"
	return "امکان ایجاد تراکنش در پارسیان نیست"
