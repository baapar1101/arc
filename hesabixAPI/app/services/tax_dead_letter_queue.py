"""
Dead Letter Queue برای فاکتورهای failed
"""

from __future__ import annotations

import logging
from typing import Dict, Any, List, Optional
from datetime import datetime

from sqlalchemy.orm import Session
from adapters.db.models.tax_failed_invoice import TaxFailedInvoice
from adapters.db.models.document import Document

logger = logging.getLogger(__name__)


def add_to_dead_letter_queue(
    db: Session,
    business_id: int,
    invoice_id: int,
    error_code: str,
    error_message: str,
    error_details: Optional[Dict[str, Any]] = None,
    tracking_code: Optional[str] = None,
    invoice_data: Optional[Dict[str, Any]] = None,
) -> TaxFailedInvoice:
    """
    افزودن فاکتور failed به Dead Letter Queue
    
    Args:
        db: Database session
        business_id: شناسه کسب‌وکار
        invoice_id: شناسه فاکتور
        error_code: کد خطا
        error_message: پیام خطا
        error_details: جزئیات خطا
        tracking_code: کد رهگیری (در صورت وجود)
        invoice_data: داده‌های فاکتور برای retry
    
    Returns:
        رکورد ایجاد شده
    """
    # بررسی وجود رکورد قبلی
    existing = (
        db.query(TaxFailedInvoice)
        .filter(
            TaxFailedInvoice.business_id == business_id,
            TaxFailedInvoice.invoice_id == invoice_id,
            TaxFailedInvoice.status.in_(["pending", "retrying"]),
        )
        .first()
    )
    
    if existing:
        # به‌روزرسانی رکورد موجود
        existing.error_code = error_code
        existing.error_message = error_message
        existing.error_details = error_details
        existing.tracking_code = tracking_code
        existing.attempt_count += 1
        existing.last_attempt_at = datetime.utcnow()
        existing.status = "pending"
        if invoice_data:
            existing.invoice_data = invoice_data
        db.add(existing)
        return existing
    
    # ایجاد رکورد جدید
    failed_invoice = TaxFailedInvoice(
        business_id=business_id,
        invoice_id=invoice_id,
        tracking_code=tracking_code,
        error_code=error_code,
        error_message=error_message,
        error_details=error_details,
        invoice_data=invoice_data,
        status="pending",
    )
    db.add(failed_invoice)
    return failed_invoice


def get_failed_invoices(
    db: Session,
    business_id: int,
    status: Optional[str] = None,
    limit: int = 100,
    offset: int = 0,
) -> List[TaxFailedInvoice]:
    """
    دریافت لیست فاکتورهای failed
    
    Args:
        db: Database session
        business_id: شناسه کسب‌وکار
        status: وضعیت (pending, retrying, resolved, ignored)
        limit: تعداد رکوردها
        offset: offset
    
    Returns:
        لیست فاکتورهای failed
    """
    query = db.query(TaxFailedInvoice).filter(
        TaxFailedInvoice.business_id == business_id
    )
    
    if status:
        query = query.filter(TaxFailedInvoice.status == status)
    
    return query.order_by(TaxFailedInvoice.first_failed_at.desc()).offset(offset).limit(limit).all()


def retry_failed_invoice(
    db: Session,
    failed_invoice_id: int,
) -> Dict[str, Any]:
    """
    تلاش مجدد برای ارسال فاکتور failed
    
    Args:
        db: Database session
        failed_invoice_id: شناسه رکورد failed
    
    Returns:
        نتیجه retry
    """
    failed_invoice = db.query(TaxFailedInvoice).filter(
        TaxFailedInvoice.id == failed_invoice_id
    ).first()
    
    if not failed_invoice:
        raise ValueError("Failed invoice not found")
    
    if failed_invoice.status not in ["pending", "retrying"]:
        raise ValueError(f"Cannot retry invoice with status: {failed_invoice.status}")
    
    # دریافت فاکتور
    doc = db.query(Document).filter(
        Document.id == failed_invoice.invoice_id,
        Document.business_id == failed_invoice.business_id,
    ).first()
    
    if not doc:
        failed_invoice.status = "resolved"
        failed_invoice.error_message = "فاکتور یافت نشد"
        db.add(failed_invoice)
        return {"success": False, "message": "فاکتور یافت نشد"}
    
    # تلاش برای ارسال مجدد
    failed_invoice.status = "retrying"
    db.add(failed_invoice)
    db.flush()
    
    try:
        from app.services.tax_submission_service import send_document_to_tax_system
        result = send_document_to_tax_system(db, doc)
        
        # در صورت موفقیت، حذف از dead letter queue
        db.delete(failed_invoice)
        return {"success": True, "result": result}
        
    except Exception as e:
        # در صورت خطا، به‌روزرسانی رکورد
        failed_invoice.status = "pending"
        failed_invoice.attempt_count += 1
        failed_invoice.last_attempt_at = datetime.utcnow()
        failed_invoice.error_message = str(e)
        db.add(failed_invoice)
        return {"success": False, "error": str(e)}


def mark_failed_invoice_resolved(
    db: Session,
    failed_invoice_id: int,
) -> None:
    """علامت‌گذاری فاکتور failed به عنوان resolved"""
    failed_invoice = db.query(TaxFailedInvoice).filter(
        TaxFailedInvoice.id == failed_invoice_id
    ).first()
    
    if failed_invoice:
        failed_invoice.status = "resolved"
        db.add(failed_invoice)




