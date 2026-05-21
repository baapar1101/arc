"""
مرجع‌یابی و مدیریت شناسه‌های مالیاتی مودیان (taxid / irtaxid).
"""
from __future__ import annotations

from datetime import datetime
from typing import Any, Dict, Optional, Tuple

from sqlalchemy.orm import Session

from adapters.db.models.document import Document
from adapters.db.models.tax_setting import TaxSetting
from app.integrations.moadian.utils import generate_tax_id


TAX_SENT_STATUSES = frozenset({"sent", "finalized", "accepted"})
TAX_REFERENCE_INVOICE_KEYS = (
    "reference_invoice_id",
    "source_invoice_id",
    "original_invoice_id",
    "return_from_invoice_id",
)


def get_document_extra(document: Document) -> dict:
    return dict(document.extra_info or {})


def get_stored_taxid(extra: dict) -> Optional[str]:
    raw = (extra.get("tax_moadian_taxid") or extra.get("taxid") or "").strip()
    return raw or None


def compute_taxid_for_document(document: Document, tax_setting: TaxSetting) -> str:
    extra = get_document_extra(document)
    stored = get_stored_taxid(extra)
    if stored:
        return stored

    doc_date = document.document_date
    if doc_date is None:
        doc_date = datetime.utcnow()
    elif isinstance(doc_date, str):
        try:
            doc_date = datetime.fromisoformat(doc_date.replace("Z", "+00:00"))
        except Exception:
            doc_date = datetime.utcnow()

    client_id = tax_setting.tax_memory_id or tax_setting.economic_code or ""
    return generate_tax_id(
        client_id=client_id,
        timestamp=doc_date,
        internal_id=int(document.id),
    )


def persist_taxid_on_document(document: Document, taxid: str, db: Session) -> None:
    extra = get_document_extra(document)
    extra["tax_moadian_taxid"] = taxid
    document.extra_info = extra
    db.add(document)


def resolve_reference_document(
    db: Session,
    business_id: int,
    document: Document,
) -> Optional[Document]:
    extra = get_document_extra(document)
    ref_id = None
    for key in TAX_REFERENCE_INVOICE_KEYS:
        val = extra.get(key)
        if val is not None:
            try:
                ref_id = int(val)
                break
            except (TypeError, ValueError):
                continue

    if ref_id is None:
        return None

    return (
        db.query(Document)
        .filter(Document.id == ref_id, Document.business_id == business_id)
        .first()
    )


def resolve_irtaxid(
    db: Session,
    business_id: int,
    document: Document,
    tax_setting: TaxSetting,
) -> Optional[str]:
    extra = get_document_extra(document)
    manual = (extra.get("reference_tax_id") or extra.get("irtaxid") or "").strip()
    if manual:
        return manual

    ref_doc = resolve_reference_document(db, business_id, document)
    if ref_doc is None:
        return None

    ref_extra = get_document_extra(ref_doc)
    stored = get_stored_taxid(ref_extra)
    if stored:
        return stored

    if ref_doc.document_date and ref_doc.id:
        return compute_taxid_for_document(ref_doc, tax_setting)

    return None


def document_tax_status(extra: dict) -> str:
    return str(extra.get("tax_status") or "").strip().lower()


def is_modian_submitted(extra: dict) -> bool:
    status = document_tax_status(extra)
    if status in TAX_SENT_STATUSES:
        return True
    return bool(extra.get("tax_tracking_code"))


def can_cancel_in_modian(document: Document) -> Tuple[bool, str]:
    extra = get_document_extra(document)
    if not bool(extra.get("tax_workspace")):
        return False, "فاکتور در کارپوشه مالیاتی نیست."
    if not is_modian_submitted(extra):
        return False, "فقط فاکتورهای ارسال‌شده به مودیان قابل ابطال هستند."
    if extra.get("tax_cancelled_in_modian"):
        return False, "این فاکتور قبلاً در سامانه مودیان ابطال شده است."
    return True, ""


def can_send_corrective(document: Document) -> Tuple[bool, str]:
    extra = get_document_extra(document)
    if not bool(extra.get("tax_workspace")):
        return False, "فاکتور در کارپوشه مالیاتی نیست."
    if not is_modian_submitted(extra):
        return False, "فقط پس از ارسال اولیه می‌توان صورتحساب اصلاحی صادر کرد."
    if not get_stored_taxid(extra) and not extra.get("tax_tracking_code"):
        return False, "شناسه مالیاتی فاکتور مرجع یافت نشد."
    return True, ""


def link_reference_invoice(
    db: Session,
    business_id: int,
    document: Document,
    reference_invoice_id: int,
) -> Document:
    ref = (
        db.query(Document)
        .filter(Document.id == reference_invoice_id, Document.business_id == business_id)
        .first()
    )
    if not ref:
        from app.core.responses import ApiError
        raise ApiError("REFERENCE_INVOICE_NOT_FOUND", "فاکتور مرجع یافت نشد.", http_status=404)

    extra = get_document_extra(document)
    extra["reference_invoice_id"] = int(reference_invoice_id)
    document.extra_info = extra
    db.add(document)
    db.flush()
    return ref
