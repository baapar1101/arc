from typing import Any, List, Optional, Union
from pydantic import BaseModel, EmailStr, Field
from enum import Enum


class FilterItem(BaseModel):
	property: str = Field(..., description="نام فیلد مورد نظر برای اعمال فیلتر")
	operator: str = Field(..., description="نوع عملگر: =, >, >=, <, <=, !=, *, ?*, *?, in")
	value: Any = Field(..., description="مقدار مورد نظر")


class QueryInfo(BaseModel):
	sort_by: Optional[str] = Field(default=None, description="نام فیلد مورد نظر برای مرتب سازی")
	sort_desc: bool = Field(default=False, description="false = مرتب سازی صعودی، true = مرتب سازی نزولی")
	take: int = Field(default=10, ge=1, le=1000, description="حداکثر تعداد رکورد بازگشتی")
	skip: int = Field(default=0, ge=0, description="تعداد رکوردی که از ابتدای لیست صرف نظر می شود")
	search: Optional[str] = Field(default=None, description="عبارت جستجو")
	search_fields: Optional[List[str]] = Field(default=None, description="آرایه ای از فیلدهایی که جستجو در آن انجام می گیرد")
	filters: Optional[List[FilterItem]] = Field(default=None, description="آرایه ای از اشیا برای اعمال فیلتر بر روی لیست")


class CaptchaSolve(BaseModel):
	captcha_id: str = Field(..., min_length=8)
	captcha_code: str = Field(..., min_length=3, max_length=8)


class RegisterRequest(CaptchaSolve):
	first_name: Optional[str] = Field(default=None, max_length=100)
	last_name: Optional[str] = Field(default=None, max_length=100)
	email: Optional[EmailStr] = None
	mobile: Optional[str] = Field(default=None, max_length=32)
	password: str = Field(..., min_length=8, max_length=128)
	device_id: Optional[str] = Field(default=None, max_length=100)
	referrer_code: Optional[str] = Field(default=None, min_length=4, max_length=32)


class LoginRequest(CaptchaSolve):
	identifier: str = Field(..., min_length=3, max_length=255)
	password: str = Field(..., min_length=8, max_length=128)
	device_id: Optional[str] = Field(default=None, max_length=100)


class ForgotPasswordRequest(CaptchaSolve):
	identifier: str = Field(..., min_length=3, max_length=255)


class ResetPasswordRequest(CaptchaSolve):
	token: str = Field(..., min_length=16)
	new_password: str = Field(..., min_length=8, max_length=128)


class ChangePasswordRequest(BaseModel):
	current_password: str = Field(..., min_length=8, max_length=128)
	new_password: str = Field(..., min_length=8, max_length=128)
	confirm_password: str = Field(..., min_length=8, max_length=128)


class CreateApiKeyRequest(BaseModel):
	name: Optional[str] = Field(default=None, max_length=100)
	scopes: Optional[str] = Field(default=None, max_length=500)
	expires_at: Optional[str] = None  # ISO string; parse server-side if provided


# Response Models
class SuccessResponse(BaseModel):
	success: bool = Field(default=True, description="وضعیت موفقیت عملیات")
	message: Optional[str] = Field(default=None, description="پیام توضیحی")
	data: Optional[Union[dict, list]] = Field(default=None, description="داده‌های بازگشتی")


class ErrorResponse(BaseModel):
	success: bool = Field(default=False, description="وضعیت موفقیت عملیات")
	message: str = Field(..., description="پیام خطا")
	error_code: Optional[str] = Field(default=None, description="کد خطا")
	details: Optional[dict] = Field(default=None, description="جزئیات خطا")


class UserResponse(BaseModel):
	id: int = Field(..., description="شناسه کاربر")
	email: Optional[str] = Field(default=None, description="ایمیل کاربر")
	mobile: Optional[str] = Field(default=None, description="شماره موبایل")
	first_name: Optional[str] = Field(default=None, description="نام")
	last_name: Optional[str] = Field(default=None, description="نام خانوادگی")
	is_active: bool = Field(..., description="وضعیت فعال بودن")
	referral_code: str = Field(..., description="کد معرفی")
	referred_by_user_id: Optional[int] = Field(default=None, description="شناسه کاربر معرف")
	app_permissions: Optional[dict] = Field(default=None, description="مجوزهای اپلیکیشن")
	created_at: str = Field(..., description="تاریخ ایجاد")
	updated_at: str = Field(..., description="تاریخ آخرین بروزرسانی")


class CaptchaResponse(BaseModel):
	captcha_id: str = Field(..., description="شناسه کپچا")
	image_base64: str = Field(..., description="تصویر کپچا به صورت base64")
	ttl_seconds: int = Field(..., description="زمان انقضا به ثانیه")


class LoginResponse(BaseModel):
	api_key: str = Field(..., description="کلید API")
	expires_at: Optional[str] = Field(default=None, description="تاریخ انقضا")
	user: UserResponse = Field(..., description="اطلاعات کاربر")


class ApiKeyResponse(BaseModel):
	id: int = Field(..., description="شناسه کلید")
	name: Optional[str] = Field(default=None, description="نام کلید")
	scopes: Optional[str] = Field(default=None, description="محدوده دسترسی")
	device_id: Optional[str] = Field(default=None, description="شناسه دستگاه")
	user_agent: Optional[str] = Field(default=None, description="اطلاعات مرورگر")
	ip: Optional[str] = Field(default=None, description="آدرس IP")
	expires_at: Optional[str] = Field(default=None, description="تاریخ انقضا")
	last_used_at: Optional[str] = Field(default=None, description="آخرین استفاده")
	created_at: str = Field(..., description="تاریخ ایجاد")


class ReferralStatsResponse(BaseModel):
	total_referrals: int = Field(..., description="تعداد کل معرفی‌ها")
	active_referrals: int = Field(..., description="تعداد معرفی‌های فعال")
	recent_referrals: int = Field(..., description="تعداد معرفی‌های اخیر")
	referral_rate: float = Field(..., description="نرخ معرفی")


class PaginationInfo(BaseModel):
	total: int = Field(..., description="تعداد کل رکوردها")
	page: int = Field(..., description="شماره صفحه فعلی")
	per_page: int = Field(..., description="تعداد رکورد در هر صفحه")
	total_pages: int = Field(..., description="تعداد کل صفحات")
	has_next: bool = Field(..., description="آیا صفحه بعدی وجود دارد")
	has_prev: bool = Field(..., description="آیا صفحه قبلی وجود دارد")


class UsersListResponse(BaseModel):
	items: List[UserResponse] = Field(..., description="لیست کاربران")
	pagination: PaginationInfo = Field(..., description="اطلاعات صفحه‌بندی")
	query_info: dict = Field(..., description="اطلاعات جستجو و فیلتر")


class UsersSummaryResponse(BaseModel):
	total_users: int = Field(..., description="تعداد کل کاربران")
	active_users: int = Field(..., description="تعداد کاربران فعال")
	inactive_users: int = Field(..., description="تعداد کاربران غیرفعال")
	active_percentage: float = Field(..., description="درصد کاربران فعال")


# Business Schemas
class BusinessType(str, Enum):
	COMPANY = "شرکت"
	SHOP = "مغازه"
	STORE = "فروشگاه"
	UNION = "اتحادیه"
	CLUB = "باشگاه"
	INSTITUTE = "موسسه"
	INDIVIDUAL = "شخصی"


class BusinessField(str, Enum):
	MANUFACTURING = "تولیدی"
	COMMERCIAL = "بازرگانی"
	SERVICE = "خدماتی"
	OTHER = "سایر"


class BusinessCreateRequest(BaseModel):
	name: str = Field(..., min_length=1, max_length=255, description="نام کسب و کار")
	business_type: BusinessType = Field(..., description="نوع کسب و کار")
	business_field: BusinessField = Field(..., description="زمینه فعالیت")
	address: Optional[str] = Field(default=None, max_length=1000, description="آدرس")
	phone: Optional[str] = Field(default=None, max_length=20, description="تلفن ثابت")
	mobile: Optional[str] = Field(default=None, max_length=20, description="موبایل")
	national_id: Optional[str] = Field(default=None, max_length=20, description="کد ملی")
	registration_number: Optional[str] = Field(default=None, max_length=50, description="شماره ثبت")
	economic_id: Optional[str] = Field(default=None, max_length=50, description="شناسه اقتصادی")
	country: Optional[str] = Field(default=None, max_length=100, description="کشور")
	province: Optional[str] = Field(default=None, max_length=100, description="استان")
	city: Optional[str] = Field(default=None, max_length=100, description="شهر")
	postal_code: Optional[str] = Field(default=None, max_length=20, description="کد پستی")


class BusinessUpdateRequest(BaseModel):
	name: Optional[str] = Field(default=None, min_length=1, max_length=255, description="نام کسب و کار")
	business_type: Optional[BusinessType] = Field(default=None, description="نوع کسب و کار")
	business_field: Optional[BusinessField] = Field(default=None, description="زمینه فعالیت")
	address: Optional[str] = Field(default=None, max_length=1000, description="آدرس")
	phone: Optional[str] = Field(default=None, max_length=20, description="تلفن ثابت")
	mobile: Optional[str] = Field(default=None, max_length=20, description="موبایل")
	national_id: Optional[str] = Field(default=None, max_length=20, description="کد ملی")
	registration_number: Optional[str] = Field(default=None, max_length=50, description="شماره ثبت")
	economic_id: Optional[str] = Field(default=None, max_length=50, description="شناسه اقتصادی")
	country: Optional[str] = Field(default=None, max_length=100, description="کشور")
	province: Optional[str] = Field(default=None, max_length=100, description="استان")
	city: Optional[str] = Field(default=None, max_length=100, description="شهر")
	postal_code: Optional[str] = Field(default=None, max_length=20, description="کد پستی")


class BusinessResponse(BaseModel):
	id: int = Field(..., description="شناسه کسب و کار")
	name: str = Field(..., description="نام کسب و کار")
	business_type: str = Field(..., description="نوع کسب و کار")
	business_field: str = Field(..., description="زمینه فعالیت")
	owner_id: int = Field(..., description="شناسه مالک")
	address: Optional[str] = Field(default=None, description="آدرس")
	phone: Optional[str] = Field(default=None, description="تلفن ثابت")
	mobile: Optional[str] = Field(default=None, description="موبایل")
	national_id: Optional[str] = Field(default=None, description="کد ملی")
	registration_number: Optional[str] = Field(default=None, description="شماره ثبت")
	economic_id: Optional[str] = Field(default=None, description="شناسه اقتصادی")
	country: Optional[str] = Field(default=None, description="کشور")
	province: Optional[str] = Field(default=None, description="استان")
	city: Optional[str] = Field(default=None, description="شهر")
	postal_code: Optional[str] = Field(default=None, description="کد پستی")
	created_at: str = Field(..., description="تاریخ ایجاد")
	updated_at: str = Field(..., description="تاریخ آخرین بروزرسانی")


class BusinessListResponse(BaseModel):
	items: List[BusinessResponse] = Field(..., description="لیست کسب و کارها")
	pagination: PaginationInfo = Field(..., description="اطلاعات صفحه‌بندی")
	query_info: dict = Field(..., description="اطلاعات جستجو و فیلتر")


class BusinessSummaryResponse(BaseModel):
	total_businesses: int = Field(..., description="تعداد کل کسب و کارها")
	by_type: dict = Field(..., description="تعداد بر اساس نوع")
	by_field: dict = Field(..., description="تعداد بر اساس زمینه فعالیت")


