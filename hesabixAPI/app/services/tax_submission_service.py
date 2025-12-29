from __future__ import annotations

import datetime
import logging
import time
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

logger = logging.getLogger(__name__)


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

    # 2. بررسی تنظیمات مالیاتی
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

    # 3.5. بررسی rate limit
    from app.services.tax_rate_limiter import get_tax_rate_limiter
    settings = get_settings()
    rate_limiter = get_tax_rate_limiter()
    allowed, rate_info = rate_limiter.check_rate_limit(
        business_id=document.business_id,
        operation="send_invoice",
        max_requests=settings.tax_system_rate_limit_max_requests,
        window_seconds=settings.tax_system_rate_limit_window_seconds,
    )
    if not allowed:
        raise ApiError(
            "RATE_LIMIT_EXCEEDED",
            "تعداد درخواست‌های ارسال به سامانه مالیاتی از حد مجاز تجاوز کرده است.",
            http_status=429,
            details=rate_info,
        )

    # 3.6. ثبت لاگ شروع
    from app.services.tax_logging import log_tax_operation
    log_tax_operation(
        operation="send_invoice",
        business_id=document.business_id,
        invoice_id=document.id,
        status="started",
    )

    # 4. وضعیت در حال ارسال
    _mark_document_pending(document, db)

    # 5. ارسال به سامانه با retry mechanism
    client = None
    settings = get_settings()
    max_retries = settings.tax_system_retry_max_attempts
    initial_retry_delay = settings.tax_system_retry_initial_delay_seconds
    
    try:
        client = MoadianClient(settings=settings, tax_setting=tax_setting)
        
        for attempt in range(max_retries):
            retry_delay = initial_retry_delay * (2 ** attempt)  # exponential backoff
            try:
                submission = client.send_invoice(invoice_dto)
                # 6. ذخیره نتیجه
                _apply_submission_result(document, submission, db)
                
                # ثبت لاگ موفقیت
                from app.services.tax_logging import log_tax_operation
                log_tax_operation(
                    operation="send_invoice",
                    business_id=document.business_id,
                    invoice_id=document.id,
                    tracking_code=submission.get("tracking_code"),
                    status="completed",
                    details={"status": submission.get("status")},
                )
                
                return submission
                
            except ApiError as e:
                # خطاهای validation یا business logic را retry نمی‌کنیم
                status_code = getattr(e, "status_code", None)
                if status_code in (400, 401, 403, 404):
                    # در صورت خطای validation، وضعیت را به failed تغییر می‌دهیم
                    _mark_document_failed(document, str(e), db)
                    
                    # ثبت لاگ خطا
                    from app.services.tax_logging import log_tax_operation
                    log_tax_operation(
                        operation="send_invoice",
                        business_id=document.business_id,
                        invoice_id=document.id,
                        status="failed",
                        error=str(e),
                    )
                    
                    # افزودن به Dead Letter Queue
                    from app.services.tax_dead_letter_queue import add_to_dead_letter_queue
                    try:
                        error_code = (getattr(e, "detail", {}) or {}).get("error", {}).get("code") if hasattr(e, "detail") else str(e)
                        add_to_dead_letter_queue(
                            db,
                            business_id=document.business_id,
                            invoice_id=document.id,
                            error_code=error_code or "UNKNOWN_ERROR",
                            error_message=str(e),
                            error_details={"http_status": getattr(e, "status_code", None)} if hasattr(e, "status_code") else None,
                        )
                    except Exception as dlq_error:
                        logger.warning(f"Failed to add to dead letter queue: {dlq_error}")
                    
                    raise
                
                # خطاهای شبکه یا سرور را retry می‌کنیم
                if attempt < max_retries - 1:
                    logger.warning(
                        f"Attempt {attempt + 1}/{max_retries} failed for document {document.id}: {e}. "
                        f"Retrying in {retry_delay}s..."
                    )
                    time.sleep(retry_delay)
                else:
                    # در صورت خطای نهایی، وضعیت را به failed تغییر می‌دهیم
                    _mark_document_failed(document, str(e), db)
                    
                    # ثبت لاگ خطا
                    from app.services.tax_logging import log_tax_operation
                    log_tax_operation(
                        operation="send_invoice",
                        business_id=document.business_id,
                        invoice_id=document.id,
                        status="failed",
                        error=str(e),
                    )
                    
                    # افزودن به Dead Letter Queue
                    from app.services.tax_dead_letter_queue import add_to_dead_letter_queue
                    try:
                        error_code = (getattr(e, "detail", {}) or {}).get("error", {}).get("code") if hasattr(e, "detail") else str(e)
                        add_to_dead_letter_queue(
                            db,
                            business_id=document.business_id,
                            invoice_id=document.id,
                            error_code=error_code or "RETRY_EXHAUSTED",
                            error_message=str(e),
                            error_details={"http_status": getattr(e, "status_code", None), "attempts": max_retries} if hasattr(e, "status_code") else {"attempts": max_retries},
                        )
                    except Exception as dlq_error:
                        logger.warning(f"Failed to add to dead letter queue: {dlq_error}")
                    
                    raise
                    
            except Exception as e:
                if attempt < max_retries - 1:
                    logger.warning(
                        f"Attempt {attempt + 1}/{max_retries} failed for document {document.id}: {e}. "
                        f"Retrying in {retry_delay}s..."
                    )
                    time.sleep(retry_delay)
                else:
                    # در صورت خطای نهایی، وضعیت را به failed تغییر می‌دهیم
                    _mark_document_failed(document, str(e), db)
                    
                    # ثبت لاگ خطا
                    from app.services.tax_logging import log_tax_operation
                    log_tax_operation(
                        operation="send_invoice",
                        business_id=document.business_id,
                        invoice_id=document.id,
                        status="failed",
                        error=str(e),
                    )
                    
                    # افزودن به Dead Letter Queue
                    from app.services.tax_dead_letter_queue import add_to_dead_letter_queue
                    try:
                        add_to_dead_letter_queue(
                            db,
                            business_id=document.business_id,
                            invoice_id=document.id,
                            error_code="RETRY_EXHAUSTED",
                            error_message=str(e),
                            error_details={"attempts": max_retries},
                        )
                    except Exception as dlq_error:
                        logger.warning(f"Failed to add to dead letter queue: {dlq_error}")
                    
                    raise
        
        # این خط نباید اجرا شود
        raise ApiError("TAX_SUBMISSION_FAILED", "خطا در ارسال فاکتور پس از چندین تلاش", http_status=500)
        
    finally:
        if client:
            try:
                client.close()
            except Exception as close_error:
                logger.warning(f"Error closing MoadianClient: {close_error}")


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
    extra["tax_last_send_at"] = datetime.datetime.utcnow().isoformat()
    doc.extra_info = extra
    db.add(doc)
    db.flush()


def _mark_document_failed(doc: Document, error_message: str, db: Session) -> None:
    """علامت‌گذاری سند به عنوان failed در صورت خطا"""
    extra = dict(doc.extra_info or {})
    extra["tax_workspace"] = True
    extra["tax_status"] = "failed"
    extra["tax_error_message"] = error_message
    extra["tax_last_send_at"] = datetime.datetime.utcnow().isoformat()
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

