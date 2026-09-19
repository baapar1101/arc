"""Background job: اجرای زمان‌بندی‌شده ثبت نرخ تسعیر کسب‌وکارها از اسنپ‌شات مرکزی."""

from __future__ import annotations

import asyncio
import logging
from datetime import datetime, timezone
from typing import Any, Dict, List

logger = logging.getLogger(__name__)


def _run_due_auto_syncs_sync(*, limit: int = 40) -> List[Dict[str, Any]]:
	from adapters.db.session import SessionLocal
	from app.core.responses import ApiError
	from app.services.business_fx_auto_sync_service import (
		list_due_business_ids,
		run_auto_sync_for_business,
	)
	from app.services.fx_rate_provider_service import business_is_multi_currency

	out: List[Dict[str, Any]] = []
	db = SessionLocal()
	try:
		due_ids = list_due_business_ids(db, limit=limit)
		for business_id in due_ids:
			try:
				if not business_is_multi_currency(db, business_id):
					# کسب‌وکار دیگر چندارزی نیست — زمان‌بندی را خاموش کن
					from app.services.business_fx_auto_sync_service import get_or_create_settings

					settings = get_or_create_settings(db, business_id)
					settings.enabled = False
					settings.next_run_at = None
					settings.last_run_status = "disabled"
					settings.last_run_message = "کسب‌وکار دیگر چندارزی نیست؛ زمان‌بندی خاموش شد"
					settings.updated_at = datetime.now(timezone.utc)
					db.commit()
					out.append({"business_id": business_id, "ok": False, "skipped": "not_multi_currency"})
					continue

				result = run_auto_sync_for_business(
					db,
					business_id,
					triggered_by="schedule",
					actor_user_id=None,
				)
				db.commit()
				out.append({"business_id": business_id, "ok": True, "result": result})
			except ApiError as e:
				try:
					db.rollback()
				except Exception:
					pass
				# جلو انداختن next_run تا گیر نکند
				try:
					from app.services.business_fx_auto_sync_service import (
						compute_next_run_at,
						get_or_create_settings,
					)

					settings = get_or_create_settings(db, business_id)
					now = datetime.now(timezone.utc)
					settings.last_run_at = now
					settings.last_run_status = "error"
					detail = getattr(e, "detail", None)
					msg = str(e)
					if isinstance(detail, dict) and isinstance(detail.get("error"), dict):
						msg = detail["error"].get("message") or msg
					settings.last_run_message = msg[:2000]
					settings.next_run_at = compute_next_run_at(
						enabled=settings.enabled,
						schedule_mode=settings.schedule_mode,
						interval_hours=settings.interval_hours,
						daily_times=list(settings.daily_times or []),
						timezone_name=settings.timezone,
						from_utc=now,
						last_run_at=now,
					)
					settings.updated_at = now
					db.commit()
				except Exception:
					try:
						db.rollback()
					except Exception:
						pass
				out.append({"business_id": business_id, "ok": False, "error": str(e)})
			except Exception as e:
				try:
					db.rollback()
				except Exception:
					pass
				out.append({"business_id": business_id, "ok": False, "error": str(e)})
				logger.exception("FX auto-sync failed business_id=%s", business_id)
	finally:
		db.close()
	return out


async def fx_auto_sync_loop(check_interval_seconds: int = 60) -> None:
	"""هر دقیقه کسب‌وکارهای due را اجرا می‌کند."""
	await asyncio.sleep(25)
	while True:
		try:
			results = await asyncio.to_thread(_run_due_auto_syncs_sync)
			for item in results:
				if item.get("ok"):
					r = item.get("result") or {}
					logger.info(
						"FX auto-sync ok business=%s status=%s created=%s",
						item.get("business_id"),
						r.get("status"),
						len(r.get("created") or []),
					)
				elif item.get("skipped"):
					logger.info(
						"FX auto-sync skipped business=%s reason=%s",
						item.get("business_id"),
						item.get("skipped"),
					)
				else:
					logger.warning(
						"FX auto-sync failed business=%s: %s",
						item.get("business_id"),
						item.get("error"),
					)
		except Exception as e:
			logger.exception("FX auto-sync loop error: %s", e)
		await asyncio.sleep(max(30, int(check_interval_seconds)))
