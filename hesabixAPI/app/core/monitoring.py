from __future__ import annotations

import time
import logging
from typing import Optional, Dict, Any
from datetime import datetime
from functools import wraps
from fastapi import Request, Response

from app.core.cache import get_cache

logger = logging.getLogger(__name__)


class PerformanceMonitor:
	"""مانیتورینگ Performance و Metrics"""
	
	def __init__(self, cache_service=None):
		self.cache = cache_service or get_cache()
	
	def record_request(
		self,
		method: str,
		path: str,
		duration_ms: float,
		status_code: int,
		user_id: Optional[int] = None,
	) -> None:
		"""ثبت اطلاعات درخواست برای monitoring"""
		if not self.cache.enabled:
			return
		
		try:
			# ذخیره در Redis با TTL 24 ساعت
			timestamp = int(time.time())
			key = f"metrics:request:{timestamp}:{method}:{path}"
			
			# فقط درخواست‌های کند یا خطا را ذخیره می‌کنیم
			if duration_ms > 1000 or status_code >= 400:
				data = {
					"method": method,
					"path": path,
					"duration_ms": duration_ms,
					"status_code": status_code,
					"user_id": user_id,
					"timestamp": timestamp,
				}
				self.cache.set(key, data, ttl=86400)  # 24 ساعت
			
			# آمار کلی (aggregated)
			stats_key = f"metrics:stats:{method}:{path}"
			stats = self.cache.get(stats_key) or {
				"count": 0,
				"total_duration": 0,
				"max_duration": 0,
				"error_count": 0,
			}
			
			stats["count"] += 1
			stats["total_duration"] += duration_ms
			stats["max_duration"] = max(stats["max_duration"], duration_ms)
			if status_code >= 400:
				stats["error_count"] += 1
			
			# ذخیره آمار (TTL 7 روز)
			self.cache.set(stats_key, stats, ttl=604800)
		except Exception as e:
			logger.warning(f"Failed to record request metrics: {e}")
	
	def get_endpoint_stats(self, method: str, path: str) -> Dict[str, Any]:
		"""دریافت آمار یک endpoint"""
		if not self.cache.enabled:
			return {}
		
		try:
			stats_key = f"metrics:stats:{method}:{path}"
			stats = self.cache.get(stats_key)
			if stats:
				avg_duration = stats["total_duration"] / stats["count"] if stats["count"] > 0 else 0
				return {
					**stats,
					"avg_duration": avg_duration,
					"error_rate": stats["error_count"] / stats["count"] if stats["count"] > 0 else 0,
				}
		except Exception as e:
			logger.warning(f"Failed to get endpoint stats: {e}")
		
		return {}
	
	def record_slow_query(
		self,
		query: str,
		duration_ms: float,
		table: Optional[str] = None,
	) -> None:
		"""ثبت query های کند"""
		if duration_ms < 1000:  # فقط query های بیشتر از 1 ثانیه
			return
		
		logger.warning(
			"slow_query",
			extra={
				"query": query[:200],  # محدود کردن طول query
				"duration_ms": duration_ms,
				"table": table,
			}
		)


# Global monitor instance
_performance_monitor = PerformanceMonitor()


def get_performance_monitor() -> PerformanceMonitor:
	"""Get global performance monitor instance"""
	return _performance_monitor


def monitor_performance(func):
	"""
	Decorator برای monitoring performance endpoint ها
	"""
	@wraps(func)
	async def wrapper(*args, **kwargs):
		import time
		# پیدا کردن Request object
		request = None
		user_id = None
		
		for arg in args:
			if isinstance(arg, Request):
				request = arg
			elif hasattr(arg, 'get_user_id'):  # AuthContext
				try:
					user_id = arg.get_user_id()
				except:
					pass
		
		if not request:
			for value in kwargs.values():
				if isinstance(value, Request):
					request = value
				elif hasattr(value, 'get_user_id'):
					try:
						user_id = value.get_user_id()
					except:
						pass
		
		start_time = time.perf_counter()
		status_code = 200
		
		try:
			response = await func(*args, **kwargs)
			
			# اگر response یک dict باشد (success_response)
			if isinstance(response, dict):
				if not response.get("success", True):
					status_code = 400
			
			return response
		except Exception as e:
			status_code = getattr(e, 'http_status', 500) if hasattr(e, 'http_status') else 500
			raise
		finally:
			if request:
				duration_ms = (time.perf_counter() - start_time) * 1000
				monitor = get_performance_monitor()
				monitor.record_request(
					method=request.method,
					path=str(request.url.path),
					duration_ms=duration_ms,
					status_code=status_code,
					user_id=user_id,
				)
	
	return wrapper

