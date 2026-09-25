# noqa: D100
"""Jobهای پس‌زمینه CRM: یادآوری پیگیری، وظایف، SLA، فرصت‌های راکد و پردازش توالی‌ها."""
from __future__ import annotations

import logging
from typing import Dict

logger = logging.getLogger(__name__)


def tick_once() -> Dict[str, Dict]:
    """یک بار اجرای همه Jobهای CRM (برای زمان‌بند یا تست)."""
    from adapters.db.session import get_db_session
    from app.services import crm_automation_service as automation

    out: Dict[str, Dict] = {}
    with get_db_session() as db:
        try:
            out["follow_up_reminders"] = automation.process_follow_up_reminders(db)
        except Exception as e:
            logger.error("crm follow-up reminders tick failed: %s", e, exc_info=True)
            out["follow_up_reminders"] = {"error": str(e)}
        try:
            out["sequences"] = automation.tick_sequences(db)
        except Exception as e:
            logger.error("crm sequences tick failed: %s", e, exc_info=True)
            out["sequences"] = {"error": str(e)}
        try:
            out["stale_deals"] = automation.flag_stale_deals(db)
        except Exception as e:
            logger.error("crm stale deals tick failed: %s", e, exc_info=True)
            out["stale_deals"] = {"error": str(e)}
    return out


async def crm_automation_background_loop(interval_seconds: int = 60) -> None:
    """حلقه پس‌زمینه: هر ۶۰ ثانیه Jobهای CRM را اجرا می‌کند."""
    import asyncio

    while True:
        try:
            await asyncio.to_thread(tick_once)
        except Exception:
            logger.exception("crm_automation_background_loop tick error")
        await asyncio.sleep(max(30, int(interval_seconds)))
