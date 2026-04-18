"""
Job پر کردن ستون‌های سود/بهای تمام‌شده قطعی (دفتر) برای اسناد قبلی.
"""
from __future__ import annotations

import logging
from typing import Any, Dict, List, Optional

from adapters.db.session import get_db_session

logger = logging.getLogger(__name__)


def backfill_invoice_profit_ledger_job(
    business_id: int,
    user_id: int,
    fiscal_year_id: Optional[int] = None,
    invoice_ids: Optional[List[int]] = None,
    limit: Optional[int] = None,
    **kwargs: Any,
) -> Dict[str, Any]:
    """
    اجرای backfill_invoice_profit_ledger در worker (RQ).
    """
    try:
        with get_db_session() as db:
            from app.services.invoice_profit_ledger_service import (
                backfill_recognized_profit_for_business,
            )

            result = backfill_recognized_profit_for_business(
                db,
                int(business_id),
                fiscal_year_id=fiscal_year_id,
                invoice_ids=invoice_ids,
                limit=limit,
            )
            return {"success": True, **result}
    except Exception as e:
        logger.exception("backfill_invoice_profit_ledger_job failed: %s", e)
        return {"success": False, "error": str(e), "processed": 0, "skipped": 0}
