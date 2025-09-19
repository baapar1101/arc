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
		fiscal_year_id: Optional[int] = None
	) -> None:
		self.user = user
		self.api_key_id = api_key_id
		self.language = language
		self.calendar_type = calendar_type
		self.timezone = timezone
		self.business_id = business_id
		self.fiscal_year_id = fiscal_year_id
		
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
				"created_at": self.user.created_at.isoformat() if self.user.created_at else None,
				"updated_at": self.user.updated_at.isoformat() if self.user.updated_at else None,
			},
			"api_key_id": self.api_key_id,
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
		fiscal_year_id=fiscal_year_id
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


