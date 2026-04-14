"""
Background jobs برای مدیریت کسب و کارها
"""

from __future__ import annotations

import asyncio
import logging
from datetime import datetime

from adapters.db.session import get_db_session
from adapters.db.models.business import Business

logger = logging.getLogger(__name__)


async def check_expired_deleted_businesses_loop(interval_hours: int = 24) -> None:
    """
    Job برای بررسی کسب و کارهای حذف شده که مهلت بازیابی آن‌ها به پایان رسیده است
    
    توجه: این job حذف دائمی انجام نمی‌دهد - فقط لاگ می‌کند.
    اطلاعات کسب و کارها حفظ می‌شوند.
    
    Args:
        interval_hours: فاصله زمانی بین اجراها (به ساعت)
    """
    while True:
        try:
            def _check_expired_businesses() -> dict:
                """بررسی کسب و کارهای منقضی شده در thread جداگانه"""
                with get_db_session() as db:
                    try:
                        # پیدا کردن کسب و کارهایی که باید حذف دائمی شوند
                        cutoff_date = datetime.utcnow()
                        expired_businesses = db.query(Business).filter(
                            Business.deleted_at.isnot(None),
                            Business.auto_delete_at <= cutoff_date
                        ).all()
                        
                        expired_count = len(expired_businesses)
                        
                        if expired_count > 0:
                            # فقط لاگ می‌کنیم - حذف نمی‌کنیم
                            logger.info(
                                f"Found {expired_count} businesses with expired restore deadline",
                                extra={
                                    "expired_count": expired_count,
                                    "business_ids": [b.id for b in expired_businesses],
                                    "cutoff_date": cutoff_date.isoformat(),
                                }
                            )
                            
                            # لاگ برای هر کسب و کار
                            for business in expired_businesses:
                                logger.info(
                                    f"Business {business.id} ({business.name}) restore deadline expired",
                                    extra={
                                        "business_id": business.id,
                                        "business_name": business.name,
                                        "owner_id": business.owner_id,
                                        "deleted_at": business.deleted_at.isoformat() if business.deleted_at else None,
                                        "auto_delete_at": business.auto_delete_at.isoformat() if business.auto_delete_at else None,
                                        "days_since_deletion": (
                                            (cutoff_date - business.deleted_at).days 
                                            if business.deleted_at else None
                                        ),
                                    }
                                )
                        
                        return {
                            "expired_count": expired_count,
                            "checked_at": cutoff_date.isoformat(),
                        }
                    except Exception as e:
                        logger.error(f"Error checking expired businesses: {e}", exc_info=True)
                        return {"error": str(e)}
            
            # اجرا در thread جداگانه
            result = await asyncio.to_thread(_check_expired_businesses)
            
            if result.get("expired_count", 0) > 0:
                logger.info(
                    f"Expired businesses check completed: {result['expired_count']} businesses found",
                    extra=result
                )
        except Exception as e:
            logger.error(f"Error in expired businesses check loop: {e}", exc_info=True)
        
        # انتظار برای اجرای بعدی
        interval_seconds = interval_hours * 3600
        await asyncio.sleep(interval_seconds)

