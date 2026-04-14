from __future__ import annotations

import json
from dataclasses import dataclass
from typing import Any, Dict, Optional, Tuple

import httpx
from sqlalchemy.orm import Session

from app.core.responses import ApiError
from adapters.db.models.payment_gateway import PaymentGateway
from adapters.db.models.wallet import WalletTransaction
from app.services.wallet_service import confirm_top_up


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
	"""
	Minimal integration:
	- expects cfg fields: terminal_id, merchant_id(optional), callback_url, api_base(optional), startpay_base(optional)
	- returns token with redirect to StartPay
	"""
	terminal_id = str(cfg.get("terminal_id") or "").strip()
	callback_url = str(cfg.get("callback_url") or "").strip()
	if not terminal_id or not callback_url:
		raise ApiError("INVALID_CONFIG", "terminal_id و callback_url الزامی هستند", http_status=400)
	api_base = str(cfg.get("api_base") or ("https://sandbox.banktest.ir/parsian" if gw.is_sandbox else "https://pec.shaparak.ir"))
	startpay_base = str(cfg.get("startpay_base") or ("https://sandbox.banktest.ir/parsian/startpay" if gw.is_sandbox else "https://pec.shaparak.ir/NewIPG/?Token"))
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

	token: Optional[str] = None
	try:
		with httpx.Client(timeout=10.0) as client:
			# This is a placeholder; real Parsian API may differ
			resp = client.post(f"{api_base}/SalePaymentRequest", json={
				"TerminalId": terminal_id,
				"Amount": int(round(float(amount))),
				"CallbackUrl": cb_url,
				"OrderId": tx_id,
			})
			data = resp.json() if resp.headers.get("content-type","").startswith("application/json") else {}
			if (data.get("Status") in (0, "0", 100, "100")) and data.get("Token"):
				token = str(data["Token"])
	except Exception:
		token = token or f"TEST-TOKEN-{tx_id}"

	if not token:
		raise ApiError("GATEWAY_INIT_FAILED", "امکان ایجاد تراکنش در پارسیان نیست", http_status=502)

	payment_url = f"{startpay_base}={token}" if "Token" in startpay_base or startpay_base.endswith("=") else f"{startpay_base}/{token}"
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
		})
		_tx.external_ref = token
		_tx.extra_info = json.dumps(extra, ensure_ascii=False)
		db.flush()
	return InitiateResult(payment_url=payment_url, external_ref=token)


def _verify_parsian(db: Session, params: Dict[str, Any]) -> Dict[str, Any]:
	# Params expected: Token, status, tx_id
	token = str(params.get("Token") or params.get("token") or "").strip()
	status = str(params.get("status") or "").lower()
	tx_id = int(params.get("tx_id") or 0)
	success = status in ("ok", "success", "0", "100")
	fee_amount = None
	user_id = None
	if tx_id > 0:
		# بارگذاری تراکنش برای استخراج user_id
		from adapters.db.models.wallet import WalletTransaction
		tx = db.query(WalletTransaction).filter(WalletTransaction.id == int(tx_id)).first()
		if tx:
			try:
				extra = json.loads(tx.extra_info or "{}") if tx.extra_info else {}
				user_id = extra.get("created_by_user_id")
			except Exception:
				pass
		confirm_top_up(db, tx_id, success=success, external_ref=token or None, user_id=user_id)
	return {"transaction_id": tx_id, "success": success, "external_ref": token, "fee_amount": fee_amount}


# --------------------------
# BITPAY
# --------------------------
def _initiate_bitpay(db: Session, gw: PaymentGateway, cfg: Dict[str, Any], business_id: int, tx_id: int, amount: float) -> InitiateResult:
	"""
	BitPay integration:
	- expects cfg fields: api (52 characters), callback_url (redirect)
	- amount must be at least 5000 Rials (500 Tomans)
	- returns id_get which is used to build payment URL
	"""
	api_key = str(cfg.get("api") or "").strip()
	callback_url = str(cfg.get("callback_url") or "").strip()
	if not api_key or not callback_url:
		raise ApiError("INVALID_CONFIG", "api و callback_url الزامی هستند", http_status=400)
	if len(api_key) != 52:
		raise ApiError("INVALID_CONFIG", "API key باید 52 کاراکتر باشد", http_status=400)
	# حداقل مبلغ 5000 ریال
	if amount < 5000:
		raise ApiError("INVALID_AMOUNT", "حداقل مبلغ 5000 ریال (500 تومان) است", http_status=400)
	# تعیین URL بر اساس sandbox
	base_url = "https://bitpay.ir/payment-test" if gw.is_sandbox else "https://bitpay.ir/payment"
	gateway_send_url = f"{base_url}/gateway-send"
	# encode کردن callback_url و اضافه کردن tx_id و source
	from urllib.parse import urlencode, urlparse, parse_qsl, urlunparse, quote
	
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
		# encode کردن کل URL برای BitPay (مطابق مستندات)
		cb_url = quote(cb_url, safe='')
	except Exception:
		cb_url_temp = f"{callback_url}{'&' if '?' in callback_url else '?'}tx_id={tx_id}&source={source}"
		cb_url = quote(cb_url_temp, safe='')
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
		"amount": int(round(float(amount))),
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
		# در محیط توسعه، می‌توان یک id_get تستی تولید کرد
		id_get = None
	if not id_get:
		# بررسی خطاهای احتمالی بر اساس مستندات
		error_msg = "امکان ایجاد تراکنش در بیت‌پی نیست"
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



