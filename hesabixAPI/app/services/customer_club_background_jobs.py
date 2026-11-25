"""Durable periodic processing for customer club point expiry."""
from __future__ import annotations

import asyncio
import logging

logger = logging.getLogger(__name__)


def tick_once() -> dict:
	from adapters.db.session import get_db_session
	from app.services.customer_club_service import expire_due_points
	from app.services.customer_club_program_service import run_due_campaigns

	with get_db_session() as db:
		try:
			return {"points": expire_due_points(db), "campaigns": run_due_campaigns(db)}
		except Exception:
			db.rollback()
			logger.exception("customer club expiry tick failed")
			return {"error": "expiry_tick_failed"}


async def customer_club_background_loop(interval_seconds: int = 300) -> None:
	while True:
		try:
			await asyncio.to_thread(tick_once)
		except Exception:
			logger.exception("customer club background loop failed")
		await asyncio.sleep(max(60, int(interval_seconds)))
