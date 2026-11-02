"""پرداخت آنلاین از لینک واریز عمومی کسب‌وکار.

پس از تأیید درگاه، سند دریافت استاندارد ثبت می‌شود:
  بدهکار 10204 (نزد پرداخت‌یار) = مبلغ ناخالص
  بستانکار حساب شخص (10401 از مسیر receipt) = مبلغ
  در صورت کارمزد پلتفرم: هزینه کارمزد طبق create_receipt_payment

مانده کیف‌پول SaaS (10205 / available_balance) تغییر نمی‌کند.
مبلغ و ارز سند برابر ارز پایه درگاه/کیف‌پول سامانه است، نه لزوماً ارز پیش‌فرض کسب‌وکار.
"""
from __future__ import annotations

import json
import logging
import secrets
from datetime import datetime
from decimal import Decimal, ROUND_HALF_UP
from typing import Any, Dict, Optional
from uuid import UUID

from sqlalchemy.orm import Session

from adapters.api.v1.schema_models.person import PersonCreateRequest, PersonType
from adapters.db.models.business import Business
from adapters.db.models.business_pay_page import BusinessPayPage, PublicPayPageReceipt
from adapters.db.models.person import Person
from adapters.db.models.wallet import WalletTransaction
from app.core.responses import ApiError
from app.services.business_pay_page_service import (
	GATEWAY_MIN_AMOUNT,
	WALLET_TX_TYPE_PUBLIC_PAY_LINK,
	find_pay_page_by_username,
	gateway_tracking_from_extra,
	parse_pay_amount,
	public_business_contact_rows,
	validate_payer_mobile,
	validate_payer_name,
	validate_payer_note,
)
from app.services.business_service import ensure_wallet_currency_in_business
from app.services.customer_quick_entry_service import (
	get_business_default_phone_region,
	load_quick_customer_mobile_matches,
	normalize_customer_mobile,
)
from app.services.document_share_link_service import _assert_gateway_allowed_for_business
from app.services.payment_service import initiate_payment
from app.services.person_service import create_person
from app.services.quick_sales_service import get_quick_sales_settings
from app.services.receipt_payment_service import create_receipt_payment
from app.services.system_settings_service import (
	get_share_link_invoice_gateway_fee_percent,
	get_wallet_settings,
	resolve_public_app_base_url_for_public_links,
)

logger = logging.getLogger(__name__)


def _parse_extra(tx: WalletTransaction) -> Dict[str, Any]:
	try:
		return json.loads(tx.extra_info or "{}") if tx.extra_info else {}
	except Exception:
		return {}


def _active_page_or_error(db: Session, username: str) -> tuple[BusinessPayPage, Business]:
	page, redirect_to = find_pay_page_by_username(db, username)
	if not page:
		raise ApiError("PAY_PAGE_NOT_FOUND", "صفحه پرداخت یافت نشد", http_status=404)
	if redirect_to and redirect_to != page.username:
		# پرداخت فقط روی نام کاربری فعلی پذیرفته می‌شود
		raise ApiError("PAY_PAGE_MOVED", redirect_to, http_status=409)
	business = db.query(Business).filter(Business.id == int(page.business_id)).first()
	if not business or getattr(business, "deleted_at", None):
		raise ApiError("PAY_PAGE_NOT_FOUND", "صفحه پرداخت یافت نشد", http_status=404)
	if not page.is_enabled or not page.username or not page.gateway_id:
		raise ApiError("PAY_PAGE_DISABLED", "دریافت آنلاین فعلاً غیرفعال است", http_status=403)
	return page, business


def _ensure_anonymous_customer(db: Session, business_id: int) -> Person:
	from sqlalchemy import and_
	from adapters.db.models.quick_sales_settings import QuickSalesSetting
	from app.core.transaction_lock import acquire_transaction_lock
	from app.services.person_service import invalidate_persons_cache

	acquire_transaction_lock(db, f"quick_sales_anonymous_customer:{business_id}")
	settings = get_quick_sales_settings(db, business_id)
	row = (
		db.query(QuickSalesSetting)
		.filter(QuickSalesSetting.business_id == int(business_id))
		.first()
	)
	customer_id = (
		row.default_anonymous_customer_id
		if row is not None
		else settings.get("default_anonymous_customer_id")
	)
	if customer_id:
		customer = db.query(Person).filter(
			and_(
				Person.id == int(customer_id),
				Person.business_id == int(business_id),
			)
		).first()
		if customer:
			return customer

	name_fa = settings.get("anonymous_customer_name") or "مشتری ناشناس"
	created = create_person(
		db,
		int(business_id),
		PersonCreateRequest(alias_name=str(name_fa), person_types=[PersonType.CUSTOMER]),
		commit=False,
	)
	person = db.query(Person).filter(Person.id == int(created["id"])).first()
	if not person:
		raise ApiError("ANONYMOUS_CUSTOMER_FAILED", "ایجاد مشتری ناشناس ناموفق بود", http_status=500)
	if row is None:
		row = QuickSalesSetting(business_id=int(business_id))
		db.add(row)
	row.default_anonymous_customer_id = person.id
	db.flush()
	invalidate_persons_cache(int(business_id), fiscal_year_id=None)
	return person


def resolve_pay_link_person(
	db: Session,
	*,
	page: BusinessPayPage,
	business: Business,
	payer_name: Optional[str],
	payer_mobile: Optional[str],
) -> Person:
	if payer_mobile and page.match_customer_by_mobile:
		region = get_business_default_phone_region(db, int(business.id))
		normalized = normalize_customer_mobile(payer_mobile, default_region=region)
		if normalized:
			matches = load_quick_customer_mobile_matches(
				db, business_id=int(business.id), normalized_mobile=normalized
			)
			if matches:
				person = matches[0]
				if payer_name and not (person.alias_name or "").strip():
					person.alias_name = payer_name
					db.add(person)
					db.flush()
				return person
		if page.create_customer_if_missing:
			alias = payer_name or f"مشتری {payer_mobile}"
			created = create_person(
				db,
				int(business.id),
				PersonCreateRequest(
					alias_name=alias,
					mobile=payer_mobile,
					person_types=[PersonType.CUSTOMER],
				),
				commit=False,
			)
			person = db.query(Person).filter(Person.id == int(created["id"])).first()
			if person:
				return person
			raise ApiError("CUSTOMER_CREATE_FAILED", "ثبت مشتری ناموفق بود", http_status=500)

	if page.use_anonymous_if_no_mobile:
		return _ensure_anonymous_customer(db, int(business.id))

	raise ApiError(
		"CUSTOMER_REQUIRED",
		"برای ثبت این واریز باید موبایل وارد شود یا مشتری ناشناس در تنظیمات فعال باشد",
		http_status=400,
	)


def start_public_pay_page_payment(
	db: Session,
	*,
	username: str,
	amount: Any,
	payer_name: str | None = None,
	payer_mobile: str | None = None,
	payer_note: str | None = None,
) -> Dict[str, Any]:
	page, business = _active_page_or_error(db, username)
	_assert_gateway_allowed_for_business(db, int(page.business_id), int(page.gateway_id))

	amt = parse_pay_amount(amount)
	min_amt = Decimal(str(page.min_amount or GATEWAY_MIN_AMOUNT))
	if min_amt < GATEWAY_MIN_AMOUNT:
		min_amt = GATEWAY_MIN_AMOUNT
	if amt < min_amt:
		raise ApiError(
			"AMOUNT_TOO_SMALL",
			f"حداقل مبلغ پرداخت {min_amt} است",
			http_status=400,
		)
	if page.max_amount is not None:
		max_amt = Decimal(str(page.max_amount))
		if amt > max_amt:
			raise ApiError("AMOUNT_TOO_LARGE", "مبلغ از سقف مجاز بیشتر است", http_status=400)

	name = validate_payer_name(payer_name)
	mobile = validate_payer_mobile(payer_mobile)
	note = validate_payer_note(payer_note)

	wallet = get_wallet_settings(db)
	currency_id = wallet.get("wallet_base_currency_id")
	if not currency_id:
		raise ApiError("WALLET_CURRENCY_NOT_SET", "ارز پایه درگاه تنظیم نشده است", http_status=400)
	ensure_wallet_currency_in_business(db, int(page.business_id))

	fee_percent = Decimal(str(get_share_link_invoice_gateway_fee_percent(db)))
	if fee_percent < 0:
		fee_percent = Decimal(0)
	if fee_percent > Decimal("100"):
		fee_percent = Decimal("100")
	commission = (amt * fee_percent / Decimal("100")).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
	if commission > amt:
		commission = amt

	owner_id = int(getattr(business, "owner_id", 0) or 0)
	desc = "واریز از لینک پرداخت"
	if name:
		desc = f"واریز از لینک پرداخت — {name}"

	extra_info: Dict[str, Any] = {
		"kind": "public_pay_link",
		"username": page.username,
		"gateway_id": int(page.gateway_id),
		"accounting_commission": float(commission),
		"fee_percent_applied": float(fee_percent),
		"created_by_user_id": owner_id,
		"currency_id": int(currency_id),
		"currency_code": wallet.get("wallet_base_currency_code"),
		"payer_name": name,
		"payer_mobile": mobile,
		"payer_note": note,
		"notify_inapp": bool(page.notify_inapp),
		"notify_sms": bool(page.notify_sms),
		"match_customer_by_mobile": bool(page.match_customer_by_mobile),
		"create_customer_if_missing": bool(page.create_customer_if_missing),
		"use_anonymous_if_no_mobile": bool(page.use_anonymous_if_no_mobile),
	}

	tx = WalletTransaction(
		business_id=int(page.business_id),
		type=WALLET_TX_TYPE_PUBLIC_PAY_LINK,
		status="pending",
		amount=float(amt),
		fee_amount=float(commission) if commission > 0 else None,
		description=(desc[:500] if desc else None),
		external_ref=None,
		document_id=None,
		extra_info=json.dumps(extra_info, ensure_ascii=False),
	)
	db.add(tx)
	db.flush()
	token = ensure_public_pay_receipt_token(db, tx, username=str(page.username or ""))
	extra_info["receipt_token"] = token
	tx.extra_info = json.dumps(extra_info, ensure_ascii=False)
	db.flush()

	try:
		init_res = initiate_payment(
			db=db,
			business_id=int(page.business_id),
			tx_id=int(tx.id),
			amount=float(amt),
			gateway_id=int(page.gateway_id),
		)
	except ApiError:
		tx.status = "failed"
		db.flush()
		raise
	except Exception as ex:
		logger.exception("public_pay_page_gateway_init_failed")
		tx.status = "failed"
		db.flush()
		raise ApiError("GATEWAY_INIT_FAILED", "خطا در ایجاد لینک پرداخت", http_status=502) from ex

	db.flush()
	return {
		"transaction_id": int(tx.id),
		"payment_url": init_res.payment_url,
		"amount": float(amt),
		"currency_code": wallet.get("wallet_base_currency_code"),
		"accounting_commission": float(commission),
		"fee_percent": float(fee_percent),
	}


def confirm_public_pay_page_payment(
	db: Session,
	tx: WalletTransaction,
	*,
	success: bool,
	external_ref: str | None = None,
	user_id: int | None = None,
) -> Dict[str, Any]:
	if (tx.type or "") != WALLET_TX_TYPE_PUBLIC_PAY_LINK:
		raise ApiError("INVALID_TX", "نوع تراکنش نامعتبر است", http_status=400)

	if (tx.status or "").lower() in ("succeeded", "failed"):
		tx.external_ref = external_ref or tx.external_ref
		db.flush()
		return {"transaction_id": tx.id, "status": tx.status}

	if not success:
		tx.status = "failed"
		tx.external_ref = external_ref
		db.flush()
		return {"transaction_id": tx.id, "status": tx.status}

	ex = _parse_extra(tx)
	try:
		gateway_id = int(ex.get("gateway_id") or 0)
		currency_id = int(ex.get("currency_id") or 0)
	except Exception:
		tx.status = "failed"
		tx.external_ref = external_ref
		db.flush()
		return {"transaction_id": tx.id, "status": tx.status, "error": "INVALID_TX_METADATA"}

	business = db.query(Business).filter(Business.id == int(tx.business_id)).first()
	page = (
		db.query(BusinessPayPage)
		.filter(BusinessPayPage.business_id == int(tx.business_id))
		.first()
	)
	if not business or not page:
		tx.status = "failed"
		tx.external_ref = external_ref
		db.flush()
		return {"transaction_id": tx.id, "status": tx.status, "error": "PAY_PAGE_MISSING"}

	gross = Decimal(str(tx.amount or 0)).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
	if gross <= 0:
		tx.status = "failed"
		tx.external_ref = external_ref
		db.flush()
		return {"transaction_id": tx.id, "status": tx.status, "error": "INVALID_AMOUNT"}

	if currency_id <= 0:
		wallet = get_wallet_settings(db)
		currency_id = int(wallet.get("wallet_base_currency_id") or 0)
	if currency_id <= 0:
		tx.status = "failed"
		tx.external_ref = external_ref
		db.flush()
		return {"transaction_id": tx.id, "status": tx.status, "error": "CURRENCY_MISSING"}

	ensure_wallet_currency_in_business(db, int(tx.business_id))

	try:
		person = resolve_pay_link_person(
			db,
			page=page,
			business=business,
			payer_name=ex.get("payer_name"),
			payer_mobile=ex.get("payer_mobile"),
		)
	except Exception:
		logger.exception("public_pay_page_person_resolve_failed tx_id=%s", tx.id)
		tx.status = "failed"
		tx.external_ref = external_ref
		db.flush()
		return {"transaction_id": tx.id, "status": tx.status, "error": "PERSON_RESOLVE_FAILED"}

	commission = Decimal(str(ex.get("accounting_commission") or tx.fee_amount or 0))
	if commission < 0:
		commission = Decimal(0)
	if commission > gross:
		commission = gross

	paid_at = datetime.utcnow()
	doc_user_id = user_id if user_id and user_id > 0 else int(ex.get("created_by_user_id") or 0)
	if doc_user_id <= 0:
		doc_user_id = int(getattr(business, "owner_id", 0) or 0)

	note = (ex.get("payer_note") or "").strip()
	payer_name = (ex.get("payer_name") or "").strip()
	desc_parts = ["دریافت آنلاین از لینک واریز"]
	if payer_name:
		desc_parts.append(payer_name)
	if note:
		desc_parts.append(note[:200])
	doc_desc = " — ".join(desc_parts)
	tracking = gateway_tracking_from_extra(ex)

	account_line: Dict[str, Any] = {
		"transaction_type": "wallet",
		"amount": float(gross),
		"transaction_date": paid_at.date().isoformat(),
		"description": doc_desc[:500],
	}
	if commission > 0:
		account_line["commission"] = float(commission)

	rp_data: Dict[str, Any] = {
		"document_type": "receipt",
		"document_date": paid_at.date().isoformat(),
		"currency_id": int(currency_id),
		"description": doc_desc[:500],
		"person_lines": [
			{
				"person_id": int(person.id),
				"amount": float(gross),
				"description": doc_desc[:255],
			}
		],
		"account_lines": [account_line],
		"extra_info": {
			"source": "public_pay_link",
			"wallet_transaction_id": int(tx.id),
			"payment_gateway_id": gateway_id,
			"person_is_receivable": True,
			"payer_name": ex.get("payer_name"),
			"payer_mobile": ex.get("payer_mobile"),
			"payer_note": ex.get("payer_note"),
			"username": ex.get("username"),
			"card_num": tracking.get("card_num"),
			"gateway_ref_id": tracking.get("gateway_ref_id"),
			"factor_id": tracking.get("factor_id"),
			"external_ref": external_ref,
			"provider": tracking.get("provider"),
		},
	}

	rp_doc = create_receipt_payment(
		db=db,
		business_id=int(tx.business_id),
		user_id=int(doc_user_id),
		data=rp_data,
		commit=False,
	)
	receipt_id = int(rp_doc.get("id") or 0)
	if not receipt_id:
		db.rollback()
		raise ApiError("RECEIPT_CREATE_FAILED", "ثبت سند دریافت ناموفق بود", http_status=500)

	ex["person_id"] = int(person.id)
	tx.status = "succeeded"
	tx.document_id = receipt_id
	tx.external_ref = external_ref
	tx.extra_info = json.dumps(ex, ensure_ascii=False)
	db.flush()

	try:
		_notify_owner_after_payment(
			db,
			business=business,
			page=page,
			tx=tx,
			person=person,
			extra=ex,
			paid_at=paid_at,
		)
	except Exception:
		logger.exception("public_pay_page_notify_failed tx_id=%s", tx.id)

	return {
		"transaction_id": tx.id,
		"status": tx.status,
		"receipt_document_id": receipt_id,
		"person_id": int(person.id),
	}


def _notify_owner_after_payment(
	db: Session,
	*,
	business: Business,
	page: BusinessPayPage,
	tx: WalletTransaction,
	person: Person,
	extra: Dict[str, Any],
	paid_at: datetime,
) -> None:
	from app.core.calendar import CalendarConverter
	from app.services.notification_service import NotificationService

	if not bool(page.notify_inapp) and not bool(page.notify_sms):
		return
	owner_id = int(getattr(business, "owner_id", 0) or 0)
	if owner_id <= 0:
		return

	payer_name = extra.get("payer_name") or getattr(person, "alias_name", None) or "پرداخت‌کننده"
	amount = float(tx.amount or 0)
	jalali = CalendarConverter.to_jalali(paid_at) or {}
	gregorian = CalendarConverter.to_gregorian(paid_at) or {}
	date_time = jalali.get("formatted") or gregorian.get("formatted") or paid_at.isoformat()
	amount_fmt = f"{amount:,.0f}"
	message = (
		f"در تاریخ و ساعت {date_time} مبلغ {amount_fmt} توسط {payer_name} "
		f"از لینک واریز به حساب شما دریافت شد."
	)
	channels: list[str] = []
	if page.notify_inapp:
		channels.append("inapp")
	if page.notify_sms:
		channels.append("sms")
	if not channels:
		return
	svc = NotificationService(db)
	svc.send(
		user_id=owner_id,
		event_key="pay_link.received",
		context={
			"subject": "واریز جدید از لینک پرداخت",
			"message": message,
			"amount": amount_fmt,
			"payer_name": payer_name,
			"business_name": business.name,
			"date_time": date_time,
			"username": extra.get("username") or page.username,
		},
		preferred_channels=channels,
		broadcast_mode=True,
	)


def maybe_redirect_public_pay_page_payment_return(
	db: Session,
	*,
	tx_id: int,
	verify_data: Dict[str, Any],
):
	from urllib.parse import quote

	from fastapi.responses import RedirectResponse

	tx = db.query(WalletTransaction).filter(WalletTransaction.id == int(tx_id)).first()
	if not tx or (tx.type or "").strip() != WALLET_TX_TYPE_PUBLIC_PAY_LINK:
		return None
	ex = _parse_extra(tx)
	username = (ex.get("username") or "").strip()
	if not username:
		return None
	base = (resolve_public_app_base_url_for_public_links(db) or "").strip().rstrip("/")
	if not base:
		return None
	token = (ex.get("receipt_token") or "").strip()
	if not token:
		token = ensure_public_pay_receipt_token(db, tx, username=username)
	enc = quote(username, safe="")
	return RedirectResponse(url=f"{base}/u/{enc}/r/{quote(token, safe='')}", status_code=302)


def ensure_public_pay_receipt_token(db: Session, tx: WalletTransaction, *, username: str) -> str:
	existing = (
		db.query(PublicPayPageReceipt)
		.filter(PublicPayPageReceipt.wallet_transaction_id == int(tx.id))
		.first()
	)
	if existing:
		return existing.token
	ex = _parse_extra(tx)
	token = (ex.get("receipt_token") or "").strip() or secrets.token_urlsafe(16)
	row = PublicPayPageReceipt(
		token=token,
		wallet_transaction_id=int(tx.id),
		username=(username or ex.get("username") or "")[:30],
	)
	db.add(row)
	ex["receipt_token"] = token
	tx.extra_info = json.dumps(ex, ensure_ascii=False)
	db.flush()
	return token


def _status_label(status: str) -> str:
	value = (status or "").strip().lower()
	if value in ("succeeded", "success"):
		return "موفق"
	if value in ("failed", "fail"):
		return "ناموفق"
	return "در انتظار تأیید"


def public_pay_receipt_url(db: Session, *, username: str, token: str, request_base: str | None = None) -> str:
	from urllib.parse import quote

	from app.core.payment_response import join_frontend_url

	base = (resolve_public_app_base_url_for_public_links(db) or "").strip().rstrip("/")
	if not base:
		base = (request_base or "").rstrip("/")
	path = f"/u/{quote(username, safe='')}/r/{quote(token, safe='')}"
	return join_frontend_url(base, path)


def qr_png_data_uri(payload: str) -> str:
	import base64
	import io

	import qrcode
	from qrcode.constants import ERROR_CORRECT_M

	buf = io.BytesIO()
	qr = qrcode.QRCode(version=1, error_correction=ERROR_CORRECT_M, box_size=4, border=2)
	qr.add_data(payload)
	qr.make(fit=True)
	img = qr.make_image(fill_color="black", back_color="white")
	img.save(buf, format="PNG")
	return "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode("ascii")


def get_public_pay_receipt(db: Session, username: str, token: str, *, request_base: str | None = None) -> Dict[str, Any]:
	from app.core.calendar import CalendarConverter
	from app.services.business_pay_page_service import get_public_pay_page, normalize_username

	token = (token or "").strip()
	if not token:
		raise ApiError("RECEIPT_NOT_FOUND", "رسید یافت نشد", http_status=404)
	row = db.query(PublicPayPageReceipt).filter(PublicPayPageReceipt.token == token).first()
	if not row:
		raise ApiError("RECEIPT_NOT_FOUND", "رسید یافت نشد", http_status=404)
	tx = db.query(WalletTransaction).filter(WalletTransaction.id == int(row.wallet_transaction_id)).first()
	if not tx or (tx.type or "").strip() != WALLET_TX_TYPE_PUBLIC_PAY_LINK:
		raise ApiError("RECEIPT_NOT_FOUND", "رسید یافت نشد", http_status=404)
	page_payload = get_public_pay_page(db, username)
	canonical = str(page_payload.get("username") or username)
	wanted = normalize_username(username)
	if normalize_username(row.username) not in {wanted, normalize_username(canonical)}:
		raise ApiError("RECEIPT_NOT_FOUND", "رسید یافت نشد", http_status=404)
	ex = _parse_extra(tx)
	when = tx.updated_at or tx.created_at or datetime.utcnow()
	jalali = CalendarConverter.to_jalali(when) or {}
	status = (tx.status or "").strip().lower()
	success = status in ("succeeded", "success")
	failed = status in ("failed", "fail")
	amount = float(tx.amount or 0)
	currency = str(ex.get("currency_code") or page_payload.get("currency_code") or "").strip()
	identity = {
		"business_name": page_payload.get("business_name") or page_payload.get("display_title"),
		"business_type": page_payload.get("business_type"),
		"phone": page_payload.get("phone"),
		"mobile": page_payload.get("mobile"),
		"postal_code": page_payload.get("postal_code"),
		"address": page_payload.get("address"),
		"national_id": page_payload.get("national_id"),
		"economic_id": page_payload.get("economic_id"),
		"registration_number": page_payload.get("registration_number"),
	}
	url = public_pay_receipt_url(db, username=canonical, token=token, request_base=request_base)
	try:
		qr_uri = qr_png_data_uri(url)
	except Exception:
		logger.exception("public_pay_receipt_qr_failed")
		qr_uri = ""
	return {
		"token": token,
		"username": canonical,
		"receipt_url": url,
		"pdf_url": f"{url}/pdf",
		"qr_data_uri": qr_uri,
		"status": status or "pending",
		"status_label": _status_label(status),
		"success": success,
		"failed": failed,
		"amount": amount,
		"amount_formatted": f"{int(amount):,}" if amount == int(amount) else f"{amount:,.2f}",
		"currency_code": currency,
		"currency_title": page_payload.get("currency_title") or currency,
		"external_ref": tx.external_ref or "",
		"transaction_id": int(tx.id),
		"paid_at": jalali.get("formatted") or (when.strftime("%Y/%m/%d %H:%M") if when else ""),
		"payer_name": ex.get("payer_name") or "",
		"payer_mobile": ex.get("payer_mobile") or "",
		"payer_note": ex.get("payer_note") or "",
		"display_title": page_payload.get("display_title"),
		"show_logo": bool(page_payload.get("show_logo")),
		"business_rows": public_business_contact_rows(identity),
		**identity,
	}


def render_public_pay_receipt_pdf(context: Dict[str, Any]) -> bytes:
	from app.core.payment_response import jinja_env
	from app.core.weasyprint_runtime import load_weasyprint

	html = jinja_env.get_template("pdf/public_pay_receipt.html").render(**context)
	runtime = load_weasyprint()
	font_config = runtime.FontConfiguration()
	return runtime.HTML(string=html).write_pdf(font_config=font_config)


def business_logo_file_id_for_pay_page(db: Session, username: str) -> Optional[UUID]:
	page, _redirect = find_pay_page_by_username(db, username)
	if not page or not page.show_logo:
		return None
	business = db.query(Business).filter(Business.id == int(page.business_id)).first()
	if not business:
		return None
	fid = getattr(business, "logo_file_id", None)
	if not fid:
		return None
	try:
		return UUID(str(fid))
	except Exception:
		return None
