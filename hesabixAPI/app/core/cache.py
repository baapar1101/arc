from __future__ import annotations

import json
import logging
from typing import Optional, Any
from functools import wraps
import redis
from redis.exceptions import RedisError, ConnectionError as RedisConnectionError

from app.core.settings import get_settings

logger = logging.getLogger(__name__)

# Global Redis client instance
_redis_client: Optional[redis.Redis] = None


def get_redis_client(force_reconnect: bool = False) -> Optional[redis.Redis]:
	"""Get or create Redis client instance"""
	global _redis_client
	
	if _redis_client is not None and not force_reconnect:
		return _redis_client
	
	settings = get_settings()
	
	# تلاش برای خواندن تنظیمات از DB (اگر در دسترس باشد)
	redis_enabled = getattr(settings, 'redis_enabled', False)
	redis_host = getattr(settings, 'redis_host', 'localhost')
	redis_port = getattr(settings, 'redis_port', 6379)
	redis_db = getattr(settings, 'redis_db', 0)
	redis_password = getattr(settings, 'redis_password', None)
	
	# خواندن از DB اگر در دسترس باشد
	try:
		from adapters.db.session import get_db
		from app.services.system_settings_service import get_redis_configuration
		db_gen = get_db()
		db = next(db_gen)
		try:
			redis_config = get_redis_configuration(db)
			redis_enabled = redis_config.get('enabled', False)
			redis_host = redis_config.get('host', 'localhost')
			redis_port = redis_config.get('port', 6379)
			redis_db = redis_config.get('db', 0)
			redis_password = redis_config.get('password')
		finally:
			db.close()
	except Exception:
		# اگر DB در دسترس نبود، از env استفاده می‌کنیم
		pass
	
	# اگر Redis غیرفعال باشد، None برمی‌گردانیم
	if not redis_enabled:
		if _redis_client is not None:
			try:
				_redis_client.close()
			except Exception:
				pass
			_redis_client = None
		return None
	
	try:
		# بستن اتصال قبلی اگر وجود داشت
		if _redis_client is not None:
			try:
				_redis_client.close()
			except Exception:
				pass
		
		_redis_client = redis.Redis(
			host=redis_host,
			port=redis_port,
			db=redis_db,
			password=redis_password,
			decode_responses=True,  # برای کار با string ها
			socket_connect_timeout=2,
			socket_timeout=2,
			retry_on_timeout=True,
			health_check_interval=30
		)
		
		# تست اتصال
		_redis_client.ping()
		logger.info(f"Redis connected successfully to {redis_host}:{redis_port}")
		return _redis_client
	except (RedisConnectionError, RedisError) as e:
		logger.warning(f"Redis connection failed: {e}. Cache will be disabled.")
		_redis_client = None
		return None
	except Exception as e:
		logger.error(f"Unexpected error connecting to Redis: {e}", exc_info=True)
		_redis_client = None
		return None


class CacheService:
	"""Service برای مدیریت cache با Redis"""
	
	def __init__(self):
		self._refresh_client()
	
	def _refresh_client(self):
		"""Refresh Redis client connection"""
		self.client = get_redis_client()
		self.enabled = self.client is not None
	
	def get(self, key: str) -> Optional[Any]:
		"""دریافت مقدار از cache"""
		if not self.enabled:
			return None
		
		try:
			value = self.client.get(key)
			if value is None:
				return None
			
			# تلاش برای deserialize JSON
			try:
				return json.loads(value)
			except (json.JSONDecodeError, TypeError):
				# اگر JSON نبود، تلاش می‌کنیم boolean های متنی را تشخیص دهیم
				if isinstance(value, str):
					lowered = value.strip().lower()
					if lowered in {"true", "false"}:
						return lowered == "true"
				# در غیر این صورت همان مقدار بازگردانده می‌شود
				return value
		except (RedisError, Exception) as e:
			logger.warning(f"Cache get error for key {key}: {e}")
			return None
	
	def set(self, key: str, value: Any, ttl: int = 300) -> bool:
		"""ذخیره مقدار در cache با TTL (ثانیه)"""
		if not self.enabled:
			return False
		
		try:
			# Serialize به JSON برای انواع ساختاری/عددی/بولی
			if isinstance(value, (dict, list, bool, int, float)):
				serialized = json.dumps(value, ensure_ascii=False)
			else:
				serialized = str(value)
			
			self.client.setex(key, ttl, serialized)
			return True
		except (RedisError, Exception) as e:
			logger.warning(f"Cache set error for key {key}: {e}")
			return False
	
	def delete(self, key: str) -> bool:
		"""حذف یک کلید از cache"""
		if not self.enabled:
			return False
		
		try:
			self.client.delete(key)
			return True
		except (RedisError, Exception) as e:
			logger.warning(f"Cache delete error for key {key}: {e}")
			return False
	
	def delete_pattern(self, pattern: str) -> int:
		"""حذف تمام کلیدهای مطابق با pattern"""
		if not self.enabled:
			return 0
		
		try:
			keys = self.client.keys(pattern)
			if keys:
				return self.client.delete(*keys)
			return 0
		except (RedisError, Exception) as e:
			logger.warning(f"Cache delete_pattern error for pattern {pattern}: {e}")
			return 0
	
	def exists(self, key: str) -> bool:
		"""بررسی وجود کلید در cache"""
		if not self.enabled:
			return False
		
		try:
			return self.client.exists(key) > 0
		except (RedisError, Exception) as e:
			logger.warning(f"Cache exists error for key {key}: {e}")
			return False
	
	def invalidate(self, pattern: str) -> int:
		"""Invalidate تمام کلیدهای مطابق با pattern"""
		return self.delete_pattern(pattern)


# Global cache service instance
_cache_service = CacheService()


def get_cache() -> CacheService:
	"""Get global cache service instance"""
	# Refresh client در صورت نیاز
	_cache_service._refresh_client()
	return _cache_service


def cached(key_prefix: str, ttl: int = 300):
	"""
	Decorator برای cache کردن نتیجه function
	
	Args:
		key_prefix: پیشوند برای کلید cache
		ttl: زمان انقضا به ثانیه (پیش‌فرض 5 دقیقه)
	
	Example:
		@cached("user", ttl=600)
		def get_user(user_id: int):
			...
	"""
	def decorator(func):
		@wraps(func)
		def wrapper(*args, **kwargs):
			cache = get_cache()
			
			# ساخت کلید cache از args و kwargs
			cache_key = f"{key_prefix}:{func.__name__}"
			if args:
				cache_key += f":{':'.join(str(arg) for arg in args)}"
			if kwargs:
				# فقط kwargs مهم را اضافه می‌کنیم
				important_kwargs = {k: v for k, v in kwargs.items() if k not in ['db', 'request']}
				if important_kwargs:
					cache_key += f":{':'.join(f'{k}={v}' for k, v in sorted(important_kwargs.items()))}"
			
			# تلاش برای دریافت از cache
			cached_value = cache.get(cache_key)
			if cached_value is not None:
				return cached_value
			
			# اگر در cache نبود، function را اجرا کن
			result = func(*args, **kwargs)
			
			# ذخیره در cache
			if result is not None:
				cache.set(cache_key, result, ttl)
			
			return result
		return wrapper
	return decorator

