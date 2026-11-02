# noqa: D100
"""Jobهای پس‌زمینه اتوماسیون اداری: هشدار سررسید پیگیری و مهلت ارجاع."""
from __future__ import annotations

import logging
from typing import Dict

logger = logging.getLogger(__name__)


def tick_once() -> Dict[str, Dict]:
	"""یک بار اجرای هشدارهای سررسید نامه و ارجاع."""
	from adapters.db.session import get_db_session
	from app.services.office_automation_extended_service import notify_due_followups

	out: Dict[str, Dict] = {}
	with get_db_session() as db:
		try:
			out["due_followups"] = notify_due_followups(db)
		except Exception as e:
			logger.error("OA due-followup tick failed: %s", e, exc_info=True)
			out["due_followups"] = {"error": str(e)}
	return out


async def oa_automation_background_loop(interval_seconds: int = 300) -> None:
	"""حلقه پس‌زمینه: هر چند دقیقه هشدار سررسید کارتابل را ارسال می‌کند."""
	import asyncio

	while True:
		try:
			await asyncio.to_thread(tick_once)
		except Exception:
			logger.exception("oa_automation_background_loop tick error")
		await asyncio.sleep(max(60, int(interval_seconds)))
