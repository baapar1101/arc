"""
کمک‌کننده‌های session دیتابیس برای اجرای ابزارهای AI.
"""
from __future__ import annotations

import logging
from typing import Any, Dict

from sqlalchemy.orm import Session

logger = logging.getLogger(__name__)


def safe_db_rollback(db: Session | None) -> None:
    """پاک‌سازی تراکنش abort‌شده بدون پرتاب خطای ثانویه."""
    if db is None:
        return
    try:
        db.rollback()
    except Exception as exc:
        logger.debug("safe_db_rollback ignored: %s", exc)


def run_ai_registry_function(
    function_name: str,
    arguments: Dict[str, Any],
    context: Dict[str, Any],
) -> Any:
    """
    اجرای function AI با session مستقل.

    از اشتراک session استریم چت جلوگیری می‌کند تا خطای یک tool
    بقیه را با InFailedSqlTransaction خراب نکند.
    """
    from adapters.db.session import get_db_session
    from app.services.ai.function_registry import registry

    tool_context = {k: v for k, v in context.items() if k != "db"}
    with get_db_session() as db:
        tool_context["db"] = db
        return registry.call_function(function_name, arguments, tool_context)
