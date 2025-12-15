"""
Subscriber برای دریافت پیام‌های invalidation از Redis Pub/Sub
این subscriber در startup برنامه راه‌اندازی می‌شود و به صورت background پیام‌های invalidation را دریافت می‌کند
"""

import json
import logging
import threading
from typing import Optional, Any
from app.core.cache import get_cache

logger = logging.getLogger(__name__)

# Global pubsub instance
_pubsub: Optional[Any] = None
_subscriber_thread: Optional[threading.Thread] = None


def handle_invalidation_message(message_data: dict):
	"""
	Handler برای پردازش پیام‌های invalidation
	
	Args:
		message_data: دیکشنری حاوی اطلاعات invalidation
			- type: نوع invalidation (مثلاً "persons_cache_invalidation")
			- business_id: شناسه کسب‌وکار
			- fiscal_year_id: شناسه سال مالی (اختیاری)
	"""
	try:
		message_type = message_data.get("type")
		
		if message_type == "persons_cache_invalidation":
			business_id = message_data.get("business_id")
			fiscal_year_id = message_data.get("fiscal_year_id")
			
			if business_id:
				# فراخوانی تابع invalidate_persons_cache
				# اما بدون publish کردن دوباره (برای جلوگیری از loop)
				from app.services.person_service import invalidate_persons_cache
				
				# استفاده از invalidate_by_business مستقیم برای جلوگیری از publish مجدد
				cache = get_cache()
				if cache.enabled:
					deleted_count = cache.invalidate_by_business(business_id, fiscal_year_id)
					if deleted_count > 0:
						logger.info(f"Received invalidation message: Invalidated {deleted_count} cache keys for business_id {business_id}, fiscal_year_id {fiscal_year_id}")
					
					# همچنین pattern-based invalidation را هم انجام می‌دهیم
					pattern = "persons_list:*"
					deleted_pattern = cache.delete_pattern(pattern)
					if deleted_pattern > 0:
						logger.info(f"Received invalidation message: Invalidated {deleted_pattern} cache keys using pattern: {pattern}")
		else:
			logger.warning(f"Unknown invalidation message type: {message_type}")
			
	except Exception as e:
		logger.error(f"Error handling invalidation message: {e}", exc_info=True)


def start_cache_invalidation_subscriber():
	"""
	شروع subscriber برای دریافت پیام‌های invalidation از Redis Pub/Sub
	"""
	global _pubsub, _subscriber_thread
	
	cache = get_cache()
	if not cache.enabled:
		logger.info("Cache is disabled, skipping cache invalidation subscriber")
		return
	
	try:
		# ایجاد subscriber برای کانال cache_invalidation
		_pubsub = cache.subscribe_invalidation("cache_invalidation", handle_invalidation_message)
		
		if _pubsub:
			logger.info("Cache invalidation subscriber started successfully")
		else:
			logger.warning("Failed to start cache invalidation subscriber")
	except Exception as e:
		logger.error(f"Error starting cache invalidation subscriber: {e}", exc_info=True)


def stop_cache_invalidation_subscriber():
	"""
	توقف subscriber برای دریافت پیام‌های invalidation
	"""
	global _pubsub, _subscriber_thread
	
	if _pubsub:
		try:
			_pubsub.unsubscribe("cache_invalidation")
			_pubsub.close()
			_pubsub = None
			logger.info("Cache invalidation subscriber stopped")
		except Exception as e:
			logger.warning(f"Error stopping cache invalidation subscriber: {e}")

