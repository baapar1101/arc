from __future__ import annotations

import datetime
from typing import Dict, Any

from sqlalchemy.orm import Session

from adapters.db.models.document import Document
from adapters.db.models.tax_setting import TaxSetting
from app.core.responses import ApiError
from app.core.settings import get_settings
from app.integrations.moadian.client import MoadianClient
from app.services.invoice_service import invoice_document_to_dict
from app.services.tax_validation_service import validate_document_for_tax


def send_document_to_tax_system(db: Session, document: Document) -> Dict[str, Any]:
    """
    نقطه ورود اصلی ارسال سند به سامانه مودیان.
    در حال حاضر اگر force_simulation فعال باشد، خروجی به‌صورت شبیه‌سازی‌شده
    برگردانده می‌شود؛ اما زیرساخت ارسال واقعی آماده است.
    """
    validation = validate_document_for_tax(db, document)
    if not validation["valid"]:
        raise ApiError(
            "TAX_VALIDATION_FAILED",
            "فاکتور حداقل الزامات سامانه مودیان را ندارد.",
            http_status=400,
            details={"issues": validation["issues"]},
        )

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

    payload = invoice_document_to_dict(db, document)
    payload.setdefault("id", document.id)
    payload.setdefault("document_code", document.code)

    client = MoadianClient(settings=get_settings(), tax_setting=tax_setting)
    try:
        submission = client.send_invoice(payload)
    finally:
        client.close()

    _apply_submission_result(document, submission, db)
    return submission


def _apply_submission_result(doc: Document, submission: Dict[str, Any], db: Session) -> None:
    extra = dict(doc.extra_info or {})
    extra["tax_workspace"] = True
    extra["tax_status"] = submission.get("status") or "sent"
    extra["tax_tracking_code"] = submission.get("tracking_code") or extra.get("tax_tracking_code")
    extra["tax_last_send_at"] = submission.get("sent_at") or datetime.datetime.utcnow().isoformat()
    if "raw_response" in submission:
        extra["tax_last_response"] = submission["raw_response"]
    extra.pop("tax_error_message", None)
    doc.extra_info = extra
    db.add(doc)

