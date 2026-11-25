"""سرویس پرداخت اعتباری دیجی‌پی: تیکت UPG، اسناد فروش روی ۱۰۴۰۱ و تسویه تأخیری."""

from __future__ import annotations

import json
import logging
import re
import uuid
from datetime import date, datetime
from decimal import Decimal, ROUND_HALF_UP
from typing import Any, Dict, List, Optional

from sqlalchemy import func
from sqlalchemy.orm import Session

from adapters.db.models.bank_account import BankAccount
from adapters.db.models.digipay import DigipayPurchase, DigipaySettlement, DigipaySettings
from adapters.db.models.person import Person
from app.core.date_input import format_user_date, parse_user_date
from app.core.datetime_utils import utc_now
from app.core.digipay_plugin_dependency import PLUGIN_CODE, ensure_digipay_plugin_active
from app.core.i18n import get_translator
from app.core.responses import ApiError
from app.services.ai.encryption import decrypt_api_key, encrypt_api_key
from app.services.digipay_client import (
	CREDIT_TYPES,
	TYPE_CREDIT,
	DigipayClient,
	DigipayClientError,
)

logger = logging.getLogger(__name__)

DIGIPAY_PERSON_ALIAS_FA = "دیجی‌پی"
DIGIPAY_PERSON_ALIAS_EN = "DigiPay"
SETTLED_STATUS = "settled"
TWOPLACES = Decimal("0.01")


def _tr(locale: str):
	return get_translator(locale or "fa")


def _msg(locale: str, key: str, fa: str, en: str) -> str:
	chosen = fa if (locale or "fa").startswith("fa") else en
	return _tr(locale).t(key, chosen)


def _enc(value: str | None) -> str | None:
	if not value:
		return None
	out = encrypt_api_key(value)
	if not out:
		raise ApiError("SECRET_ENCRYPTION_FAILED", "Credential encryption failed", http_status=500)
	return out


def _dec(value: str | None, locale: str, label_fa: str, label_en: str) -> str | None:
	if not value:
		return None
	out = decrypt_api_key(value)
	if not out:
		raise ApiError(
			"SECRET_DECRYPTION_FAILED",
			_msg(locale, "DIGIPAY_DECRYPT_FAILED", f"بازیابی {label_fa} ممکن نیست.", f"Could not decrypt {label_en}."),
			http_status=500,
		)
	return out


def _mask_encrypted(value: str | None) -> str | None:
	"""Mask credentials for GET settings without failing the whole payload."""
	if not value:
		return None
	plain = decrypt_api_key(value)
	if not plain:
		return "****"
	return _mask(plain)


def _ticket_redirect_url(resp: Dict[str, Any]) -> Optional[str]:
	# Docs prose says payUrl; official sample JSON uses redirectUrl.
	url = str(resp.get("redirectUrl") or resp.get("payUrl") or "").strip()
	return url or None


def _callback_amount_rials(value: Any) -> Optional[int]:
	if value is None or value == "":
		return None
	try:
		return int(Decimal(str(value)).quantize(Decimal("1"), rounding=ROUND_HALF_UP))
	except Exception:
		return None


def _mask(value: str | None) -> str | None:
	if not value:
		return None
	if len(value) <= 4:
		return "*" * len(value)
	return value[:2] + ("*" * (len(value) - 4)) + value[-2:]


def _money(value: Any) -> Decimal:
	return Decimal(str(value or 0)).quantize(TWOPLACES, rounding=ROUND_HALF_UP)


def _rials(amount: Decimal) -> int:
	return int(amount.quantize(Decimal("1"), rounding=ROUND_HALF_UP))


def _normalize_mobile(raw: str | None, locale: str) -> str:
	digits = re.sub(r"\D+", "", str(raw or ""))
	if digits.startswith("0098"):
		digits = "0" + digits[4:]
	elif digits.startswith("98") and len(digits) >= 12:
		digits = "0" + digits[2:]
	elif digits.startswith("9") and len(digits) == 10:
		digits = "0" + digits
	if not re.fullmatch(r"09\d{9}", digits):
		raise ApiError(
			"DIGIPAY_INVALID_MOBILE",
			_msg(locale, "DIGIPAY_INVALID_MOBILE", "شماره همراه مشتری نامعتبر است.", "Customer mobile number is invalid."),
			http_status=400,
		)
	return digits


def _calendar(request) -> str:
	try:
		return str(getattr(request.state, "calendar_type", None) or "jalali")
	except Exception:
		return "jalali"


def _locale_of(request) -> str:
	try:
		tr = getattr(request.state, "translator", None)
		if tr is not None:
			return str(getattr(tr, "locale", "fa") or "fa")
	except Exception:
		pass
	return "fa"


def _get_settings_row(db: Session, business_id: int) -> Optional[DigipaySettings]:
	return db.query(DigipaySettings).filter(DigipaySettings.business_id == int(business_id)).first()


def ensure_settings_row(db: Session, business_id: int) -> DigipaySettings:
	row = _get_settings_row(db, business_id)
	if row:
		return row
	row = DigipaySettings(
		business_id=int(business_id),
		environment="sandbox",
		commission_percent=Decimal("0"),
		vat_on_commission_percent=Decimal("10"),
		auto_deliver_in_store=True,
	)
	db.add(row)
	db.flush()
	return row


def ensure_digipay_person(db: Session, business_id: int, locale: str = "fa") -> Person:
	alias = DIGIPAY_PERSON_ALIAS_FA if str(locale).startswith("fa") else DIGIPAY_PERSON_ALIAS_EN
	existing = (
		db.query(Person)
		.filter(Person.business_id == int(business_id), Person.alias_name.in_([DIGIPAY_PERSON_ALIAS_FA, DIGIPAY_PERSON_ALIAS_EN]))
		.order_by(Person.id.asc())
		.first()
	)
	if existing:
		return existing
	max_code = db.query(func.max(Person.code)).filter(Person.business_id == int(business_id)).scalar()
	person = Person(
		business_id=int(business_id),
		code=int(max_code or 0) + 1,
		alias_name=alias,
		company_name=DIGIPAY_PERSON_ALIAS_FA,
		legal_entity_type="legal",
		person_types=json.dumps(["همکار"], ensure_ascii=False),
	)
	db.add(person)
	db.flush()
	return person


def _settings_public(db: Session, row: DigipaySettings, locale: str) -> Dict[str, Any]:
	person = None
	if row.person_id:
		person = db.query(Person).filter(Person.id == int(row.person_id)).first()
	return {
		"plugin_code": PLUGIN_CODE,
		"environment": row.environment,
		"username_masked": _mask_encrypted(row.username_encrypted),
		"client_id_masked": _mask_encrypted(row.client_id_encrypted),
		"password_configured": bool(row.password_encrypted),
		"client_secret_configured": bool(row.client_secret_encrypted),
		"credentials_ready": bool(
			row.username_encrypted and row.password_encrypted and row.client_id_encrypted and row.client_secret_encrypted
		),
		"person_id": row.person_id,
		"person_name": person.alias_name if person else None,
		"settlement_bank_account_id": row.settlement_bank_account_id,
		"commission_percent": float(row.commission_percent or 0),
		"vat_on_commission_percent": float(row.vat_on_commission_percent or 0),
		"seller_id": row.seller_id,
		"auto_deliver_in_store": bool(row.auto_deliver_in_store),
	}


def get_settings(db: Session, business_id: int, *, locale: str = "fa") -> Dict[str, Any]:
	ensure_digipay_plugin_active(db, business_id, locale=locale)
	row = ensure_settings_row(db, business_id)
	if not row.person_id:
		person = ensure_digipay_person(db, business_id, locale=locale)
		row.person_id = person.id
		db.flush()
	return _settings_public(db, row, locale)


def update_settings(db: Session, business_id: int, payload: Dict[str, Any], *, locale: str = "fa") -> Dict[str, Any]:
	ensure_digipay_plugin_active(db, business_id, locale=locale)
	row = ensure_settings_row(db, business_id)
	env = str(payload.get("environment") or row.environment or "sandbox").strip().lower()
	if env not in {"sandbox", "live"}:
		raise ApiError("DIGIPAY_INVALID_ENVIRONMENT", _msg(locale, "DIGIPAY_INVALID_ENVIRONMENT", "محیط باید تست یا عملیاتی باشد.", "Environment must be sandbox or live."), http_status=400)
	row.environment = env
	if payload.get("username"):
		row.username_encrypted = _enc(str(payload.get("username")).strip())
	if payload.get("password"):
		row.password_encrypted = _enc(str(payload.get("password")))
	if payload.get("client_id"):
		row.client_id_encrypted = _enc(str(payload.get("client_id")).strip())
	if payload.get("client_secret"):
		row.client_secret_encrypted = _enc(str(payload.get("client_secret")))
	if payload.get("person_id") is not None:
		pid = int(payload.get("person_id"))
		person = db.query(Person).filter(Person.id == pid, Person.business_id == int(business_id)).first()
		if not person:
			raise ApiError("PERSON_NOT_FOUND", _msg(locale, "PERSON_NOT_FOUND", "شخص یافت نشد.", "Person not found."), http_status=404)
		row.person_id = pid
	elif not row.person_id:
		row.person_id = ensure_digipay_person(db, business_id, locale=locale).id
	if payload.get("settlement_bank_account_id") is not None:
		bid = int(payload.get("settlement_bank_account_id") or 0)
		if bid:
			bank = db.query(BankAccount).filter(BankAccount.id == bid, BankAccount.business_id == int(business_id)).first()
			if not bank:
				raise ApiError("BANK_ACCOUNT_NOT_FOUND", _msg(locale, "BANK_ACCOUNT_NOT_FOUND", "حساب بانکی یافت نشد.", "Bank account not found."), http_status=404)
			row.settlement_bank_account_id = bid
		else:
			row.settlement_bank_account_id = None
	if payload.get("commission_percent") is not None:
		row.commission_percent = _money(payload.get("commission_percent"))
	if payload.get("vat_on_commission_percent") is not None:
		row.vat_on_commission_percent = _money(payload.get("vat_on_commission_percent"))
	if "seller_id" in payload:
		row.seller_id = str(payload.get("seller_id") or "").strip() or None
	if "auto_deliver_in_store" in payload:
		row.auto_deliver_in_store = bool(payload.get("auto_deliver_in_store"))
	row.updated_at = utc_now()
	db.commit()
	db.refresh(row)
	return _settings_public(db, row, locale)


def _client_from_settings(row: DigipaySettings, locale: str) -> DigipayClient:
	username = _dec(row.username_encrypted, locale, "نام کاربری", "username")
	password = _dec(row.password_encrypted, locale, "رمز عبور", "password")
	client_id = _dec(row.client_id_encrypted, locale, "شناسه کلاینت", "client id")
	client_secret = _dec(row.client_secret_encrypted, locale, "رمز کلاینت", "client secret")
	if not all([username, password, client_id, client_secret]):
		raise ApiError(
			"DIGIPAY_CREDENTIALS_MISSING",
			_msg(locale, "DIGIPAY_CREDENTIALS_MISSING", "اعتبارنامه UPG دیجی‌پی کامل نیست.", "DigiPay UPG credentials are incomplete."),
			http_status=400,
		)
	return DigipayClient(
		username=username,
		password=password,
		client_id=client_id,
		client_secret=client_secret,
		environment=row.environment or "sandbox",
	)


def test_connection(db: Session, business_id: int, *, locale: str = "fa") -> Dict[str, Any]:
	ensure_digipay_plugin_active(db, business_id, locale=locale)
	row = ensure_settings_row(db, business_id)
	client = _client_from_settings(row, locale)
	try:
		client.login()
	except DigipayClientError as exc:
		raise ApiError(
			exc.code if hasattr(exc, "code") else "DIGIPAY_AUTH_FAILED",
			_msg(locale, "DIGIPAY_AUTH_FAILED", "ورود به دیجی‌پی ناموفق بود. اعتبارنامه را بررسی کنید.", "DigiPay login failed. Check the credentials."),
			http_status=400,
		) from exc
	return {"ok": True, "environment": row.environment}


def _purchase_dict(row: DigipayPurchase, *, calendar_type: str = "jalali") -> Dict[str, Any]:
	return {
		"id": row.id,
		"provider_id": row.provider_id,
		"ticket": row.ticket,
		"redirect_url": row.redirect_url,
		"amount": float(row.amount or 0),
		"cash_amount": float(row.cash_amount or 0),
		"credit_amount": float(row.credit_amount or 0),
		"cell_number": row.cell_number,
		"tracking_code": row.tracking_code,
		"ticket_type": row.ticket_type,
		"payment_gateway": row.payment_gateway,
		"status": row.status,
		"source": row.source,
		"invoice_id": row.invoice_id,
		"receipt_document_id": row.receipt_document_id,
		"settlement_id": row.settlement_id,
		"created_at": format_user_date(row.created_at, calendar_type=calendar_type),
		"verified_at": format_user_date(row.verified_at, calendar_type=calendar_type),
		"delivered_at": format_user_date(row.delivered_at, calendar_type=calendar_type),
	}


def _build_basket(payload: Dict[str, Any], settings: DigipaySettings) -> Dict[str, Any]:
	items = payload.get("items") or []
	normalized = []
	for item in items:
		normalized.append(
			{
				"sellerId": str(item.get("seller_id") or settings.seller_id or "hesabix"),
				"supplierId": str(item.get("supplier_id") or settings.seller_id or "hesabix"),
				"productCode": str(item.get("product_code") or item.get("code") or "item"),
				"brand": str(item.get("brand") or "generic"),
				"productType": int(item.get("product_type") or 2),
				"count": int(item.get("count") or item.get("quantity") or 1),
				"categoryId": str(item.get("category_id") or "general"),
			}
		)
	if not normalized:
		normalized.append(
			{
				"sellerId": str(settings.seller_id or "hesabix"),
				"supplierId": str(settings.seller_id or "hesabix"),
				"productCode": "pos-sale",
				"brand": "generic",
				"productType": 2,
				"count": 1,
				"categoryId": "general",
			}
		)
	return {"basketId": str(payload.get("basket_id") or uuid.uuid4()), "items": normalized}


def create_ticket(
	db: Session,
	business_id: int,
	user_id: int,
	payload: Dict[str, Any],
	*,
	locale: str = "fa",
	callback_url: str,
	calendar_type: str = "jalali",
) -> Dict[str, Any]:
	ensure_digipay_plugin_active(db, business_id, locale=locale)
	row = ensure_settings_row(db, business_id)
	if not row.person_id:
		row.person_id = ensure_digipay_person(db, business_id, locale=locale).id
	amount = _money(payload.get("amount"))
	if amount <= 0:
		raise ApiError("DIGIPAY_INVALID_AMOUNT", _msg(locale, "DIGIPAY_INVALID_AMOUNT", "مبلغ باید بزرگ‌تر از صفر باشد.", "Amount must be greater than zero."), http_status=400)
	mobile = _normalize_mobile(payload.get("cell_number") or payload.get("cellNumber"), locale)
	provider_id = f"hx{business_id}{uuid.uuid4().hex[:16]}"
	basket = _build_basket(payload, row)
	body = {
		"cellNumber": mobile,
		"amount": _rials(amount),
		"providerId": provider_id,
		"callbackUrl": callback_url,
		"basketDetailsDto": basket,
	}
	client = _client_from_settings(row, locale)
	try:
		resp = client.create_ticket(body)
	except DigipayClientError as exc:
		logger.warning("digipay ticket failed: %s", exc)
		raise ApiError(
			"DIGIPAY_TICKET_FAILED",
			_msg(locale, "DIGIPAY_TICKET_FAILED", "صدور تیکت دیجی‌پی ناموفق بود.", "Could not create a DigiPay ticket."),
			http_status=502,
			details=getattr(exc, "details", None),
		) from exc
	purchase = DigipayPurchase(
		business_id=int(business_id),
		provider_id=provider_id,
		ticket=str(resp.get("ticket") or "") or None,
		redirect_url=_ticket_redirect_url(resp),
		amount=amount,
		cell_number=mobile,
		status="pending",
		source=str(payload.get("source") or "quick_sales"),
		invoice_id=int(payload["invoice_id"]) if payload.get("invoice_id") else None,
		basket_json=basket,
		extra_info={"callback_url": callback_url},
		created_by_user_id=int(user_id) if user_id else None,
	)
	db.add(purchase)
	db.commit()
	db.refresh(purchase)
	out = _purchase_dict(purchase, calendar_type=calendar_type)
	out["person_id"] = row.person_id
	person = db.query(Person).filter(Person.id == int(row.person_id)).first() if row.person_id else None
	out["person_name"] = person.alias_name if person else DIGIPAY_PERSON_ALIAS_FA
	return out


def _apply_verify_payload(purchase: DigipayPurchase, data: Dict[str, Any]) -> None:
	purchase.tracking_code = str(data.get("trackingCode") or purchase.tracking_code or "")
	if data.get("paymentGateway") is not None:
		try:
			purchase.payment_gateway = int(data.get("paymentGateway"))
		except (TypeError, ValueError):
			pass
	info = data.get("additionalInfo") if isinstance(data.get("additionalInfo"), dict) else {}
	if info:
		purchase.cash_amount = _money(info.get("cashAmount") or 0)
		purchase.credit_amount = _money(info.get("creditAmount") or purchase.amount)
		extra = dict(purchase.extra_info or {})
		extra["verify_additional"] = info
		purchase.extra_info = extra
	purchase.status = "verified"
	purchase.verified_at = utc_now()
	purchase.updated_at = utc_now()


def verify_purchase(
	db: Session,
	business_id: int,
	purchase: DigipayPurchase,
	*,
	tracking_code: str,
	ticket_type: int,
	locale: str = "fa",
) -> DigipayPurchase:
	row = ensure_settings_row(db, business_id)
	client = _client_from_settings(row, locale)
	try:
		data = client.verify(tracking_code=tracking_code, provider_id=purchase.provider_id, ticket_type=ticket_type)
	except DigipayClientError as exc:
		extra = dict(purchase.extra_info or {})
		extra["verify_error"] = getattr(exc, "details", None)
		purchase.extra_info = extra
		db.commit()
		raise ApiError(
			"DIGIPAY_VERIFY_FAILED",
			_msg(locale, "DIGIPAY_VERIFY_FAILED", "تأیید پرداخت دیجی‌پی ناموفق بود.", "DigiPay payment verification failed."),
			http_status=400,
			details=getattr(exc, "details", None),
		) from exc
	purchase.ticket_type = int(ticket_type)
	_apply_verify_payload(purchase, data)
	db.flush()
	if row.auto_deliver_in_store and purchase.source in {"quick_sales", "manual", "pos"} and purchase.ticket_type in CREDIT_TYPES:
		try:
			_deliver_internal(client, purchase, locale=locale)
		except ApiError as exc:
			logger.warning("digipay auto-deliver deferred provider=%s: %s", purchase.provider_id, exc)
			extra = dict(purchase.extra_info or {})
			extra["auto_deliver_error"] = getattr(exc, "message", str(exc))
			purchase.extra_info = extra
	db.commit()
	db.refresh(purchase)
	return purchase


def _deliver_internal(client: DigipayClient, purchase: DigipayPurchase, *, locale: str) -> None:
	if purchase.ticket_type not in CREDIT_TYPES:
		return
	if purchase.status == "delivered":
		return
	products = []
	basket = purchase.basket_json or {}
	for item in basket.get("items") or []:
		products.append(str(item.get("productCode") or "item"))
	if not products:
		products = ["pos-sale"]
	try:
		client.deliver(
			ticket_type=int(purchase.ticket_type or TYPE_CREDIT),
			body={
				"deliveryDate": int(utc_now().timestamp() * 1000),
				"invoiceNumber": str(purchase.invoice_id or purchase.provider_id),
				"trackingCode": purchase.tracking_code,
				"products": products,
			},
		)
	except DigipayClientError as exc:
		logger.warning("digipay deliver failed provider=%s: %s", purchase.provider_id, exc)
		raise ApiError(
			"DIGIPAY_DELIVER_FAILED",
			_msg(locale, "DIGIPAY_DELIVER_FAILED", "ثبت تحویل در دیجی‌پی ناموفق بود.", "DigiPay delivery notification failed."),
			http_status=502,
		) from exc
	purchase.status = "delivered"
	purchase.delivered_at = utc_now()


def handle_callback(db: Session, business_id: int, payload: Dict[str, Any], *, locale: str = "fa") -> DigipayPurchase:
	provider_id = str(payload.get("providerId") or payload.get("provider_id") or "").strip()
	if not provider_id:
		raise ApiError("DIGIPAY_PROVIDER_ID_REQUIRED", _msg(locale, "DIGIPAY_PROVIDER_ID_REQUIRED", "شناسه خرید ارسال نشده است.", "providerId is required."), http_status=400)
	purchase = (
		db.query(DigipayPurchase)
		.filter(DigipayPurchase.business_id == int(business_id), DigipayPurchase.provider_id == provider_id)
		.first()
	)
	if not purchase:
		raise ApiError("DIGIPAY_PURCHASE_NOT_FOUND", _msg(locale, "DIGIPAY_PURCHASE_NOT_FOUND", "خرید دیجی‌پی یافت نشد.", "DigiPay purchase was not found."), http_status=404)
	if purchase.status in {"verified", "delivered", "settled"}:
		return purchase
	result = str(payload.get("result") or "").upper()
	tracking = str(payload.get("trackingCode") or payload.get("tracking_code") or "")
	ticket_type = payload.get("type") or payload.get("ticket_type") or TYPE_CREDIT
	try:
		ticket_type = int(ticket_type)
	except (TypeError, ValueError):
		ticket_type = TYPE_CREDIT
	if result != "SUCCESS":
		purchase.status = "failed"
		purchase.tracking_code = tracking or purchase.tracking_code
		purchase.ticket_type = ticket_type
		db.commit()
		db.refresh(purchase)
		return purchase
	callback_amount = _callback_amount_rials(payload.get("amount"))
	if callback_amount is not None and _rials(purchase.amount) != callback_amount:
		purchase.status = "failed"
		extra = dict(purchase.extra_info or {})
		extra["amount_mismatch"] = {"expected": _rials(purchase.amount), "got": callback_amount}
		purchase.extra_info = extra
		db.commit()
		raise ApiError(
			"DIGIPAY_AMOUNT_MISMATCH",
			_msg(locale, "DIGIPAY_AMOUNT_MISMATCH", "مبلغ بازگشتی با خرید ثبت‌شده یکسان نیست.", "Callback amount does not match the ticket."),
			http_status=400,
		)
	purchase.status = "paid"
	purchase.tracking_code = tracking
	purchase.ticket_type = ticket_type
	db.flush()
	return verify_purchase(db, business_id, purchase, tracking_code=tracking, ticket_type=ticket_type, locale=locale)


def get_purchase(db: Session, business_id: int, purchase_id: int, *, locale: str = "fa", calendar_type: str = "jalali") -> Dict[str, Any]:
	ensure_digipay_plugin_active(db, business_id, locale=locale)
	row = (
		db.query(DigipayPurchase)
		.filter(DigipayPurchase.business_id == int(business_id), DigipayPurchase.id == int(purchase_id))
		.first()
	)
	if not row:
		raise ApiError("DIGIPAY_PURCHASE_NOT_FOUND", _msg(locale, "DIGIPAY_PURCHASE_NOT_FOUND", "خرید دیجی‌پی یافت نشد.", "DigiPay purchase was not found."), http_status=404)
	settings = ensure_settings_row(db, business_id)
	data = _purchase_dict(row, calendar_type=calendar_type)
	data["person_id"] = settings.person_id
	return data


def list_purchases(
	db: Session,
	business_id: int,
	*,
	locale: str = "fa",
	calendar_type: str = "jalali",
	status: str | None = None,
	date_from: str | None = None,
	date_to: str | None = None,
	limit: int = 50,
	offset: int = 0,
) -> Dict[str, Any]:
	ensure_digipay_plugin_active(db, business_id, locale=locale)
	q = db.query(DigipayPurchase).filter(DigipayPurchase.business_id == int(business_id))
	if status:
		q = q.filter(DigipayPurchase.status == status)
	if date_from:
		q = q.filter(DigipayPurchase.created_at >= datetime.combine(parse_user_date(date_from, calendar_type=calendar_type), datetime.min.time()))
	if date_to:
		q = q.filter(DigipayPurchase.created_at <= datetime.combine(parse_user_date(date_to, calendar_type=calendar_type), datetime.max.time()))
	total = q.count()
	rows = q.order_by(DigipayPurchase.id.desc()).offset(max(offset, 0)).limit(min(max(limit, 1), 200)).all()
	return {"items": [_purchase_dict(r, calendar_type=calendar_type) for r in rows], "total": total}


def record_manual_purchase(
	db: Session,
	business_id: int,
	user_id: int,
	payload: Dict[str, Any],
	*,
	locale: str = "fa",
	calendar_type: str = "jalali",
) -> Dict[str, Any]:
	"""ثبت خرید QR/پوز خارج از UPG؛ فقط سند حسابداری بعدی را آماده می‌کند."""
	ensure_digipay_plugin_active(db, business_id, locale=locale)
	row = ensure_settings_row(db, business_id)
	if not row.person_id:
		row.person_id = ensure_digipay_person(db, business_id, locale=locale).id
	amount = _money(payload.get("amount"))
	if amount <= 0:
		raise ApiError("DIGIPAY_INVALID_AMOUNT", _msg(locale, "DIGIPAY_INVALID_AMOUNT", "مبلغ باید بزرگ‌تر از صفر باشد.", "Amount must be greater than zero."), http_status=400)
	provider_id = str(payload.get("provider_id") or f"manual-{uuid.uuid4().hex[:16]}")
	purchase = DigipayPurchase(
		business_id=int(business_id),
		provider_id=provider_id,
		amount=amount,
		credit_amount=amount,
		cell_number=str(payload.get("cell_number") or "") or None,
		tracking_code=str(payload.get("tracking_code") or "") or None,
		status="delivered",
		source=str(payload.get("source") or "manual"),
		invoice_id=int(payload["invoice_id"]) if payload.get("invoice_id") else None,
		delivered_at=utc_now(),
		verified_at=utc_now(),
		created_by_user_id=int(user_id) if user_id else None,
		extra_info={"channel": payload.get("channel") or "qr"},
	)
	db.add(purchase)
	db.commit()
	db.refresh(purchase)
	data = _purchase_dict(purchase, calendar_type=calendar_type)
	data["person_id"] = row.person_id
	person = db.query(Person).filter(Person.id == int(row.person_id)).first()
	data["person_name"] = person.alias_name if person else DIGIPAY_PERSON_ALIAS_FA
	return data


def deliver_purchase(
	db: Session,
	business_id: int,
	purchase_id: int,
	*,
	locale: str = "fa",
	calendar_type: str = "jalali",
) -> Dict[str, Any]:
	ensure_digipay_plugin_active(db, business_id, locale=locale)
	purchase = (
		db.query(DigipayPurchase)
		.filter(DigipayPurchase.business_id == int(business_id), DigipayPurchase.id == int(purchase_id))
		.first()
	)
	if not purchase:
		raise ApiError("DIGIPAY_PURCHASE_NOT_FOUND", _msg(locale, "DIGIPAY_PURCHASE_NOT_FOUND", "خرید دیجی‌پی یافت نشد.", "DigiPay purchase was not found."), http_status=404)
	if purchase.status not in {"verified", "paid", "delivered"}:
		raise ApiError("DIGIPAY_INVALID_STATUS", _msg(locale, "DIGIPAY_INVALID_STATUS", "وضعیت خرید برای تحویل مناسب نیست.", "Purchase is not ready for delivery."), http_status=400)
	client = _client_from_settings(ensure_settings_row(db, business_id), locale)
	_deliver_internal(client, purchase, locale=locale)
	db.commit()
	db.refresh(purchase)
	return _purchase_dict(purchase, calendar_type=calendar_type)


def refund_purchase(
	db: Session,
	business_id: int,
	purchase_id: int,
	payload: Dict[str, Any],
	*,
	locale: str = "fa",
	calendar_type: str = "jalali",
) -> Dict[str, Any]:
	ensure_digipay_plugin_active(db, business_id, locale=locale)
	purchase = (
		db.query(DigipayPurchase)
		.filter(DigipayPurchase.business_id == int(business_id), DigipayPurchase.id == int(purchase_id))
		.first()
	)
	if not purchase:
		raise ApiError("DIGIPAY_PURCHASE_NOT_FOUND", _msg(locale, "DIGIPAY_PURCHASE_NOT_FOUND", "خرید دیجی‌پی یافت نشد.", "DigiPay purchase was not found."), http_status=404)
	if purchase.source in {"manual", "qr", "pos"} and not purchase.ticket:
		raise ApiError(
			"DIGIPAY_REFUND_IN_PERSON_UNSUPPORTED",
			_msg(locale, "DIGIPAY_REFUND_IN_PERSON_UNSUPPORTED", "عودت خرید حضوری QR/پوز از API پشتیبانی نمی‌شود.", "In-person QR/POS refunds are not supported via the API."),
			http_status=400,
		)
	amount = _money(payload.get("amount") or purchase.amount)
	client = _client_from_settings(ensure_settings_row(db, business_id), locale)
	refund_provider = f"rf{uuid.uuid4().hex[:16]}"
	try:
		data = client.refund(
			ticket_type=int(purchase.ticket_type or TYPE_CREDIT),
			body={
				"providerId": refund_provider,
				"amount": _rials(amount),
				"saleTrackingCode": purchase.tracking_code,
			},
		)
	except DigipayClientError as exc:
		raise ApiError(
			"DIGIPAY_REFUND_FAILED",
			_msg(locale, "DIGIPAY_REFUND_FAILED", "عودت دیجی‌پی ناموفق بود.", "DigiPay refund failed."),
			http_status=502,
			details=getattr(exc, "details", None),
		) from exc
	purchase.status = "refunded"
	extra = dict(purchase.extra_info or {})
	extra["refund"] = data
	purchase.extra_info = extra
	db.commit()
	return {"ok": True, "refund": data, "purchase": _purchase_dict(purchase, calendar_type=calendar_type)}


def attach_purchase_to_invoice(
	db: Session,
	business_id: int,
	purchase_id: int,
	invoice_id: int,
	receipt_document_id: int | None,
	*,
	locale: str = "fa",
) -> Dict[str, Any]:
	ensure_digipay_plugin_active(db, business_id, locale=locale)
	purchase = (
		db.query(DigipayPurchase)
		.filter(DigipayPurchase.business_id == int(business_id), DigipayPurchase.id == int(purchase_id))
		.first()
	)
	if not purchase:
		raise ApiError("DIGIPAY_PURCHASE_NOT_FOUND", _msg(locale, "DIGIPAY_PURCHASE_NOT_FOUND", "خرید دیجی‌پی یافت نشد.", "DigiPay purchase was not found."), http_status=404)
	purchase.invoice_id = int(invoice_id)
	if receipt_document_id:
		purchase.receipt_document_id = int(receipt_document_id)
	db.commit()
	db.refresh(purchase)
	return _purchase_dict(purchase)


def link_purchases_from_invoice_payments(
	db: Session,
	business_id: int,
	invoice_id: int,
	payment_document_ids: List[int],
	payments: List[Dict[str, Any]],
) -> None:
	"""پس از صدور سند دریافت فاکتور، خریدهای دیجی‌پی را به فاکتور وصل می‌کند."""
	doc_iter = iter(payment_document_ids)
	for p in payments:
		amount = _money(p.get("amount"))
		doc_id = next(doc_iter, None) if amount > 0 else None
		extra = p.get("extra_info") if isinstance(p.get("extra_info"), dict) else {}
		provider_id = extra.get("digipay_provider_id") or p.get("digipay_provider_id")
		desc = str(p.get("description") or "")
		if not provider_id and desc.startswith("DIGIPAY:"):
			provider_id = desc.split(":", 1)[-1].strip()
		if not provider_id:
			continue
		purchase = (
			db.query(DigipayPurchase)
			.filter(DigipayPurchase.business_id == int(business_id), DigipayPurchase.provider_id == str(provider_id))
			.first()
		)
		if not purchase:
			continue
		purchase.invoice_id = int(invoice_id)
		if doc_id:
			purchase.receipt_document_id = int(doc_id)


def _settlement_splits(
	gross: Decimal,
	commission_percent: Decimal,
	vat_percent: Decimal,
	*,
	locale: str = "fa",
) -> Dict[str, Decimal]:
	commission = (gross * (commission_percent / Decimal("100"))).quantize(TWOPLACES, rounding=ROUND_HALF_UP)
	vat = (commission * (vat_percent / Decimal("100"))).quantize(TWOPLACES, rounding=ROUND_HALF_UP)
	net = (gross - commission - vat).quantize(TWOPLACES, rounding=ROUND_HALF_UP)
	if net < 0:
		raise ApiError(
			"DIGIPAY_SETTLEMENT_NEGATIVE",
			_msg(locale, "DIGIPAY_SETTLEMENT_NEGATIVE", "مبلغ خالص تسویه منفی است.", "Settlement net amount is negative."),
			http_status=400,
		)
	return {"gross": gross, "commission": commission, "vat": vat, "net": net}


def register_settlement(
	db: Session,
	business_id: int,
	user_id: int,
	payload: Dict[str, Any],
	*,
	locale: str = "fa",
	calendar_type: str = "jalali",
) -> Dict[str, Any]:
	ensure_digipay_plugin_active(db, business_id, locale=locale)
	settings = ensure_settings_row(db, business_id)
	if not settings.person_id:
		raise ApiError("DIGIPAY_PERSON_REQUIRED", _msg(locale, "DIGIPAY_PERSON_REQUIRED", "شخص دیجی‌پی در تنظیمات مشخص نشده است.", "DigiPay person is not configured."), http_status=400)
	bank_id = int(payload.get("bank_account_id") or settings.settlement_bank_account_id or 0)
	bank = db.query(BankAccount).filter(BankAccount.id == bank_id, BankAccount.business_id == int(business_id)).first()
	if not bank:
		raise ApiError("BANK_ACCOUNT_NOT_FOUND", _msg(locale, "BANK_ACCOUNT_NOT_FOUND", "حساب بانکی تسویه یافت نشد.", "Settlement bank account was not found."), http_status=404)
	purchase_ids = [int(x) for x in (payload.get("purchase_ids") or []) if x]
	q = db.query(DigipayPurchase).filter(
		DigipayPurchase.business_id == int(business_id),
		DigipayPurchase.status.in_(["verified", "delivered"]),
		DigipayPurchase.settlement_id.is_(None),
	)
	if purchase_ids:
		q = q.filter(DigipayPurchase.id.in_(purchase_ids))
	purchases = q.order_by(DigipayPurchase.id.asc()).all()
	if not purchases:
		raise ApiError("DIGIPAY_NO_OPEN_PURCHASES", _msg(locale, "DIGIPAY_NO_OPEN_PURCHASES", "خرید تسویه‌نشده‌ای برای ثبت وجود ندارد.", "There are no unsettled DigiPay purchases."), http_status=400)
	gross = sum((p.amount for p in purchases), Decimal("0"))
	if payload.get("gross_amount") is not None:
		gross = _money(payload.get("gross_amount"))
	commission_percent = _money(payload.get("commission_percent") if payload.get("commission_percent") is not None else settings.commission_percent)
	vat_percent = _money(payload.get("vat_on_commission_percent") if payload.get("vat_on_commission_percent") is not None else settings.vat_on_commission_percent)
	if payload.get("commission_amount") is not None or payload.get("vat_amount") is not None or payload.get("net_amount") is not None:
		commission = _money(payload.get("commission_amount") or 0)
		vat = _money(payload.get("vat_amount") or 0)
		net = _money(payload.get("net_amount")) if payload.get("net_amount") is not None else (gross - commission - vat)
		splits = {"gross": gross, "commission": commission, "vat": vat, "net": _money(net)}
		if splits["net"] < 0 or splits["gross"] != splits["net"] + splits["commission"] + splits["vat"]:
			raise ApiError(
				"DIGIPAY_SETTLEMENT_UNBALANCED",
				_msg(locale, "DIGIPAY_SETTLEMENT_UNBALANCED", "مبالغ تسویه با هم تراز نیستند.", "Settlement amounts do not balance."),
				http_status=400,
			)
	else:
		splits = _settlement_splits(gross, commission_percent, vat_percent, locale=locale)
	settlement_date = parse_user_date(payload.get("settlement_date") or utc_now().date().isoformat(), calendar_type=calendar_type)
	from app.services.receipt_payment_service import create_receipt_payment

	fx_lines = []
	if splits["commission"] > 0:
		fx_lines.append({"account_code": "70902", "side": "debit", "amount": float(splits["commission"]), "description": _msg(locale, "DIGIPAY_COMMISSION_LINE", "کارمزد توسعه فروش دیجی‌پی", "DigiPay sales-development commission")})
	if splits["vat"] > 0:
		fx_lines.append({"account_code": "10104", "side": "debit", "amount": float(splits["vat"]), "description": _msg(locale, "DIGIPAY_COMMISSION_VAT_LINE", "مالیات ارزش افزوده کارمزد دیجی‌پی", "VAT on DigiPay commission")})
	rp = create_receipt_payment(
		db=db,
		business_id=int(business_id),
		user_id=int(user_id),
		commit=False,
		data={
			"document_type": "receipt",
			"document_date": settlement_date.isoformat(),
			"currency_id": int(getattr(bank, "currency_id", 0) or 0) or None,
			"description": _msg(locale, "DIGIPAY_SETTLEMENT_DOC", "تسویه دیجی‌پی", "DigiPay settlement"),
			"person_lines": [{
				"person_id": int(settings.person_id),
				"amount": float(splits["gross"]),
				"description": _msg(locale, "DIGIPAY_SETTLEMENT_PERSON", "بستن طلب دیجی‌پی", "Close DigiPay receivable"),
			}],
			"account_lines": [{
				"transaction_type": "bank",
				"bank_id": int(bank.id),
				"amount": float(splits["net"]),
				"description": _msg(locale, "DIGIPAY_SETTLEMENT_BANK", "واریز تسویه دیجی‌پی", "DigiPay settlement deposit"),
			}],
			"fx_adjustment_lines": fx_lines,
			"extra_info": {
				"source": "digipay_settlement",
				"person_is_receivable": True,
				"plugin_code": PLUGIN_CODE,
			},
		},
	)
	doc_id = int(rp["id"]) if isinstance(rp, dict) and rp.get("id") else None
	settlement = DigipaySettlement(
		business_id=int(business_id),
		document_id=doc_id,
		bank_account_id=int(bank.id),
		settlement_date=settlement_date,
		gross_amount=splits["gross"],
		commission_amount=splits["commission"],
		vat_amount=splits["vat"],
		net_amount=splits["net"],
		notes=str(payload.get("notes") or "") or None,
		created_by_user_id=int(user_id) if user_id else None,
	)
	db.add(settlement)
	db.flush()
	for purchase in purchases:
		purchase.settlement_id = settlement.id
		purchase.status = SETTLED_STATUS
		purchase.updated_at = utc_now()
	db.commit()
	db.refresh(settlement)
	return {
		"id": settlement.id,
		"document_id": settlement.document_id,
		"settlement_date": format_user_date(settlement.settlement_date, calendar_type=calendar_type),
		"gross_amount": float(settlement.gross_amount),
		"commission_amount": float(settlement.commission_amount),
		"vat_amount": float(settlement.vat_amount),
		"net_amount": float(settlement.net_amount),
		"purchase_ids": [p.id for p in purchases],
	}


def list_settlements(
	db: Session,
	business_id: int,
	*,
	locale: str = "fa",
	calendar_type: str = "jalali",
	limit: int = 50,
	offset: int = 0,
) -> Dict[str, Any]:
	ensure_digipay_plugin_active(db, business_id, locale=locale)
	q = db.query(DigipaySettlement).filter(DigipaySettlement.business_id == int(business_id))
	total = q.count()
	rows = q.order_by(DigipaySettlement.id.desc()).offset(max(offset, 0)).limit(min(max(limit, 1), 200)).all()
	return {
		"items": [
			{
				"id": r.id,
				"document_id": r.document_id,
				"bank_account_id": r.bank_account_id,
				"settlement_date": format_user_date(r.settlement_date, calendar_type=calendar_type),
				"gross_amount": float(r.gross_amount),
				"commission_amount": float(r.commission_amount),
				"vat_amount": float(r.vat_amount),
				"net_amount": float(r.net_amount),
			}
			for r in rows
		],
		"total": total,
	}


def preview_settlement(
	db: Session,
	business_id: int,
	payload: Dict[str, Any],
	*,
	locale: str = "fa",
) -> Dict[str, Any]:
	ensure_digipay_plugin_active(db, business_id, locale=locale)
	settings = ensure_settings_row(db, business_id)
	purchase_ids = [int(x) for x in (payload.get("purchase_ids") or []) if x]
	q = db.query(DigipayPurchase).filter(
		DigipayPurchase.business_id == int(business_id),
		DigipayPurchase.status.in_(["verified", "delivered"]),
		DigipayPurchase.settlement_id.is_(None),
	)
	if purchase_ids:
		q = q.filter(DigipayPurchase.id.in_(purchase_ids))
	purchases = q.all()
	gross = sum((p.amount for p in purchases), Decimal("0"))
	commission_percent = _money(payload.get("commission_percent") if payload.get("commission_percent") is not None else settings.commission_percent)
	vat_percent = _money(payload.get("vat_on_commission_percent") if payload.get("vat_on_commission_percent") is not None else settings.vat_on_commission_percent)
	splits = _settlement_splits(gross, commission_percent, vat_percent, locale=locale) if purchases else {"gross": Decimal("0"), "commission": Decimal("0"), "vat": Decimal("0"), "net": Decimal("0")}
	return {
		"purchase_count": len(purchases),
		"purchase_ids": [p.id for p in purchases],
		"gross_amount": float(splits["gross"]),
		"commission_amount": float(splits["commission"]),
		"vat_amount": float(splits["vat"]),
		"net_amount": float(splits["net"]),
		"accounts": {
			"person_receivable": "10401",
			"bank": "10203",
			"commission": "70902",
			"input_vat": "10104",
		},
	}
