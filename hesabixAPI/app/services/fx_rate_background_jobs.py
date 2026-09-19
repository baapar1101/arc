"""Background job: واکشی دوره‌ای نرخ ارز از ارائه‌دهندگان فعال (متمرکز، نه per-business)."""

from __future__ import annotations

import asyncio
import logging
from datetime import datetime, timezone
from typing import Any, Dict, List

logger = logging.getLogger(__name__)


def _run_due_fetches_sync() -> List[Dict[str, Any]]:
	"""اجرای همگام در thread جدا تا event loop API بلاک نشود."""
	from adapters.db.session import SessionLocal
	from app.services.fx_rate_provider_service import fetch_and_store_provider, providers_due_for_fetch

	out: List[Dict[str, Any]] = []
	db = SessionLocal()
	try:
		due = providers_due_for_fetch(db)
		for provider in due:
			code = provider.code
			try:
				result = fetch_and_store_provider(db, provider)
				db.commit()
				out.append({"provider": code, "ok": True, "result": result})
			except Exception as e:
				try:
					db.commit()
				except Exception:
					db.rollback()
				out.append({"provider": code, "ok": False, "error": str(e)})
	finally:
		db.close()
	return out


async def fx_global_rates_fetch_loop(check_interval_seconds: int = 60) -> None:
	"""هر check_interval_seconds بررسی می‌کند کدام provider due است و واکشی می‌کند."""
	await asyncio.sleep(15)
	while True:
		try:
			results = await asyncio.to_thread(_run_due_fetches_sync)
			for item in results:
				if item.get("ok"):
					r = item.get("result") or {}
					logger.info(
						"FX fetch ok provider=%s rates=%s at=%s",
						item.get("provider"),
						r.get("rates_upserted"),
						datetime.now(timezone.utc).isoformat(),
					)
				else:
					logger.warning(
						"FX fetch failed provider=%s: %s",
						item.get("provider"),
						item.get("error"),
					)
		except Exception as e:
			logger.exception("FX global rates loop error: %s", e)
		await asyncio.sleep(max(30, int(check_interval_seconds)))
