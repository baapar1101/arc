"""
مرجع‌یابی و مدیریت شناسه‌های مالیاتی مودیان (taxid / irtaxid).
"""
from __future__ import annotations

from typing import Any, Dict, List, Optional, Tuple

from sqlalchemy.orm import Session

from adapters.db.models.document import Document
from adapters.db.models.tax_setting import TaxSetting
from app.integrations.moadian.utils import coerce_to_datetime, generate_tax_id


TAX_SENT_STATUSES = frozenset({"sent", "finalized", "accepted"})
TAX_TYPE_CHANGE_BLOCKED_STATUSES = TAX_SENT_STATUSES
TAX_WORKSPACE_ALLOWED_TYPES = frozenset({"invoice_sales", "invoice_sales_return"})
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

    doc_date = coerce_to_datetime(document.document_date)

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


def build_tax_edit_constraints_for_api(document: Document) -> Dict[str, Any]:
    """
    قیود ویرایش فاکتور از منظر کارپوشه/ارسال مودیان برای API و UI.
    """
    extra = get_document_extra(document)
    in_workspace = bool(extra.get("tax_workspace"))
    submitted = is_modian_submitted(extra)
    cancelled = bool(extra.get("tax_cancelled_in_modian"))
    status = document_tax_status(extra)
    if not status:
        status = "in_workspace" if in_workspace else "not_in_workspace"

    type_change_allowed = True
    type_change_block_reason: Optional[str] = None
    header_locked = False
    locked_fields: List[str] = []

    if cancelled:
        type_change_allowed = False
        header_locked = True
        type_change_block_reason = (
            "این فاکتور در سامانه مودیان ابطال شده است. تغییر نوع مجاز نیست؛ فاکتور جدید ثبت کنید."
        )
        locked_fields.extend(["invoice_type", "is_proforma"])
    elif submitted:
        type_change_allowed = False
        header_locked = True
        type_change_block_reason = (
            "این فاکتور به سامانه مودیان ارسال شده است. تغییر نوع مجاز نیست. "
            "برای ابطال از «ابطال در سامانه مودیان»، برای اصلاح جزئی از «صورتحساب اصلاحی»، "
            "و برای تغییر اساسی (مثل خرید) پس از ابطال، فاکتور جدید ایجاد کنید."
        )
        locked_fields.append("invoice_type")
    elif in_workspace:
        locked_fields.append("invoice_type_outside_sales_family")

    allowed_actions: List[str] = []
    ok_cancel, _ = can_cancel_in_modian(document)
    if ok_cancel:
        allowed_actions.append("cancel_in_modian")
    ok_corrective, _ = can_send_corrective(document)
    if ok_corrective:
        allowed_actions.append("send_corrective")
    if in_workspace and not submitted and not cancelled:
        allowed_actions.append("remove_from_tax_workspace")

    return {
        "is_in_tax_workspace": in_workspace,
        "tax_status": status,
        "tax_tracking_code": extra.get("tax_tracking_code"),
        "tax_type_change_allowed": type_change_allowed,
        "tax_type_change_block_reason": type_change_block_reason,
        "tax_header_locked": header_locked,
        "tax_locked_fields": sorted(set(locked_fields)),
        "tax_allowed_actions": allowed_actions,
    }


def validate_invoice_type_change_for_tax(
    document: Document,
    old_type: str,
    new_type: str,
) -> None:
    """جلوگیری از تغییر نوع فاکتور ناسازگار با وضعیت مودیان."""
    from app.core.responses import ApiError

    old_t = str(old_type or "").strip()
    new_t = str(new_type or "").strip()
    if not new_t or old_t == new_t:
        return

    extra = get_document_extra(document)
    constraints = build_tax_edit_constraints_for_api(document)

    if extra.get("tax_cancelled_in_modian"):
        raise ApiError(
            "TAX_TYPE_CHANGE_BLOCKED",
            constraints.get("tax_type_change_block_reason")
            or "این فاکتور در سامانه مودیان ابطال شده است.",
            http_status=409,
            details=constraints,
        )

    if is_modian_submitted(extra):
        raise ApiError(
            "TAX_TYPE_CHANGE_BLOCKED",
            constraints.get("tax_type_change_block_reason")
            or "تغییر نوع فاکتور ارسال‌شده به مودیان مجاز نیست.",
            http_status=409,
            details=constraints,
        )

    if bool(extra.get("tax_workspace")) and new_t not in TAX_WORKSPACE_ALLOWED_TYPES:
        raise ApiError(
            "TAX_WORKSPACE_TYPE_RESTRICTED",
            "فاکتور در کارپوشه مالیاتی است و فقط می‌تواند «فروش» یا «برگشت از فروش» باشد. "
            "برای تغییر به نوع دیگر (مثل خرید)، ابتدا از کارپوشه مودیان خارج کنید.",
            http_status=409,
            details=constraints,
        )


def validate_invoice_proforma_change_for_tax(
    document: Document,
    *,
    old_is_proforma: bool,
    new_is_proforma: bool,
) -> None:
    """پس از ارسال به مودیان، تبدیل قطعی/پیش‌فاکتور مجاز نیست."""
    from app.core.responses import ApiError

    if bool(old_is_proforma) == bool(new_is_proforma):
        return

    extra = get_document_extra(document)
    if extra.get("tax_cancelled_in_modian") or is_modian_submitted(extra):
        constraints = build_tax_edit_constraints_for_api(document)
        raise ApiError(
            "TAX_EDIT_LOCKED",
            "فاکتور ارسال‌شده یا ابطال‌شده در مودیان قابل تبدیل به پیش‌فاکتور/قطعی نیست.",
            http_status=409,
            details=constraints,
        )
