"""پرداخت مستقیم درگاه برای اشتراک پشتیبانی — بدون کیف‌پول و بدون کسب‌وکار."""

from __future__ import annotations

import json
import logging
from dataclasses import dataclass
from typing import Any, Dict, Optional, Tuple
from urllib.parse import parse_qsl, quote, urlencode, urlparse, urlunparse

import httpx
from sqlalchemy.orm import Session

from adapters.db.models.payment_gateway import PaymentGateway
from adapters.db.models.support.billing import SupportPaymentSession
from app.core.responses import ApiError
from app.core.settings import get_settings
from app.services.parsian_gateway import (
	build_startpay_url,
	callback_paid,
	confirm_payment,
	is_test_token,
	make_order_id,
	parse_amount,
	resolve_login_account,
	resolve_startpay_base,
	sale_error_message,
	sale_payment_request,
)
from app.services.payment_service import (
	_BITPAY_WIRE_MAX,
	_BITPAY_WIRE_MIN,
	_bitpay_amount_unit,
	_bitpay_wire_amount,
)

logger = logging.getLogger(__name__)


@dataclass
class InitiateResult:
	payment_url: str
	external_ref: str


def _load_config(gw: PaymentGateway) -> Dict[str, Any]:
	try:
		return json.loads(gw.config_json or "{}")
	except Exception:
		return {}


def _get_gateway(db: Session, gateway_id: int) -> PaymentGateway:
	gw = db.query(PaymentGateway).filter(PaymentGateway.id == int(gateway_id)).first()
	if not gw:
		raise ApiError("GATEWAY_NOT_FOUND", "درگاه پرداخت یافت نشد", http_status=404)
	if not gw.is_active:
		raise ApiError("GATEWAY_DISABLED", "درگاه پرداخت غیرفعال است", http_status=400)
	return gw


def resolve_support_gateway(db: Session, gateway_id: Optional[int] = None) -> PaymentGateway:
	from app.services.support.support_billing_settings import get_support_default_gateway_id

	if gateway_id:
		return _get_gateway(db, int(gateway_id))

	default_id = get_support_default_gateway_id(db)
	if default_id:
		gw = db.query(PaymentGateway).filter(PaymentGateway.id == int(default_id), PaymentGateway.is_active.is_(True)).first()
		if gw:
			return gw

	gw = (
		db.query(PaymentGateway)
		.filter(PaymentGateway.is_active.is_(True))
		.order_by(PaymentGateway.id.asc())
		.first()
	)
	if not gw:
		raise ApiError(
			"NO_ACTIVE_GATEWAY",
			"درگاه پرداخت سیستم برای پشتیبانی پیکربندی نشده است",
			http_status=400,
		)
	return gw


def list_active_system_gateways(db: Session) -> list[Dict[str, Any]]:
	items = (
		db.query(PaymentGateway)
		.filter(PaymentGateway.is_active.is_(True))
		.order_by(PaymentGateway.id.asc())
		.all()
	)
	return [
		{
			"id": g.id,
			"provider": g.provider,
			"display_name": g.display_name,
			"is_sandbox": bool(g.is_sandbox),
		}
		for g in items
	]


def _support_callback_url(provider: str, session_id: int, source: str = "app") -> str:
	"""ساخت URL بازگشت اختصاصی پشتیبانی از روی callback درگاه یا app_public_url."""
	settings = get_settings()
	prefix = (settings.api_v1_prefix or "/api/v1").rstrip("/")
	path = f"{prefix}/support/payments/callback/{provider.lower()}"

	# ترجیح: جایگزینی مسیر wallet در callback_url درگاه
	# اینجا فقط base ساخته می‌شود؛ پارامترها بعداً اضافه می‌شوند
	base = (settings.app_public_url or "").strip().rstrip("/")
	if base:
		return f"{base}{path}?session_id={int(session_id)}&source={source}"
	# fallback نسبی — درگاه معمولاً absolute می‌خواهد؛ caller باید override کند
	return f"{path}?session_id={int(session_id)}&source={source}"


def _build_callback_from_gateway_cfg(
	cfg: Dict[str, Any],
	provider: str,
	session_id: int,
	source: str = "app",
) -> str:
	raw = str(cfg.get("callback_url") or "").strip()
	if raw:
		# wallet callback → support callback روی همان host
		replaced = raw
		for needle in (
			"/wallet/payments/callback/zarinpal",
			"/wallet/payments/callback/parsian",
			"/wallet/payments/callback/bitpay",
			"/wallet/payments/callback/",
		):
			if needle in replaced:
				replaced = replaced.replace(
					needle,
					f"/support/payments/callback/{provider.lower()}"
					if not needle.endswith("/")
					else f"/support/payments/callback/{provider.lower()}",
				)
				# اگر needle با / تمام شده بود مسیر کامل نبود؛ اصلاح:
				break
		# ساده‌تر: parse و عوض کردن path
		try:
			u = urlparse(replaced if "support/payments/callback" in replaced else raw)
			new_path = u.path
			if "/wallet/payments/callback" in new_path:
				# /api/v1/wallet/payments/callback/zarinpal → /api/v1/support/payments/callback/zarinpal
				idx = new_path.find("/wallet/payments/callback")
				prefix = new_path[:idx]
				new_path = f"{prefix}/support/payments/callback/{provider.lower()}"
			elif "/support/payments/callback" not in new_path:
				# اگر path چیز دیگری بود، از app_public_url استفاده کن
				return _support_callback_url(provider, session_id, source)
			q = dict(parse_qsl(u.query))
			q["session_id"] = str(session_id)
			q["source"] = source
			# حذف tx_id کیف‌پول اگر بود
			q.pop("tx_id", None)
			return urlunparse((u.scheme, u.netloc, new_path, u.params, urlencode(q), u.fragment))
		except Exception:
			pass
	return _support_callback_url(provider, session_id, source)


def initiate_support_gateway_payment(
	db: Session,
	*,
	session: SupportPaymentSession,
	gateway: PaymentGateway,
	description: str = "خرید اشتراک پشتیبانی حسابیکس",
	source: str = "app",
	user_name: Optional[str] = None,
	user_email: Optional[str] = None,
) -> InitiateResult:
	cfg = _load_config(gateway)
	provider = (gateway.provider or "").lower().strip()
	amount = float(session.amount or 0)
	if amount <= 0:
		raise ApiError("INVALID_AMOUNT", "مبلغ پرداخت نامعتبر است", http_status=400)

	if provider == "zarinpal":
		result = _initiate_zarinpal(db, gateway, cfg, session, amount, description, source)
	elif provider == "parsian":
		result = _initiate_parsian(db, gateway, cfg, session, amount, source)
	elif provider == "bitpay":
		result = _initiate_bitpay(
			db, gateway, cfg, session, amount, description, source, user_name, user_email
		)
	else:
		raise ApiError("UNSUPPORTED_PROVIDER", f"درگاه '{gateway.provider}' پشتیبانی نمی‌شود", http_status=400)

	session.external_ref = result.external_ref
	session.status = "redirected"
	payload: Dict[str, Any] = {
		"payment_url": result.payment_url,
		"external_ref": result.external_ref,
		"provider": provider,
		"internal_amount": amount,
	}
	if provider == "bitpay":
		payload["bitpay_amount_unit"] = _bitpay_amount_unit(cfg)
		payload["bitpay_wire_amount"] = _bitpay_wire_amount(amount, cfg)
	if provider == "parsian":
		payload["parsian_order_id"] = make_order_id("support", session.id)
	session.provider_payload = payload
	db.flush()
	return result


def verify_support_gateway_payment(
	db: Session,
	*,
	provider: str,
	params: Dict[str, Any],
) -> Dict[str, Any]:
	provider_l = (provider or "").lower().strip()
	session_id = int(params.get("session_id") or 0)
	if session_id <= 0:
		raise ApiError("SESSION_REQUIRED", "شناسه نشست پرداخت الزامی است", http_status=400)

	session = db.query(SupportPaymentSession).filter(SupportPaymentSession.id == session_id).first()
	if not session:
		raise ApiError("SESSION_NOT_FOUND", "نشست پرداخت یافت نشد", http_status=404)

	# Idempotent
	if session.status == "paid":
		return {
			"session_id": session.id,
			"invoice_id": session.invoice_id,
			"success": True,
			"external_ref": session.external_ref,
			"already_paid": True,
			"ref_id": None,
		}

	gateway = _get_gateway(db, session.gateway_id)
	cfg = _load_config(gateway)

	if provider_l == "zarinpal":
		success, external_ref, ref_id, verify_payload = _verify_zarinpal(session, gateway, cfg, params)
	elif provider_l == "parsian":
		success, external_ref, ref_id, verify_payload = _verify_parsian(session, gateway, cfg, params)
	elif provider_l == "bitpay":
		success, external_ref, ref_id, verify_payload = _verify_bitpay(session, gateway, cfg, params)
	else:
		raise ApiError("UNSUPPORTED_PROVIDER", f"درگاه '{provider}' پشتیبانی نمی‌شود", http_status=400)

	session.verify_payload = verify_payload
	session.status = "verifying"
	db.flush()

	from app.services.support.support_billing_service import confirm_support_payment

	confirm_support_payment(
		db,
		session=session,
		success=success,
		external_ref=external_ref,
		gateway_trace=str(ref_id) if ref_id is not None else None,
	)
	return {
		"session_id": session.id,
		"invoice_id": session.invoice_id,
		"success": success,
		"external_ref": external_ref,
		"already_paid": False,
		"ref_id": ref_id,
	}


# ---- Zarinpal ----
def _initiate_zarinpal(
	db: Session,
	gw: PaymentGateway,
	cfg: Dict[str, Any],
	session: SupportPaymentSession,
	amount: float,
	description: str,
	source: str,
) -> InitiateResult:
	merchant_id = str(cfg.get("merchant_id") or "").strip()
	if not merchant_id:
		raise ApiError("INVALID_CONFIG", "merchant_id الزامی است", http_status=400)
	cb_url = _build_callback_from_gateway_cfg(cfg, "zarinpal", session.id, source)
	v4_domain = "https://sandbox.zarinpal.com" if gw.is_sandbox else "https://api.zarinpal.com"
	api_v4_url = str(cfg.get("api_v4_url") or f"{v4_domain}/pg/v4/payment/request.json")
	startpay_base = str(
		cfg.get("startpay_base")
		or ("https://sandbox.zarinpal.com/pg/StartPay" if gw.is_sandbox else "https://payment.zarinpal.com/pg/StartPay")
	)
	payload = {
		"merchant_id": merchant_id,
		"amount": int(round(float(amount))),
		"callback_url": cb_url,
		"description": description or "Support subscription",
	}
	authority: Optional[str] = None
	try:
		with httpx.Client(timeout=15.0) as client:
			resp = client.post(
				api_v4_url,
				json=payload,
				headers={"Accept": "application/json", "Content-Type": "application/json"},
			)
			data = resp.json() if "application/json" in (resp.headers.get("content-type") or "") else {}
			d_data = data.get("data") if isinstance(data, dict) else None
			auth_v4 = (d_data or {}).get("authority") if isinstance(d_data, dict) else None
			if auth_v4:
				authority = str(auth_v4)
	except Exception as ex:
		logger.warning("support_zarinpal_initiate_failed session=%s err=%s", session.id, ex)
		authority = None

	if not authority and gw.is_sandbox:
		authority = f"TEST-SUPPORT-{session.id}"

	if not authority:
		raise ApiError("GATEWAY_INIT_FAILED", "ایجاد درخواست پرداخت زرین‌پال ناموفق بود", http_status=502)

	payment_url = f"{startpay_base}/{authority}"
	return InitiateResult(payment_url=payment_url, external_ref=authority)


def _verify_zarinpal(
	session: SupportPaymentSession,
	gw: PaymentGateway,
	cfg: Dict[str, Any],
	params: Dict[str, Any],
) -> Tuple[bool, Optional[str], Optional[Any], Dict[str, Any]]:
	authority = str(params.get("Authority") or params.get("authority") or session.external_ref or "").strip()
	status = str(params.get("Status") or params.get("status") or "").lower()
	is_ok = status in ("ok", "ok.", "success", "succeeded")
	success = False
	ref_id = None
	payload: Dict[str, Any] = {"status": status, "authority": authority}
	if is_ok and authority:
		merchant_id = str(cfg.get("merchant_id") or "").strip()
		v4_domain = "https://sandbox.zarinpal.com" if gw.is_sandbox else "https://payment.zarinpal.com"
		verify_url = f"{v4_domain}/pg/v4/payment/verify.json"
		try:
			with httpx.Client(timeout=15.0) as client:
				resp = client.post(
					verify_url,
					json={
						"merchant_id": merchant_id,
						"amount": int(round(float(session.amount or 0))),
						"authority": authority,
					},
					headers={"Accept": "application/json", "Content-Type": "application/json"},
				)
				data = resp.json() if "application/json" in (resp.headers.get("content-type") or "") else {}
				payload["verify"] = data
				d_data = data.get("data") if isinstance(data, dict) else None
				code = (d_data or {}).get("code") if isinstance(d_data, dict) else None
				ref_id = (d_data or {}).get("ref_id")
				success = int(code or -1) in (100, 101)
		except Exception as ex:
			logger.warning("support_zarinpal_verify_failed session=%s err=%s", session.id, ex)
			success = False
			# sandbox fallback
			if gw.is_sandbox and authority.startswith("TEST-SUPPORT-"):
				success = True
	return success or (gw.is_sandbox and is_ok and bool(authority)), authority or None, ref_id, payload


# ---- Parsian ----
def _initiate_parsian(
	db: Session,
	gw: PaymentGateway,
	cfg: Dict[str, Any],
	session: SupportPaymentSession,
	amount: float,
	source: str,
) -> InitiateResult:
	login_account = resolve_login_account(cfg)
	if not login_account:
		raise ApiError("INVALID_CONFIG", "شناسه پذیرنده (PIN) الزامی است", http_status=400)
	cb_url = _build_callback_from_gateway_cfg(cfg, "parsian", session.id, source)
	order_id = make_order_id("support", int(session.id))
	wire_amount = parse_amount(amount)
	sale = sale_payment_request(
		cfg,
		is_sandbox=bool(gw.is_sandbox),
		order_id=order_id,
		amount=wire_amount,
		callback_url=cb_url,
	)
	token: Optional[str] = None
	if sale.ok and sale.token:
		token = str(sale.token)
	elif gw.is_sandbox:
		logger.warning("support_parsian_sandbox_fallback session=%s status=%s", session.id, sale.status)
		token = f"TEST-PARSIAN-{session.id}"
	else:
		raise ApiError("GATEWAY_INIT_FAILED", sale_error_message(sale), http_status=502)

	startpay_base = resolve_startpay_base(cfg, is_sandbox=bool(gw.is_sandbox))
	payment_url = build_startpay_url(startpay_base, token)
	return InitiateResult(payment_url=payment_url, external_ref=token)


def _verify_parsian(
	session: SupportPaymentSession,
	gw: PaymentGateway,
	cfg: Dict[str, Any],
	params: Dict[str, Any],
) -> Tuple[bool, Optional[str], Optional[Any], Dict[str, Any]]:
	token = str(params.get("Token") or params.get("token") or session.external_ref or "").strip()
	cb_status = params.get("status") if params.get("status") is not None else params.get("Status")
	payload: Dict[str, Any] = {"token": token, "raw": {k: str(v) for k, v in params.items() if k != "db"}}
	success = False
	ref_id = params.get("RRN") or params.get("rrn") or params.get("RefNum")
	stored = session.provider_payload if isinstance(session.provider_payload, dict) else {}
	if gw.is_sandbox and is_test_token(token):
		success = True
	elif callback_paid(cb_status) and token:
		order_id = parse_amount(
			params.get("OrderId") or stored.get("parsian_order_id") or make_order_id("support", session.id)
		)
		cb_amount = parse_amount(params.get("Amount"))
		amount = cb_amount if cb_amount > 0 else parse_amount(session.amount)
		confirm = confirm_payment(
			cfg,
			is_sandbox=bool(gw.is_sandbox),
			token=token,
			order_id=order_id,
			amount=amount,
		)
		payload["confirm"] = {
			"status": confirm.status,
			"rrn": confirm.rrn,
			"message": confirm.message,
		}
		success = bool(confirm.ok)
		if confirm.rrn:
			ref_id = confirm.rrn
	return success, token or None, ref_id, payload


# ---- BitPay ----
def _initiate_bitpay(
	db: Session,
	gw: PaymentGateway,
	cfg: Dict[str, Any],
	session: SupportPaymentSession,
	amount: float,
	description: str,
	source: str,
	user_name: Optional[str],
	user_email: Optional[str],
) -> InitiateResult:
	api_key = str(cfg.get("api") or "").strip()
	if not api_key:
		raise ApiError("INVALID_CONFIG", "api الزامی است", http_status=400)
	unit = _bitpay_amount_unit(cfg)
	wire_amount = _bitpay_wire_amount(amount, cfg)
	if wire_amount < _BITPAY_WIRE_MIN[unit]:
		raise ApiError("INVALID_AMOUNT", "حداقل مبلغ ۵۰٬۰۰۰ ریال (۵٬۰۰۰ تومان) است", http_status=400)
	if wire_amount > _BITPAY_WIRE_MAX[unit]:
		raise ApiError(
			"AMOUNT_TOO_LARGE",
			"حداکثر مبلغ هر تراکنش در بیت‌پی ۵۰۰٬۰۰۰٬۰۰۰ ریال است",
			http_status=400,
		)
	cb_url = _build_callback_from_gateway_cfg(cfg, "bitpay", session.id, source)
	base_url = "https://bitpay.ir/payment-test" if gw.is_sandbox else "https://bitpay.ir/payment"
	gateway_send_url = f"{base_url}/gateway-send"
	data = {
		"api": api_key,
		"redirect": cb_url,
		"amount": wire_amount,
		"factorId": str(session.id),
		"description": description or "Support subscription",
	}
	if user_name:
		data["name"] = str(user_name)
	if user_email:
		data["email"] = str(user_email)

	id_get: Optional[str] = None
	try:
		with httpx.Client(timeout=15.0) as client:
			resp = client.post(gateway_send_url, data=data)
			text = resp.text.strip()
			id_get_int = int(text)
			if id_get_int > 0:
				id_get = str(id_get_int)
	except Exception as ex:
		logger.warning("support_bitpay_initiate_failed session=%s err=%s", session.id, ex)
		id_get = None

	if not id_get and gw.is_sandbox:
		id_get = f"TEST-BITPAY-{session.id}"

	if not id_get:
		raise ApiError("GATEWAY_INIT_FAILED", "ایجاد درخواست پرداخت بیت‌پی ناموفق بود", http_status=502)

	payment_url = f"{base_url}/gateway-{id_get}-get"
	return InitiateResult(payment_url=payment_url, external_ref=id_get)


def _verify_bitpay(
	session: SupportPaymentSession,
	gw: PaymentGateway,
	cfg: Dict[str, Any],
	params: Dict[str, Any],
) -> Tuple[bool, Optional[str], Optional[Any], Dict[str, Any]]:
	trans_id = str(params.get("trans_id") or params.get("id_get") or session.external_ref or "").strip()
	id_get = str(params.get("id_get") or session.external_ref or "").strip()
	payload: Dict[str, Any] = {"trans_id": trans_id, "id_get": id_get, "raw": dict(params)}
	success = False
	ref_id = trans_id or None
	if gw.is_sandbox and str(session.external_ref or "").startswith("TEST-BITPAY-"):
		success = True
	else:
		api_key = str(cfg.get("api") or "").strip()
		base_url = "https://bitpay.ir/payment-test" if gw.is_sandbox else "https://bitpay.ir/payment"
		verify_url = f"{base_url}/gateway-result-second"
		try:
			with httpx.Client(timeout=15.0) as client:
				resp = client.post(
					verify_url,
					data={
						"api": api_key,
						"trans_id": trans_id,
						"id_get": id_get,
						"json": 1,
					},
				)
				data = resp.json() if resp.content else {}
				payload["verify"] = data
				# status 1 = success typical for bitpay
				st = data.get("status") if isinstance(data, dict) else None
				success = str(st) in ("1", "OK", "ok")
		except Exception as ex:
			logger.warning("support_bitpay_verify_failed session=%s err=%s", session.id, ex)
			success = False
	return success, id_get or trans_id or None, ref_id, payload
