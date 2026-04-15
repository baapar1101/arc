"""
کارهای پس‌زمینهٔ تست/اسکن FTP برای صف RQ (در صورت فعال بودن Redis).
"""

from __future__ import annotations

import logging
from datetime import datetime, timezone
from typing import Any

logger = logging.getLogger(__name__)


def run_business_ftp_test_job(business_id: int, body_dict: dict[str, Any]) -> dict[str, Any]:
	from rq.job import get_current_job

	from app.services.business_ftp_service import do_ftp_test

	job = get_current_job()

	def on_progress(p: int, msg: str) -> None:
		if job is None:
			return
		meta = dict(job.meta or {})
		meta["progress"] = p
		meta["message"] = msg
		job.meta = meta
		try:
			job.save_meta()
		except Exception as e:
			logger.debug("save_meta failed for ftp test job: %s", e)

	on_progress(5, "FTP test starting")
	try:
		return do_ftp_test(business_id, body_dict, on_progress=on_progress)
	finally:
		on_progress(100, "FTP test completed")


def run_business_ftp_usage_job(business_id: int) -> dict[str, Any]:
	from rq.job import get_current_job

	from app.services.business_ftp_service import do_ftp_usage_scan

	job = get_current_job()

	def on_progress(p: int, msg: str) -> None:
		if job is None:
			return
		meta = dict(job.meta or {})
		meta["progress"] = p
		meta["message"] = msg
		job.meta = meta
		try:
			job.save_meta()
		except Exception as e:
			logger.debug("save_meta failed for ftp usage job: %s", e)

	on_progress(5, "Scanning FTP usage")
	result = do_ftp_usage_scan(business_id, on_progress=on_progress)
	result["scanned_at"] = datetime.now(timezone.utc).isoformat()
	on_progress(100, "FTP usage scan completed")
	return result
