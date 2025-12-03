"""
Background jobs برای سیستم درآمدزایی اسناد
"""

from __future__ import annotations

import asyncio
import logging
from datetime import datetime

from adapters.db.session import get_db_session
from app.services.document_monetization_service import (
	finalize_volume_periods,
)

logger = logging.getLogger(__name__)


async def document_monetization_finalize_periods_loop(interval_hours: int = 24) -> None:
	"""
Background loop برای finalize کردن دوره‌های حجمی منقضی شده
هر interval_hours ساعت یکبار اجرا می‌شود (پیش‌فرض: روزانه)
	
	این job تمام period های volume policy که به پایان رسیده‌اند را بررسی می‌کند
	و در صورت نیاز، صورتحساب ایجاد و از wallet کسر می‌کند.
	"""
	interval_seconds = interval_hours * 3600
	
	while True:
		try:
			with get_db_session() as db:
				logger.info("Starting document monetization period finalization check...")
				
				# Finalize کردن تمام period های منقضی شده
				result = finalize_volume_periods(db, business_id=None)
				
				if result.get("finalized", 0) > 0:
					logger.info(
						f"Finalized {result['finalized']} volume periods, "
						f"created invoices and accounting documents"
					)
				else:
					logger.debug("No periods to finalize")
					
		except Exception as e:
			logger.error(
				f"Error in document monetization finalize periods loop: {str(e)}",
				exc_info=True,
			)
		
		await asyncio.sleep(interval_seconds)



