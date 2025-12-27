"""
Audit Trail برای عملیات مالیاتی
"""

from __future__ import annotations

import logging
from typing import Dict, Any, Optional, List
from datetime import datetime

from sqlalchemy.orm import Session
from adapters.db.models.document import Document

logger = logging.getLogger(__name__)


def log_tax_audit_event(
    db: Session,
    business_id: int,
    invoice_id: Optional[int],
    action: str,
    user_id: Optional[int],
    details: Optional[Dict[str, Any]] = None,
    ip_address: Optional[str] = None,
    user_agent: Optional[str] = None,
) -> None:
    """
    ثبت رویداد در Audit Trail
    
    Actions:
        - add_to_workspace
        - remove_from_workspace
        - send_to_system
        - inquire_status
        - validate
        - retry
        - mark_resolved
    
    Args:
        db: Database session
        business_id: شناسه کسب‌وکار
        invoice_id: شناسه فاکتور (اختیاری)
        action: نوع عملیات
        user_id: شناسه کاربر
        details: جزئیات اضافی
        ip_address: آدرس IP
        user_agent: User Agent
    """
    # ذخیره در extra_info فاکتور (اگر invoice_id موجود باشد)
    if invoice_id:
        try:
            doc = db.query(Document).filter(
                Document.id == invoice_id,
                Document.business_id == business_id,
            ).first()
            
            if doc:
                extra = dict(doc.extra_info or {})
                
                # ایجاد یا به‌روزرسانی audit trail
                if "tax_audit_trail" not in extra:
                    extra["tax_audit_trail"] = []
                
                audit_entry = {
                    "action": action,
                    "timestamp": datetime.utcnow().isoformat(),
                    "user_id": user_id,
                    "details": details or {},
                }
                
                if ip_address:
                    audit_entry["ip_address"] = ip_address
                if user_agent:
                    audit_entry["user_agent"] = user_agent
                
                extra["tax_audit_trail"].append(audit_entry)
                
                # نگه داشتن فقط 50 رویداد آخر
                if len(extra["tax_audit_trail"]) > 50:
                    extra["tax_audit_trail"] = extra["tax_audit_trail"][-50:]
                
                doc.extra_info = extra
                db.add(doc)
        except Exception as e:
            logger.warning(f"Failed to log audit trail: {e}")
    
    # همچنین در structured logging
    from app.services.tax_logging import log_tax_operation
    log_tax_operation(
        operation=f"audit_{action}",
        business_id=business_id,
        invoice_id=invoice_id,
        status="completed",
        details={
            **(details or {}),
            "user_id": user_id,
            "ip_address": ip_address,
        },
    )


def get_tax_audit_trail(
    db: Session,
    business_id: int,
    invoice_id: Optional[int] = None,
) -> List[Dict[str, Any]]:
    """
    دریافت Audit Trail
    
    Args:
        db: Database session
        business_id: شناسه کسب‌وکار
        invoice_id: شناسه فاکتور (اختیاری)
    
    Returns:
        لیست رویدادهای audit
    """
    if invoice_id:
        doc = db.query(Document).filter(
            Document.id == invoice_id,
            Document.business_id == business_id,
        ).first()
        
        if doc:
            extra = dict(doc.extra_info or {})
            return extra.get("tax_audit_trail", [])
    
    return []




