from __future__ import annotations

from typing import Optional
from fastapi import Depends, Header, Request
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from adapters.db.repositories.api_key_repo import ApiKeyRepository
from adapters.db.models.user import User
from app.core.security import hash_api_key
from app.core.responses import ApiError
from app.core.i18n import negotiate_locale, Translator
from app.core.calendar import get_calendar_type_from_header, CalendarType


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
			return permission_obj.business_permissions
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
	
	def is_business_owner(self) -> bool:
		"""بررسی اینکه آیا کاربر مالک کسب و کار است یا نه"""
		if not self.business_id or not self.db:
			return False
		
		from adapters.db.models.business import Business
		business = self.db.get(Business, self.business_id)
		return business and business.owner_id == self.user.id
	
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
	
	def can_manage_business_users(self) -> bool:
		"""بررسی دسترسی مدیریت کاربران کسب و کار"""
		return self.has_business_permission("settings", "manage_users")
	
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
		# SuperAdmin دسترسی به همه کسب و کارها دارد
		if self.is_superadmin():
			return True
		
		# اگر مالک کسب و کار است، دسترسی دارد
		if self.is_business_owner() and business_id == self.business_id:
			return True
		
		# بررسی دسترسی‌های کسب و کار
		return business_id == self.business_id
	
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
	authorization: Optional[str] = Header(default=None), 
	db: Session = Depends(get_db)
) -> AuthContext:
	"""دریافت اطلاعات کامل کاربر کنونی و تنظیمات از درخواست"""
	if not authorization or not authorization.startswith("ApiKey "):
		raise ApiError("UNAUTHORIZED", "Missing or invalid API key", http_status=401)

	api_key = authorization[len("ApiKey ") :].strip()
	key_hash = hash_api_key(api_key)
	repo = ApiKeyRepository(db)
	obj = repo.get_by_hash(key_hash)
	if not obj or obj.revoked_at is not None:
		raise ApiError("UNAUTHORIZED", "Invalid API key", http_status=401)

	from adapters.db.models.user import User
	user = db.get(User, obj.user_id)
	if not user or not user.is_active:
		raise ApiError("UNAUTHORIZED", "Invalid API key", http_status=401)

	# تشخیص زبان از هدر Accept-Language
	language = _detect_language(request)
	
	# تشخیص نوع تقویم از هدر X-Calendar-Type
	calendar_type = _detect_calendar_type(request)
	
	# تشخیص منطقه زمانی از هدر X-Timezone (اختیاری)
	timezone = _detect_timezone(request)
	
	# تشخیص کسب و کار از هدر X-Business-ID (آینده)
	business_id = _detect_business_id(request)
	
	# تشخیص سال مالی از هدر X-Fiscal-Year-ID (آینده)
	fiscal_year_id = _detect_fiscal_year_id(request)

	return AuthContext(
		user=user, 
		api_key_id=obj.id,
		language=language,
		calendar_type=calendar_type,
		timezone=timezone,
		business_id=business_id,
		fiscal_year_id=fiscal_year_id,
		db=db
	)


def _detect_language(request: Request) -> str:
	"""تشخیص زبان از هدر Accept-Language"""
	accept_language = request.headers.get("Accept-Language")
	return negotiate_locale(accept_language)


def _detect_calendar_type(request: Request) -> CalendarType:
	"""تشخیص نوع تقویم از هدر X-Calendar-Type"""
	calendar_header = request.headers.get("X-Calendar-Type")
	return get_calendar_type_from_header(calendar_header)


def _detect_timezone(request: Request) -> Optional[str]:
	"""تشخیص منطقه زمانی از هدر X-Timezone"""
	return request.headers.get("X-Timezone")


def _detect_business_id(request: Request) -> Optional[int]:
	"""تشخیص ID کسب و کار از هدر X-Business-ID (آینده)"""
	business_id_str = request.headers.get("X-Business-ID")
	if business_id_str:
		try:
			return int(business_id_str)
		except ValueError:
			pass
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


