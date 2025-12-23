"""
Structured Logging برای عملیات مالیاتی
"""

from __future__ import annotations

import logging
import json
from typing import Dict, Any, Optional
from datetime import datetime

logger = logging.getLogger(__name__)


def log_tax_operation(
    operation: str,
    business_id: int,
    invoice_id: Optional[int] = None,
    tracking_code: Optional[str] = None,
    status: str = "started",
    details: Optional[Dict[str, Any]] = None,
    error: Optional[str] = None,
    user_id: Optional[int] = None,
) -> None:
    """
    ثبت لاگ ساختاریافته برای عملیات مالیاتی
    
    Args:
        operation: نوع عملیات (send_invoice, inquire_status, validate, etc.)
        business_id: شناسه کسب‌وکار
        invoice_id: شناسه فاکتور (اختیاری)
        tracking_code: کد رهگیری (اختیاری)
        status: وضعیت (started, completed, failed)
        details: جزئیات اضافی
        error: پیام خطا (در صورت وجود)
        user_id: شناسه کاربر
    """
    log_data = {
        "timestamp": datetime.utcnow().isoformat(),
        "operation": operation,
        "business_id": business_id,
        "status": status,
    }
    
    if invoice_id:
        log_data["invoice_id"] = invoice_id
    if tracking_code:
        log_data["tracking_code"] = tracking_code
    if user_id:
        log_data["user_id"] = user_id
    if details:
        log_data["details"] = details
    if error:
        log_data["error"] = error
    
    # استفاده از structured logging
    if status == "failed" or error:
        logger.error(f"TAX_OP: {json.dumps(log_data, ensure_ascii=False)}")
    elif status == "completed":
        logger.info(f"TAX_OP: {json.dumps(log_data, ensure_ascii=False)}")
    else:
        logger.debug(f"TAX_OP: {json.dumps(log_data, ensure_ascii=False)}")


def log_tax_batch_operation(
    operation: str,
    business_id: int,
    total_count: int,
    succeeded_count: int,
    failed_count: int,
    job_id: Optional[str] = None,
    user_id: Optional[int] = None,
    details: Optional[Dict[str, Any]] = None,
) -> None:
    """
    ثبت لاگ برای عملیات گروهی
    
    Args:
        operation: نوع عملیات
        business_id: شناسه کسب‌وکار
        total_count: تعداد کل
        succeeded_count: تعداد موفق
        failed_count: تعداد ناموفق
        job_id: شناسه job (در صورت استفاده از background job)
        user_id: شناسه کاربر
        details: جزئیات اضافی
    """
    log_data = {
        "timestamp": datetime.utcnow().isoformat(),
        "operation": operation,
        "business_id": business_id,
        "total_count": total_count,
        "succeeded_count": succeeded_count,
        "failed_count": failed_count,
        "status": "completed" if failed_count == 0 else "partial_failure",
    }
    
    if job_id:
        log_data["job_id"] = job_id
    if user_id:
        log_data["user_id"] = user_id
    if details:
        log_data["details"] = details
    
    if failed_count == 0:
        logger.info(f"TAX_BATCH: {json.dumps(log_data, ensure_ascii=False)}")
    else:
        logger.warning(f"TAX_BATCH: {json.dumps(log_data, ensure_ascii=False)}")

