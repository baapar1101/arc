from __future__ import annotations

import json
import logging
from dataclasses import dataclass
from typing import Any, Dict, Optional

import httpx
from sqlalchemy.orm import Session

from app.core.responses import ApiError
from adapters.db.models.payment_gateway import PaymentGateway
from adapters.db.models.wallet import WalletTransaction
from app.services.parsian_gateway import (
	WALLET_ORDER_BASE,
	build_startpay_url,
	callback_paid,
	confirm_payment,
	decode_order_id,
	is_test_token,
	make_order_id,
	parse_amount,
	resolve_login_account,
	resolve_startpay_base,
	sale_error_message,
	sale_payment_request,
)
from app.services.wallet_service import confirm_top_up

logger = logging.getLogger(__name__)

_BITPAY_ERROR_MESSAGES: Dict[int, str] = {
	-1: "کلید API بیت‌پی با نوع درگاه سازگار نیست",
	-2: "مبلغ نامعتبر است یا کمتر از حداقل مجاز بیت‌پی است",
	-3: "آدرس بازگشت (callback) نامعتبر است",
	-4: "درگاه بیت‌پی فعال نیست یا یافت نشد",
	-5: "شناسه فاکتور تکراری است",
}

# API بیت‌پی مبلغ را به ریال می‌گیرد. حداقل ۵۰٬۰۰۰ ریال (۵٬۰۰۰ تومان).
# amount_unit=toman فقط برای درگاه‌هایی است که صریحاً تومان تنظیم شده‌اند.
_BITPAY_WIRE_MIN = {"toman": 5000, "rial": 50_000}
_BITPAY_WIRE_MAX = {"toman": 50_000_000, "rial": 500_000_000}


def _bitpay_amount_unit(cfg: Dict[str, Any]) -> str:
	"""واحد ارسال مبلغ به بیت‌پی: rial (پیش‌فرض، مطابق API) یا toman."""
	raw = str(cfg.get("amount_unit") or cfg.get("currency") or "rial").strip().lower()
	if raw in ("t", "toman", "irt", "tmn"):
		return "toman"
	return "rial"


def _bitpay_wire_amount(internal_rial_amount: float, cfg: Dict[str, Any]) -> int:
	"""تبدیل مبلغ داخلی (ریال حسابیکس) به واحد ارسالی بیت‌پی."""
	amt = float(internal_rial_amount)
	if _bitpay_amount_unit(cfg) == "toman":
		return int(round(amt / 10.0))
	return int(round(amt))


@dataclass
class InitiateResult:
	payment_url: str
	external_ref: str  # Authority/Token/etc.


def _load_config(gw: PaymentGateway) -> Dict[str, Any]:
	try:
		return json.loads(gw.config_json or "{}")
	except Exception:
		return {}


def _get_gateway_or_error(db: Session, gateway_id: int) -> PaymentGateway:
	gw = db.query(PaymentGateway).filter(PaymentGateway.id == int(gateway_id)).first()
	if not gw:
		raise ApiError("GATEWAY_NOT_FOUND", "درگاه پرداخت یافت نشد", http_status=404)
	if not gw.is_active:
		raise ApiError("GATEWAY_DISABLED", "درگاه پرداخت غیرفعال است", http_status=400)
	return gw


def initiate_payment(db: Session, business_id: int, tx_id: int, amount: float, gateway_id: int) -> InitiateResult:
	gw = _get_gateway_or_error(db, gateway_id)
	cfg = _load_config(gw)
	provider = gw.provider.lower().strip()

	if provider == "zarinpal":
		return _initiate_zarinpal(db, gw, cfg, business_id, tx_id, amount)
	elif provider == "parsian":
		return _initiate_parsian(db, gw, cfg, business_id, tx_id, amount)
	elif provider == "bitpay":
		return _initiate_bitpay(db, gw, cfg, business_id, tx_id, amount)
	else:
		raise ApiError("UNSUPPORTED_PROVIDER", f"درگاه '{gw.provider}' پشتیبانی نمی‌شود", http_status=400)


def verify_payment_callback(db: Session, provider: str, params: Dict[str, Any]) -> Dict[str, Any]:
	"""
	Verify callback by provider; returns standardized dict with:
	- transaction_id: int
	- success: bool
	- external_ref: str | None
	- fee_amount: float | None
	"""
	provider_l = (provider or "").lower().strip()
	if provider_l == "zarinpal":
		return _verify_zarinpal(db, params)
	elif provider_l == "parsian":
		return _verify_parsian(db, params)
	elif provider_l == "bitpay":
		return _verify_bitpay(db, params)
	else:
		raise ApiError("UNSUPPORTED_PROVIDER", f"درگاه '{provider}' پشتیبانی نمی‌شود", http_status=400)


# --------------------------
# ZARINPAL
# --------------------------
def _initiate_zarinpal(db: Session, gw: PaymentGateway, cfg: Dict[str, Any], business_id: int, tx_id: int, amount: float) -> InitiateResult:
	"""
	Minimal integration:
	- expects cfg fields: merchant_id, callback_url, api_base(optional), startpay_base(optional), description(optional), currency ('IRR' default)
	- amount must be in Rials for classic REST
	"""
	merchant_id = str(cfg.get("merchant_id") or "").strip()
	callback_url = str(cfg.get("callback_url") or "").strip()
	if not merchant_id or not callback_url:
		raise ApiError("INVALID_CONFIG", "merchant_id و callback_url الزامی هستند", http_status=400)
	description = str(cfg.get("description") or "Wallet top-up")
	# Prefer v4 endpoint; fallback to legacy WebGate if needed
	v4_domain = "https://sandbox.zarinpal.com" if gw.is_sandbox else "https://api.zarinpal.com"
	api_v4_url = str(cfg.get("api_v4_url") or f"{v4_domain}/pg/v4/payment/request.json")
	legacy_base = str(cfg.get("api_base") or ("https://sandbox.zarinpal.com/pg/rest/WebGate" if gw.is_sandbox else "https://www.zarinpal.com/pg/rest/WebGate"))
	legacy_url = f"{legacy_base}/PaymentRequest.json"
	# StartPay host per Zarinpal docs: sandbox vs payment
	startpay_base = str(cfg.get("startpay_base") or ("https://sandbox.zarinpal.com/pg/StartPay" if gw.is_sandbox else "https://payment.zarinpal.com/pg/StartPay"))
	# append tx_id to callback
	cb_url = callback_url
	try:
		from urllib.parse import urlencode, urlparse, parse_qsl, urlunparse
		u = urlparse(callback_url)
		q = dict(parse_qsl(u.query))
		q["tx_id"] = str(tx_id)
		cb_url = urlunparse((u.scheme, u.netloc, u.path, u.params, urlencode(q), u.fragment))
	except Exception:
		cb_url = f"{callback_url}{'&' if '?' in callback_url else '?'}tx_id={tx_id}"

	# Build payloads
	req_payload_v4 = {
		"merchant_id": merchant_id,
		"amount": int(round(float(amount))),
		"callback_url": cb_url,
		"description": description,
	}
	req_payload_legacy = {
		"MerchantID": merchant_id,
		"Amount": int(round(float(amount))),
		"Description": description,
		"CallbackURL": cb_url,
	}
	authority: Optional[str] = None
	try:
		with httpx.Client(timeout=10.0) as client:
			# Try v4 first
			try:
				resp = client.post(api_v4_url, json=req_payload_v4, headers={"Accept": "application/json", "Content-Type": "application/json"})
				data = resp.json() if "application/json" in (resp.headers.get("content-type","")) else {}
				d_data = data.get("data") if isinstance(data, dict) else None
				code = (d_data or {}).get("code") if isinstance(d_data, dict) else None
				auth_v4 = (d_data or {}).get("authority") if isinstance(d_data, dict) else None
				if int(code or -1) == 100 and auth_v4:
					authority = str(auth_v4)
			except Exception:
				authority = None
			# Fallback to legacy
			if not authority:
				resp = client.post(legacy_url, json=req_payload_legacy, headers={"Accept": "application/json", "Content-Type": "application/json"})
				data = resp.json() if "application/json" in (resp.headers.get("content-type","")) else {}
				if int(data.get("Status") or -1) == 100 and data.get("Authority"):
					authority = str(data["Authority"])
	except Exception:
		# Fallback: in dev, generate a pseudo authority to continue flow
		authority = authority or f"TEST-AUTH-{tx_id}"

	if not authority:
		raise ApiError("GATEWAY_INIT_FAILED", "امکان ایجاد تراکنش در زرین‌پال نیست", http_status=502)

	payment_url = f"{startpay_base}/{authority}"
	# persist ref/url on tx.extra_info
	_tx = db.query(WalletTransaction).filter(WalletTransaction.id == int(tx_id)).first()
	if _tx:
		extra = {}
		try:
			extra = json.loads(_tx.extra_info or "{}")
		except Exception:
			extra = {}
		extra.update({
			"gateway_id": gw.id,
			"provider": "zarinpal",
			"authority": authority,
			"payment_url": payment_url,
		})
		_tx.external_ref = authority
		_tx.extra_info = json.dumps(extra, ensure_ascii=False)
		db.flush()
	return InitiateResult(payment_url=payment_url, external_ref=authority)


def _verify_zarinpal(db: Session, params: Dict[str, Any]) -> Dict[str, Any]:
	# Params expected: Authority, Status, (optionally tx_id)
	authority = str(params.get("Authority") or params.get("authority") or "").strip()
	status = str(params.get("Status") or params.get("status") or "").lower()
	tx_id = int(params.get("tx_id") or 0)
	is_ok = status in ("ok", "ok.", "success", "succeeded")
	fee_amount = None
	ref_id = None
	success = False
	if tx_id > 0 and is_ok:
		# Load tx and gateway to verify via v4 endpoint
		tx = db.query(WalletTransaction).filter(WalletTransaction.id == int(tx_id)).first()
		gateway_id = None
		try:
			extra = json.loads(tx.extra_info or "{}") if tx and tx.extra_info else {}
			gateway_id = extra.get("gateway_id")
		except Exception:
			gateway_id = None
		gw = db.query(PaymentGateway).filter(PaymentGateway.id == int(gateway_id)).first() if gateway_id else None
		if tx and gw:
			cfg = _load_config(gw)
			merchant_id = str(cfg.get("merchant_id") or "").strip()
			if merchant_id:
				v4_domain = "https://sandbox.zarinpal.com" if gw.is_sandbox else "https://payment.zarinpal.com"
				verify_url = f"{v4_domain}/pg/v4/payment/verify.json"
				payload = {
					"merchant_id": merchant_id,
					"amount": int(round(float(tx.amount or 0))),
					"authority": authority,
				}
				try:
					with httpx.Client(timeout=10.0) as client:
						resp = client.post(verify_url, json=payload, headers={"Accept": "application/json", "Content-Type": "application/json"})
						data = resp.json() if "application/json" in (resp.headers.get("content-type","")) else {}
						d_data = data.get("data") if isinstance(data, dict) else None
						code = (d_data or {}).get("code") if isinstance(d_data, dict) else None
						ref_id = (d_data or {}).get("ref_id")
						fee_amount = (d_data or {}).get("fee")
						success = int(code or -1) in (100, 101)
				except Exception:
					success = False
	# Confirm or fail based on verify (or status fallback)
	user_id = None
	if tx_id > 0:
		# استخراج user_id از extra_info تراکنش
		if tx:
			try:
				extra = json.loads(tx.extra_info or "{}") if tx.extra_info else {}
				user_id = extra.get("created_by_user_id")
			except Exception:
				pass
		# به‌روزرسانی fee_amount در صورت دریافت از درگاه
		if fee_amount is not None and tx:
			from decimal import Decimal
			tx.fee_amount = Decimal(str(fee_amount))
			db.flush()
		confirm_top_up(db, tx_id, success=(success or is_ok), external_ref=authority or None, user_id=user_id)
	return {"transaction_id": tx_id, "success": (success or is_ok), "external_ref": authority, "fee_amount": fee_amount, "ref_id": ref_id}


# --------------------------
# PARSIAN
# --------------------------
def _initiate_parsian(db: Session, gw: PaymentGateway, cfg: Dict[str, Any], business_id: int, tx_id: int, amount: float) -> InitiateResult:
	"""Sale SOAP رسمی پارسیان: LoginAccount=PIN، مبلغ به ریال."""
	login_account = resolve_login_account(cfg)
	callback_url = str(cfg.get("callback_url") or "").strip()
	if not login_account or not callback_url:
		raise ApiError("INVALID_CONFIG", "شناسه پذیرنده (PIN) و callback_url الزامی هستند", http_status=400)
	cb_url = callback_url
	try:
		from urllib.parse import urlencode, urlparse, parse_qsl, urlunparse
		u = urlparse(callback_url)
		q = dict(parse_qsl(u.query))
		q["tx_id"] = str(tx_id)
		cb_url = urlunparse((u.scheme, u.netloc, u.path, u.params, urlencode(q), u.fragment))
	except Exception:
		cb_url = f"{callback_url}{'&' if '?' in callback_url else '?'}tx_id={tx_id}"

	order_id = make_order_id("wallet", int(tx_id))
	wire_amount = parse_amount(amount)
	token: Optional[str] = None
	sale = sale_payment_request(
		cfg,
		is_sandbox=bool(gw.is_sandbox),
		order_id=order_id,
		amount=wire_amount,
		callback_url=cb_url,
	)
	if sale.ok and sale.token:
		token = str(sale.token)
	elif gw.is_sandbox:
		logger.warning("parsian_wallet_sandbox_fallback tx_id=%s status=%s", tx_id, sale.status)
		token = f"TEST-TOKEN-{tx_id}"
	else:
		raise ApiError("GATEWAY_INIT_FAILED", sale_error_message(sale), http_status=502)

	startpay_base = resolve_startpay_base(cfg, is_sandbox=bool(gw.is_sandbox))
	payment_url = build_startpay_url(startpay_base, token)
	_tx = db.query(WalletTransaction).filter(WalletTransaction.id == int(tx_id)).first()
	if _tx:
		extra = {}
		try:
			extra = json.loads(_tx.extra_info or "{}")
		except Exception:
			extra = {}
		extra.update({
			"gateway_id": gw.id,
			"provider": "parsian",
			"token": token,
			"payment_url": payment_url,
			"parsian_order_id": order_id,
		})
		_tx.external_ref = token
		_tx.extra_info = json.dumps(extra, ensure_ascii=False)
		db.flush()
	return InitiateResult(payment_url=payment_url, external_ref=token)


def _verify_parsian(db: Session, params: Dict[str, Any]) -> Dict[str, Any]:
	"""تأیید پرداخت پارسیان با همان ConfirmPayment نمونه رسمی درگاه."""
	token = str(params.get("Token") or params.get("token") or "").strip()
	cb_status = params.get("status") if params.get("status") is not None else params.get("Status")
	try:
		tx_id = int(params.get("tx_id") or 0)
	except (TypeError, ValueError):
		tx_id = parse_amount(params.get("tx_id"))
	if tx_id <= 0:
		raw_oid = parse_amount(params.get("OrderId") or 0)
		scope, decoded = decode_order_id(raw_oid)
		if scope == "wallet" and decoded > 0:
			tx_id = decoded
		elif raw_oid > 0 and raw_oid < WALLET_ORDER_BASE:
			tx_id = raw_oid
	success = False
	fee_amount = None
	user_id = None
	ref_id = params.get("RRN") or params.get("rrn")
	card_num = None
	tx = None
	extra: Dict[str, Any] = {}
	if tx_id > 0:
		tx = db.query(WalletTransaction).filter(WalletTransaction.id == int(tx_id)).first()
		if tx:
			try:
				extra = json.loads(tx.extra_info or "{}") if tx.extra_info else {}
				user_id = extra.get("created_by_user_id")
			except Exception:
				extra = {}
		if not token:
			token = str((extra.get("token") if extra else None) or (tx.external_ref if tx else "") or "").strip()
		gateway_id = extra.get("gateway_id") if extra else None
		gw = db.query(PaymentGateway).filter(PaymentGateway.id == int(gateway_id)).first() if gateway_id else None
		paid_at_bank = callback_paid(cb_status)
		callback_rrn = parse_amount(params.get("RRN") or params.get("rrn"))
		if gw and paid_at_bank and callback_rrn > 0 and token:
			if gw.is_sandbox and is_test_token(token):
				success = True
			else:
				cfg = _load_config(gw)
				confirm = confirm_payment(
					cfg,
					is_sandbox=bool(gw.is_sandbox),
					token=token,
					order_id=parse_amount(params.get("OrderId") or extra.get("parsian_order_id") or make_order_id("wallet", tx_id)),
					amount=parse_amount(params.get("Amount")) or parse_amount(tx.amount if tx else 0),
				)
				success = bool(confirm.ok)
				if confirm.rrn:
					ref_id = confirm.rrn
				card_num = confirm.card_number
				if extra is not None:
					extra["parsian_confirm_status"] = confirm.status
					if confirm.rrn:
						extra["parsian_rrn"] = confirm.rrn
					if confirm.card_number:
						extra["parsian_card"] = confirm.card_number
					if tx:
						tx.extra_info = json.dumps(extra, ensure_ascii=False)
		elif paid_at_bank and gw is None and is_test_token(token):
			success = True
		confirm_top_up(db, tx_id, success=success, external_ref=(str(ref_id) if ref_id else token) or None, user_id=user_id)
	return {
		"transaction_id": tx_id,
		"success": success,
		"external_ref": (str(ref_id) if ref_id else token) or None,
		"fee_amount": fee_amount,
		"ref_id": ref_id,
		"card_num": card_num,
	}


# --------------------------
# BITPAY
# --------------------------
def _initiate_bitpay(db: Session, gw: PaymentGateway, cfg: Dict[str, Any], business_id: int, tx_id: int, amount: float) -> InitiateResult:
	"""
	BitPay integration:
	- expects cfg fields: api (52 characters), callback_url (redirect)
	- amount_unit (اختیاری): rial (پیش‌فرض، مطابق API بیت‌پی) | toman — مبلغ داخلی همیشه ریال است
	- returns id_get which is used to build payment URL
	"""
	api_key = str(cfg.get("api") or "").strip()
	callback_url = str(cfg.get("callback_url") or "").strip()
	if not api_key or not callback_url:
		raise ApiError("INVALID_CONFIG", "api و callback_url الزامی هستند", http_status=400)
	if len(api_key) != 52:
		raise ApiError("INVALID_CONFIG", "API key باید 52 کاراکتر باشد", http_status=400)
	unit = _bitpay_amount_unit(cfg)
	wire_amount = _bitpay_wire_amount(amount, cfg)
	if wire_amount < _BITPAY_WIRE_MIN[unit]:
		raise ApiError(
			"INVALID_AMOUNT",
			"حداقل مبلغ پرداخت ۵۰٬۰۰۰ ریال (۵٬۰۰۰ تومان) است",
			http_status=400,
		)
	if wire_amount > _BITPAY_WIRE_MAX[unit]:
		raise ApiError(
			"AMOUNT_TOO_LARGE",
			"حداکثر مبلغ هر تراکنش در بیت‌پی ۵۰۰٬۰۰۰٬۰۰۰ ریال (۵۰٬۰۰۰٬۰۰۰ تومان) است",
			http_status=400,
		)
	# تعیین URL بر اساس sandbox
	base_url = "https://bitpay.ir/payment-test" if gw.is_sandbox else "https://bitpay.ir/payment"
	gateway_send_url = f"{base_url}/gateway-send"
	# اضافه کردن tx_id و source به callback
	from urllib.parse import urlencode, urlparse, parse_qsl, urlunparse
	
	# استخراج source از extra_info تراکنش
	source = "app"  # پیش‌فرض
	_tx_for_source = db.query(WalletTransaction).filter(WalletTransaction.id == int(tx_id)).first()
	if _tx_for_source and _tx_for_source.extra_info:
		try:
			extra_source = json.loads(_tx_for_source.extra_info)
			source = extra_source.get("source", "app")
		except Exception:
			pass
	
	try:
		u = urlparse(callback_url)
		q = dict(parse_qsl(u.query))
		q["tx_id"] = str(tx_id)
		q["source"] = source
		cb_url = urlunparse((u.scheme, u.netloc, u.path, u.params, urlencode(q), u.fragment))
	except Exception:
		cb_url = f"{callback_url}{'&' if '?' in callback_url else '?'}tx_id={tx_id}&source={source}"
	# بارگذاری اطلاعات کاربر از تراکنش
	_tx = db.query(WalletTransaction).filter(WalletTransaction.id == int(tx_id)).first()
	user_name = None
	user_email = None
	user_description = "افزایش اعتبار کیف پول"
	
	if _tx and _tx.extra_info:
		try:
			extra = json.loads(_tx.extra_info)
			user_name = extra.get("user_name") or extra.get("user_mobile")
			user_email = extra.get("user_email")
			if _tx.description:
				user_description = _tx.description
		except Exception:
			pass
	
	# آماده‌سازی داده‌های ارسالی (form data)
	data = {
		"api": api_key,
		"redirect": cb_url,
		"amount": wire_amount,
		"factorId": str(tx_id),  # شماره فاکتور
	}
	
	# فیلدهای اختیاری - استفاده از اطلاعات واقعی کاربر
	if user_name:
		data["name"] = str(user_name)
	if user_email:
		data["email"] = str(user_email)
	# توضیحات از تراکنش
	data["description"] = str(user_description)
	id_get: Optional[str] = None
	response_text = ""
	try:
		with httpx.Client(timeout=10.0) as client:
			# ارسال به صورت form data (نه JSON)
			resp = client.post(gateway_send_url, data=data)
			# پاسخ یک عدد است (id_get) که باید به string تبدیل شود
			response_text = resp.text.strip()
			# بررسی اینکه پاسخ یک عدد معتبر است
			try:
				id_get_int = int(response_text)
				if id_get_int > 0:
					id_get = str(id_get_int)
			except ValueError:
				# اگر عدد نبود، ممکن است خطا باشد
				id_get = None
	except Exception as e:
		logger.warning("bitpay_gateway_send_request_failed tx_id=%s amount=%s error=%s", tx_id, amount, e)
		id_get = None
	if not id_get:
		error_msg = "امکان ایجاد تراکنش در بیت‌پی نیست"
		try:
			err_code = int(response_text)
			if err_code < 0:
				error_msg = _BITPAY_ERROR_MESSAGES.get(err_code, f"خطای بیت‌پی (کد {err_code})")
				logger.warning(
					"bitpay_gateway_send_rejected tx_id=%s amount=%s code=%s",
					tx_id,
					amount,
					err_code,
				)
		except ValueError:
			if response_text:
				logger.warning(
					"bitpay_gateway_send_unexpected_response tx_id=%s amount=%s response=%s",
					tx_id,
					amount,
					response_text[:200],
				)
		raise ApiError("GATEWAY_INIT_FAILED", error_msg, http_status=502)
	# ساخت لینک پرداخت
	payment_url = f"{base_url}/gateway-{id_get}-get"
	# ذخیره اطلاعات در تراکنش
	_tx = db.query(WalletTransaction).filter(WalletTransaction.id == int(tx_id)).first()
	if _tx:
		extra = {}
		try:
			extra = json.loads(_tx.extra_info or "{}")
		except Exception:
			extra = {}
		extra.update({
			"gateway_id": gw.id,
			"provider": "bitpay",
			"id_get": id_get,
			"payment_url": payment_url,
			"bitpay_amount_unit": unit,
			"bitpay_wire_amount": wire_amount,
		})
		_tx.external_ref = id_get
		_tx.extra_info = json.dumps(extra, ensure_ascii=False)
		db.flush()
	return InitiateResult(payment_url=payment_url, external_ref=id_get)


def _verify_bitpay(db: Session, params: Dict[str, Any]) -> Dict[str, Any]:
	"""
	Verify BitPay payment:
	- Params expected: trans_id (id_trans), id_get (get_id), tx_id (optional)
	- Returns standardized dict with transaction_id, success, external_ref, fee_amount
	"""
	trans_id = str(params.get("trans_id") or params.get("id_trans") or "").strip()
	id_get = str(params.get("id_get") or params.get("get_id") or "").strip()
	tx_id = int(params.get("tx_id") or 0)
	if not trans_id or not id_get:
		# اگر پارامترهای لازم وجود نداشت، تراکنش ناموفق است
		if tx_id > 0:
			user_id = None
			tx = db.query(WalletTransaction).filter(WalletTransaction.id == int(tx_id)).first()
			if tx:
				try:
					extra = json.loads(tx.extra_info or "{}") if tx.extra_info else {}
					user_id = extra.get("created_by_user_id")
				except Exception:
					pass
			confirm_top_up(db, tx_id, success=False, external_ref=None, user_id=user_id)
		return {"transaction_id": tx_id, "success": False, "external_ref": None, "fee_amount": None}
	# بارگذاری تراکنش و درگاه
	tx = db.query(WalletTransaction).filter(WalletTransaction.id == int(tx_id)).first() if tx_id > 0 else None
	gateway_id = None
	if tx and tx.extra_info:
		try:
			extra = json.loads(tx.extra_info or "{}")
			gateway_id = extra.get("gateway_id")
		except Exception:
			pass
	gw = db.query(PaymentGateway).filter(PaymentGateway.id == int(gateway_id)).first() if gateway_id else None
	if not gw:
		# اگر درگاه پیدا نشد، تراکنش ناموفق است
		if tx_id > 0:
			user_id = None
			if tx:
				try:
					extra = json.loads(tx.extra_info or "{}") if tx.extra_info else {}
					user_id = extra.get("created_by_user_id")
				except Exception:
					pass
			confirm_top_up(db, tx_id, success=False, external_ref=id_get, user_id=user_id)
		return {"transaction_id": tx_id, "success": False, "external_ref": id_get, "fee_amount": None}
	cfg = _load_config(gw)
	api_key = str(cfg.get("api") or "").strip()
	if not api_key:
		# اگر API key وجود نداشت، تراکنش ناموفق است
		if tx_id > 0:
			user_id = None
			if tx:
				try:
					extra = json.loads(tx.extra_info or "{}") if tx.extra_info else {}
					user_id = extra.get("created_by_user_id")
				except Exception:
					pass
			confirm_top_up(db, tx_id, success=False, external_ref=id_get, user_id=user_id)
		return {"transaction_id": tx_id, "success": False, "external_ref": id_get, "fee_amount": None}
	# تعیین URL بر اساس sandbox
	base_url = "https://bitpay.ir/payment-test" if gw.is_sandbox else "https://bitpay.ir/payment"
	verify_url = f"{base_url}/gateway-result-second"
	# آماده‌سازی داده‌های ارسالی (form data با json=1)
	data = {
		"api": api_key,
		"trans_id": trans_id,
		"id_get": id_get,
		"json": "1",  # برای دریافت پاسخ JSON
	}
	success = False
	fee_amount = None
	amount = None
	card_num = None
	factor_id = None
	try:
		with httpx.Client(timeout=10.0) as client:
			# ارسال به صورت form data
			resp = client.post(verify_url, data=data)
			# پاسخ JSON است
			if "application/json" in (resp.headers.get("content-type", "").lower()):
				result = resp.json()
			else:
				# اگر JSON نبود، سعی می‌کنیم parse کنیم
				try:
					result = resp.json()
				except Exception:
					result = {}
			status = result.get("status")
			# بررسی status
			# 1 = موفق
			# -1 تا -5 = خطا
			# 11 = قبلاً verify شده
			if status == 1:
				success = True
				amount = result.get("amount")
				card_num = result.get("cardNum")
				factor_id = result.get("factorId")
			elif status == 11:
				# تراکنش قبلاً verify شده است
				success = True  # قبلاً موفق بوده
			else:
				# خطا (status < 0)
				success = False
	except Exception:
		success = False
	# تایید یا رد تراکنش
	user_id = None
	if tx_id > 0 and tx:
		try:
			extra = json.loads(tx.extra_info or "{}") if tx.extra_info else {}
			user_id = extra.get("created_by_user_id")
		except Exception:
			pass
		# به‌روزرسانی fee_amount در صورت وجود (BitPay معمولاً fee را برنمی‌گرداند)
		confirm_top_up(db, tx_id, success=success, external_ref=id_get, user_id=user_id)
	return {
		"transaction_id": tx_id,
		"success": success,
		"external_ref": id_get,
		"fee_amount": fee_amount,
		"amount": amount,
		"card_num": card_num,
		"factor_id": factor_id,
	}



