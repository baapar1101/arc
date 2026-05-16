from __future__ import annotations

import hashlib
import logging
import secrets
import string
from datetime import datetime, timedelta
from typing import Any, Dict, Optional

from sqlalchemy import and_, func, or_
from sqlalchemy.orm import Session

from adapters.db.models.business import Business
from adapters.db.models.currency import Currency
from adapters.db.models.document import Document
from adapters.db.models.document_line import DocumentLine
from adapters.db.models.person import Person
from adapters.db.models.person_share_link import PersonShareLink
from app.core.responses import ApiError
from app.core.settings import get_settings
from app.services.invoice_service import SUPPORTED_INVOICE_TYPES, invoice_document_to_dict
from app.services.person_service import calculate_person_balance
from app.services.system_settings_service import resolve_share_url_http_origin


logger = logging.getLogger(__name__)

BASE62_ALPHABET = "23456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
DEFAULT_OPTIONS: Dict[str, Any] = {
    "include_ledger": True,
    "include_invoices": True,
    "documents_limit": 50,
}
MIN_DOCUMENT_LIMIT = 10
MAX_DOCUMENT_LIMIT = 200
DEFAULT_CODE_LENGTH = 9

DOCUMENT_TYPE_TITLES = {
    "invoice_sales": "فاکتور فروش",
    "invoice_sales_return": "برگشت از فروش",
    "invoice_purchase": "فاکتور خرید",
    "invoice_purchase_return": "برگشت از خرید",
    "invoice_direct_consumption": "مصرف مستقیم",
    "invoice_production": "تولید",
    "invoice_waste": "ضایعات",
    "receipt": "دریافت",
    "payment": "پرداخت",
    "expense": "هزینه",
    "income": "درآمد",
    "manual": "سند دستی",
    "transfer": "انتقال",
}


def _settings():
    return get_settings()


def _hash_code(code: str) -> str:
    secret = _settings().share_link_secret
    payload = f"{secret}:{code}".encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def _generate_code(db: Session) -> str:
    length = max(6, min(_settings().share_link_code_length or DEFAULT_CODE_LENGTH, 16))
    for _ in range(10):
        candidate = "".join(secrets.choice(BASE62_ALPHABET) for _ in range(length))
        exists = (
            db.query(PersonShareLink)
            .filter(PersonShareLink.code == candidate)
            .first()
        )
        if not exists:
            return candidate
    # fallback to timestamp code
    return f"{int(datetime.utcnow().timestamp())}{secrets.randbelow(9999):04d}"[-length:]


def _normalize_bool(value: Any, default: bool) -> bool:
    if value is None:
        return default
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return bool(value)
    s = str(value).strip().lower()
    if s in {"1", "true", "on", "yes", "y"}:
        return True
    if s in {"0", "false", "off", "no", "n"}:
        return False
    return default


def _normalize_options(raw: Optional[Dict[str, Any]]) -> Dict[str, Any]:
    options = dict(DEFAULT_OPTIONS)
    if isinstance(raw, dict):
        options.update({k: raw.get(k) for k in raw.keys()})

    limit = options.get("documents_limit", DEFAULT_OPTIONS["documents_limit"])
    try:
        limit = int(limit)
    except Exception:
        limit = DEFAULT_OPTIONS["documents_limit"]
    limit = max(MIN_DOCUMENT_LIMIT, min(MAX_DOCUMENT_LIMIT, limit))

    options["documents_limit"] = limit
    options["include_ledger"] = _normalize_bool(
        options.get("include_ledger"), DEFAULT_OPTIONS["include_ledger"]
    )
    options["include_invoices"] = _normalize_bool(
        options.get("include_invoices"), DEFAULT_OPTIONS["include_invoices"]
    )
    return options


def _document_type_label(doc_type: Optional[str]) -> str:
    if not doc_type:
        return "سند"
    return DOCUMENT_TYPE_TITLES.get(doc_type, doc_type.replace("_", " "))


def _safe_float(value: Any, default: float = 0.0) -> float:
    if value is None:
        return default
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def _public_invoice_financials_from_extra_info(extra_info: Any) -> Dict[str, float]:
    """
    مبالغ نمایشی فاکتور: ساختار استاندارد در extra_info.totals
    (gross, discount, tax, net)؛ در غیر این صورت کلیدهای قدیمی ریشه extra_info.
    """
    if not isinstance(extra_info, dict):
        extra_info = {}
    totals = extra_info.get("totals")
    if isinstance(totals, dict):
        gross = _safe_float(totals.get("gross"))
        discount = _safe_float(totals.get("discount"))
        tax = _safe_float(totals.get("tax"))
        net = _safe_float(totals.get("net"))
        if not net and (gross or discount):
            net = gross - discount
        total_final = net + tax
        return {
            "subtotal": gross,
            "discount_amount": discount,
            "tax_amount": tax,
            "total": total_final,
        }
    tax_amount = _safe_float(extra_info.get("tax_amount"))
    discount_amount = _safe_float(extra_info.get("discount_amount"))
    subtotal = _safe_float(extra_info.get("subtotal"))
    if subtotal or discount_amount or tax_amount:
        total = subtotal - discount_amount + tax_amount
        return {
            "subtotal": subtotal,
            "discount_amount": discount_amount,
            "tax_amount": tax_amount,
            "total": total,
        }
    return {
        "subtotal": 0.0,
        "discount_amount": 0.0,
        "tax_amount": 0.0,
        "total": 0.0,
    }


def get_active_share_link_for_person(
    db: Session, business_id: int, person_id: int
) -> Optional[PersonShareLink]:
    now = datetime.utcnow()
    return (
        db.query(PersonShareLink)
        .filter(
            PersonShareLink.business_id == business_id,
            PersonShareLink.person_id == person_id,
            PersonShareLink.revoked_at.is_(None),
            or_(
                PersonShareLink.expires_at.is_(None),
                PersonShareLink.expires_at > now,
            ),
            or_(
                PersonShareLink.max_view_count.is_(None),
                PersonShareLink.view_count < PersonShareLink.max_view_count,
            ),
        )
        .order_by(PersonShareLink.created_at.desc())
        .first()
    )


def build_person_share_p_url(
    code: str,
    request_base_url: Optional[str] = None,
    db: Optional[Session] = None,
) -> str:
    base = resolve_share_url_http_origin(db, request_base_url)
    if base:
        return f"{base}/p/{code}"
    return f"/p/{code}"


def serialize_share_link(
    link: Optional[PersonShareLink],
    request_base_url: Optional[str] = None,
    db: Optional[Session] = None,
) -> Optional[Dict[str, Any]]:
    if not link:
        return None
    public_url = build_person_share_p_url(
        link.code, request_base_url=request_base_url, db=db
    )
    options = _normalize_options(link.options or {})
    now = datetime.utcnow()
    expires_in = None
    if link.expires_at:
        expires_in = (link.expires_at - now).total_seconds()
    remaining_hours = (
        None if expires_in is None else round(max(expires_in, 0) / 3600, 2)
    )
    status = "فعال"
    if link.is_revoked:
        status = "لغو شده"
    elif link.is_expired:
        status = "منقضی"
    elif link.is_view_limited:
        status = "به سقف بازدید رسیده"

    return {
        "id": link.id,
        "business_id": link.business_id,
        "person_id": link.person_id,
        "code": link.code,
        "short_url": public_url,
        "created_at": link.created_at.isoformat(),
        "expires_at": link.expires_at.isoformat() if link.expires_at else None,
        "revoked_at": link.revoked_at.isoformat() if link.revoked_at else None,
        "last_view_at": link.last_view_at.isoformat() if link.last_view_at else None,
        "view_count": link.view_count,
        "max_view_count": link.max_view_count,
        "is_active": link.is_active,
        "is_expired": link.is_expired,
        "status": status,
        "remaining_hours": remaining_hours,
        "options": options,
    }


def create_share_link(
    db: Session,
    *,
    business_id: int,
    person_id: int,
    user_id: int,
    expires_in_hours: Optional[int],
    max_view_count: Optional[int],
    options: Optional[Dict[str, Any]],
    replace_existing: bool = True,
) -> PersonShareLink:
    person = db.query(Person).filter(Person.id == person_id).first()
    if not person or person.business_id != business_id:
        raise ApiError(
            "PERSON_NOT_FOUND",
            "شخص یافت نشد یا به این کسب‌وکار تعلق ندارد",
            http_status=404,
        )

    normalized_options = _normalize_options(options or {})

    ttl_hours = expires_in_hours or _settings().share_link_default_ttl_hours
    max_allowed_ttl = _settings().share_link_max_ttl_hours or (24 * 30)
    if ttl_hours:
        ttl_hours = max(1, min(ttl_hours, max_allowed_ttl))
    expires_at = (
        datetime.utcnow() + timedelta(hours=ttl_hours) if ttl_hours else None
    )

    normalized_max_view = None
    if max_view_count is not None:
        try:
            normalized_max_view = max(1, min(int(max_view_count), 1000))
        except Exception:
            normalized_max_view = None

    try:
        if replace_existing:
            existing = get_active_share_link_for_person(db, business_id, person_id)
            if existing:
                existing.revoked_at = datetime.utcnow()
                existing.revoked_by_user_id = user_id
                db.add(existing)

        code = _generate_code(db)
        link = PersonShareLink(
            business_id=business_id,
            person_id=person_id,
            created_by_user_id=user_id,
            code=code,
            token_hash=_hash_code(code),
            expires_at=expires_at,
            view_count=0,
            max_view_count=normalized_max_view,
            options=normalized_options,
        )
        db.add(link)
        db.commit()
        db.refresh(link)
        return link
    except ApiError:
        db.rollback()
        raise
    except Exception as exc:
        logger.exception("Failed to create share link", exc_info=exc)
        db.rollback()
        raise ApiError(
            "CREATE_SHARE_LINK_FAILED",
            "ایجاد لینک اشتراک ممکن نشد",
            http_status=500,
        )


def revoke_share_link(
    db: Session,
    *,
    business_id: int,
    person_id: int,
    user_id: int,
) -> bool:
    link = get_active_share_link_for_person(db, business_id, person_id)
    if not link:
        return False
    link.revoked_at = datetime.utcnow()
    link.revoked_by_user_id = user_id
    db.add(link)
    db.commit()
    return True


def get_share_link_by_code(db: Session, code: str) -> Optional[PersonShareLink]:
    normalized = (code or "").strip()
    if not normalized:
        return None
    return db.query(PersonShareLink).filter(PersonShareLink.code == normalized).first()


def record_share_link_view(db: Session, link: PersonShareLink) -> PersonShareLink:
    link.view_count = int(link.view_count or 0) + 1
    link.last_view_at = datetime.utcnow()
    if (
        link.max_view_count is not None
        and link.view_count >= link.max_view_count
        and link.revoked_at is None
    ):
        link.revoked_at = datetime.utcnow()
    db.add(link)
    db.commit()
    db.refresh(link)
    return link


def _fetch_summary_totals(
    db: Session, business_id: int, person_id: int
) -> Dict[str, float]:
    row = (
        db.query(
            func.coalesce(func.sum(DocumentLine.debit), 0).label("total_debit"),
            func.coalesce(func.sum(DocumentLine.credit), 0).label("total_credit"),
        )
        .join(Document, Document.id == DocumentLine.document_id)
        .filter(
            Document.business_id == business_id,
            DocumentLine.person_id == person_id,
            Document.is_proforma == False,  # noqa: E712
        )
        .first()
    )
    total_debit = float(getattr(row, "total_debit", 0) or 0)
    total_credit = float(getattr(row, "total_credit", 0) or 0)
    return {"total_debit": total_debit, "total_credit": total_credit}


def _fetch_ledger_items(
    db: Session,
    business_id: int,
    person_id: int,
    limit: int,
) -> list[Dict[str, Any]]:
    rows = (
        db.query(DocumentLine, Document, Currency)
        .join(Document, Document.id == DocumentLine.document_id)
        .join(Currency, Currency.id == Document.currency_id)
        .filter(
            Document.business_id == business_id,
            DocumentLine.person_id == person_id,
            Document.is_proforma == False,  # noqa: E712
        )
        .order_by(
            Document.document_date.desc(),
            Document.id.desc(),
            DocumentLine.id.desc(),
        )
        .limit(limit)
        .all()
    )
    items: list[Dict[str, Any]] = []
    for line, doc, cur in rows:
        items.append(
            {
                "line_id": line.id,
                "document_id": doc.id,
                "document_code": doc.code,
                "document_type": doc.document_type,
                "document_type_name": _document_type_label(doc.document_type),
                "document_date": doc.document_date.isoformat(),
                "description": line.description,
                "debit": float(line.debit or 0),
                "credit": float(line.credit or 0),
                "currency_code": getattr(cur, "code", None),
                "extra_info": line.extra_info or {},
            }
        )
    return items


def _fetch_invoice_items(
    db: Session,
    business_id: int,
    person_id: int,
    limit: int,
) -> list[Dict[str, Any]]:
    rows = (
        db.query(
            Document.id.label("document_id"),
            Document.code.label("document_code"),
            Document.document_type,
            Document.document_date,
            Document.description,
            Document.extra_info,
            Currency.code.label("currency_code"),
            func.coalesce(func.sum(DocumentLine.debit), 0).label("total_debit"),
            func.coalesce(func.sum(DocumentLine.credit), 0).label("total_credit"),
        )
        .join(DocumentLine, DocumentLine.document_id == Document.id)
        .join(Currency, Currency.id == Document.currency_id)
        .filter(
            Document.business_id == business_id,
            Document.is_proforma == False,  # noqa: E712
            Document.document_type.in_(tuple(SUPPORTED_INVOICE_TYPES)),
            DocumentLine.person_id == person_id,
        )
        # GROUP BY فقط id و currency: در PostgreSQL ستون‌های دیگر سند تابع id هستند.
        # قرار دادن extra_info (نوع json) در GROUP BY در PostgreSQL خطای عدم وجود عملگر برابری می‌دهد.
        .group_by(Document.id, Currency.code)
        .order_by(Document.document_date.desc(), Document.id.desc())
        .limit(min(limit, 40))
        .all()
    )
    items: list[Dict[str, Any]] = []
    for row in rows:
        total_debit = float(getattr(row, "total_debit", 0) or 0)
        total_credit = float(getattr(row, "total_credit", 0) or 0)
        # برای فاکتور فروش سطر شخص معمولاً بدهکار است؛ مبلغ نمایشی مثبت می‌خواهیم
        net_amount = abs(total_credit - total_debit)
        extra_info = getattr(row, "extra_info", {}) or {}
        items.append(
            {
                "document_id": row.document_id,
                "document_code": row.document_code,
                "document_type": row.document_type,
                "document_type_name": _document_type_label(row.document_type),
                "document_date": row.document_date.isoformat(),
                "description": row.description,
                "amount": net_amount,
                "currency_code": row.currency_code,
                "status": extra_info.get("lifecycle_status") or extra_info.get("status"),
                "extra_info": extra_info,
            }
        )
    return items


def build_public_payload(
    db: Session, link: PersonShareLink, *, allow_inactive: bool = False
) -> Dict[str, Any]:
    if not allow_inactive and not link.is_active:
        raise ApiError(
            "LINK_INACTIVE",
            "این لینک منقضی یا غیرفعال شده است",
            http_status=404,
        )

    person = db.query(Person).filter(Person.id == link.person_id).first()
    business = db.query(Business).filter(Business.id == link.business_id).first()
    if not person or not business:
        raise ApiError(
            "LINK_TARGET_NOT_FOUND",
            "اطلاعات شخص یا کسب‌وکار یافت نشد",
            http_status=404,
        )

    options = _normalize_options(link.options or {})
    balance, status = calculate_person_balance(db, person.id)
    totals = _fetch_summary_totals(db, link.business_id, link.person_id)

    ledger_items = (
        _fetch_ledger_items(
            db,
            link.business_id,
            link.person_id,
            options["documents_limit"],
        )
        if options["include_ledger"]
        else []
    )
    invoice_items = (
        _fetch_invoice_items(
            db,
            link.business_id,
            link.person_id,
            options["documents_limit"],
        )
        if options["include_invoices"]
        else []
    )

    return {
        "share_link": serialize_share_link(link, db=db),
        "person": {
            "id": person.id,
            "code": person.code,
            "alias_name": person.alias_name,
            "company_name": person.company_name,
            "mobile": person.mobile,
            "mobile_2": person.mobile_2,
            "mobile_3": person.mobile_3,
            "phone": person.phone,
            "email": person.email,
            "city": person.city,
        },
        "business": {
            "id": business.id,
            "name": business.name,
            "phone": business.phone,
            "mobile": business.mobile,
            "address": business.address,
            "city": business.city,
            "has_logo": bool(getattr(business, "logo_file_id", None)),
        },
        "summary": {
            "balance": balance,
            "status": status,
            "total_credit": totals["total_credit"],
            "total_debit": totals["total_debit"],
        },
        "ledger": ledger_items,
        "invoices": invoice_items,
        "options": options,
    }


def resolve_public_payload_by_code(db: Session, code: str) -> Dict[str, Any]:
    link = get_share_link_by_code(db, code)
    if not link or not link.is_active:
        raise ApiError(
            "LINK_NOT_FOUND",
            "لینک اشتراک معتبر نیست یا منقضی شده",
            http_status=404,
        )
    refreshed = record_share_link_view(db, link)
    return build_public_payload(db, refreshed, allow_inactive=True)


def get_public_invoice_details(db: Session, code: str, document_id: int) -> Dict[str, Any]:
    """
    دریافت جزئیات یک فاکتور از طریق کد لینک اشتراک
    بررسی می‌کند که فاکتور متعلق به شخص در لینک اشتراک باشد
    """
    link = get_share_link_by_code(db, code)
    if not link or not link.is_active:
        raise ApiError(
            "LINK_NOT_FOUND",
            "لینک اشتراک معتبر نیست یا منقضی شده",
            http_status=404,
        )

    # بررسی اینکه فاکتور متعلق به کسب‌وکار و شخص در لینک باشد
    document = db.query(Document).filter(
        and_(
            Document.id == document_id,
            Document.business_id == link.business_id,
            Document.document_type.in_(tuple(SUPPORTED_INVOICE_TYPES)),
        )
    ).first()

    if not document:
        raise ApiError(
            "INVOICE_NOT_FOUND",
            "فاکتور یافت نشد",
            http_status=404,
        )

    # بررسی اینکه فاکتور متعلق به شخص در لینک باشد
    person_line = db.query(DocumentLine).filter(
        and_(
            DocumentLine.document_id == document_id,
            DocumentLine.person_id == link.person_id,
        )
    ).first()

    if not person_line:
        raise ApiError(
            "INVOICE_ACCESS_DENIED",
            "این فاکتور متعلق به این شخص نیست",
            http_status=403,
        )

    # دریافت جزئیات کامل فاکتور (بدون commit جانبی برای پاکسازی لینک‌ها)
    details = invoice_document_to_dict(db, document, persist_link_cleanup=False)

    fin = _public_invoice_financials_from_extra_info(document.extra_info)
    details["tax_amount"] = fin["tax_amount"]
    details["discount_amount"] = fin["discount_amount"]
    details["subtotal"] = fin["subtotal"]
    details["total"] = fin["total"]

    return details


