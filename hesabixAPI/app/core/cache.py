from __future__ import annotations

import json
import logging
import time
from datetime import date, datetime
from decimal import Decimal
from functools import wraps
from typing import Any, Optional

import redis
from redis.exceptions import ConnectionError as RedisConnectionError, RedisError
from pydantic import BaseModel

from app.core.settings import get_settings

logger = logging.getLogger(__name__)

# Global Redis client instance
_redis_client: Optional[redis.Redis] = None


def _json_serializer(obj: Any) -> Any:
	"""Serializer برای مقادیر غیرقابل JSON مثل Decimal/Datetime/BaseModel"""
	if isinstance(obj, Decimal):
		return float(obj)
	if isinstance(obj, (datetime, date)):
		return obj.isoformat()
	if isinstance(obj, BaseModel):
		return obj.model_dump()
	if hasattr(obj, "dict"):
		try:
			return obj.dict()
		except Exception:
			pass
	if hasattr(obj, "__dict__"):
		return obj.__dict__
	return str(obj)


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
	
	# خواندن از DB اگر در دسترس باشد - استفاده از context manager برای جلوگیری از connection leak
	try:
		from adapters.db.session import get_db_session
		from app.services.system_settings_service import get_redis_configuration
		with get_db_session() as db:
			redis_config = get_redis_configuration(db)
			redis_enabled = redis_config.get('enabled', False)
			redis_host = redis_config.get('host', 'localhost')
			redis_port = redis_config.get('port', 6379)
			redis_db = redis_config.get('db', 0)
			redis_password = redis_config.get('password')
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
	
	def set_with_tag(self, key: str, value: Any, tag: str, ttl: int = 300) -> bool:
		"""
		ذخیره مقدار در cache با tag برای مدیریت بهتر
		
		Args:
			key: کلید cache
			value: مقدار برای ذخیره
			tag: tag برای گروه‌بندی کلیدها (مثلاً business_id)
			ttl: زمان انقضا به ثانیه
		
		Returns:
			True اگر موفق باشد
		"""
		if not self.enabled:
			return False
		
		try:
			# ذخیره مقدار با serializer ایمن برای Decimal/Datetime/BaseModel
			serialized = json.dumps(value, ensure_ascii=False, default=_json_serializer)
			self.client.setex(key, ttl, serialized)
			
			# اضافه کردن کلید به set مربوط به tag
			tag_key = f"cache_tag:{tag}"
			self.client.sadd(tag_key, key)
			# تنظیم TTL برای tag set (بیشتر از TTL کلید اصلی)
			self.client.expire(tag_key, ttl + 60)
			
			return True
		except (RedisError, Exception) as e:
			logger.warning(f"Cache set_with_tag error for key {key}, tag {tag}: {e}")
			return False
	
	def invalidate_by_tag(self, tag: str) -> int:
		"""
		حذف تمام کلیدهای مربوط به یک tag
		
		Args:
			tag: tag برای حذف کلیدها
		
		Returns:
			تعداد کلیدهای حذف شده
		"""
		if not self.enabled:
			return 0
		
		try:
			tag_key = f"cache_tag:{tag}"
			# دریافت تمام کلیدهای مربوط به tag
			keys = self.client.smembers(tag_key)
			if keys:
				deleted = self.client.delete(*keys)
				# حذف tag set
				self.client.delete(tag_key)
				return deleted
			return 0
		except (RedisError, Exception) as e:
			logger.warning(f"Cache invalidate_by_tag error for tag {tag}: {e}")
			return 0
	
	def set_with_business_tag(self, key: str, value: Any, business_id: int, fiscal_year_id: Optional[int] = None, ttl: int = 300) -> bool:
		"""
		ذخیره مقدار در cache با tag بر اساس business_id و fiscal_year_id
		
		این متد کلید را در چند set ذخیره می‌کند:
		- cache_tag:persons:business:{business_id} - برای تمام کش‌های business
		- cache_tag:persons:business:{business_id}:fiscal_year:{fiscal_year_id} - برای کش‌های خاص fiscal_year
		
		Args:
			key: کلید cache
			value: مقدار برای ذخیره
			business_id: شناسه کسب‌وکار
			fiscal_year_id: شناسه سال مالی (اختیاری)
			ttl: زمان انقضا به ثانیه
		
		Returns:
			True اگر موفق باشد
		"""
		if not self.enabled:
			return False
		
		try:
			# ذخیره مقدار با serializer ایمن برای Decimal/Datetime/BaseModel
			serialized = json.dumps(value, ensure_ascii=False, default=_json_serializer)
			self.client.setex(key, ttl, serialized)
			
			# اضافه کردن کلید به set مربوط به business_id
			business_tag_key = f"cache_tag:persons:business:{business_id}"
			self.client.sadd(business_tag_key, key)
			self.client.expire(business_tag_key, ttl + 60)
			
			# اگر fiscal_year_id مشخص باشد، به set مربوط به آن هم اضافه می‌کنیم
			if fiscal_year_id:
				fiscal_tag_key = f"cache_tag:persons:business:{business_id}:fiscal_year:{fiscal_year_id}"
				self.client.sadd(fiscal_tag_key, key)
				self.client.expire(fiscal_tag_key, ttl + 60)
			
			return True
		except (RedisError, Exception) as e:
			logger.warning(f"Cache set_with_business_tag error for key {key}, business_id {business_id}: {e}")
			return False
	
	def invalidate_by_business(self, business_id: int, fiscal_year_id: Optional[int] = None) -> int:
		"""
		حذف انتخابی کش‌های مربوط به business_id و fiscal_year_id
		
		Args:
			business_id: شناسه کسب‌وکار
			fiscal_year_id: شناسه سال مالی (اختیاری)
				- اگر None باشد، تمام کش‌های مربوط به business_id حذف می‌شوند
				- اگر مشخص باشد، فقط کش‌های مربوط به آن fiscal_year_id حذف می‌شوند
		
		Returns:
			تعداد کلیدهای حذف شده
		"""
		if not self.enabled:
			return 0
		
		total_deleted = 0
		
		try:
			if fiscal_year_id:
				# حذف فقط کش‌های مربوط به fiscal_year_id مشخص
				fiscal_tag_key = f"cache_tag:persons:business:{business_id}:fiscal_year:{fiscal_year_id}"
				keys = self.client.smembers(fiscal_tag_key)
				if keys:
					deleted = self.client.delete(*keys)
					self.client.delete(fiscal_tag_key)
					total_deleted += deleted
			else:
				# حذف تمام کش‌های مربوط به business_id
				business_tag_key = f"cache_tag:persons:business:{business_id}"
				keys = self.client.smembers(business_tag_key)
				if keys:
					deleted = self.client.delete(*keys)
					self.client.delete(business_tag_key)
					total_deleted += deleted
				
				# همچنین تمام tag های مربوط به fiscal_year های مختلف را هم حذف می‌کنیم
				fiscal_pattern = f"cache_tag:persons:business:{business_id}:fiscal_year:*"
				fiscal_tag_keys = self.client.keys(fiscal_pattern)
				for fiscal_tag_key in fiscal_tag_keys:
					fiscal_keys = self.client.smembers(fiscal_tag_key)
					if fiscal_keys:
						deleted = self.client.delete(*fiscal_keys)
						self.client.delete(fiscal_tag_key)
						total_deleted += deleted
			
			return total_deleted
		except (RedisError, Exception) as e:
			logger.warning(f"Cache invalidate_by_business error for business_id {business_id}, fiscal_year_id {fiscal_year_id}: {e}")
			return total_deleted
	
	def publish_invalidation(self, channel: str, message: dict) -> bool:
		"""
		انتشار پیام invalidation از طریق Redis Pub/Sub
		
		Args:
			channel: نام کانال Pub/Sub
			message: پیام برای انتشار (dict که به JSON تبدیل می‌شود)
		
		Returns:
			True اگر موفق باشد
		"""
		if not self.enabled:
			return False
		
		try:
			message_json = json.dumps(message, ensure_ascii=False)
			self.client.publish(channel, message_json)
			return True
		except (RedisError, Exception) as e:
			logger.warning(f"Cache publish_invalidation error for channel {channel}: {e}")
			return False
	
	def subscribe_invalidation(self, channel: str, callback: callable) -> Optional[Any]:
		"""
		اشتراک در کانال Pub/Sub برای دریافت پیام‌های invalidation
		
		Args:
			channel: نام کانال Pub/Sub
			callback: تابع callback که با پیام دریافت شده فراخوانی می‌شود
				callback(message_dict) -> None
		
		Returns:
			PubSub object یا None در صورت خطا
		"""
		if not self.enabled:
			return None
		
		try:
			pubsub = self.client.pubsub()
			pubsub.subscribe(channel)
			
			def message_handler(message):
				if message['type'] == 'message':
					try:
						message_data = json.loads(message['data'])
						callback(message_data)
					except (json.JSONDecodeError, Exception) as e:
						logger.warning(f"Error processing invalidation message: {e}")
			
			# اجرای handler در thread جداگانه (برای non-blocking)
			import threading
			def listen():
				try:
					for message in pubsub.listen():
						if message['type'] == 'message':
							message_handler(message)
				except Exception as e:
					logger.error(f"Error in pubsub listen thread: {e}", exc_info=True)
				finally:
					try:
						pubsub.close()
					except Exception:
						pass
			
			thread = threading.Thread(target=listen, daemon=True, name=f"cache-invalidation-subscriber-{channel}")
			thread.start()
			
			return pubsub
		except (RedisError, Exception) as e:
			logger.warning(f"Cache subscribe_invalidation error for channel {channel}: {e}")
			return None
	
	def set_with_products_tag(self, key: str, value: Any, business_id: int, category_id: Optional[int] = None, ttl: int = 300) -> bool:
		"""
		ذخیره مقدار در cache با tag بر اساس business_id و category_id برای محصولات
		
		این متد کلید را در چند set ذخیره می‌کند:
		- cache_tag:products:business:{business_id} - برای تمام کش‌های products این business
		- cache_tag:products:business:{business_id}:category:{category_id} - برای کش‌های خاص category
		
		Args:
			key: کلید cache
			value: مقدار برای ذخیره
			business_id: شناسه کسب‌وکار
			category_id: شناسه دسته‌بندی (اختیاری)
			ttl: زمان انقضا به ثانیه
		
		Returns:
			True اگر موفق باشد
		"""
		if not self.enabled:
			return False
		
		try:
			# ذخیره مقدار با serializer ایمن برای Decimal/Datetime/BaseModel
			serialized = json.dumps(value, ensure_ascii=False, default=_json_serializer)
			self.client.setex(key, ttl, serialized)
			
			# اضافه کردن کلید به set مربوط به business_id
			business_tag_key = f"cache_tag:products:business:{business_id}"
			self.client.sadd(business_tag_key, key)
			self.client.expire(business_tag_key, ttl + 60)
			
			# اگر category_id مشخص باشد، به set مربوط به آن هم اضافه می‌کنیم
			if category_id:
				category_tag_key = f"cache_tag:products:business:{business_id}:category:{category_id}"
				self.client.sadd(category_tag_key, key)
				self.client.expire(category_tag_key, ttl + 60)
			
			return True
		except (RedisError, Exception) as e:
			logger.warning(f"Cache set_with_products_tag error for key {key}, business_id {business_id}: {e}")
			return False
	
	def invalidate_products_by_business(self, business_id: int, category_id: Optional[int] = None, product_id: Optional[int] = None) -> int:
		"""
		حذف انتخابی کش‌های مربوط به products بر اساس business_id، category_id و product_id
		
		Args:
			business_id: شناسه کسب‌وکار (الزامی)
			category_id: شناسه دسته‌بندی (اختیاری)
				- اگر None باشد، تمام کش‌های products مربوط به business_id حذف می‌شوند
				- اگر مشخص باشد، فقط کش‌های مربوط به آن category_id حذف می‌شوند
			product_id: شناسه محصول خاص (اختیاری)
				- اگر مشخص باشد، کش محصول خاص هم حذف می‌شود
		
		Returns:
			تعداد کلیدهای حذف شده
		"""
		if not self.enabled:
			return 0
		
		total_deleted = 0
		
		try:
			# حذف کش محصول خاص اگر مشخص شده باشد
			if product_id:
				product_key = f"product:{business_id}:{product_id}"
				if self.client.exists(product_key):
					self.client.delete(product_key)
					total_deleted += 1
			
			if category_id:
				# حذف فقط کش‌های مربوط به category_id مشخص
				category_tag_key = f"cache_tag:products:business:{business_id}:category:{category_id}"
				keys = self.client.smembers(category_tag_key)
				if keys:
					deleted = self.client.delete(*keys)
					self.client.delete(category_tag_key)
					total_deleted += deleted
			else:
				# حذف تمام کش‌های مربوط به business_id
				business_tag_key = f"cache_tag:products:business:{business_id}"
				keys = self.client.smembers(business_tag_key)
				if keys:
					deleted = self.client.delete(*keys)
					self.client.delete(business_tag_key)
					total_deleted += deleted
				
				# همچنین تمام tag های مربوط به category های مختلف را هم حذف می‌کنیم
				category_pattern = f"cache_tag:products:business:{business_id}:category:*"
				category_tag_keys = self.client.keys(category_pattern)
				for category_tag_key in category_tag_keys:
					category_keys = self.client.smembers(category_tag_key)
					if category_keys:
						deleted = self.client.delete(*category_keys)
						self.client.delete(category_tag_key)
						total_deleted += deleted
			
			return total_deleted
		except (RedisError, Exception) as e:
			logger.warning(f"Cache invalidate_products_by_business error for business_id {business_id}, category_id {category_id}, product_id {product_id}: {e}")
			return total_deleted
	
	def set_with_invoices_tag(self, key: str, value: Any, business_id: int, fiscal_year_id: Optional[int] = None, document_type: Optional[str] = None, project_id: Optional[int] = None, ttl: int = 300) -> bool:
		"""
		ذخیره مقدار در cache با tag بر اساس business_id, fiscal_year_id, document_type و project_id برای فاکتورها
		
		این متد کلید را در چند set ذخیره می‌کند:
		- cache_tag:invoices:business:{business_id} - برای تمام کش‌های invoices این business
		- cache_tag:invoices:business:{business_id}:fiscal_year:{fiscal_year_id} - برای کش‌های خاص fiscal_year
		- cache_tag:invoices:business:{business_id}:document_type:{document_type} - برای کش‌های خاص document_type
		- cache_tag:invoices:business:{business_id}:project:{project_id} - برای کش‌های خاص project
		
		Args:
			key: کلید cache
			value: مقدار برای ذخیره
			business_id: شناسه کسب‌وکار
			fiscal_year_id: شناسه سال مالی (اختیاری - بسیار مهم)
			document_type: نوع فاکتور (invoice_sales, invoice_purchase, ...) (اختیاری)
			project_id: شناسه پروژه (اختیاری)
			ttl: زمان انقضا به ثانیه
		
		Returns:
			True اگر موفق باشد
		"""
		if not self.enabled:
			return False
		
		try:
			# ذخیره مقدار
			if isinstance(value, (dict, list, bool, int, float)):
				serialized = json.dumps(value, ensure_ascii=False)
			else:
				serialized = str(value)
			
			self.client.setex(key, ttl, serialized)
			
			# اضافه کردن کلید به set مربوط به business_id
			business_tag_key = f"cache_tag:invoices:business:{business_id}"
			self.client.sadd(business_tag_key, key)
			self.client.expire(business_tag_key, ttl + 60)
			
			# اگر fiscal_year_id مشخص باشد، به set مربوط به آن هم اضافه می‌کنیم
			if fiscal_year_id:
				fiscal_tag_key = f"cache_tag:invoices:business:{business_id}:fiscal_year:{fiscal_year_id}"
				self.client.sadd(fiscal_tag_key, key)
				self.client.expire(fiscal_tag_key, ttl + 60)
			
			# اگر document_type مشخص باشد
			if document_type:
				doc_type_tag_key = f"cache_tag:invoices:business:{business_id}:document_type:{document_type}"
				self.client.sadd(doc_type_tag_key, key)
				self.client.expire(doc_type_tag_key, ttl + 60)
			
			# اگر project_id مشخص باشد
			if project_id:
				project_tag_key = f"cache_tag:invoices:business:{business_id}:project:{project_id}"
				self.client.sadd(project_tag_key, key)
				self.client.expire(project_tag_key, ttl + 60)
			
			return True
		except (RedisError, Exception) as e:
			logger.warning(f"Cache set_with_invoices_tag error for key {key}, business_id {business_id}: {e}")
			return False
	
	def invalidate_invoices_by_business(self, business_id: int, fiscal_year_id: Optional[int] = None, invoice_id: Optional[int] = None, document_type: Optional[str] = None, project_id: Optional[int] = None) -> int:
		"""
		حذف انتخابی کش‌های مربوط به invoices بر اساس business_id, fiscal_year_id, invoice_id, document_type و project_id
		
		Args:
			business_id: شناسه کسب‌وکار (الزامی)
			fiscal_year_id: شناسه سال مالی (اختیاری - بسیار مهم)
				- اگر None باشد، تمام کش‌های invoices مربوط به business_id حذف می‌شوند
				- اگر مشخص باشد، فقط کش‌های مربوط به آن fiscal_year_id حذف می‌شوند
			invoice_id: شناسه فاکتور خاص (اختیاری)
			document_type: نوع فاکتور (اختیاری)
			project_id: شناسه پروژه (اختیاری)
		
		Returns:
			تعداد کلیدهای حذف شده
		"""
		if not self.enabled:
			return 0
		
		total_deleted = 0
		
		try:
			# حذف کش فاکتور خاص اگر مشخص شده باشد
			if invoice_id:
				invoice_key = f"invoice:{business_id}:{invoice_id}"
				if self.client.exists(invoice_key):
					self.client.delete(invoice_key)
					total_deleted += 1
			
			# اگر fiscal_year_id مشخص باشد، فقط کش‌های مربوط به آن را حذف می‌کنیم
			if fiscal_year_id:
				fiscal_tag_key = f"cache_tag:invoices:business:{business_id}:fiscal_year:{fiscal_year_id}"
				keys = self.client.smembers(fiscal_tag_key)
				if keys:
					deleted = self.client.delete(*keys)
					self.client.delete(fiscal_tag_key)
					total_deleted += deleted
			else:
				# حذف تمام کش‌های مربوط به business_id
				business_tag_key = f"cache_tag:invoices:business:{business_id}"
				keys = self.client.smembers(business_tag_key)
				if keys:
					deleted = self.client.delete(*keys)
					self.client.delete(business_tag_key)
					total_deleted += deleted
				
				# همچنین تمام tag های مربوط به fiscal_year های مختلف را هم حذف می‌کنیم
				fiscal_pattern = f"cache_tag:invoices:business:{business_id}:fiscal_year:*"
				fiscal_tag_keys = self.client.keys(fiscal_pattern)
				for fiscal_tag_key in fiscal_tag_keys:
					fiscal_keys = self.client.smembers(fiscal_tag_key)
					if fiscal_keys:
						deleted = self.client.delete(*fiscal_keys)
						self.client.delete(fiscal_tag_key)
						total_deleted += deleted
			
			# حذف tag های document_type
			if document_type:
				doc_type_pattern = f"cache_tag:invoices:business:{business_id}:document_type:{document_type}"
				if self.client.exists(doc_type_pattern):
					doc_type_keys = self.client.smembers(doc_type_pattern)
					if doc_type_keys:
						deleted = self.client.delete(*doc_type_keys)
						self.client.delete(doc_type_pattern)
						total_deleted += deleted
			
			# حذف tag های project
			if project_id:
				project_pattern = f"cache_tag:invoices:business:{business_id}:project:{project_id}"
				if self.client.exists(project_pattern):
					project_keys = self.client.smembers(project_pattern)
					if project_keys:
						deleted = self.client.delete(*project_keys)
						self.client.delete(project_pattern)
						total_deleted += deleted
			
			return total_deleted
		except (RedisError, Exception) as e:
			logger.warning(f"Cache invalidate_invoices_by_business error for business_id {business_id}, fiscal_year_id {fiscal_year_id}, invoice_id {invoice_id}, document_type {document_type}, project_id {project_id}: {e}")
			return total_deleted
	
	def set_with_documents_tag(self, key: str, value: Any, business_id: int, fiscal_year_id: Optional[int] = None, document_type: Optional[str] = None, ttl: int = 300) -> bool:
		"""
		ذخیره مقدار در cache با tag بر اساس business_id, fiscal_year_id و document_type برای اسناد عمومی
		
		Args:
			key: کلید cache
			value: مقدار برای ذخیره
			business_id: شناسه کسب‌وکار
			fiscal_year_id: شناسه سال مالی (اختیاری)
			document_type: نوع سند (اختیاری)
			ttl: زمان انقضا به ثانیه
		
		Returns:
			True اگر موفق باشد
		"""
		if not self.enabled:
			return False
		
		try:
			# ذخیره مقدار
			if isinstance(value, (dict, list, bool, int, float)):
				serialized = json.dumps(value, ensure_ascii=False)
			else:
				serialized = str(value)
			
			self.client.setex(key, ttl, serialized)
			
			# اضافه کردن کلید به set مربوط به business_id
			business_tag_key = f"cache_tag:documents:business:{business_id}"
			self.client.sadd(business_tag_key, key)
			self.client.expire(business_tag_key, ttl + 60)
			
			# اگر fiscal_year_id مشخص باشد
			if fiscal_year_id:
				fiscal_tag_key = f"cache_tag:documents:business:{business_id}:fiscal_year:{fiscal_year_id}"
				self.client.sadd(fiscal_tag_key, key)
				self.client.expire(fiscal_tag_key, ttl + 60)
			
			# اگر document_type مشخص باشد
			if document_type:
				doc_type_tag_key = f"cache_tag:documents:business:{business_id}:document_type:{document_type}"
				self.client.sadd(doc_type_tag_key, key)
				self.client.expire(doc_type_tag_key, ttl + 60)
			
			return True
		except (RedisError, Exception) as e:
			logger.warning(f"Cache set_with_documents_tag error for key {key}, business_id {business_id}: {e}")
			return False
	
	def invalidate_documents_by_business(self, business_id: int, fiscal_year_id: Optional[int] = None, document_id: Optional[int] = None, document_type: Optional[str] = None) -> int:
		"""
		حذف انتخابی کش‌های مربوط به documents بر اساس business_id, fiscal_year_id, document_id و document_type
		
		Args:
			business_id: شناسه کسب‌وکار (الزامی)
			fiscal_year_id: شناسه سال مالی (اختیاری)
			document_id: شناسه سند خاص (اختیاری)
			document_type: نوع سند (اختیاری)
		
		Returns:
			تعداد کلیدهای حذف شده
		"""
		if not self.enabled:
			return 0
		
		total_deleted = 0
		
		try:
			# حذف کش سند خاص اگر مشخص شده باشد
			if document_id:
				document_key = f"document:{business_id}:{document_id}"
				if self.client.exists(document_key):
					self.client.delete(document_key)
					total_deleted += 1
			
			if fiscal_year_id:
				# حذف فقط کش‌های مربوط به fiscal_year_id مشخص
				fiscal_tag_key = f"cache_tag:documents:business:{business_id}:fiscal_year:{fiscal_year_id}"
				keys = self.client.smembers(fiscal_tag_key)
				if keys:
					deleted = self.client.delete(*keys)
					self.client.delete(fiscal_tag_key)
					total_deleted += deleted
			else:
				# حذف تمام کش‌های مربوط به business_id
				business_tag_key = f"cache_tag:documents:business:{business_id}"
				keys = self.client.smembers(business_tag_key)
				if keys:
					deleted = self.client.delete(*keys)
					self.client.delete(business_tag_key)
					total_deleted += deleted
				
				# همچنین تمام tag های مربوط به fiscal_year های مختلف را هم حذف می‌کنیم
				fiscal_pattern = f"cache_tag:documents:business:{business_id}:fiscal_year:*"
				fiscal_tag_keys = self.client.keys(fiscal_pattern)
				for fiscal_tag_key in fiscal_tag_keys:
					fiscal_keys = self.client.smembers(fiscal_tag_key)
					if fiscal_keys:
						deleted = self.client.delete(*fiscal_keys)
						self.client.delete(fiscal_tag_key)
						total_deleted += deleted
			
			# حذف tag های document_type
			if document_type:
				doc_type_pattern = f"cache_tag:documents:business:{business_id}:document_type:{document_type}"
				if self.client.exists(doc_type_pattern):
					doc_type_keys = self.client.smembers(doc_type_pattern)
					if doc_type_keys:
						deleted = self.client.delete(*doc_type_keys)
						self.client.delete(doc_type_pattern)
						total_deleted += deleted
			
			return total_deleted
		except (RedisError, Exception) as e:
			logger.warning(f"Cache invalidate_documents_by_business error for business_id {business_id}, fiscal_year_id {fiscal_year_id}, document_id {document_id}, document_type {document_type}: {e}")
			return total_deleted
	
	def set_with_expense_income_tag(self, key: str, value: Any, business_id: int, fiscal_year_id: Optional[int] = None, ttl: int = 300) -> bool:
		"""
		ذخیره مقدار در cache با tag بر اساس business_id و fiscal_year_id برای هزینه/درآمد
		
		Args:
			key: کلید cache
			value: مقدار برای ذخیره
			business_id: شناسه کسب‌وکار
			fiscal_year_id: شناسه سال مالی (اختیاری)
			ttl: زمان انقضا به ثانیه
		
		Returns:
			True اگر موفق باشد
		"""
		if not self.enabled:
			return False
		
		try:
			# ذخیره مقدار
			if isinstance(value, (dict, list, bool, int, float)):
				serialized = json.dumps(value, ensure_ascii=False)
			else:
				serialized = str(value)
			
			self.client.setex(key, ttl, serialized)
			
			# اضافه کردن کلید به set مربوط به business_id
			business_tag_key = f"cache_tag:expense_income:business:{business_id}"
			self.client.sadd(business_tag_key, key)
			self.client.expire(business_tag_key, ttl + 60)
			
			# اگر fiscal_year_id مشخص باشد
			if fiscal_year_id:
				fiscal_tag_key = f"cache_tag:expense_income:business:{business_id}:fiscal_year:{fiscal_year_id}"
				self.client.sadd(fiscal_tag_key, key)
				self.client.expire(fiscal_tag_key, ttl + 60)
			
			return True
		except (RedisError, Exception) as e:
			logger.warning(f"Cache set_with_expense_income_tag error for key {key}, business_id {business_id}: {e}")
			return False
	
	def invalidate_expense_income_by_business(self, business_id: int, fiscal_year_id: Optional[int] = None, document_id: Optional[int] = None) -> int:
		"""
		حذف انتخابی کش‌های مربوط به expense_income بر اساس business_id, fiscal_year_id و document_id
		
		Args:
			business_id: شناسه کسب‌وکار (الزامی)
			fiscal_year_id: شناسه سال مالی (اختیاری)
			document_id: شناسه سند خاص (اختیاری)
		
		Returns:
			تعداد کلیدهای حذف شده
		"""
		if not self.enabled:
			return 0
		
		total_deleted = 0
		
		try:
			# حذف کش سند خاص اگر مشخص شده باشد
			if document_id:
				document_key = f"expense_income:{business_id}:{document_id}"
				if self.client.exists(document_key):
					self.client.delete(document_key)
					total_deleted += 1
			
			if fiscal_year_id:
				# حذف فقط کش‌های مربوط به fiscal_year_id مشخص
				fiscal_tag_key = f"cache_tag:expense_income:business:{business_id}:fiscal_year:{fiscal_year_id}"
				keys = self.client.smembers(fiscal_tag_key)
				if keys:
					deleted = self.client.delete(*keys)
					self.client.delete(fiscal_tag_key)
					total_deleted += deleted
			else:
				# حذف تمام کش‌های مربوط به business_id
				business_tag_key = f"cache_tag:expense_income:business:{business_id}"
				keys = self.client.smembers(business_tag_key)
				if keys:
					deleted = self.client.delete(*keys)
					self.client.delete(business_tag_key)
					total_deleted += deleted
				
				# همچنین تمام tag های مربوط به fiscal_year های مختلف را هم حذف می‌کنیم
				fiscal_pattern = f"cache_tag:expense_income:business:{business_id}:fiscal_year:*"
				fiscal_tag_keys = self.client.keys(fiscal_pattern)
				for fiscal_tag_key in fiscal_tag_keys:
					fiscal_keys = self.client.smembers(fiscal_tag_key)
					if fiscal_keys:
						deleted = self.client.delete(*fiscal_keys)
						self.client.delete(fiscal_tag_key)
						total_deleted += deleted
			
			return total_deleted
		except (RedisError, Exception) as e:
			logger.warning(f"Cache invalidate_expense_income_by_business error for business_id {business_id}, fiscal_year_id {fiscal_year_id}, document_id {document_id}: {e}")
			return total_deleted
	
	def set_with_warehouses_tag(self, key: str, value: Any, business_id: int, ttl: int = 60) -> bool:
		"""
		ذخیره مقدار در cache با tag بر اساس business_id برای لیست انبارها
		
		Args:
			key: کلید cache
			value: مقدار برای ذخیره
			business_id: شناسه کسب‌وکار
			ttl: زمان انقضا به ثانیه
		
		Returns:
			True اگر موفق باشد
		"""
		if not self.enabled:
			return False
		
		try:
			# ذخیره مقدار
			if isinstance(value, (dict, list, bool, int, float)):
				serialized = json.dumps(value, ensure_ascii=False)
			else:
				serialized = str(value)
			
			self.client.setex(key, ttl, serialized)
			
			# اضافه کردن کلید به set مربوط به business_id
			business_tag_key = f"cache_tag:warehouses:business:{business_id}"
			self.client.sadd(business_tag_key, key)
			self.client.expire(business_tag_key, ttl + 60)
			
			return True
		except (RedisError, Exception) as e:
			logger.warning(f"Cache set_with_warehouses_tag error for key {key}, business_id {business_id}: {e}")
			return False
	
	def invalidate_warehouses_by_business(self, business_id: int) -> int:
		"""
		حذف کش‌های مربوط به warehouses بر اساس business_id
		
		Args:
			business_id: شناسه کسب‌وکار (الزامی)
		
		Returns:
			تعداد کلیدهای حذف شده
		"""
		if not self.enabled:
			return 0
		
		total_deleted = 0
		
		try:
			# حذف تمام کش‌های مربوط به business_id
			business_tag_key = f"cache_tag:warehouses:business:{business_id}"
			keys = self.client.smembers(business_tag_key)
			if keys:
				deleted = self.client.delete(*keys)
				self.client.delete(business_tag_key)
				total_deleted += deleted
			
			# Pattern-based invalidation به عنوان fallback
			pattern = f"warehouses_list:*"
			pattern_keys = self.client.keys(pattern)
			if pattern_keys:
				deleted = self.client.delete(*pattern_keys)
				total_deleted += deleted
			
			# ارسال پیام invalidation از طریق Pub/Sub
			invalidation_message = {
				"type": "warehouses_cache_invalidation",
				"business_id": business_id,
				"timestamp": time.time()
			}
			self.publish_invalidation("cache_invalidation", invalidation_message)
			
			return total_deleted
		except (RedisError, Exception) as e:
			logger.warning(f"Cache invalidate_warehouses_by_business error for business_id {business_id}: {e}")
			return total_deleted
	
	def set_with_warehouse_docs_tag(self, key: str, value: Any, business_id: int, fiscal_year_id: Optional[int] = None, doc_type: Optional[str] = None, warehouse_id: Optional[int] = None, status: Optional[str] = None, ttl: int = 60) -> bool:
		"""
		ذخیره مقدار در cache با tag بر اساس business_id, fiscal_year_id, doc_type, warehouse_id و status برای اسناد انبار
		
		Args:
			key: کلید cache
			value: مقدار برای ذخیره
			business_id: شناسه کسب‌وکار
			fiscal_year_id: شناسه سال مالی (اختیاری)
			doc_type: نوع سند (receipt, issue, transfer, adjustment, production_in, production_out) (اختیاری)
			warehouse_id: شناسه انبار (اختیاری)
			status: وضعیت سند (draft, posted, cancelled) (اختیاری)
			ttl: زمان انقضا به ثانیه
		
		Returns:
			True اگر موفق باشد
		"""
		if not self.enabled:
			return False
		
		try:
			# ذخیره مقدار
			if isinstance(value, (dict, list, bool, int, float)):
				serialized = json.dumps(value, ensure_ascii=False)
			else:
				serialized = str(value)
			
			self.client.setex(key, ttl, serialized)
			
			# اضافه کردن کلید به set مربوط به business_id
			business_tag_key = f"cache_tag:warehouse_docs:business:{business_id}"
			self.client.sadd(business_tag_key, key)
			self.client.expire(business_tag_key, ttl + 60)
			
			# اگر fiscal_year_id مشخص باشد
			if fiscal_year_id:
				fiscal_tag_key = f"cache_tag:warehouse_docs:business:{business_id}:fiscal_year:{fiscal_year_id}"
				self.client.sadd(fiscal_tag_key, key)
				self.client.expire(fiscal_tag_key, ttl + 60)
			
			# اگر doc_type مشخص باشد
			if doc_type:
				doc_type_tag_key = f"cache_tag:warehouse_docs:business:{business_id}:doc_type:{doc_type}"
				self.client.sadd(doc_type_tag_key, key)
				self.client.expire(doc_type_tag_key, ttl + 60)
			
			# اگر warehouse_id مشخص باشد
			if warehouse_id:
				warehouse_tag_key = f"cache_tag:warehouse_docs:business:{business_id}:warehouse:{warehouse_id}"
				self.client.sadd(warehouse_tag_key, key)
				self.client.expire(warehouse_tag_key, ttl + 60)
			
			# اگر status مشخص باشد
			if status:
				status_tag_key = f"cache_tag:warehouse_docs:business:{business_id}:status:{status}"
				self.client.sadd(status_tag_key, key)
				self.client.expire(status_tag_key, ttl + 60)
			
			return True
		except (RedisError, Exception) as e:
			logger.warning(f"Cache set_with_warehouse_docs_tag error for key {key}, business_id {business_id}: {e}")
			return False
	
	def invalidate_warehouse_docs_by_business(self, business_id: int, fiscal_year_id: Optional[int] = None, doc_type: Optional[str] = None, warehouse_id: Optional[int] = None, status: Optional[str] = None, document_id: Optional[int] = None) -> int:
		"""
		حذف انتخابی کش‌های مربوط به warehouse_docs بر اساس business_id, fiscal_year_id, doc_type, warehouse_id, status و document_id
		
		Args:
			business_id: شناسه کسب‌وکار (الزامی)
			fiscal_year_id: شناسه سال مالی (اختیاری)
			doc_type: نوع سند (اختیاری)
			warehouse_id: شناسه انبار (اختیاری)
			status: وضعیت سند (اختیاری)
			document_id: شناسه سند خاص (اختیاری)
		
		Returns:
			تعداد کلیدهای حذف شده
		"""
		if not self.enabled:
			return 0
		
		total_deleted = 0
		
		try:
			# حذف کش سند خاص اگر مشخص شده باشد
			if document_id:
				document_key = f"warehouse_doc:{business_id}:{document_id}"
				if self.client.exists(document_key):
					self.client.delete(document_key)
					total_deleted += 1
			
			# جمع‌آوری کلیدها از tag های مختلف
			keys_to_delete = set()
			
			# اگر fiscal_year_id مشخص باشد، فقط کش‌های مربوط به آن را حذف می‌کنیم
			if fiscal_year_id:
				fiscal_tag_key = f"cache_tag:warehouse_docs:business:{business_id}:fiscal_year:{fiscal_year_id}"
				keys = self.client.smembers(fiscal_tag_key)
				if keys:
					keys_to_delete.update(keys)
					self.client.delete(fiscal_tag_key)
			else:
				# حذف تمام کش‌های مربوط به business_id
				business_tag_key = f"cache_tag:warehouse_docs:business:{business_id}"
				keys = self.client.smembers(business_tag_key)
				if keys:
					keys_to_delete.update(keys)
				
				# همچنین تمام tag های مربوط به fiscal_year های مختلف را هم حذف می‌کنیم
				fiscal_pattern = f"cache_tag:warehouse_docs:business:{business_id}:fiscal_year:*"
				fiscal_tag_keys = self.client.keys(fiscal_pattern)
				for fiscal_tag_key in fiscal_tag_keys:
					fiscal_keys = self.client.smembers(fiscal_tag_key)
					if fiscal_keys:
						keys_to_delete.update(fiscal_keys)
						self.client.delete(fiscal_tag_key)
			
			# حذف tag های doc_type
			if doc_type:
				doc_type_tag_key = f"cache_tag:warehouse_docs:business:{business_id}:doc_type:{doc_type}"
				keys = self.client.smembers(doc_type_tag_key)
				if keys:
					keys_to_delete.update(keys)
					self.client.delete(doc_type_tag_key)
			else:
				# حذف تمام tag های doc_type
				doc_type_pattern = f"cache_tag:warehouse_docs:business:{business_id}:doc_type:*"
				doc_type_tag_keys = self.client.keys(doc_type_pattern)
				for doc_type_tag_key in doc_type_tag_keys:
					doc_type_keys = self.client.smembers(doc_type_tag_key)
					if doc_type_keys:
						keys_to_delete.update(doc_type_keys)
						self.client.delete(doc_type_tag_key)
			
			# حذف tag های warehouse
			if warehouse_id:
				warehouse_tag_key = f"cache_tag:warehouse_docs:business:{business_id}:warehouse:{warehouse_id}"
				keys = self.client.smembers(warehouse_tag_key)
				if keys:
					keys_to_delete.update(keys)
					self.client.delete(warehouse_tag_key)
			else:
				# حذف تمام tag های warehouse
				warehouse_pattern = f"cache_tag:warehouse_docs:business:{business_id}:warehouse:*"
				warehouse_tag_keys = self.client.keys(warehouse_pattern)
				for warehouse_tag_key in warehouse_tag_keys:
					warehouse_keys = self.client.smembers(warehouse_tag_key)
					if warehouse_keys:
						keys_to_delete.update(warehouse_keys)
						self.client.delete(warehouse_tag_key)
			
			# حذف tag های status
			if status:
				status_tag_key = f"cache_tag:warehouse_docs:business:{business_id}:status:{status}"
				keys = self.client.smembers(status_tag_key)
				if keys:
					keys_to_delete.update(keys)
					self.client.delete(status_tag_key)
			else:
				# حذف تمام tag های status
				status_pattern = f"cache_tag:warehouse_docs:business:{business_id}:status:*"
				status_tag_keys = self.client.keys(status_pattern)
				for status_tag_key in status_tag_keys:
					status_keys = self.client.smembers(status_tag_key)
					if status_keys:
						keys_to_delete.update(status_keys)
						self.client.delete(status_tag_key)
			
			# حذف کلیدهای جمع‌آوری شده
			if keys_to_delete:
				deleted = self.client.delete(*keys_to_delete)
				total_deleted += deleted
			
			# حذف business tag
			business_tag_key = f"cache_tag:warehouse_docs:business:{business_id}"
			if self.client.exists(business_tag_key):
				self.client.delete(business_tag_key)
			
			# Pattern-based invalidation به عنوان fallback
			pattern = f"warehouse_docs_list:*"
			pattern_keys = self.client.keys(pattern)
			if pattern_keys:
				deleted = self.client.delete(*pattern_keys)
				total_deleted += deleted
			
			# ارسال پیام invalidation از طریق Pub/Sub
			invalidation_message = {
				"type": "warehouse_docs_cache_invalidation",
				"business_id": business_id,
				"fiscal_year_id": fiscal_year_id,
				"doc_type": doc_type,
				"warehouse_id": warehouse_id,
				"status": status,
				"document_id": document_id,
				"timestamp": time.time()
			}
			self.publish_invalidation("cache_invalidation", invalidation_message)
			
			return total_deleted
		except (RedisError, Exception) as e:
			logger.warning(f"Cache invalidate_warehouse_docs_by_business error for business_id {business_id}, fiscal_year_id {fiscal_year_id}, doc_type {doc_type}, warehouse_id {warehouse_id}, status {status}, document_id {document_id}: {e}")
			return total_deleted


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

