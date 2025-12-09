from __future__ import annotations

import datetime
from typing import Dict, Any, List

from sqlalchemy.orm import Session

from adapters.db.models.document import Document
from adapters.db.models.tax_setting import TaxSetting
from app.core.responses import ApiError
from app.core.settings import get_settings
from app.integrations.moadian.client import MoadianClient
from app.integrations.moadian.invoice_builder import build_invoice_for_moadian
from app.services.invoice_service import invoice_document_to_dict
from app.services.tax_validation_service import validate_document_for_tax


def send_document_to_tax_system(db: Session, document: Document) -> Dict[str, Any]:
    """
    نقطه ورود اصلی ارسال سند به سامانه مودیان.
    
    مراحل:
    1. اعتبارسنجی فاکتور
    2. بررسی تنظیمات مالیاتی
    3. ساخت DTO استاندارد
    4. ارسال به سامانه
    5. ذخیره نتیجه
    
    Args:
        db: Database session
        document: سند/فاکتور برای ارسال
    
    Returns:
        نتیجه ارسال شامل کد رهگیری و وضعیت
    """
    # 1. اعتبارسنجی
    validation = validate_document_for_tax(db, document)
    if not validation["valid"]:
        raise ApiError(
            "TAX_VALIDATION_FAILED",
            "فاکتور حداقل الزامات سامانه مودیان را ندارد.",
            http_status=400,
            details={"issues": validation["issues"]},
        )

    # 2. بررسی تنظیمات
    tax_setting = (
        db.query(TaxSetting)
        .filter(TaxSetting.business_id == document.business_id)
        .first()
    )
    if not tax_setting:
        raise ApiError(
            "TAX_SETTINGS_NOT_CONFIGURED",
            "تنظیمات سامانه مودیان برای این کسب‌وکار ثبت نشده است.",
            http_status=400,
        )
    if not (tax_setting.tax_memory_id and tax_setting.private_key and tax_setting.economic_code):
        raise ApiError(
            "TAX_SETTINGS_INCOMPLETE",
            "تنظیمات سامانه مودیان ناقص است. شناسه حافظه، کد اقتصادی و کلید خصوصی الزامی است.",
            http_status=400,
        )

    # 3. ساخت DTO استاندارد
    raw_document = invoice_document_to_dict(db, document)
    invoice_dto = build_invoice_for_moadian(raw_document, tax_setting)

    # 4. وضعیت در حال ارسال
    _mark_document_pending(document, db)

    # 5. ارسال به سامانه
    client = MoadianClient(settings=get_settings(), tax_setting=tax_setting)
    try:
        submission = client.send_invoice(invoice_dto)
    finally:
        client.close()

    # 6. ذخیره نتیجه
    _apply_submission_result(document, submission, db)
    
    return submission


def inquire_tax_status(
    db: Session,
    business_id: int,
    *,
    invoice_ids: List[int] | None = None,
    tracking_codes: List[str] | None = None,
) -> Dict[str, Any]:
    invoice_ids = invoice_ids or []
    tracking_codes = tracking_codes or []

    if not invoice_ids and not tracking_codes:
        raise ApiError("INVALID_REQUEST", "لیست فاکتورها یا کد رهگیری لازم است.", http_status=400)

    docs: List[Document] = []
    if invoice_ids:
        docs = (
            db.query(Document)
            .filter(Document.business_id == business_id, Document.id.in_(invoice_ids))
            .all()
        )

    doc_by_tracking: Dict[str, Document] = {}
    for doc in docs:
        code = (doc.extra_info or {}).get("tax_tracking_code")
        if code:
            doc_by_tracking[str(code)] = doc

    merged_codes = {str(code) for code in tracking_codes if code}
    merged_codes.update(doc_by_tracking.keys())

    if not merged_codes:
        raise ApiError("TAX_TRACKING_CODE_MISSING", "هیچ کد رهگیری معتبری یافت نشد.", http_status=400)

    tax_setting = (
        db.query(TaxSetting)
        .filter(TaxSetting.business_id == business_id)
        .first()
    )
    if not tax_setting:
        raise ApiError(
            "TAX_SETTINGS_NOT_CONFIGURED",
            "تنظیمات سامانه مودیان برای این کسب‌وکار ثبت نشده است.",
            http_status=400,
        )

    client = MoadianClient(settings=get_settings(), tax_setting=tax_setting)
    try:
        response = client.inquire_status(sorted(merged_codes))
    finally:
        client.close()

    results = response.get("results") or []
    now = datetime.datetime.utcnow().isoformat()
    for item in results:
        reference = item.get("reference_number") or item.get("tracking_code")
        if not reference:
            continue
        doc = doc_by_tracking.get(str(reference))
        if not doc:
            continue
        extra = dict(doc.extra_info or {})
        mapped_status = _map_inquiry_status(item.get("status"))
        if mapped_status:
            extra["tax_status"] = mapped_status
        if item.get("error_message"):
            extra["tax_error_message"] = item.get("error_message")
        elif item.get("status") not in ("failed", "error"):
            extra.pop("tax_error_message", None)
        extra["tax_last_inquiry_at"] = now
        doc.extra_info = extra
        db.add(doc)

    return {
        "mode": response.get("mode"),
        "results": results,
    }


def _mark_document_pending(doc: Document, db: Session) -> None:
    extra = dict(doc.extra_info or {})
    extra["tax_workspace"] = True
    extra["tax_status"] = "pending"
    doc.extra_info = extra
    db.add(doc)
    db.flush()


def _apply_submission_result(doc: Document, submission: Dict[str, Any], db: Session) -> None:
    extra = dict(doc.extra_info or {})
    extra["tax_workspace"] = True
    extra["tax_status"] = submission.get("status") or "sent"
    extra["tax_tracking_code"] = submission.get("tracking_code") or extra.get("tax_tracking_code")
    extra["tax_last_send_at"] = submission.get("sent_at") or datetime.datetime.utcnow().isoformat()
    if "raw_response" in submission:
        extra["tax_last_response"] = submission["raw_response"]
    if submission.get("error_message"):
        extra["tax_error_message"] = submission["error_message"]
    else:
        extra.pop("tax_error_message", None)
    doc.extra_info = extra
    db.add(doc)


def _map_inquiry_status(status: Any) -> str | None:
    if not status:
        return None
    normalized = str(status).lower()
    mapping = {
        "sent": "sent",
        "pending": "pending",
        "finalized": "finalized",
        "accepted": "finalized",
        "success": "finalized",
        "failed": "failed",
        "error": "failed",
    }
    return mapping.get(normalized, normalized or None)

