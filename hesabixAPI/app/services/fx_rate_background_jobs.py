"""Background job: واکشی دوره‌ای نرخ ارز از ارائه‌دهندگان فعال (متمرکز، نه per-business)."""

from __future__ import annotations

import asyncio
import logging
from datetime import datetime, timezone

logger = logging.getLogger(__name__)


async def fx_global_rates_fetch_loop(check_interval_seconds: int = 60) -> None:
	"""هر check_interval_seconds بررسی می‌کند کدام provider due است و واکشی می‌کند."""
	from adapters.db.session import SessionLocal
	from app.services.fx_rate_provider_service import fetch_and_store_provider, providers_due_for_fetch

	# تأخیر کوتاه بعد از استارت تا فشار روی استارتاپ کم شود
	await asyncio.sleep(15)
	while True:
		try:
			db = SessionLocal()
			try:
				due = providers_due_for_fetch(db)
				for provider in due:
					try:
						result = fetch_and_store_provider(db, provider)
						db.commit()
						logger.info(
							"FX fetch ok provider=%s rates=%s at=%s",
							provider.code,
							result.get("rates_upserted"),
							datetime.now(timezone.utc).isoformat(),
						)
					except Exception as e:
						# وضعیت خطا داخل سرویس flush شده؛ commit کن تا در ادمین دیده شود
						try:
							db.commit()
						except Exception:
							db.rollback()
						logger.warning("FX fetch failed provider=%s: %s", provider.code, e)
			finally:
				db.close()
		except Exception as e:
			logger.exception("FX global rates loop error: %s", e)
		await asyncio.sleep(max(30, int(check_interval_seconds)))
