"""Job پس‌زمینه برای اجرای HScript روی QUEUE_REPORTS."""

from __future__ import annotations

import logging
from typing import Any, Optional

logger = logging.getLogger(__name__)


def run_hscript_report_job(
	business_id: int,
	user_id: int,
	*,
	source_code: Optional[str] = None,
	report_id: Optional[int] = None,
	params: Optional[dict[str, Any]] = None,
	fiscal_year_id: Optional[int] = None,
	preview: bool = False,
	persist: bool = True,
	calendar_type: Optional[str] = None,
) -> dict[str, Any]:
	"""
	اجرای گزارش HScript در worker جدا از API process.

	امنیت:
	- business_id فقط از آرگومان سروری (نه از params کاربر)
	- همان مسیر run_report با caps منابع
	"""
	try:
		from adapters.db.session import get_db_session
		from app.services import hscript_report_service as svc

		# params را از ورودی job پاکسازی می‌کنیم (دفاع مضاعف)
		safe_params = dict(params or {})
		for banned in ("business_id", "user_id", "db", "session", "settings", "token", "api_key"):
			safe_params.pop(banned, None)

		logger.info(
			"HScript job start business=%s user=%s report_id=%s preview=%s",
			business_id,
			user_id,
			report_id,
			preview,
		)

		with get_db_session() as db:
			result = svc.run_report(
				db,
				int(business_id),
				user_id=int(user_id),
				report_id=report_id,
				source_code=source_code,
				params=safe_params,
				fiscal_year_id=fiscal_year_id,
				preview=bool(preview),
				persist=bool(persist),
				use_worker_limits=True,
				calendar_type=calendar_type,
			)

		from app.services.hscript.hardening import sanitize_public_error

		# خروجی فشرده برای Redis result
		payload = {
			"success": bool(result.get("ok")),
			"ok": bool(result.get("ok")),
			"spec": result.get("spec"),
			"error": sanitize_public_error(result.get("error")),
			"stats": result.get("stats"),
			"source_hash": result.get("source_hash"),
			"run_id": result.get("run_id"),
			"preview": bool(preview),
			"business_id": int(business_id),
			"user_id": int(user_id),
		}
		logger.info(
			"HScript job done business=%s ok=%s run_id=%s",
			business_id,
			payload["ok"],
			payload.get("run_id"),
		)
		return payload
	except Exception as exc:
		logger.error("HScript job failed business=%s: %s", business_id, exc, exc_info=True)
		# بدون نشت traceback به کلاینت
		return {
			"success": False,
			"ok": False,
			"error": {
				"code": "E040_RUNTIME",
				"message": f"اجرای پس‌زمینه ناموفق بود: {type(exc).__name__}",
			},
			"business_id": int(business_id),
			"user_id": int(user_id),
		}
