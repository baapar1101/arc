"""
پاکسازی دوره‌ای اعلان‌های in-app خوانده‌شده طبق تنظیمات مدیر سیستم.
"""

from __future__ import annotations

import asyncio
import logging

from adapters.db.session import get_db_session
from app.services.announcement_service import purge_read_announcements_after_retention
from app.services.system_settings_service import get_notifications_settings

logger = logging.getLogger(__name__)


async def announcement_read_retention_loop(interval_hours: int = 24) -> None:
	interval_seconds = max(3600, int(interval_hours) * 3600)
	while True:
		try:
			with get_db_session() as db:
				cfg = get_notifications_settings(db)
				enabled = bool(cfg.get("inapp_read_retention_enabled"))
				days = int(cfg.get("inapp_read_retention_days") or 0)
				if enabled and days > 0:
					n = purge_read_announcements_after_retention(db, days)
					if n > 0:
						logger.info("announcement read retention applied: %s operations", n)
		except Exception as e:
			logger.error("announcement_read_retention_loop error: %s", e, exc_info=True)
		await asyncio.sleep(interval_seconds)
