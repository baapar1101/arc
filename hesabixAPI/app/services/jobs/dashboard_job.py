"""
Job برای پردازش dashboard widgets
"""

from __future__ import annotations

import logging
from typing import Any, Dict, Optional

logger = logging.getLogger(__name__)


def process_dashboard_widgets_job(
    business_id: int,
    user_id: int,
    widget_keys: list[str],
    filters: Optional[Dict[str, Any]] = None,
    calendar_type: str = "gregorian",
    **kwargs
) -> Dict[str, Any]:
    """
    پردازش dashboard widgets به صورت background job
    
    Args:
        business_id: شناسه کسب‌وکار
        user_id: شناسه کاربر
        widget_keys: لیست کلیدهای ویجت
        filters: فیلترها
        calendar_type: نوع تقویم
        **kwargs: سایر پارامترها
    
    Returns:
        داده‌های ویجت‌ها
    """
    try:
        from adapters.db.session import get_db_session
        from app.services.dashboard_widgets_service import get_widgets_batch_data
        
        logger.info(f"Processing dashboard widgets for business {business_id}, user {user_id}")
        
        filters = filters or {}
        
        with get_db_session() as db:
            data = get_widgets_batch_data(
                db=db,
                business_id=business_id,
                user_id=user_id,
                widget_keys=widget_keys,
                filters=filters,
                calendar_type=calendar_type,
            )
            
            logger.info(f"Dashboard widgets processed successfully for business {business_id}")
            return {
                "success": True,
                "data": data,
                "business_id": business_id,
                "user_id": user_id,
            }
        
    except Exception as e:
        logger.error(f"Error processing dashboard widgets for business {business_id}: {e}", exc_info=True)
        raise

