from __future__ import annotations

from typing import Optional
from fastapi import Depends, Header, Request
from sqlalchemy.orm import Session
from datetime import datetime

from adapters.db.session import get_db
from adapters.db.repositories.api_key_repo import ApiKeyRepository
from adapters.db.models.user import User
from app.core.security import hash_api_key
from app.core.responses import ApiError
from app.core.i18n import negotiate_locale, Translator
from app.core.calendar import get_calendar_type_from_header, CalendarType
from app.core.cache import get_cache


class AuthContext:
	"""کلاس مرکزی برای نگهداری اطلاعات کاربر کنونی و تنظیمات"""
	
	def __init__(
		self, 
		user: User, 
		api_key_id: int,
		language: str = "fa",
		calendar_type: CalendarType = "jalali",
		timezone: Optional[str] = None,
		business_id: Optional[int] = None,
		fiscal_year_id: Optional[int] = None,
		db: Optional[Session] = None
	) -> None:
		self.user = user
		self.api_key_id = api_key_id
		self.language = language
		self.calendar_type = calendar_type
		self.timezone = timezone
		self.business_id = business_id
		self.fiscal_year_id = fiscal_year_id
		self.db = db
		
		# دسترسی‌های اپلیکیشن
		self.app_permissions = user.app_permissions or {}
		
		# دسترسی‌های کسب و کار (در صورت وجود business_id)
		self.business_permissions = self._get_business_permissions() if business_id and db else {}
		
		# ایجاد translator برای زبان تشخیص داده شده
		self._translator = Translator(language)
	
	@staticmethod
	def _normalize_permissions_value(value) -> dict:
		"""نرمال‌سازی مقدار JSON دسترسی‌ها به dict برای سازگاری با داده‌های legacy"""
		if isinstance(value, dict):
			return value
		if isinstance(value, list):
			try:
				# لیست جفت‌ها مانند [["join", true], ["sales", {..}]]
				if all(isinstance(item, list) and len(item) == 2 for item in value):
					return {k: v for k, v in value if isinstance(k, str)}
				# لیست دیکشنری‌ها مانند [{"join": true}, {"sales": {...}}]
				if all(isinstance(item, dict) for item in value):
					merged = {}
					for item in value:
						merged.update({k: v for k, v in item.items()})
					return merged
			except Exception:
				return {}
		
		return {}
	
	def get_translator(self) -> Translator:
		"""دریافت translator برای ترجمه"""
		return self._translator
	
	def get_calendar_type(self) -> CalendarType:
		"""دریافت نوع تقویم"""
		return self.calendar_type
	
	def get_user_id(self) -> int:
		"""دریافت ID کاربر"""
		return self.user.id
	
	def get_user_email(self) -> Optional[str]:
		"""دریافت ایمیل کاربر"""
		return self.user.email
	
	def get_user_mobile(self) -> Optional[str]:
		"""دریافت شماره موبایل کاربر"""
		return self.user.mobile
	
	def get_user_name(self) -> str:
		"""دریافت نام کامل کاربر"""
		first_name = self.user.first_name or ""
		last_name = self.user.last_name or ""
		return f"{first_name} {last_name}".strip()
	
	def get_referral_code(self) -> Optional[str]:
		"""دریافت کد معرف کاربر"""
		return getattr(self.user, "referral_code", None)
	
	def is_user_active(self) -> bool:
		"""بررسی فعال بودن کاربر"""
		return self.user.is_active
	
	def _get_business_permissions(self) -> dict:
		"""دریافت دسترسی‌های کسب و کار از دیتابیس"""
		if not self.business_id or not self.db:
			return {}
		
		from adapters.db.repositories.business_permission_repo import BusinessPermissionRepository
		repo = BusinessPermissionRepository(self.db)
		permission_obj = repo.get_by_user_and_business(self.user.id, self.business_id)
		
		if permission_obj and permission_obj.business_permissions:
			raw_permissions = permission_obj.business_permissions
			normalized_permissions = AuthContext._normalize_permissions_value(raw_permissions)
			return normalized_permissions
		
		return {}
	
	# بررسی دسترسی‌های اپلیکیشن
	def has_app_permission(self, permission: str) -> bool:
		"""بررسی دسترسی در سطح اپلیکیشن"""
		# SuperAdmin تمام دسترسی‌های اپلیکیشن را دارد
		if self.app_permissions.get("superadmin", False):
			return True
		
		return self.app_permissions.get(permission, False)
	
	def is_superadmin(self) -> bool:
		"""بررسی superadmin بودن"""
		return self.has_app_permission("superadmin")
	
	def can_manage_users(self) -> bool:
		"""بررسی دسترسی مدیریت کاربران در سطح اپلیکیشن"""
		return self.has_app_permission("user_management")
	
	def can_manage_businesses(self) -> bool:
		"""بررسی دسترسی مدیریت کسب و کارها"""
		return self.has_app_permission("business_management")
	
	def can_access_system_settings(self) -> bool:
		"""بررسی دسترسی به تنظیمات سیستم"""
		return self.has_app_permission("system_settings")
	
	def can_access_support_operator(self) -> bool:
		"""بررسی دسترسی به پنل اپراتور پشتیبانی"""
		return self.has_app_permission("support_operator")
	
	def is_business_owner(self, business_id: int = None) -> bool:
		"""بررسی اینکه آیا کاربر مالک کسب و کار است یا نه"""
		import logging
		logger = logging.getLogger(__name__)
		
		logger.info(f"=== is_business_owner START ===")
		logger.info(f"Requested business_id: {business_id}")
		logger.info(f"Context business_id: {self.business_id}")
		logger.info(f"User ID: {self.user.id}")
		logger.info(f"DB available: {self.db is not None}")
		
		target_business_id = business_id or self.business_id
		logger.info(f"Target business_id: {target_business_id}")
		
		if not target_business_id or not self.db:
			logger.info(f"is_business_owner: no business_id ({target_business_id}) or db ({self.db is not None})")
			logger.info(f"=== is_business_owner END (no business_id or db) ===")
			return False
		
		from adapters.db.models.business import Business
		business = self.db.get(Business, target_business_id)
		logger.info(f"Business lookup result: {business}")
		
		if business:
			logger.info(f"Business owner_id: {business.owner_id}")
			is_owner = business.owner_id == self.user.id
			logger.info(f"is_owner: {is_owner}")
		else:
			logger.info("Business not found")
			is_owner = False
		
		logger.info(f"=== is_business_owner END (result: {is_owner}) ===")
		return is_owner
	
	# بررسی دسترسی‌های کسب و کار
	def has_business_permission(self, section: str, action: str) -> bool:
		"""بررسی دسترسی در سطح کسب و کار"""
		if not self.business_id:
			return False
		
		# SuperAdmin تمام دسترسی‌ها را دارد
		if self.is_superadmin():
			return True
		
		# مالک کسب و کار تمام دسترسی‌ها را دارد
		if self.is_business_owner():
			return True
		
		# بررسی دسترسی‌های عادی
		if not self.business_permissions:
			return False
		
		# بررسی وجود بخش
		if section not in self.business_permissions:
			return False
		
		section_perms = self.business_permissions[section]
		
		# اگر بخش خالی است، فقط خواندن
		if not section_perms:
			return action == "read"
		
		# بررسی دسترسی خاص
		return section_perms.get(action, False)
	
	def can_read_section(self, section: str) -> bool:
		"""بررسی دسترسی خواندن بخش در کسب و کار"""
		if not self.business_id:
			return False
		
		# SuperAdmin و مالک کسب و کار دسترسی کامل دارند
		if self.is_superadmin() or self.is_business_owner():
			return True
		
		return section in self.business_permissions
	
	def can_write_section(self, section: str) -> bool:
		"""بررسی دسترسی نوشتن در بخش"""
		return self.has_business_permission(section, "write")
	
	def can_delete_section(self, section: str) -> bool:
		"""بررسی دسترسی حذف در بخش"""
		return self.has_business_permission(section, "delete")
	
	def can_approve_section(self, section: str) -> bool:
		"""بررسی دسترسی تأیید در بخش"""
		return self.has_business_permission(section, "approve")
	
	def can_export_section(self, section: str) -> bool:
		"""بررسی دسترسی صادرات در بخش"""
		return self.has_business_permission(section, "export")
	
	def can_manage_business_users(self, business_id: int = None) -> bool:
		"""بررسی دسترسی مدیریت کاربران کسب و کار"""
		import logging
		logger = logging.getLogger(__name__)
		
		# SuperAdmin دسترسی کامل دارد
		if self.is_superadmin():
			logger.info(f"can_manage_business_users: user {self.user.id} is superadmin")
			return True
		
		# مالک کسب و کار دسترسی کامل دارد
		if self.is_business_owner(business_id):
			logger.info(f"can_manage_business_users: user {self.user.id} is business owner")
			return True
		
		# بررسی دسترسی در سطح کسب و کار
		has_permission = self.has_business_permission("settings", "manage_users")
		logger.info(f"can_manage_business_users: user {self.user.id} has permission: {has_permission}")
		return has_permission
	
	# ترکیب دسترسی‌ها
	def has_any_permission(self, section: str, action: str) -> bool:
		"""بررسی دسترسی در هر دو سطح"""
		# SuperAdmin دسترسی کامل دارد
		if self.is_superadmin():
			return True
		
		# بررسی دسترسی کسب و کار
		return self.has_business_permission(section, action)
	
	def can_access_business(self, business_id: int) -> bool:
		"""بررسی دسترسی به کسب و کار خاص"""
		import logging
		logger = logging.getLogger(__name__)
		
		logger.info(f"=== can_access_business START ===")
		logger.info(f"User ID: {self.user.id}")
		logger.info(f"Requested business ID: {business_id}")
		logger.info(f"User context business_id: {self.business_id}")
		logger.info(f"User app permissions: {self.app_permissions}")
		
		# SuperAdmin دسترسی به همه کسب و کارها دارد
		if self.is_superadmin():
			logger.info(f"User {self.user.id} is superadmin, granting access to business {business_id}")
			logger.info(f"=== can_access_business END (superadmin) ===")
			return True
		
		# بررسی مالکیت کسب و کار
		if self.db:
			from adapters.db.models.business import Business
			business = self.db.get(Business, business_id)
			logger.info(f"Business lookup result: {business}")
			if business:
				# بررسی حذف‌شدگی کسب و کار
				if business.deleted_at is not None:
					logger.warning(f"Business {business_id} is deleted (deleted_at: {business.deleted_at}), denying access")
					logger.info(f"=== can_access_business END (deleted) ===")
					return False
				
				logger.info(f"Business owner ID: {business.owner_id}")
				if business.owner_id == self.user.id:
					logger.info(f"User {self.user.id} is business owner of {business_id}, granting access")
					logger.info(f"=== can_access_business END (owner) ===")
					return True
		else:
			logger.info("No database connection available for business lookup")
		
		# بررسی عضویت در کسب و کار
		if self.db:
			from adapters.db.repositories.business_permission_repo import BusinessPermissionRepository
			permission_repo = BusinessPermissionRepository(self.db)
			business_permission = permission_repo.get_by_user_and_business(self.user.id, business_id)
			logger.info(f"Business permission lookup result: {business_permission}")
			
			if business_permission:
				# بررسی دسترسی join
				permissions = business_permission.business_permissions or {}
				logger.info(f"User permissions for business {business_id}: {permissions}")
				join_permission = permissions.get('join')
				logger.info(f"Join permission: {join_permission}")
				
				if join_permission == True:
					logger.info(f"User {self.user.id} is member of business {business_id}, granting access")
					logger.info(f"=== can_access_business END (member) ===")
					return True
				else:
					logger.info(f"User {self.user.id} does not have join permission for business {business_id}")
			else:
				logger.info(f"No business permission found for user {self.user.id} and business {business_id}")
		else:
			logger.info("No database connection available for permission lookup")
		
		# اگر کسب و کار در context کاربر است، دسترسی دارد
		if business_id == self.business_id:
			logger.info(f"User {self.user.id} has context access to business {business_id}")
			logger.info(f"=== can_access_business END (context) ===")
			return True
		
		logger.info(f"User {self.user.id} does not have access to business {business_id}")
		logger.info(f"=== can_access_business END (denied) ===")
		return False
	
	def is_business_member(self, business_id: int) -> bool:
		"""بررسی اینکه آیا کاربر عضو کسب و کار است یا نه (دسترسی join)"""
		import logging
		logger = logging.getLogger(__name__)
		
		logger.info(f"Checking business membership: user {self.user.id}, business {business_id}")
		
		# SuperAdmin عضو همه کسب و کارها محسوب می‌شود
		if self.is_superadmin():
			logger.info(f"User {self.user.id} is superadmin, is member of all businesses")
			return True
		
		# اگر مالک کسب و کار است، عضو محسوب می‌شود
		if self.is_business_owner() and business_id == self.business_id:
			logger.info(f"User {self.user.id} is business owner of {business_id}, is member")
			return True
		
		# بررسی دسترسی join در business_permissions
		if not self.db:
			logger.info(f"No database session available")
			return False
		
		from adapters.db.repositories.business_permission_repo import BusinessPermissionRepository
		repo = BusinessPermissionRepository(self.db)
		permission_obj = repo.get_by_user_and_business(self.user.id, business_id)
		
		if not permission_obj:
			logger.info(f"No business permission found for user {self.user.id} and business {business_id}")
			return False
		
		# بررسی دسترسی join
		business_perms = AuthContext._normalize_permissions_value(permission_obj.business_permissions)
		has_join_access = business_perms.get('join', False)
		logger.info(f"Business membership check: user {self.user.id} join access to business {business_id}: {has_join_access}")
		return has_join_access
	
	def to_dict(self) -> dict:
		"""تبدیل به dictionary برای استفاده در API"""
		return {
			"user": {
				"id": self.user.id,
				"first_name": self.user.first_name,
				"last_name": self.user.last_name,
				"email": self.user.email,
				"mobile": self.user.mobile,
				"referral_code": getattr(self.user, "referral_code", None),
				"is_active": self.user.is_active,
				"email_verified": getattr(self.user, "email_verified", False),
				"mobile_verified": getattr(self.user, "mobile_verified", False),
				"app_permissions": self.app_permissions,
				"created_at": self.user.created_at.isoformat() if self.user.created_at else None,
				"updated_at": self.user.updated_at.isoformat() if self.user.updated_at else None,
			},
			"api_key_id": self.api_key_id,
			"permissions": {
				"app_permissions": self.app_permissions,
				"business_permissions": self.business_permissions,
				"is_superadmin": self.is_superadmin(),
				"is_business_owner": self.is_business_owner(),
			},
			"settings": {
				"language": self.language,
				"calendar_type": self.calendar_type,
				"timezone": self.timezone,
				"business_id": self.business_id,
				"fiscal_year_id": self.fiscal_year_id,
			}
		}


def get_current_user(
	request: Request,
	db: Session = Depends(get_db)
) -> AuthContext:
	"""دریافت اطلاعات کامل کاربر کنونی و تنظیمات از درخواست"""
	import logging
	logger = logging.getLogger(__name__)
	
	# Get authorization from request headers
	auth_header = request.headers.get("Authorization")
	logger.info(f"Auth header: {auth_header}")
	
	if not auth_header or not auth_header.startswith("ApiKey "):
		logger.warning(f"Invalid auth header: {auth_header}")
		raise ApiError("UNAUTHORIZED", "Missing or invalid API key", http_status=401)

	api_key = auth_header[len("ApiKey ") :].strip()
	key_hash = hash_api_key(api_key)
	
	# تلاش برای دریافت از cache
	cache = get_cache()
	cache_key = f"api_key:{key_hash}"
	cached_data = cache.get(cache_key)
	
	if cached_data:
		# استفاده از داده‌های cache شده
		api_key_id = cached_data.get("id")
		user_id = cached_data.get("user_id")
		key_type = cached_data.get("key_type")
		expires_at_str = cached_data.get("expires_at")
		revoked_at_str = cached_data.get("revoked_at")
		ip_whitelist = cached_data.get("ip")
		
		# بررسی revoked
		if revoked_at_str:
			raise ApiError("UNAUTHORIZED", "Invalid API key", http_status=401)
		
		# بررسی انقضا
		if expires_at_str:
			expires_at = datetime.fromisoformat(expires_at_str)
			if expires_at < datetime.utcnow():
				# حذف از cache اگر منقضی شده
				cache.delete(cache_key)
				raise ApiError("UNAUTHORIZED", "API key has expired", http_status=401)
		
		# دریافت user از دیتابیس (user ممکن است تغییر کند، پس cache نمی‌کنیم)
		user = db.get(User, user_id)
		if not user or not user.is_active:
			# حذف از cache اگر user معتبر نیست
			cache.delete(cache_key)
			raise ApiError("UNAUTHORIZED", "Invalid API key", http_status=401)
		
		# بررسی IP Whitelist (فقط برای personal keys)
		if key_type == "personal" and ip_whitelist:
			client_ip = request.client.host if request.client else None
			if not client_ip:
				x_forwarded_for = request.headers.get("X-Forwarded-For")
				if x_forwarded_for:
					client_ip = x_forwarded_for.split(",")[0].strip()
				else:
					x_real_ip = request.headers.get("X-Real-IP")
					if x_real_ip:
						client_ip = x_real_ip
			
			if client_ip:
				allowed_ips = [ip.strip() for ip in ip_whitelist.split(",") if ip.strip()]
				if allowed_ips and client_ip not in allowed_ips:
					logger.warning(f"IP {client_ip} not in whitelist for API key {api_key_id}")
					raise ApiError("FORBIDDEN", "IP address not allowed", http_status=403)
		
		# به‌روزرسانی last_used_at (هر 60 ثانیه یکبار) - در background
		# این کار را به صورت async انجام نمی‌دهیم تا blocking نباشد
		# در production می‌توان از background task استفاده کرد
		
		# ساخت یک mock object برای obj (فقط برای سازگاری با کد بعدی)
		from types import SimpleNamespace
		obj = SimpleNamespace(
			id=api_key_id,
			user_id=user_id,
			key_type=key_type,
			expires_at=datetime.fromisoformat(expires_at_str) if expires_at_str else None,
			ip=ip_whitelist,
			last_used_at=None  # برای به‌روزرسانی بعدی
		)
	else:
		# اگر در cache نبود، از دیتابیس بخوان
		repo = ApiKeyRepository(db)
		obj = repo.get_by_hash(key_hash)
		if not obj or obj.revoked_at is not None:
			raise ApiError("UNAUTHORIZED", "Invalid API key", http_status=401)
		
		# بررسی انقضا (فقط برای personal API keys - session keys همیشه expires_at=None دارند)
		if obj.expires_at and obj.expires_at < datetime.utcnow():
			raise ApiError("UNAUTHORIZED", "API key has expired", http_status=401)
		
		# ذخیره در cache
		cache.set(cache_key, {
			"id": obj.id,
			"user_id": obj.user_id,
			"key_type": obj.key_type,
			"expires_at": obj.expires_at.isoformat() if obj.expires_at else None,
			"revoked_at": obj.revoked_at.isoformat() if obj.revoked_at else None,
			"ip": obj.ip,
		}, ttl=300)  # 5 دقیقه cache
		
		# بررسی IP Whitelist (فقط برای personal keys)
		if obj.key_type == "personal" and obj.ip:
			client_ip = request.client.host if request.client else None
			if not client_ip:
				x_forwarded_for = request.headers.get("X-Forwarded-For")
				if x_forwarded_for:
					client_ip = x_forwarded_for.split(",")[0].strip()
				else:
					x_real_ip = request.headers.get("X-Real-IP")
					if x_real_ip:
						client_ip = x_real_ip
			
			if client_ip:
				allowed_ips = [ip.strip() for ip in obj.ip.split(",") if ip.strip()]
				if allowed_ips and client_ip not in allowed_ips:
					logger.warning(f"IP {client_ip} not in whitelist for API key {obj.id}")
					raise ApiError("FORBIDDEN", "IP address not allowed", http_status=403)
		
		# دریافت user از دیتابیس
		user = db.get(User, obj.user_id)
		if not user or not user.is_active:
			raise ApiError("UNAUTHORIZED", "Invalid API key", http_status=401)
		
		# به‌روزرسانی last_used_at (هر 60 ثانیه یکبار)
		if obj.last_used_at is None or (datetime.utcnow() - obj.last_used_at).total_seconds() > 60:
			obj.last_used_at = datetime.utcnow()
			db.add(obj)
			db.commit()

	# دریافت user از دیتابیس (اگر قبلاً دریافت نشده باشد)
	# user در خط 490 یا 568 دریافت شده است
	if 'user' not in locals():
		user = db.get(User, obj.user_id)
		if not user or not user.is_active:
			raise ApiError("UNAUTHORIZED", "Invalid API key", http_status=401)

	# تشخیص زبان از هدر Accept-Language با fallback به تنظیمات سیستم
	language = _detect_language(request, db)
	
	# تشخیص نوع تقویم از هدر X-Calendar-Type
	calendar_type = _detect_calendar_type(request)
	
	# تشخیص منطقه زمانی از هدر X-Timezone (اختیاری)
	timezone = _detect_timezone(request)
	
	# تشخیص کسب و کار از هدر X-Business-ID (آینده)
	business_id = _detect_business_id(request)
	
	# تشخیص سال مالی از هدر X-Fiscal-Year-ID (آینده)
	fiscal_year_id = _detect_fiscal_year_id(request)

	auth_context = AuthContext(
		user=user, 
		api_key_id=obj.id,
		language=language,
		calendar_type=calendar_type,
		timezone=timezone,
		business_id=business_id,
		fiscal_year_id=fiscal_year_id,
		db=db
	)
	
	# تنظیم context برای لاگ‌گیری خودکار
	try:
		from adapters.db.activity_log_hooks import ActivityLogContext
		ActivityLogContext.set_context(
			session=db,
			user_id=user.id,
			business_id=business_id,
			request=request
		)
	except Exception as e:
		# اگر خطا در تنظیم context بود، لاگ کن اما ادامه بده
		logger.warning(f"Failed to set activity log context: {e}")
	
	logger.info(f"AuthContext created successfully")
	return auth_context


def _detect_language(request: Request, db: Session | None = None) -> str:
	"""تشخیص زبان از هدر Accept-Language با fallback به تنظیمات سیستم"""
	accept_language = request.headers.get("Accept-Language")
	detected = negotiate_locale(accept_language)
	
	# اگر زبان تشخیص داده نشد یا db ارائه شده، از تنظیمات سیستم استفاده کن
	if detected == "en" and db is not None:
		from app.services.system_settings_service import get_default_language
		default_lang = get_default_language(db)
		# اگر default_language تنظیم شده و با detected متفاوت است، از default استفاده کن
		# اما اگر accept_language وجود دارد، اولویت با آن است
		if not accept_language:
			return default_lang
	
	return detected


def _detect_calendar_type(request: Request) -> CalendarType:
	"""تشخیص نوع تقویم از هدر X-Calendar-Type"""
	calendar_header = request.headers.get("X-Calendar-Type")
	return get_calendar_type_from_header(calendar_header)


def _detect_timezone(request: Request) -> Optional[str]:
	"""تشخیص منطقه زمانی از هدر X-Timezone"""
	return request.headers.get("X-Timezone")


def _detect_business_id(request: Request) -> Optional[int]:
	"""تشخیص ID کسب و کار از هدر X-Business-ID (آینده)"""
	import logging
	logger = logging.getLogger(__name__)
	
	business_id_str = request.headers.get("X-Business-ID")
	logger.info(f"X-Business-ID header: {business_id_str}")
	
	if business_id_str:
		try:
			business_id = int(business_id_str)
			logger.info(f"Detected business ID: {business_id}")
			return business_id
		except ValueError:
			logger.warning(f"Invalid business ID format: {business_id_str}")
			pass
	
	logger.info("No business ID detected from headers")
	return None


def _detect_fiscal_year_id(request: Request) -> Optional[int]:
	"""تشخیص ID سال مالی از هدر X-Fiscal-Year-ID (آینده)"""
	fiscal_year_id_str = request.headers.get("X-Fiscal-Year-ID")
	if fiscal_year_id_str:
		try:
			return int(fiscal_year_id_str)
		except ValueError:
			pass
	return None


