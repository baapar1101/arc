"""
Background jobs برای سیستم مالیاتی
"""

from __future__ import annotations

import asyncio
import logging
from datetime import datetime

from adapters.db.session import get_db_session
from app.services.tax_auto_inquiry_service import auto_inquire_pending_invoices

logger = logging.getLogger(__name__)


async def tax_auto_inquiry_loop(interval_minutes: int = 30) -> None:
    """
    Background loop برای استعلام خودکار وضعیت فاکتورهای pending
    هر interval_minutes دقیقه یکبار اجرا می‌شود (پیش‌فرض: 30 دقیقه)
    """
    interval_seconds = interval_minutes * 60
    
    while True:
        try:
            def _inquire_pending() -> dict:
                """استعلام وضعیت فاکتورهای pending در thread جداگانه"""
                try:
                    with get_db_session() as db:
                        result = auto_inquire_pending_invoices(
                            db,
                            business_id=None,  # همه کسب‌وکارها
                            max_invoices=50,  # حداکثر 50 فاکتور در هر اجرا
                            hours_ago=24,  # فاکتورهایی که بیش از 24 ساعت در pending هستند
                        )
                        return result
                except Exception as e:
                    logger.error(f"Error in auto inquiry: {e}", exc_info=True)
                    return {"success": False, "error": str(e)}
            
            # اجرا در thread جداگانه
            result = await asyncio.to_thread(_inquire_pending)
            
            if result.get("success") and result.get("total_inquired", 0) > 0:
                logger.info(
                    f"Tax auto-inquiry completed: {result.get('total_inquired')} invoices inquired "
                    f"(checked {result.get('total_checked')} pending invoices)"
                )
            elif result.get("total_checked", 0) > 0:
                logger.debug(
                    f"Tax auto-inquiry: {result.get('total_checked')} pending invoices checked, "
                    f"{result.get('total_inquired')} inquired"
                )
                
        except Exception as e:
            logger.error(f"Error in tax auto-inquiry loop: {e}", exc_info=True)
        
        await asyncio.sleep(interval_seconds)

