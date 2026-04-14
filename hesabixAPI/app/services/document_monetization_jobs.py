from __future__ import annotations

import asyncio
import logging

from adapters.db.session import get_db_session
from app.services.document_monetization_service import (
	process_document_usage_queue,
	finalize_volume_periods,
)


logger = logging.getLogger(__name__)


async def document_monetization_loop(interval_minutes: int = 10) -> None:
	"""
	Background loop برای پردازش سناریوی درآمدزایی اسناد حسابداری
	هر interval_minutes دقیقه اجرا می‌شود
	"""
	interval_seconds = max(60, interval_minutes * 60)
	while True:
		try:
			with get_db_session() as db:
				queue_result = process_document_usage_queue(db, batch_size=100)
				finalize_result = finalize_volume_periods(db)
				logger.info(
					"document_monetization_loop | processed=%s last_document_id=%s finalized=%s",
					queue_result.get("processed"),
					queue_result.get("last_document_id"),
					finalize_result.get("finalized"),
				)
		except Exception as ex:
			logger.error("document_monetization_loop_error | %s", ex, exc_info=True)
		await asyncio.sleep(interval_seconds)

