"""تنظیمات لینک واریز عمومی کسب‌وکار و یکتایی نام کاربری."""
from __future__ import annotations

import json
import re
from datetime import datetime, timedelta
from decimal import Decimal, ROUND_HALF_UP
from typing import Any, Dict, Optional

from sqlalchemy import or_
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from adapters.db.models.business import Business
from adapters.db.models.business_pay_page import BusinessPayPage, BusinessPayPageUsernameHistory
from adapters.db.models.person import Person
from adapters.db.models.wallet import WalletTransaction
from app.core.responses import ApiError
from app.core.transaction_lock import acquire_transaction_lock
from app.services.document_share_link_service import _assert_gateway_allowed_for_business
from app.services.system_settings_service import (
	get_wallet_settings,
	resolve_public_app_base_url_for_public_links,
)

WALLET_TX_TYPE_PUBLIC_PAY_LINK = "public_pay_link"
USERNAME_RE = re.compile(r"^[a-z0-9](?:[a-z0-9-]{1,28}[a-z0-9])$|^[a-z0-9]$")
USERNAME_MIN_LEN = 3
USERNAME_MAX_LEN = 30
USERNAME_REDIRECT_DAYS = 30
GATEWAY_MIN_AMOUNT = Decimal("50000")
NAME_MAX_LEN = 30
NOTE_MAX_LEN = 1000
# حروف فارسی/عربی/لاتین + فاصله + نیم‌فاصله
PAYER_NAME_RE = re.compile(
	r"^[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF\uFB50-\uFDFF\uFE70-\uFEFFa-zA-Z\s\u200c]{1,30}$"
)

RESERVED_USERNAMES = frozenset(
	{
		"u",
		"i",
		"p",
		"api",
		"app",
		"admin",
		"login",
		"logout",
		"public",
		"business",
		"wallet",
		"pay",
		"help",
		"static",
		"assets",
		"www",
		"hesabix",
		"support",
		"status",
		"cdn",
		"docs",
		"auth",
		"user",
		"users",
		"profile",
		"settings",
		"invoice",
		"invoices",
		"person",
		"persons",
		"share",
		"storage",
		"warranty",
		"health",
		"ws",
		"webhook",
		"callback",
		"root",
		"null",
		"undefined",
		"me",
		"new",
		"edit",
		"system",
		"owner",
		"account",
		"accounts",
		"dashboard",
		"mobile-launcher",
		"mobile_launcher",
	}
)


def normalize_username(raw: str | None) -> str:
	return (raw or "").strip().lower()


def validate_username_format(username: str) -> str:
	value = normalize_username(username)
	if len(value) < USERNAME_MIN_LEN or len(value) > USERNAME_MAX_LEN:
		raise ApiError(
			"INVALID_USERNAME",
			f"نام کاربری باید بین {USERNAME_MIN_LEN} و {USERNAME_MAX_LEN} کاراکتر باشد",
			http_status=400,
		)
	if "--" in value:
		raise ApiError("INVALID_USERNAME", "نام کاربری نمی‌تواند دو خط تیره پشت‌سرهم داشته باشد", http_status=400)
	if not USERNAME_RE.match(value):
		raise ApiError(
			"INVALID_USERNAME",
			"نام کاربری فقط می‌تواند حروف کوچک انگلیسی، رقم و خط تیره باشد و نباید با خط تیره شروع یا تمام شود",
			http_status=400,
		)
	if value in RESERVED_USERNAMES:
		raise ApiError("USERNAME_RESERVED", "این نام کاربری رزرو شده است", http_status=400)
	return value


def validate_payer_name(raw: str | None) -> Optional[str]:
	if raw is None:
		return None
	cleaned = " ".join(str(raw).replace("\u200c", " ").split())
	if not cleaned:
		return None
	if len(cleaned) > NAME_MAX_LEN:
		raise ApiError("INVALID_PAYER_NAME", f"نام حداکثر {NAME_MAX_LEN} کاراکتر است", http_status=400)
	if not PAYER_NAME_RE.match(cleaned):
		raise ApiError(
			"INVALID_PAYER_NAME",
			"نام فقط می‌تواند حروف فارسی، عربی یا انگلیسی باشد",
			http_status=400,
		)
	return cleaned


def validate_payer_mobile(raw: str | None) -> Optional[str]:
	if raw is None:
		return None
	digits = re.sub(r"[^\d۰-۹٠-٩]", "", str(raw))
	trans = str.maketrans("۰۱۲۳۴۵۶۷۸۹٠١٢٣٤٥٦٧٨٩", "01234567890123456789")
	digits = digits.translate(trans)
	if not digits:
		return None
	if len(digits) != 11 or not digits.startswith("09"):
		raise ApiError(
			"INVALID_MOBILE",
			"شماره موبایل باید ۱۱ رقم و با ۰۹ شروع شود",
			http_status=400,
		)
	return digits


def validate_payer_note(raw: str | None) -> Optional[str]:
	if raw is None:
		return None
	note = str(raw).strip()
	if not note:
		return None
	if len(note) > NOTE_MAX_LEN:
		raise ApiError("INVALID_NOTE", f"توضیح حداکثر {NOTE_MAX_LEN} کاراکتر است", http_status=400)
	return note


def parse_pay_amount(raw: Any) -> Decimal:
	if raw is None or raw == "":
		raise ApiError("INVALID_AMOUNT", "مبلغ الزامی است", http_status=400)
	text = str(raw).strip().replace(",", "").replace("٬", "").replace("،", "")
	trans = str.maketrans("۰۱۲۳۴۵۶۷۸۹٠١٢٣٤٥٦٧٨٩", "01234567890123456789")
	text = text.translate(trans)
	try:
		amt = Decimal(text)
	except Exception as exc:
		raise ApiError("INVALID_AMOUNT", "مبلغ نامعتبر است", http_status=400) from exc
	if amt <= 0:
		raise ApiError("INVALID_AMOUNT", "مبلغ باید بزرگتر از صفر باشد", http_status=400)
	return amt.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)


def _get_or_create_row(db: Session, business_id: int) -> BusinessPayPage:
	row = (
		db.query(BusinessPayPage)
		.filter(BusinessPayPage.business_id == int(business_id))
		.first()
	)
	if row:
		return row
	row = BusinessPayPage(business_id=int(business_id), min_amount=float(GATEWAY_MIN_AMOUNT))
	db.add(row)
	db.flush()
	return row


def _username_taken(
	db: Session,
	username: str,
	*,
	exclude_business_id: int | None = None,
) -> bool:
	q = db.query(BusinessPayPage).filter(BusinessPayPage.username == username)
	if exclude_business_id is not None:
		q = q.filter(BusinessPayPage.business_id != int(exclude_business_id))
	if q.first():
		return True
	now = datetime.utcnow()
	hq = db.query(BusinessPayPageUsernameHistory).filter(
		BusinessPayPageUsernameHistory.username == username,
		BusinessPayPageUsernameHistory.expires_at > now,
	)
	if exclude_business_id is not None:
		hq = hq.filter(BusinessPayPageUsernameHistory.business_id != int(exclude_business_id))
	return hq.first() is not None


def check_username_availability(
	db: Session,
	*,
	business_id: int,
	username: str,
) -> Dict[str, Any]:
	try:
		value = validate_username_format(username)
	except ApiError as exc:
		return {
			"username": normalize_username(username),
			"available": False,
			"reason": exc.code,
			"message": getattr(exc, "message", None) or str(exc),
		}
	taken = _username_taken(db, value, exclude_business_id=int(business_id))
	if taken:
		return {
			"username": value,
			"available": False,
			"reason": "USERNAME_TAKEN",
			"message": "این نام کاربری قبلاً انتخاب شده است",
		}
	return {"username": value, "available": True, "reason": None, "message": None}


def _serialize(
	db: Session,
	row: BusinessPayPage,
	business: Business,
) -> Dict[str, Any]:
	wallet = get_wallet_settings(db)
	base = (resolve_public_app_base_url_for_public_links(db) or "").strip().rstrip("/")
	public_path = f"/u/{row.username}" if row.username else None
	public_url = f"{base}{public_path}" if base and public_path else public_path
	min_amt = Decimal(str(row.min_amount or GATEWAY_MIN_AMOUNT))
	if min_amt < GATEWAY_MIN_AMOUNT:
		min_amt = GATEWAY_MIN_AMOUNT
	max_amt = Decimal(str(row.max_amount)) if row.max_amount is not None else None
	return {
		"business_id": int(row.business_id),
		"username": row.username,
		"is_enabled": bool(row.is_enabled),
		"display_title": row.display_title or business.name,
		"business_name": business.name,
		"show_logo": bool(row.show_logo),
		"has_logo": bool(getattr(business, "logo_file_id", None)),
		"intro_text": row.intro_text,
		"gateway_id": int(row.gateway_id) if row.gateway_id else None,
		"min_amount": float(min_amt),
		"max_amount": float(max_amt) if max_amt is not None else None,
		"notify_inapp": bool(row.notify_inapp),
		"notify_sms": bool(row.notify_sms),
		"match_customer_by_mobile": bool(row.match_customer_by_mobile),
		"create_customer_if_missing": bool(row.create_customer_if_missing),
		"use_anonymous_if_no_mobile": bool(row.use_anonymous_if_no_mobile),
		"public_path": public_path,
		"public_url": public_url,
		"currency_id": wallet.get("wallet_base_currency_id"),
		"currency_code": wallet.get("wallet_base_currency_code"),
		"currency_title": wallet.get("wallet_base_currency_title"),
		"currency_symbol": wallet.get("wallet_base_currency_symbol"),
		"gateway_min_amount": float(GATEWAY_MIN_AMOUNT),
	}


def get_pay_page_settings(db: Session, business_id: int) -> Dict[str, Any]:
	business = db.query(Business).filter(Business.id == int(business_id)).first()
	if not business:
		raise ApiError("BUSINESS_NOT_FOUND", "کسب‌وکار یافت نشد", http_status=404)
	row = _get_or_create_row(db, business_id)
	db.flush()
	return _serialize(db, row, business)


def update_pay_page_settings(
	db: Session,
	business_id: int,
	payload: Dict[str, Any],
) -> Dict[str, Any]:
	business = db.query(Business).filter(Business.id == int(business_id)).first()
	if not business:
		raise ApiError("BUSINESS_NOT_FOUND", "کسب‌وکار یافت نشد", http_status=404)

	acquire_transaction_lock(db, f"business_pay_page:{int(business_id)}")
	row = _get_or_create_row(db, business_id)
	body = payload or {}

	if "username" in body:
		raw_username = body.get("username")
		if raw_username is not None and str(raw_username).strip():
			new_username = validate_username_format(str(raw_username))
			if new_username != (row.username or ""):
				if _username_taken(db, new_username, exclude_business_id=int(business_id)):
					raise ApiError("USERNAME_TAKEN", "این نام کاربری قبلاً انتخاب شده است", http_status=409)
				if row.username:
					db.add(
						BusinessPayPageUsernameHistory(
							business_id=int(business_id),
							username=row.username,
							expires_at=datetime.utcnow() + timedelta(days=USERNAME_REDIRECT_DAYS),
						)
					)
				row.username = new_username

	if "display_title" in body:
		title = (str(body.get("display_title") or "")).strip()
		row.display_title = title[:120] if title else None
	if "show_logo" in body:
		row.show_logo = bool(body.get("show_logo"))
	if "intro_text" in body:
		intro = str(body.get("intro_text") or "").strip()
		if len(intro) > 500:
			raise ApiError("INVALID_INTRO", "متن راهنما حداکثر ۵۰۰ کاراکتر است", http_status=400)
		row.intro_text = intro or None
	if "gateway_id" in body:
		gw_val = body.get("gateway_id")
		if gw_val in (None, "", 0, "0"):
			row.gateway_id = None
		else:
			try:
				row.gateway_id = int(gw_val)
			except Exception as exc:
				raise ApiError("INVALID_GATEWAY_ID", "شناسه درگاه نامعتبر است", http_status=400) from exc
			_assert_gateway_allowed_for_business(db, int(business_id), int(row.gateway_id))
	if "min_amount" in body and body.get("min_amount") is not None:
		min_amt = parse_pay_amount(body.get("min_amount"))
		if min_amt < GATEWAY_MIN_AMOUNT:
			raise ApiError(
				"AMOUNT_TOO_SMALL",
				"حداقل مبلغ نمی‌تواند از حداقل درگاه کمتر باشد",
				http_status=400,
			)
		row.min_amount = float(min_amt)
	if "max_amount" in body:
		if body.get("max_amount") in (None, "", 0, "0"):
			row.max_amount = None
		else:
			max_amt = parse_pay_amount(body.get("max_amount"))
			row.max_amount = float(max_amt)
	if "notify_inapp" in body:
		row.notify_inapp = bool(body.get("notify_inapp"))
	if "notify_sms" in body:
		row.notify_sms = bool(body.get("notify_sms"))
	if "match_customer_by_mobile" in body:
		row.match_customer_by_mobile = bool(body.get("match_customer_by_mobile"))
	if "create_customer_if_missing" in body:
		row.create_customer_if_missing = bool(body.get("create_customer_if_missing"))
	if "use_anonymous_if_no_mobile" in body:
		row.use_anonymous_if_no_mobile = bool(body.get("use_anonymous_if_no_mobile"))

	min_now = Decimal(str(row.min_amount or GATEWAY_MIN_AMOUNT))
	if row.max_amount is not None and Decimal(str(row.max_amount)) < min_now:
		raise ApiError("INVALID_AMOUNT_RANGE", "سقف مبلغ نمی‌تواند از کف مبلغ کمتر باشد", http_status=400)

	want_enabled = bool(body.get("is_enabled")) if "is_enabled" in body else bool(row.is_enabled)
	if want_enabled:
		if not row.username:
			raise ApiError("USERNAME_REQUIRED", "برای فعال‌سازی، نام کاربری الزامی است", http_status=400)
		if not row.gateway_id:
			raise ApiError("GATEWAY_NOT_CONFIGURED", "برای فعال‌سازی، انتخاب درگاه الزامی است", http_status=400)
		_assert_gateway_allowed_for_business(db, int(business_id), int(row.gateway_id))
		if not bool(row.notify_inapp) and not bool(row.notify_sms):
			raise ApiError(
				"NOTIFY_REQUIRED",
				"حداقل یکی از نوتیفیکیشن پنل یا پیامک باید فعال باشد",
				http_status=400,
			)
	if "is_enabled" in body:
		row.is_enabled = want_enabled

	row.updated_at = datetime.utcnow()
	try:
		db.commit()
	except IntegrityError as exc:
		db.rollback()
		raise ApiError("USERNAME_TAKEN", "این نام کاربری قبلاً انتخاب شده است", http_status=409) from exc
	db.refresh(row)
	return _serialize(db, row, business)


def find_pay_page_by_username(
	db: Session,
	username: str,
) -> tuple[BusinessPayPage | None, str | None]:
	"""
	Returns (page, canonical_username_if_redirect).
	If the requested name is an unexpired former username, page is the current row
	and the second value is the live username.
	"""
	value = normalize_username(username)
	if not value:
		return None, None
	page = db.query(BusinessPayPage).filter(BusinessPayPage.username == value).first()
	if page:
		return page, None
	now = datetime.utcnow()
	hist = (
		db.query(BusinessPayPageUsernameHistory)
		.filter(
			BusinessPayPageUsernameHistory.username == value,
			BusinessPayPageUsernameHistory.expires_at > now,
		)
		.order_by(BusinessPayPageUsernameHistory.id.desc())
		.first()
	)
	if not hist:
		return None, None
	page = (
		db.query(BusinessPayPage)
		.filter(BusinessPayPage.business_id == int(hist.business_id))
		.first()
	)
	if not page or not page.username:
		return None, None
	return page, page.username


def get_public_pay_page(db: Session, username: str) -> Dict[str, Any]:
	page, redirect_to = find_pay_page_by_username(db, username)
	if not page:
		raise ApiError("PAY_PAGE_NOT_FOUND", "صفحه پرداخت یافت نشد", http_status=404)
	business = db.query(Business).filter(Business.id == int(page.business_id)).first()
	if not business or getattr(business, "deleted_at", None):
		raise ApiError("PAY_PAGE_NOT_FOUND", "صفحه پرداخت یافت نشد", http_status=404)
	wallet = get_wallet_settings(db)
	title = page.display_title or business.name
	min_amt = Decimal(str(page.min_amount or GATEWAY_MIN_AMOUNT))
	if min_amt < GATEWAY_MIN_AMOUNT:
		min_amt = GATEWAY_MIN_AMOUNT
	max_amt = Decimal(str(page.max_amount)) if page.max_amount is not None else None
	identity = public_business_identity(business)
	return {
		"username": page.username,
		"redirect_to": redirect_to,
		"is_enabled": bool(page.is_enabled) and bool(page.username) and bool(page.gateway_id),
		"display_title": title,
		"business_name": business.name,
		"show_logo": bool(page.show_logo) and bool(getattr(business, "logo_file_id", None)),
		"intro_text": page.intro_text,
		"min_amount": float(min_amt),
		"max_amount": float(max_amt) if max_amt is not None else None,
		"currency_id": wallet.get("wallet_base_currency_id"),
		"currency_code": wallet.get("wallet_base_currency_code"),
		"currency_title": wallet.get("wallet_base_currency_title"),
		"currency_symbol": wallet.get("wallet_base_currency_symbol"),
		**identity,
	}


def _clean_public_text(value: Any) -> str | None:
	text = str(value).strip() if value is not None else ""
	return text or None


def public_business_identity(business: Business) -> Dict[str, Any]:
	"""فیلدهای عمومی کسب‌وکار برای نمایش در صفحه واریز (فقط اگر ثبت شده باشند)."""
	kind = getattr(business, "business_type", None)
	kind_label = getattr(kind, "value", None) or (str(kind) if kind else None)
	province = _clean_public_text(getattr(business, "province", None))
	city = _clean_public_text(getattr(business, "city", None))
	address = _clean_public_text(getattr(business, "address", None))
	location_parts = [p for p in (province, city, address) if p]
	return {
		"business_type": _clean_public_text(kind_label),
		"phone": _clean_public_text(getattr(business, "phone", None)),
		"mobile": _clean_public_text(getattr(business, "mobile", None)),
		"postal_code": _clean_public_text(getattr(business, "postal_code", None)),
		"address": "، ".join(location_parts) if location_parts else None,
		"national_id": _clean_public_text(getattr(business, "national_id", None)),
		"economic_id": _clean_public_text(getattr(business, "economic_id", None)),
		"registration_number": _clean_public_text(getattr(business, "registration_number", None)),
	}


def public_business_contact_rows(identity: Dict[str, Any]) -> list[Dict[str, str]]:
	labels = (
		("business_name", "نام کسب‌وکار"),
		("business_type", "نوع"),
		("phone", "تلفن"),
		("mobile", "موبایل"),
		("address", "نشانی"),
		("postal_code", "کد پستی"),
		("national_id", "شناسه ملی"),
		("economic_id", "کد اقتصادی"),
		("registration_number", "شماره ثبت"),
	)
	rows: list[Dict[str, str]] = []
	for key, label in labels:
		value = _clean_public_text(identity.get(key))
		if value:
			rows.append({"label": label, "value": value})
	return rows


def gateway_tracking_from_extra(extra: Dict[str, Any] | None) -> Dict[str, Any]:
	"""شماره کارت و پیگیری‌های درگاه را از extra_info تراکنش واریز استخراج می‌کند."""
	ex = extra if isinstance(extra, dict) else {}
	verify = ex.get("gateway_verify") if isinstance(ex.get("gateway_verify"), dict) else {}

	def _first(*values: Any) -> str | None:
		for value in values:
			if value is None:
				continue
			text = str(value).strip()
			if text:
				return text
		return None

	card_num = _first(
		ex.get("card_num"),
		ex.get("card_pan"),
		ex.get("parsian_card"),
		ex.get("cardNum"),
		verify.get("card_num"),
		verify.get("card_pan"),
		verify.get("cardNum"),
	)
	gateway_ref_id = _first(
		ex.get("gateway_ref_id"),
		ex.get("parsian_rrn"),
		ex.get("ref_id"),
		verify.get("ref_id"),
		verify.get("rrn"),
		verify.get("gateway_ref_id"),
	)
	factor_id = _first(ex.get("factor_id"), verify.get("factor_id"), verify.get("factorId"))
	card_hash = _first(ex.get("card_hash"), verify.get("card_hash"))
	return {
		"card_num": card_num,
		"gateway_ref_id": gateway_ref_id,
		"factor_id": factor_id,
		"card_hash": card_hash,
		"receipt_token": _first(ex.get("receipt_token")),
		"provider": _first(ex.get("provider")),
		"gateway_verify": verify or None,
	}


def list_pay_page_payments(
	db: Session,
	business_id: int,
	*,
	take: int = 20,
	skip: int = 0,
	from_date: datetime | None = None,
	to_date: datetime | None = None,
	search: str | None = None,
) -> Dict[str, Any]:
	q = db.query(WalletTransaction).filter(
		WalletTransaction.business_id == int(business_id),
		WalletTransaction.type == WALLET_TX_TYPE_PUBLIC_PAY_LINK,
	)
	if from_date is not None:
		q = q.filter(WalletTransaction.created_at >= from_date)
	if to_date is not None:
		q = q.filter(WalletTransaction.created_at <= to_date)
	items_all = q.order_by(WalletTransaction.id.desc()).all()
	needle = (search or "").strip()
	rows: list[Dict[str, Any]] = []
	for tx in items_all:
		try:
			extra = json.loads(tx.extra_info or "{}") if tx.extra_info else {}
		except Exception:
			extra = {}
		payer_name = extra.get("payer_name")
		payer_mobile = extra.get("payer_mobile")
		note = extra.get("payer_note")
		tracking = gateway_tracking_from_extra(extra)
		if needle:
			blob = " ".join(
				str(x or "")
				for x in (
					payer_name,
					payer_mobile,
					note,
					tx.description,
					tx.external_ref,
					tracking.get("card_num"),
					tracking.get("gateway_ref_id"),
					tracking.get("factor_id"),
					tracking.get("receipt_token"),
					extra.get("parsian_card"),
					extra.get("parsian_rrn"),
				)
			)
			if needle not in blob:
				continue
		person_id = extra.get("person_id")
		person_label = None
		if person_id:
			person = db.query(Person).filter(Person.id == int(person_id)).first()
			if person:
				person_label = person.alias_name
		rows.append(
			{
				"id": tx.id,
				"type": tx.type,
				"status": tx.status,
				"amount": float(tx.amount or 0),
				"fee_amount": float(tx.fee_amount or 0) if tx.fee_amount is not None else None,
				"description": tx.description,
				"external_ref": tx.external_ref,
				"document_id": tx.document_id,
				"created_at": tx.created_at,
				"updated_at": tx.updated_at,
				"payer_name": payer_name,
				"payer_mobile": payer_mobile,
				"payer_note": note,
				"person_id": int(person_id) if person_id else None,
				"person_name": person_label,
				"currency_id": extra.get("currency_id"),
				"currency_code": extra.get("currency_code"),
				"card_num": tracking.get("card_num"),
				"gateway_ref_id": tracking.get("gateway_ref_id"),
				"factor_id": tracking.get("factor_id"),
				"card_hash": tracking.get("card_hash"),
				"receipt_token": tracking.get("receipt_token"),
				"provider": tracking.get("provider"),
				"gateway_verify": tracking.get("gateway_verify"),
			}
		)
	total = len(rows)
	take = max(1, min(200, int(take)))
	skip = max(0, int(skip))
	page_rows = rows[skip : skip + take]
	return {
		"items": page_rows,
		"total": total,
		"page": (skip // take) + 1,
		"limit": take,
		"total_pages": (total + take - 1) // take if take else 1,
	}
