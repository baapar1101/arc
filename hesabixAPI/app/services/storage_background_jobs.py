"""
Background jobs برای سیستم ذخیره‌سازی
"""

from __future__ import annotations

import asyncio
import logging
from datetime import datetime

from adapters.db.session import get_db_session
from app.services.storage_cleanup_service import (
	mark_files_for_deletion,
	delete_marked_files,
)
from app.services.storage_subscription_service import check_expired_subscriptions

logger = logging.getLogger(__name__)


async def storage_cleanup_loop(interval_hours: int = 24) -> None:
	"""
Background loop برای پاک‌سازی فایل‌های منقضی شده
هر interval_hours ساعت یکبار اجرا می‌شود
"""
	interval_seconds = interval_hours * 3600
	
	while True:
		try:
			with get_db_session() as db:
				# بررسی اشتراک‌های منقضی شده
				expired = check_expired_subscriptions(db)
				if expired:
					logger.info(f"Found {len(expired)} expired subscriptions")
				
				# علامت‌گذاری فایل‌ها برای حذف
				mark_result = mark_files_for_deletion(db)
				if mark_result["marked_count"] > 0:
					logger.info(f"Marked {mark_result['marked_count']} files for deletion from {mark_result['business_count']} businesses")
				
				# حذف فایل‌های علامت‌گذاری شده (بعد از 7 روز)
				try:
					delete_result = await delete_marked_files(db, days_after_mark=7)
					if delete_result["deleted_count"] > 0:
						logger.info(f"Deleted {delete_result['deleted_count']} files, {delete_result['failed_count']} failed")
				except Exception as e:
					logger.error(f"Error deleting marked files: {str(e)}", exc_info=True)
		except Exception as e:
			logger.error(f"Error in storage cleanup loop: {str(e)}", exc_info=True)
		
		await asyncio.sleep(interval_seconds)


async def storage_subscription_check_loop(interval_hours: int = 6) -> None:
	"""
Background loop برای بررسی انقضای اشتراک‌ها
هر interval_hours ساعت یکبار اجرا می‌شود
"""
	interval_seconds = interval_hours * 3600
	
	while True:
		try:
			with get_db_session() as db:
				# بررسی اشتراک‌های منقضی شده
				expired = check_expired_subscriptions(db)
				if expired:
					logger.info(f"Checked subscriptions: {len(expired)} expired subscriptions updated")
		except Exception as e:
			logger.error(f"Error in subscription check loop: {str(e)}", exc_info=True)
		
		await asyncio.sleep(interval_seconds)

