"""Background job: اجرای زمان‌بندی‌های due گزارش HScript."""

from __future__ import annotations

import asyncio
import logging
from typing import Any, Dict, List

logger = logging.getLogger(__name__)


def _run_due_schedules_sync(*, limit: int = 40) -> List[Dict[str, Any]]:
	from adapters.db.session import SessionLocal
	from app.services.hscript_schedule_service import list_due_schedules, run_schedule_now

	out: List[Dict[str, Any]] = []
	db = SessionLocal()
	try:
		due = list_due_schedules(db, limit=limit)
		for schedule in due:
			try:
				result = run_schedule_now(db, schedule, triggered_by="schedule")
				out.append({"schedule_id": schedule.id, **result})
			except Exception as exc:  # noqa: BLE001
				try:
					db.rollback()
				except Exception:
					pass
				logger.exception("HScript schedule tick failed id=%s: %s", getattr(schedule, "id", None), exc)
				out.append({"schedule_id": getattr(schedule, "id", None), "ok": False, "error": str(exc)})
	finally:
		db.close()
	return out


async def hscript_schedule_loop(interval_seconds: int = 60) -> None:
	"""لوپ پس‌زمینه مشابه FX/Workflow."""
	while True:
		try:
			results = await asyncio.to_thread(_run_due_schedules_sync, limit=40)
			if results:
				ok = sum(1 for r in results if r.get("ok"))
				logger.info("HScript schedules tick: %s due, %s ok", len(results), ok)
		except Exception as exc:  # noqa: BLE001
			logger.exception("HScript schedule loop error: %s", exc)
		await asyncio.sleep(max(15, int(interval_seconds)))
