"""
سرویس استعلام خودکار وضعیت فاکتورهای مالیاتی
"""

from __future__ import annotations

import logging
from typing import Dict, Any, List
from datetime import datetime, timedelta

from sqlalchemy.orm import Session
from sqlalchemy import and_

from adapters.db.models.document import Document
from adapters.db.models.tax_setting import TaxSetting
from app.services.tax_submission_service import inquire_tax_status

logger = logging.getLogger(__name__)


def auto_inquire_pending_invoices(
    db: Session,
    business_id: int | None = None,
    max_invoices: int = 100,
    hours_ago: int = 24,
) -> Dict[str, Any]:
    """
    استعلام خودکار وضعیت فاکتورهای pending که بیش از hours_ago ساعت در pending هستند
    
    Args:
        db: Database session
        business_id: شناسه کسب‌وکار (اگر None باشد، همه کسب‌وکارها)
        max_invoices: حداکثر تعداد فاکتور برای استعلام
        hours_ago: فاکتورهایی که بیش از این ساعت در pending هستند
    
    Returns:
        نتیجه استعلام
    """
    cutoff_time = datetime.utcnow() - timedelta(hours=hours_ago)
    
    # ساخت query برای فاکتورهای pending
    query = db.query(Document).filter(
        Document.extra_info.isnot(None)
    )
    
    # فیلتر بر اساس business_id
    if business_id:
        query = query.filter(Document.business_id == business_id)
    
    # فیلتر فاکتورهای pending
    # استفاده از JSON_EXTRACT یا LIKE برای بررسی extra_info
    from sqlalchemy import func
    
    # دریافت تمام فاکتورها و فیلتر در Python (بهتر از JSON query در MySQL)
    all_docs = query.all()
    pending_docs: List[Document] = []
    
    for doc in all_docs:
        extra = doc.extra_info or {}
        if not isinstance(extra, dict):
            continue
        
        tax_status = extra.get("tax_status", "").strip() if isinstance(extra.get("tax_status"), str) else extra.get("tax_status")
        tax_workspace = bool(extra.get("tax_workspace"))
        tracking_code = extra.get("tax_tracking_code")
        
        # فقط فاکتورهای pending با tracking code
        if (
            tax_workspace and
            tax_status == "pending" and
            tracking_code and
            isinstance(tracking_code, str) and
            tracking_code.strip()
        ):
            # بررسی زمان آخرین ارسال
            last_send_at = extra.get("tax_last_send_at")
            if last_send_at:
                try:
                    if isinstance(last_send_at, str):
                        send_time = datetime.fromisoformat(last_send_at.replace('Z', '+00:00'))
                    else:
                        send_time = last_send_at
                    
                    if send_time < cutoff_time:
                        pending_docs.append(doc)
                except Exception:
                    # اگر زمان نامعتبر بود، اضافه می‌کنیم
                    pending_docs.append(doc)
            else:
                # اگر زمان ارسال نداشت، اضافه می‌کنیم
                pending_docs.append(doc)
    
    if not pending_docs:
        return {
            "success": True,
            "total_checked": 0,
            "total_inquired": 0,
            "results": [],
        }
    
    # محدود کردن تعداد
    pending_docs = pending_docs[:max_invoices]
    
    # گروه‌بندی بر اساس business_id
    by_business: Dict[int, List[Document]] = {}
    for doc in pending_docs:
        if doc.business_id not in by_business:
            by_business[doc.business_id] = []
        by_business[doc.business_id].append(doc)
    
    total_inquired = 0
    all_results: List[Dict[str, Any]] = []
    
    # استعلام برای هر کسب‌وکار
    for bid, docs in by_business.items():
        try:
            # دریافت تنظیمات مالیاتی
            tax_setting = (
                db.query(TaxSetting)
                .filter(TaxSetting.business_id == bid)
                .first()
            )
            
            if not tax_setting:
                logger.warning(f"Tax settings not found for business {bid}")
                continue
            
            # جمع‌آوری tracking codes
            tracking_codes: List[str] = []
            doc_by_tracking: Dict[str, Document] = {}
            
            for doc in docs:
                code = (doc.extra_info or {}).get("tax_tracking_code")
                if code and isinstance(code, str) and code.strip():
                    tracking_codes.append(code.strip())
                    doc_by_tracking[code.strip()] = doc
            
            if not tracking_codes:
                continue
            
            # استعلام وضعیت
            try:
                from app.core.settings import get_settings
                from app.integrations.moadian.client import MoadianClient
                
                client = MoadianClient(settings=get_settings(), tax_setting=tax_setting)
                try:
                    response = client.inquire_status(tracking_codes)
                    results = response.get("results") or []
                    
                    # به‌روزرسانی وضعیت فاکتورها
                    now = datetime.utcnow().isoformat()
                    for item in results:
                        reference = item.get("reference_number") or item.get("tracking_code")
                        if not reference:
                            continue
                        
                        doc = doc_by_tracking.get(str(reference))
                        if not doc:
                            continue
                        
                        extra = dict(doc.extra_info or {})
                        from app.services.tax_submission_service import _map_inquiry_status
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
                        
                        all_results.append({
                            "invoice_id": doc.id,
                            "business_id": bid,
                            "tracking_code": reference,
                            "status": mapped_status or item.get("status"),
                        })
                    
                    total_inquired += len(results)
                    db.commit()
                    
                finally:
                    client.close()
                    
            except Exception as e:
                logger.error(f"Error inquiring status for business {bid}: {e}", exc_info=True)
                db.rollback()
                continue
                
        except Exception as e:
            logger.error(f"Error processing business {bid}: {e}", exc_info=True)
            continue
    
    return {
        "success": True,
        "total_checked": len(pending_docs),
        "total_inquired": total_inquired,
        "results": all_results,
        "completed_at": datetime.utcnow().isoformat(),
    }

