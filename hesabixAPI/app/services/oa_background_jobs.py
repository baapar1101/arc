# noqa: D100
"""Jobهای پس‌زمینه اتوماسیون اداری: هشدار سررسید پیگیری و مهلت ارجاع."""
from __future__ import annotations

import logging
from typing import Dict

logger = logging.getLogger(__name__)


def tick_once() -> Dict[str, Dict]:
	"""یک بار اجرای هشدارهای سررسید نامه و ارجاع."""
	from adapters.db.session import get_db_session
	from app.services.oa_document_service import process_ocr_queue
	from app.services.oa_enterprise_service import mark_due_retention
	from app.services.oa_process_runtime import advance_due_timers, escalate_overdue_tasks
	from app.services.office_automation_extended_service import notify_due_followups

	out: Dict[str, Dict] = {}
	with get_db_session() as db:
		try:
			out["due_followups"] = notify_due_followups(db)
		except Exception as e:
			logger.error("OA due-followup tick failed: %s", e, exc_info=True)
			out["due_followups"] = {"error": str(e)}
		try:
			out["process_timers"] = advance_due_timers(db)
		except Exception as e:
			logger.error("OA process timer tick failed: %s", e, exc_info=True)
			out["process_timers"] = {"error": str(e)}
		try:
			out["ocr_queue"] = process_ocr_queue(db)
		except Exception as e:
			logger.error("OA OCR queue tick failed: %s", e, exc_info=True)
			out["ocr_queue"] = {"error": str(e)}
		try:
			out["retention"] = mark_due_retention(db)
		except Exception as e:
			logger.error("OA retention tick failed: %s", e, exc_info=True)
			out["retention"] = {"error": str(e)}
		try:
			out["process_sla"] = escalate_overdue_tasks(db)
		except Exception as e:
			logger.error("OA process SLA tick failed: %s", e, exc_info=True)
			out["process_sla"] = {"error": str(e)}
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
