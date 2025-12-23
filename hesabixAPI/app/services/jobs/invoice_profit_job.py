"""
Background job برای محاسبه مجدد سود فاکتورهای قدیمی
"""
from __future__ import annotations

import logging
from typing import Optional, List
from decimal import Decimal

from adapters.db.session import get_db_session
from adapters.db.models.document import Document
from adapters.db.models.business import Business
from app.services.invoice_service import _calculate_invoice_profit, SUPPORTED_INVOICE_TYPES

logger = logging.getLogger(__name__)


def recalculate_invoice_profits_job(
    business_id: int,
    user_id: int,
    invoice_ids: Optional[List[int]] = None,
    document_type: Optional[str] = None,
    fiscal_year_id: Optional[int] = None,
    batch_size: int = 100,
    **kwargs
) -> dict:
    """
    محاسبه مجدد سود فاکتورهای قدیمی در background
    
    توجه: این job فقط سود را محاسبه می‌کند و بررسی می‌کند.
    سود به صورت on-demand در invoice_document_to_dict محاسبه می‌شود.
    این job برای تست و بررسی استفاده می‌شود.
    """
    try:
        with get_db_session() as db:
            business = db.query(Business).filter(Business.id == business_id).first()
            if not business:
                return {
                    "success": False,
                    "error": "Business not found",
                    "processed": 0
                }
            
            # بررسی اینکه محاسبه سود فعال است
            if business.invoice_profit_calculation_method == "disabled":
                return {
                    "success": True,
                    "message": "Profit calculation is disabled for this business",
                    "processed": 0,
                    "skipped": 0
                }
            
            # ساخت query
            query = db.query(Document).filter(Document.business_id == business_id)
            query = query.filter(Document.document_type.in_(SUPPORTED_INVOICE_TYPES))
            
            if invoice_ids:
                query = query.filter(Document.id.in_(invoice_ids))
            if document_type:
                query = query.filter(Document.document_type == document_type)
            if fiscal_year_id:
                query = query.filter(Document.fiscal_year_id == fiscal_year_id)
            
            # فقط فاکتورهای فروش و تولید
            query = query.filter(
                Document.document_type.in_(["invoice_sales", "invoice_sales_return", "invoice_production"])
            )
            
            total_invoices = query.count()
            # پردازش همه فاکتورها (نه فقط batch_size)
            invoices = query.all()
            
            logger.info(f"Starting profit recalculation job for {len(invoices)} invoices (business_id={business_id})")
            
            processed = 0
            skipped = 0
            errors = []
            
            for doc in invoices:
                try:
                    # محاسبه سود (برای بررسی)
                    profit_data = _calculate_invoice_profit(
                        db,
                        business_id,
                        doc.id,
                        business.invoice_profit_calculation_method or "automatic",
                        business.invoice_profit_calculation_basis or "purchase_price",
                        business.invoice_profit_include_overhead or False,
                        business.invoice_profit_overhead_type or "none",
                        Decimal(str(business.invoice_profit_overhead_percent or 0)) if business.invoice_profit_overhead_percent else None,
                        business.invoice_profit_calculation_type or "gross"
                    )
                    
                    # بررسی اینکه آیا سود محاسبه شده است
                    if profit_data and (profit_data.get("gross_profit") is not None or profit_data.get("net_profit") is not None):
                        processed += 1
                    else:
                        skipped += 1
                        errors.append({
                            "invoice_id": doc.id,
                            "invoice_code": doc.code,
                            "error": "سود محاسبه نشد (نتیجه خالی)"
                        })
                        logger.warning(f"Empty profit result for invoice {doc.id} (code: {doc.code})")
                    
                    # Log هر 100 فاکتور
                    if (processed + skipped) % 100 == 0:
                        logger.info(f"Progress: processed={processed}, skipped={skipped}, total={processed + skipped}/{len(invoices)}")
                        
                except Exception as e:
                    skipped += 1
                    error_msg = str(e)
                    errors.append({
                        "invoice_id": doc.id,
                        "invoice_code": doc.code,
                        "error": error_msg
                    })
                    logger.error(f"Error calculating profit for invoice {doc.id} (code: {doc.code}): {e}", exc_info=True)
            
            logger.info(f"Profit recalculation job completed: processed={processed}, skipped={skipped}, total={total_invoices}")
            
            return {
                "success": True,
                "message": f"Profit recalculated for {processed} invoices",
                "processed": processed,
                "skipped": skipped,
                "total": total_invoices,
                "errors_count": len(errors),
                "errors": errors[:20] if errors else []  # فقط 20 خطای اول
            }
            
    except Exception as e:
        logger.error(f"Error in recalculate_invoice_profits_job: {e}", exc_info=True)
        return {
            "success": False,
            "error": str(e),
            "processed": 0
        }

