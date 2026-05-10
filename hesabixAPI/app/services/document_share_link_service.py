from __future__ import annotations

import copy
import hashlib
import logging
import secrets
from datetime import datetime, timedelta
from decimal import Decimal
from typing import Any, Dict, List, Optional

from sqlalchemy import or_
from sqlalchemy.orm import Session

from adapters.db.models.business import Business
from adapters.db.models.document import Document
from adapters.db.models.document_share_link import DocumentShareLink
from adapters.db.models.person_share_link import PersonShareLink
from app.core.responses import ApiError
from app.core.settings import get_settings
from app.services.invoice_service import SUPPORTED_INVOICE_TYPES, invoice_document_to_dict
from app.services.system_settings_service import resolve_share_url_http_origin

logger = logging.getLogger(__name__)

BASE62_ALPHABET = "23456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
DEFAULT_CODE_LENGTH = 9


def _settings():
    return get_settings()


def _hash_code(code: str) -> str:
    secret = _settings().share_link_secret
    payload = f"{secret}:{code}".encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def _generate_code(db: Session) -> str:
    length = max(6, min(_settings().share_link_code_length or DEFAULT_CODE_LENGTH, 16))
    for _ in range(20):
        candidate = "".join(secrets.choice(BASE62_ALPHABET) for _ in range(length))
        p = (
            db.query(PersonShareLink)
            .filter(PersonShareLink.code == candidate)
            .first()
        )
        d = (
            db.query(DocumentShareLink)
            .filter(DocumentShareLink.code == candidate)
            .first()
        )
        if not p and not d:
            return candidate
    return f"{int(datetime.utcnow().timestamp())}{secrets.randbelow(9999):04d}"[-length:]


def build_invoice_share_i_url(
    code: str,
    request_base_url: Optional[str] = None,
    db: Optional[Session] = None,
) -> str:
    """
    URL کامل برای QR و نمایش؛ اولویت با تنظیمات دامنهٔ عمومی (DB/env)،
    سپس share_link_public_base_url و در آخر host درخواست.
    """
    base = resolve_share_url_http_origin(db, request_base_url)
    if not base:
        return f"/i/{code}"
    return f"{base}/i/{code}"


def get_active_share_link_for_document(
    db: Session, business_id: int, document_id: int
) -> Optional[DocumentShareLink]:
    now = datetime.utcnow()
    return (
        db.query(DocumentShareLink)
        .filter(
            DocumentShareLink.business_id == business_id,
            DocumentShareLink.document_id == document_id,
            DocumentShareLink.revoked_at.is_(None),
            or_(
                DocumentShareLink.expires_at.is_(None),
                DocumentShareLink.expires_at > now,
            ),
            or_(
                DocumentShareLink.max_view_count.is_(None),
                DocumentShareLink.view_count < DocumentShareLink.max_view_count,
            ),
        )
        .order_by(DocumentShareLink.created_at.desc())
        .first()
    )


def serialize_document_share_link(
    link: Optional[DocumentShareLink],
    request_base_url: Optional[str] = None,
    db: Optional[Session] = None,
) -> Optional[Dict[str, Any]]:
    if not link:
        return None
    public_url = build_invoice_share_i_url(
        link.code, request_base_url, db=db
    )
    now = datetime.utcnow()
    expires_in = None
    if link.expires_at:
        expires_in = (link.expires_at - now).total_seconds()
    remaining_hours = None if expires_in is None else round(max(expires_in, 0) / 3600, 2)
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
        "document_id": link.document_id,
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
    }


def _strip_invoice_for_public(raw: Dict[str, Any]) -> Dict[str, Any]:
    out = copy.deepcopy(raw)
    out.pop("account_lines", None)
    out.pop("created_by_user_id", None)
    for k in (
        "gross_profit",
        "gross_profit_percent",
        "net_profit",
        "net_profit_percent",
        "total_profit",
        "total_profit_percent",
        "total_overhead",
        "line_profits",
        "profit_calculation_context",
        "recognized_profit_ledger",
    ):
        out.pop(k, None)
    pls = out.get("product_lines")
    if isinstance(pls, list):
        cleaned: List[Dict[str, Any]] = []
        for row in pls:
            if not isinstance(row, dict):
                continue
            r = dict(row)
            for k2 in (
                "ledger_unit_cogs",
                "ledger_line_cogs",
                "ledger_line_gross_profit",
                "ledger_recognized_at",
                "ledger_recognition_event",
            ):
                r.pop(k2, None)
            cleaned.append(r)
        out["product_lines"] = cleaned
    return out


def _enrich_public_invoice_adjustments(
    db: Session, public_invoice: Dict[str, Any]
) -> None:
    """نام/کد حساب طرف اضافات و کسورات را برای نمایش عمومی روی هر ردیف ست می‌کند.
    برای جلوگیری از افشای شناسهٔ داخلی، account_id حذف می‌شود.
    """
    extra = public_invoice.get("extra_info")
    if not isinstance(extra, dict):
        return
    rows = extra.get("invoice_adjustments")
    if not isinstance(rows, list) or not rows:
        return

    from adapters.db.models.account import Account

    acc_ids: List[int] = []
    for row in rows:
        if isinstance(row, dict) and row.get("account_id") is not None:
            try:
                acc_ids.append(int(row["account_id"]))
            except Exception:
                continue
    name_map: Dict[int, str] = {}
    code_map: Dict[int, Optional[str]] = {}
    if acc_ids:
        try:
            for acc in (
                db.query(Account).filter(Account.id.in_(set(acc_ids))).all()
            ):
                name_map[int(acc.id)] = acc.name or ""
                code_map[int(acc.id)] = getattr(acc, "code", None)
        except Exception:
            logger.exception(
                "public payload: failed to load adjustment account names"
            )

    enriched: List[Dict[str, Any]] = []
    for row in rows:
        if not isinstance(row, dict):
            continue
        r = dict(row)
        try:
            aid = int(r.get("account_id")) if r.get("account_id") is not None else None
        except Exception:
            aid = None
        if aid is not None:
            r["account_name"] = name_map.get(aid)
            r["account_code"] = code_map.get(aid)
        r.pop("account_id", None)
        enriched.append(r)
    extra["invoice_adjustments"] = enriched
    public_invoice["extra_info"] = extra


def _safe_decimal(v: Any) -> Decimal:
    try:
        return Decimal(str(v or 0))
    except Exception:
        return Decimal(0)


def _build_public_installments(extra_info: Dict[str, Any]) -> Dict[str, Any]:
    plan = (extra_info or {}).get("installment_plan")
    if not isinstance(plan, dict):
        return {
            "has_installments": False,
            "summary": None,
            "schedule": [],
        }

    schedule_raw = plan.get("schedule")
    rows = schedule_raw if isinstance(schedule_raw, list) else []
    now_date = datetime.utcnow().date()
    schedule: List[Dict[str, Any]] = []

    principal_total = _safe_decimal(plan.get("principal_total"))
    interest_total = _safe_decimal(plan.get("interest_total"))
    down_payment = _safe_decimal(plan.get("down_payment"))
    paid_total = Decimal(0)
    remaining_total = Decimal(0)

    paid_count = 0
    overdue_count = 0

    for idx, r in enumerate(rows):
        if not isinstance(r, dict):
            continue
        seq = int(r.get("seq") or (idx + 1))
        principal = _safe_decimal(r.get("principal"))
        interest = _safe_decimal(r.get("interest"))
        total = _safe_decimal(r.get("total")) or (principal + interest)
        paid = _safe_decimal(r.get("paid_amount"))
        if paid < 0:
            paid = Decimal(0)
        if paid > total:
            paid = total
        remaining = total - paid
        if remaining < 0:
            remaining = Decimal(0)

        due_raw = r.get("due_date")
        due_iso = str(due_raw) if due_raw is not None else None
        due_dt = None
        try:
            if due_iso:
                due_dt = datetime.fromisoformat(due_iso.replace("Z", "+00:00")).date()
        except Exception:
            due_dt = None

        status = str(r.get("status") or "").strip().lower()
        if not status:
            if total > 0 and paid >= total:
                status = "paid"
            elif paid > 0:
                status = "partial"
            elif due_dt and due_dt < now_date:
                status = "overdue"
            else:
                status = "pending"

        if status == "paid":
            paid_count += 1
        if status == "overdue":
            overdue_count += 1

        paid_total += paid
        remaining_total += remaining

        schedule.append(
            {
                "seq": seq,
                "due_date": due_iso,
                "principal": float(principal),
                "interest": float(interest),
                "total": float(total),
                "paid_amount": float(paid),
                "remaining": float(remaining),
                "status": status,
            }
        )

    if principal_total <= 0:
        principal_total = sum((_safe_decimal(x.get("principal")) for x in schedule), Decimal(0))
    if interest_total < 0:
        interest_total = Decimal(0)
    grand_total = principal_total + interest_total
    installment_count = len(schedule)

    return {
        "has_installments": installment_count > 0,
        "summary": {
            "down_payment": float(down_payment),
            "principal_total": float(principal_total),
            "interest_total": float(interest_total),
            "grand_total": float(grand_total),
            "paid_total": float(paid_total),
            "remaining_total": float(remaining_total),
            "installment_count": installment_count,
            "paid_count": paid_count,
            "overdue_count": overdue_count,
        },
        "schedule": schedule,
    }


def build_public_payload(
    db: Session, link: DocumentShareLink, *, allow_inactive: bool = False
) -> Dict[str, Any]:
    if not allow_inactive and not link.is_active:
        raise ApiError(
            "LINK_INACTIVE",
            "این لینک منقضی یا غیرفعال شده است",
            http_status=404,
        )
    document = (
        db.query(Document)
        .filter(
            Document.id == link.document_id,
            Document.business_id == link.business_id,
        )
        .first()
    )
    if not document:
        raise ApiError(
            "LINK_TARGET_NOT_FOUND",
            "سند یافت نشد",
            http_status=404,
        )
    if document.document_type not in SUPPORTED_INVOICE_TYPES:
        raise ApiError(
            "LINK_TARGET_NOT_FOUND",
            "سند فاکتور معتبر نیست",
            http_status=404,
        )
    business = db.query(Business).filter(Business.id == link.business_id).first()
    if not business:
        raise ApiError("LINK_TARGET_NOT_FOUND", "کسب‌وکار یافت نشد", http_status=404)

    inv = invoice_document_to_dict(db, document, persist_link_cleanup=False)
    public_invoice = _strip_invoice_for_public(inv or {})
    _enrich_public_invoice_adjustments(db, public_invoice)
    installments = _build_public_installments(public_invoice.get("extra_info") or {})

    return {
        "share_link": serialize_document_share_link(link, db=db),
        "business": {
            "id": business.id,
            "name": business.name,
            "phone": getattr(business, "phone", None),
            "mobile": getattr(business, "mobile", None),
            "address": getattr(business, "address", None),
            "has_logo": bool(getattr(business, "logo_file_id", None)),
        },
        "invoice": public_invoice,
        "installments": installments,
        "authenticity": {
            "verified": True,
            "message_fa": "این فاکتور در سامانه حسابیکس (Hesabix) ثبت شده است.",
            "message_en": "This invoice is registered in Hesabix.",
        },
    }


def get_share_link_by_code(db: Session, code: str) -> Optional[DocumentShareLink]:
    normalized = (code or "").strip()
    if not normalized:
        return None
    return (
        db.query(DocumentShareLink)
        .filter(DocumentShareLink.code == normalized)
        .first()
    )


def record_share_link_view(db: Session, link: DocumentShareLink) -> DocumentShareLink:
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


def resolve_public_payload_by_code(db: Session, code: str) -> Dict[str, Any]:
    link = get_share_link_by_code(db, code)
    if not link or not link.is_active:
        raise ApiError(
            "LINK_NOT_FOUND",
            "لینک معتبر نیست یا منقضی شده",
            http_status=404,
        )
    refreshed = record_share_link_view(db, link)
    return build_public_payload(db, refreshed, allow_inactive=True)


def create_share_link(
    db: Session,
    *,
    business_id: int,
    document_id: int,
    user_id: int,
    expires_in_hours: Optional[int],
    max_view_count: Optional[int],
    replace_existing: bool = True,
    unlimited_expiry: bool = False,
) -> DocumentShareLink:
    document = (
        db.query(Document)
        .filter(Document.id == document_id, Document.business_id == business_id)
        .first()
    )
    if not document:
        raise ApiError("DOCUMENT_NOT_FOUND", "سند یافت نشد", http_status=404)
    if document.document_type not in SUPPORTED_INVOICE_TYPES:
        raise ApiError(
            "INVALID_DOCUMENT_TYPE",
            "فقط برای اسناد فاکتور می‌توان لینک ایجاد کرد",
            http_status=400,
        )
    if unlimited_expiry:
        expires_at = None
        normalized_max_view = None
    else:
        ttl_hours = expires_in_hours or _settings().share_link_default_ttl_hours
        max_allowed_ttl = _settings().share_link_max_ttl_hours or (24 * 30)
        if ttl_hours:
            ttl_hours = max(1, min(ttl_hours, max_allowed_ttl))
        expires_at = datetime.utcnow() + timedelta(hours=ttl_hours) if ttl_hours else None

        normalized_max_view = None
        if max_view_count is not None:
            try:
                normalized_max_view = max(1, min(int(max_view_count), 1000))
            except Exception:
                normalized_max_view = None

    try:
        if replace_existing:
            existing = get_active_share_link_for_document(db, business_id, document_id)
            if existing:
                existing.revoked_at = datetime.utcnow()
                existing.revoked_by_user_id = user_id
                db.add(existing)
        code = _generate_code(db)
        link = DocumentShareLink(
            business_id=business_id,
            document_id=document_id,
            created_by_user_id=user_id,
            code=code,
            token_hash=_hash_code(code),
            expires_at=expires_at,
            view_count=0,
            max_view_count=normalized_max_view,
        )
        db.add(link)
        db.commit()
        db.refresh(link)
        return link
    except ApiError:
        db.rollback()
        raise
    except Exception as exc:
        logger.exception("Failed to create document share link", exc_info=exc)
        db.rollback()
        raise ApiError(
            "CREATE_SHARE_LINK_FAILED",
            "ایجاد لینک اشتراک ممکن نشد",
            http_status=500,
        )


def get_or_create_link_for_print(
    db: Session,
    *,
    business_id: int,
    document_id: int,
    user_id: int,
) -> DocumentShareLink:
    """برای چاپ PDF با QR: لینک فعال برگردانده می‌شود؛ در غیر این صورت با انقضای نامحدود ایجاد می‌شود."""
    existing = get_active_share_link_for_document(db, business_id, document_id)
    if existing:
        return existing
    return create_share_link(
        db,
        business_id=business_id,
        document_id=document_id,
        user_id=user_id,
        expires_in_hours=None,
        max_view_count=None,
        replace_existing=False,
        unlimited_expiry=True,
    )


def revoke_share_link(
    db: Session,
    *,
    business_id: int,
    document_id: int,
    user_id: int,
) -> bool:
    link = get_active_share_link_for_document(db, business_id, document_id)
    if not link:
        return False
    link.revoked_at = datetime.utcnow()
    link.revoked_by_user_id = user_id
    db.add(link)
    db.commit()
    return True
