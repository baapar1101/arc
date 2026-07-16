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
    cache_key: Optional[str] = None,
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
        cache_key: کلید Redis برای ذخیرهٔ نتیجه (warm load بعدی بدون صف)
        **kwargs: سایر پارامترها

    Returns:
        داده‌های ویجت‌ها
    """
    try:
        from adapters.db.session import get_db_session
        from app.services.dashboard_widgets_service import get_widgets_batch_data
        from app.core.cache import get_cache
        from app.core.responses import format_datetime_fields

        logger.info(f"Processing dashboard widgets for business {business_id}, user {user_id}")

        filters = filters or {}

        with get_db_session() as db:
            from adapters.db.models.user import User
            from app.core.auth_dependency import AuthContext

            user = db.get(User, int(user_id))
            auth_ctx = None
            if user is not None:
                auth_ctx = AuthContext(
                    user=user,
                    api_key_id=0,
                    business_id=business_id,
                    db=db,
                )
            data = get_widgets_batch_data(
                db=db,
                business_id=business_id,
                user_id=user_id,
                widget_keys=widget_keys,
                filters=filters,
                calendar_type=calendar_type,
                auth_ctx=auth_ctx,
            )

            # بدون Request واقعی؛ فیلدهای datetime را برای سازگاری با پاسخ sync فرمت می‌کنیم
            try:
                formatted = format_datetime_fields(data, request=None)
            except Exception:
                formatted = data

            cache = get_cache()
            if cache.enabled and cache_key:
                try:
                    cache.set(cache_key, formatted, ttl=30)
                except Exception as cache_err:
                    logger.warning(f"Failed to cache dashboard job result: {cache_err}")

            logger.info(f"Dashboard widgets processed successfully for business {business_id}")
            return {
                "success": True,
                "data": formatted,
                "business_id": business_id,
                "user_id": user_id,
            }

    except Exception as e:
        logger.error(f"Error processing dashboard widgets for business {business_id}: {e}", exc_info=True)
        raise
