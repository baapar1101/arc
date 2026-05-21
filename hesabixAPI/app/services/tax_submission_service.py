from __future__ import annotations

import datetime
import logging
import time
from typing import Dict, Any, List

from sqlalchemy import cast
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Session

from adapters.db.models.document import Document
from adapters.db.models.tax_setting import TaxSetting
from app.core.responses import ApiError
from app.core.settings import get_settings
from app.integrations.moadian.client import MoadianClient
from app.integrations.moadian.invoice_builder import build_invoice_for_moadian
from app.services.invoice_service import invoice_document_to_dict
from app.services.tax_validation_service import validate_document_for_tax, validate_tax_submission_scenario
from app.integrations.moadian.utils import extract_moadian_error_message
from app.services.tax_reference_service import (
    resolve_irtaxid,
    compute_taxid_for_document,
    persist_taxid_on_document,
    get_document_extra,
)
from app.core.moadian_plugin_dependency import ensure_moadian_plugin_active

logger = logging.getLogger(__name__)


def _documents_by_tracking_codes(
    db: Session,
    business_id: int,
    tracking_codes: List[str],
) -> Dict[str, Document]:
    """یافتن اسناد بر اساس کد رهگیری ذخیره‌شده در extra_info."""
    codes = {str(c).strip() for c in tracking_codes if c and str(c).strip()}
    if not codes:
        return {}

    _extra_info_jb = cast(Document.extra_info, JSONB)
    docs = (
        db.query(Document)
        .filter(
            Document.business_id == business_id,
            _extra_info_jb["tax_tracking_code"].astext.in_(sorted(codes)),
        )
        .all()
    )
    mapping: Dict[str, Document] = {}
    for doc in docs:
        code = (doc.extra_info or {}).get("tax_tracking_code")
        if code:
            mapping[str(code)] = doc
    return mapping


def _extract_inquiry_error_message(item: Dict[str, Any]) -> str | None:
    if item.get("error_message"):
        return str(item["error_message"])
    raw = item.get("raw_data")
    if not isinstance(raw, dict):
        return None
    data = raw.get("data")
    if not isinstance(data, dict):
        return None
    errors = data.get("error")
    if isinstance(errors, list) and errors:
        first = errors[0] if isinstance(errors[0], dict) else {}
        return extract_moadian_error_message(first)
    return None


def _apply_inquiry_result_to_document(doc: Document, item: Dict[str, Any], *, now: str) -> None:
    extra = dict(doc.extra_info or {})
    mapped_status = _map_inquiry_status(item.get("status"))
    if mapped_status:
        extra["tax_status"] = mapped_status
    error_message = _extract_inquiry_error_message(item)
    status_norm = str(item.get("status") or "").lower()
    if error_message:
        extra["tax_error_message"] = error_message
    elif status_norm in ("failed", "error"):
        extra["tax_error_message"] = extra.get("tax_error_message") or "رد شده توسط سامانه مودیان"
    elif mapped_status not in ("failed",):
        extra.pop("tax_error_message", None)
    extra["tax_last_inquiry_at"] = now
    if item.get("raw_data"):
        extra["tax_last_inquiry_response"] = item.get("raw_data")
    doc.extra_info = extra


def _resolve_submission_mode(document: Document, submission_mode: str | None) -> str:
    mode = (submission_mode or "").strip().lower()
    doc_type = (document.document_type or "").lower()
    if mode in ("normal", "return", "cancel", "corrective"):
        return mode
    if "return" in doc_type:
        return "return"
    return "normal"


def send_document_to_tax_system(
    db: Session,
    document: Document,
    *,
    submission_mode: str | None = None,
) -> Dict[str, Any]:
    """
    نقطه ورود اصلی ارسال سند به سامانه مودیان.
    """
    ensure_moadian_plugin_active(db, int(document.business_id))
    mode = _resolve_submission_mode(document, submission_mode)

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

    scenario = validate_tax_submission_scenario(db, document, tax_setting, mode)
    if not scenario["valid"]:
        raise ApiError(
            "TAX_VALIDATION_FAILED",
            "اعتبارسنجی سناریوی ارسال به مودیان ناموفق بود.",
            http_status=400,
            details={"issues": scenario["issues"], "submission_mode": mode},
        )

    irtaxid: str | None = None
    if mode == "return":
        irtaxid = resolve_irtaxid(db, document.business_id, document, tax_setting)
    elif mode == "cancel":
        irtaxid = compute_taxid_for_document(document, tax_setting)
    elif mode == "corrective":
        irtaxid = compute_taxid_for_document(document, tax_setting)

    raw_document = invoice_document_to_dict(db, document)
    if mode in ("cancel", "corrective"):
        # صورتحساب ابطال/اصلاح باید taxid جدید داشته باشد؛ مرجع در irtaxid است.
        raw_document["_tax_internal_id_override"] = int(
            f"{document.id}{1 if mode == 'cancel' else 2}"
        )

    invoice_dto = build_invoice_for_moadian(
        raw_document,
        tax_setting,
        submission_mode=mode,
        irtaxid=irtaxid,
    )

    if mode == "normal":
        taxid = compute_taxid_for_document(document, tax_setting)
        persist_taxid_on_document(document, taxid, db)

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
                # 6. ذخیره نتیجه اولیه (صف async)
                _apply_submission_result(document, submission, db, submission_mode=mode)

                # 6.5 استعلام فوری: «sent» یعنی پذیرش در صف، نه ثبت نهایی در کارپوشه مودیان
                tracking_code = submission.get("tracking_code")
                if tracking_code and submission.get("mode") == "live":
                    try:
                        inquiry = client.inquire_status([str(tracking_code)])
                        for item in inquiry.get("results") or []:
                            _apply_inquiry_result_to_document(
                                document,
                                item,
                                now=datetime.datetime.utcnow().isoformat(),
                            )
                            db.add(document)
                            db.flush()
                            mapped = _map_inquiry_status(item.get("status"))
                            if mapped == "failed":
                                err = _extract_inquiry_error_message(item)
                                submission["status"] = "failed"
                                if err:
                                    submission["error_message"] = err
                                submission["inquiry"] = item
                    except Exception as inquiry_exc:
                        logger.warning(
                            "Post-send tax inquiry failed for document %s: %s",
                            document.id,
                            inquiry_exc,
                        )
                
                final_status = (document.extra_info or {}).get("tax_status") or submission.get("status")
                log_status = "failed" if final_status == "failed" else "completed"
                from app.services.tax_logging import log_tax_operation
                log_tax_operation(
                    operation="send_invoice",
                    business_id=document.business_id,
                    invoice_id=document.id,
                    tracking_code=tracking_code,
                    status=log_status,
                    details={"status": final_status, "mode": submission.get("mode")},
                    error=submission.get("error_message") if log_status == "failed" else None,
                )

                # وضعیت failed در extra_info ذخیره شده؛ endpoint پس از commit خطا برمی‌گرداند
                if final_status == "failed":
                    submission["status"] = "failed"
                    submission.setdefault(
                        "error_message",
                        "فاکتور توسط سامانه مودیان رد شد.",
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
    ensure_moadian_plugin_active(db, business_id)
    invoice_ids = invoice_ids or []
    tracking_codes = tracking_codes or []

    if not invoice_ids and not tracking_codes:
        raise ApiError("INVALID_REQUEST", "لیست فاکتورها یا کد رهگیری لازم است.", http_status=400)

    doc_by_tracking: Dict[str, Document] = {}
    if invoice_ids:
        docs = (
            db.query(Document)
            .filter(Document.business_id == business_id, Document.id.in_(invoice_ids))
            .all()
        )
        for doc in docs:
            code = (doc.extra_info or {}).get("tax_tracking_code")
            if code:
                doc_by_tracking[str(code)] = doc

    merged_codes = {str(code).strip() for code in tracking_codes if code and str(code).strip()}
    merged_codes.update(doc_by_tracking.keys())
    if merged_codes:
        doc_by_tracking.update(_documents_by_tracking_codes(db, business_id, sorted(merged_codes)))

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

    results = [_enrich_inquiry_result_item(item) for item in (response.get("results") or [])]
    now = datetime.datetime.utcnow().isoformat()
    for item in results:
        reference = item.get("reference_number") or item.get("tracking_code")
        if not reference:
            continue
        doc = doc_by_tracking.get(str(reference))
        if not doc:
            continue
        _apply_inquiry_result_to_document(doc, item, now=now)
        db.add(doc)

    return {
        "mode": response.get("mode"),
        "results": results,
    }


def enrich_tax_timeline_event(event: Dict[str, Any], extra: dict | None) -> Dict[str, Any]:
    """افزودن خطاها به رویدادهای تایم‌لاین."""
    enriched = dict(event)
    if event.get("event") in ("send_attempt", "status_inquiry", "failed"):
        for err in extract_moadian_errors_from_extra(extra):
            if err.get("message") and not enriched.get("error_message"):
                enriched["error_message"] = err["message"]
                break
        errors = extract_moadian_errors_from_extra(extra)
        if errors:
            enriched["moadian_errors"] = errors
    return enriched


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


def _apply_submission_result(
    doc: Document,
    submission: Dict[str, Any],
    db: Session,
    *,
    submission_mode: str = "normal",
) -> None:
    extra = dict(doc.extra_info or {})
    extra["tax_workspace"] = True
    extra["tax_status"] = submission.get("status") or "sent"
    extra["tax_tracking_code"] = submission.get("tracking_code") or extra.get("tax_tracking_code")
    extra["tax_last_send_at"] = submission.get("sent_at") or datetime.datetime.utcnow().isoformat()
    extra["tax_last_submission_mode"] = submission_mode
    if submission_mode == "cancel":
        extra["tax_cancelled_in_modian"] = True
        extra["tax_cancelled_at"] = extra["tax_last_send_at"]
    if submission_mode == "corrective":
        extra["tax_corrective_sent_at"] = extra["tax_last_send_at"]
    if "raw_response" in submission:
        extra["tax_last_response"] = submission["raw_response"]
    if submission.get("error_message"):
        extra["tax_error_message"] = submission["error_message"]
    else:
        extra.pop("tax_error_message", None)
    doc.extra_info = extra
    db.add(doc)


def cancel_document_in_tax_system(db: Session, document: Document) -> Dict[str, Any]:
    """ابطال صورتحساب ارسال‌شده در سامانه مودیان (inp=3)."""
    return send_document_to_tax_system(db, document, submission_mode="cancel")


def send_corrective_to_tax_system(db: Session, document: Document) -> Dict[str, Any]:
    """ارسال صورتحساب اصلاحی (inp=4) برای فاکتور ارسال‌شده."""
    return send_document_to_tax_system(db, document, submission_mode="corrective")


def extract_moadian_errors_from_extra(extra: dict | None) -> List[Dict[str, Any]]:
    """استخراج خطاهای سامانه از extra_info برای نمایش در API/UI."""
    if not extra:
        return []
    seen: set[str] = set()
    errors: List[Dict[str, Any]] = []

    def _add(code: Any, message: Any) -> None:
        msg = str(message or "").strip()
        if not msg:
            return
        key = f"{code}|{msg}"
        if key in seen:
            return
        seen.add(key)
        errors.append({"code": str(code).strip() if code else None, "message": msg})

    summary = extra.get("tax_error_message")
    if summary:
        _add(None, summary)

    for source_key in ("tax_last_inquiry_response", "tax_last_response"):
        raw = extra.get(source_key)
        if not isinstance(raw, dict):
            continue
        data = raw.get("data")
        if isinstance(data, dict):
            err_list = data.get("error")
            if isinstance(err_list, list):
                for item in err_list:
                    if isinstance(item, dict):
                        _add(item.get("code"), item.get("message") or item.get("errorDetail"))
        top_status = raw.get("status")
        if str(top_status or "").upper() == "FAILED" and not errors:
            _add(raw.get("errorCode"), raw.get("errorDetail"))

    return errors


def build_tax_status_fields_for_api(extra: dict | None) -> Dict[str, Any]:
    """فیلدهای مالیاتی قابل نمایش در لیست/جزئیات."""
    extra = extra or {}
    fields: Dict[str, Any] = {
        "tax_error_message": extra.get("tax_error_message"),
        "tax_last_inquiry_at": extra.get("tax_last_inquiry_at"),
        "tax_moadian_taxid": extra.get("tax_moadian_taxid"),
        "tax_last_submission_mode": extra.get("tax_last_submission_mode"),
        "tax_cancelled_in_modian": bool(extra.get("tax_cancelled_in_modian")),
        "tax_cancelled_at": extra.get("tax_cancelled_at"),
        "tax_corrective_sent_at": extra.get("tax_corrective_sent_at"),
        "reference_invoice_id": extra.get("reference_invoice_id"),
        "reference_tax_id": extra.get("reference_tax_id"),
    }
    moadian_errors = extract_moadian_errors_from_extra(extra)
    if moadian_errors:
        fields["tax_moadian_errors"] = moadian_errors
    return fields


def build_tax_failure_details(
    extra: dict | None,
    submission: Dict[str, Any] | None = None,
) -> Dict[str, Any]:
    """جزئیات خطای ارسال برای پاسخ API."""
    extra = extra or {}
    submission = submission or {}
    details: Dict[str, Any] = {
        "tax_status": extra.get("tax_status"),
        "tax_tracking_code": extra.get("tax_tracking_code") or submission.get("tracking_code"),
        "tax_error_message": extra.get("tax_error_message") or submission.get("error_message"),
        "moadian_errors": extract_moadian_errors_from_extra(extra),
    }
    inquiry = submission.get("inquiry")
    if isinstance(inquiry, dict):
        details["inquiry"] = inquiry
        if not details["moadian_errors"]:
            err = _extract_inquiry_error_message(inquiry)
            if err:
                details["moadian_errors"] = [{"code": None, "message": err}]
    raw_inquiry = extra.get("tax_last_inquiry_response")
    if isinstance(raw_inquiry, dict):
        details["inquiry_response"] = raw_inquiry
    raw_send = extra.get("tax_last_response")
    if isinstance(raw_send, dict):
        details["send_response"] = raw_send
    return details


def _enrich_inquiry_result_item(item: Dict[str, Any]) -> Dict[str, Any]:
    """تکمیل پیام خطا در هر آیتم استعلام."""
    enriched = dict(item)
    if not enriched.get("error_message"):
        err = _extract_inquiry_error_message(enriched)
        if err:
            enriched["error_message"] = err
    raw = enriched.get("raw_data")
    if isinstance(raw, dict) and not enriched.get("moadian_errors"):
        errors = extract_moadian_errors_from_extra({"tax_last_inquiry_response": raw})
        if errors:
            enriched["moadian_errors"] = errors
    return enriched


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

