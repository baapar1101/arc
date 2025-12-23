"""
Background Job برای ارسال فاکتورها به سامانه مالیاتی
"""

from __future__ import annotations

import logging
from typing import Any, Dict, List

logger = logging.getLogger(__name__)


def send_tax_invoice_job(
    business_id: int,
    invoice_id: int,
    user_id: int,
) -> Dict[str, Any]:
    """
    ارسال یک فاکتور به سامانه مالیاتی به صورت background job
    
    Args:
        business_id: شناسه کسب‌وکار
        invoice_id: شناسه فاکتور
        user_id: شناسه کاربر
    
    Returns:
        نتیجه ارسال
    """
    try:
        from adapters.db.session import get_db_session
        from adapters.db.models.document import Document
        from app.services.tax_submission_service import send_document_to_tax_system
        from datetime import datetime
        
        logger.info(f"Sending invoice {invoice_id} to tax system (business {business_id})")
        
        with get_db_session() as db:
            # دریافت فاکتور
            doc = db.query(Document).filter(
                Document.id == invoice_id,
                Document.business_id == business_id
            ).first()
            
            if not doc:
                raise Exception(f"Invoice {invoice_id} not found")
            
            # ارسال به سامانه
            submission = send_document_to_tax_system(db, doc)
            db.commit()
            
            result = {
                "success": True,
                "invoice_id": invoice_id,
                "business_id": business_id,
                "tracking_code": submission.get("tracking_code"),
                "status": submission.get("status"),
                "sent_at": submission.get("sent_at") or datetime.utcnow().isoformat(),
            }
            
            logger.info(f"Invoice {invoice_id} sent successfully. Tracking: {submission.get('tracking_code')}")
            return result
        
    except Exception as e:
        logger.error(f"Error sending invoice {invoice_id} to tax system: {e}", exc_info=True)
        raise


def send_tax_invoices_batch_job(
    business_id: int,
    invoice_ids: List[int],
    user_id: int,
) -> Dict[str, Any]:
    """
    ارسال گروهی فاکتورها به سامانه مالیاتی به صورت background job
    
    Args:
        business_id: شناسه کسب‌وکار
        invoice_ids: لیست شناسه فاکتورها
        user_id: شناسه کاربر
    
    Returns:
        نتیجه ارسال شامل succeeded و failed
    """
    try:
        from adapters.db.session import get_db_session
        from adapters.db.models.document import Document
        from app.services.tax_submission_service import send_document_to_tax_system
        from app.core.responses import ApiError
        from datetime import datetime
        
        logger.info(f"Sending {len(invoice_ids)} invoices to tax system (business {business_id})")
        
        succeeded: List[int] = []
        failed: List[Dict[str, Any]] = []
        
        with get_db_session() as db:
            for invoice_id in invoice_ids:
                try:
                    # دریافت فاکتور
                    doc = db.query(Document).filter(
                        Document.id == invoice_id,
                        Document.business_id == business_id
                    ).first()
                    
                    if not doc:
                        failed.append({
                            "id": invoice_id,
                            "error": "NOT_FOUND",
                            "message": "فاکتور یافت نشد"
                        })
                        continue
                    
                    # ارسال به سامانه
                    submission = send_document_to_tax_system(db, doc)
                    succeeded.append(invoice_id)
                    
                    logger.debug(f"Invoice {invoice_id} sent successfully")
                    
                except ApiError as e:
                    error_detail = getattr(e, "detail", {}) or {}
                    error_info = error_detail.get("error") if isinstance(error_detail, dict) else {}
                    failed.append({
                        "id": invoice_id,
                        "error": (error_info or {}).get("code") or str(e),
                        "message": (error_info or {}).get("message") or str(e),
                        "issues": (error_info or {}).get("details", {}).get("issues")
                        if isinstance((error_info or {}).get("details"), dict)
                        else None,
                    })
                    logger.warning(f"Invoice {invoice_id} failed: {e}")
                except Exception as e:
                    failed.append({
                        "id": invoice_id,
                        "error": "UNKNOWN_ERROR",
                        "message": str(e)
                    })
                    logger.error(f"Unexpected error sending invoice {invoice_id}: {e}", exc_info=True)
            
            db.commit()
        
        result = {
            "success": True,
            "business_id": business_id,
            "total": len(invoice_ids),
            "succeeded": succeeded,
            "failed": failed,
            "succeeded_count": len(succeeded),
            "failed_count": len(failed),
            "completed_at": datetime.utcnow().isoformat(),
        }
        
        logger.info(
            f"Batch tax submission completed: {len(succeeded)} succeeded, {len(failed)} failed "
            f"(business {business_id})"
        )
        
        return result
        
    except Exception as e:
        logger.error(f"Error in batch tax submission job: {e}", exc_info=True)
        raise

