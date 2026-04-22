from __future__ import annotations

import time
import logging
import inspect
import threading
from typing import Optional, Tuple, Callable
from functools import wraps
from fastapi import Request, HTTPException, status, Response

from app.core.cache import get_cache
from app.core.responses import ApiError

logger = logging.getLogger(__name__)


class _MemoryRateWindow:
	"""
	نرخ‌سنجی درون‌پردازه وقتی Redis در دسترس نیست (نسبی برای چند worker).
	"""
	
	def __init__(self) -> None:
		self._lock = threading.RLock()
		# key -> [window_start_ts, count]
		self._counters: dict[str, list] = {}
	
	def _prune_old_windows(self, current_time: int, window_seconds: int) -> None:
		"""جلوگیری از رشد بی‌پایان dict پنجره‌های قدیمی."""
		if len(self._counters) < 8000:
			return
		max_age = max(3600, window_seconds * 4)
		stale: list[str] = []
		for k in self._counters:
			try:
				ws = int(k.rsplit(":", 1)[-1])
				if current_time - ws > max_age:
					stale.append(k)
			except (ValueError, IndexError):
				stale.append(k)
		for k in stale[:5000]:
			self._counters.pop(k, None)
	
	def check(
		self,
		key: str,
		max_requests: int,
		window_seconds: int,
	) -> Tuple[bool, int, int]:
		cache_key = f"rate_limit:{key}:{window_seconds}"
		current_time = int(time.time())
		window_start = current_time - (current_time % window_seconds)
		window_id_key = f"{cache_key}:{window_start}"
		with self._lock:
			if (len(self._counters) > 8000 and hash(key) % 97 == 0) or len(self._counters) > 50_000:
				self._prune_old_windows(current_time, window_seconds)
			row = self._counters.get(window_id_key)
			if not row or row[0] != window_start:
				row = [window_start, 0]
				self._counters[window_id_key] = row
			if row[1] >= max_requests:
				reset_after = window_seconds - (current_time % window_seconds)
				return False, 0, reset_after
			row[1] += 1
			new_count = row[1]
		remaining = max(0, max_requests - new_count)
		reset_after = window_seconds - (current_time % window_seconds)
		return True, remaining, reset_after


class RateLimiter:
	"""Rate limiter با استفاده از Redis"""
	
	def __init__(self, cache_service=None):
		self.cache = cache_service or get_cache()
		self._memory = _MemoryRateWindow()
	
	def check_rate_limit(
		self,
		key: str,
		max_requests: int,
		window_seconds: int,
	) -> Tuple[bool, int, int]:
		"""
		بررسی rate limit
		
		Args:
			key: کلید یکتا برای rate limiting (مثلاً user_id یا IP)
			max_requests: حداکثر تعداد درخواست
			window_seconds: بازه زمانی به ثانیه
		
		Returns:
			Tuple[bool, int, int]: (allowed, remaining, reset_after)
			- allowed: آیا درخواست مجاز است
			- remaining: تعداد درخواست‌های باقیمانده
			- reset_after: زمان باقیمانده تا reset (ثانیه)
		"""
		if not self.cache.enabled:
			return self._memory.check(key, max_requests, window_seconds)
		
		try:
			cache_key = f"rate_limit:{key}:{window_seconds}"
			current_time = int(time.time())
			window_start = current_time - (current_time % window_seconds)
			window_key = f"{cache_key}:{window_start}"
			
			# دریافت تعداد درخواست‌های فعلی
			current_count = self.cache.get(window_key)
			if current_count is None:
				current_count = 0
			else:
				current_count = int(current_count)
			
			# بررسی limit
			if current_count >= max_requests:
				reset_after = window_seconds - (current_time % window_seconds)
				return False, 0, reset_after
			
			# افزایش counter
			new_count = current_count + 1
			ttl = window_seconds + 1  # یک ثانیه اضافه برای اطمینان
			self.cache.set(window_key, new_count, ttl)
			
			remaining = max(0, max_requests - new_count)
			reset_after = window_seconds - (current_time % window_seconds)
			
			return True, remaining, reset_after
		except Exception as e:
			logger.warning(f"Rate limit check error for key {key}: {e}, using in-memory limiter")
			return self._memory.check(key, max_requests, window_seconds)
	
	def get_rate_limit_info(
		self,
		key: str,
		max_requests: int,
		window_seconds: int,
	) -> dict:
		"""دریافت اطلاعات rate limit بدون افزایش counter"""
		if not self.cache.enabled:
			return {
				"limit": max_requests,
				"remaining": max_requests,
				"reset_after": window_seconds,
			}
		
		try:
			cache_key = f"rate_limit:{key}:{window_seconds}"
			current_time = int(time.time())
			window_start = current_time - (current_time % window_seconds)
			window_key = f"{cache_key}:{window_start}"
			
			current_count = self.cache.get(window_key)
			if current_count is None:
				current_count = 0
			else:
				current_count = int(current_count)
			
			remaining = max(0, max_requests - current_count)
			reset_after = window_seconds - (current_time % window_seconds)
			
			return {
				"limit": max_requests,
				"remaining": remaining,
				"reset_after": reset_after,
			}
		except Exception as e:
			logger.warning(f"Rate limit info error for key {key}: {e}")
			return {
				"limit": max_requests,
				"remaining": max_requests,
				"reset_after": window_seconds,
			}


# Global rate limiter instance
_rate_limiter = RateLimiter()


def get_rate_limiter() -> RateLimiter:
	"""Get global rate limiter instance"""
	return _rate_limiter


def rate_limit(
	max_requests: int = 60,
	window_seconds: int = 60,
	key_func: Optional[Callable[[Request], str]] = None,
	error_message: str = "Too many requests. Please try again later.",
):
	"""
	Decorator برای rate limiting
	
	Args:
		max_requests: حداکثر تعداد درخواست
		window_seconds: بازه زمانی به ثانیه
		key_func: تابع برای ساخت کلید rate limit (پیش‌فرض: از IP استفاده می‌کند)
		error_message: پیام خطا در صورت exceed شدن limit
	
	Example:
		@rate_limit(max_requests=10, window_seconds=60)
		async def my_endpoint(request: Request):
			...
	"""
	def decorator(func):
		@wraps(func)
		async def wrapper(*args, **kwargs):
			# پیدا کردن Request object
			request = None
			for arg in args:
				if isinstance(arg, Request):
					request = arg
					break
			if not request:
				for value in kwargs.values():
					if isinstance(value, Request):
						request = value
						break
			
			# ساخت کلید rate limit
			remaining = max_requests
			reset_after = window_seconds
			
			if request:
				if key_func:
					rate_limit_key = key_func(request)
				else:
					# پیش‌فرض: استفاده از IP
					client_ip = request.client.host if request.client else "unknown"
					# بررسی IP از headers (برای proxy)
					if not client_ip or client_ip == "unknown":
						x_forwarded_for = request.headers.get("X-Forwarded-For")
						if x_forwarded_for:
							client_ip = x_forwarded_for.split(",")[0].strip()
						else:
							x_real_ip = request.headers.get("X-Real-IP")
							if x_real_ip:
								client_ip = x_real_ip
					
					rate_limit_key = f"ip:{client_ip}"
				
				# بررسی rate limit
				limiter = get_rate_limiter()
				allowed, remaining, reset_after = limiter.check_rate_limit(
					rate_limit_key,
					max_requests,
					window_seconds,
				)
				
				if not allowed:
					raise ApiError(
						"RATE_LIMIT_EXCEEDED",
						error_message,
						http_status=429,
						headers={
							"X-RateLimit-Limit": str(max_requests),
							"X-RateLimit-Remaining": "0",
							"X-RateLimit-Reset": str(int(time.time()) + reset_after),
							"Retry-After": str(reset_after),
						}
					)
			
			# اجرای function - بررسی اینکه آیا async است یا sync
			if inspect.iscoroutinefunction(func):
				response = await func(*args, **kwargs)
			else:
				# برای sync functions، مستقیماً فراخوانی می‌کنیم
				response = func(*args, **kwargs)
			
			# اضافه کردن rate limit headers به response
			# اگر response یک dict باشد (success_response)، باید از middleware استفاده کنیم
			# برای حال حاضر، headers را در response dict اضافه می‌کنیم
			if isinstance(response, dict):
				# اگر response dict باشد، headers را در metadata اضافه می‌کنیم
				# در production می‌توان از Response object استفاده کرد
				pass
			elif hasattr(response, 'headers'):
				response.headers["X-RateLimit-Limit"] = str(max_requests)
				response.headers["X-RateLimit-Remaining"] = str(remaining)
				response.headers["X-RateLimit-Reset"] = str(int(time.time()) + reset_after)
			
			return response
		return wrapper
	return decorator


def get_client_ip(request: Request) -> str:
	"""دریافت IP کلاینت از request"""
	client_ip = request.client.host if request.client else "unknown"
	if not client_ip or client_ip == "unknown":
		x_forwarded_for = request.headers.get("X-Forwarded-For")
		if x_forwarded_for:
			client_ip = x_forwarded_for.split(",")[0].strip()
		else:
			x_real_ip = request.headers.get("X-Real-IP")
			if x_real_ip:
				client_ip = x_real_ip
	return client_ip

