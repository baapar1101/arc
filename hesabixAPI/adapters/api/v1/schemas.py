from typing import Any, List, Optional, Union, Generic, TypeVar
from pydantic import BaseModel, EmailStr, Field
from enum import Enum
from datetime import datetime, date

T = TypeVar('T')


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
	include_inventory: bool = Field(default=False, description="در صورت true، فیلدهای موجودی انبارداری و مالی محاسبه و اضافه می‌شوند")
	inventory_as_of_date: Optional[str] = Field(default=None, description="تاریخ محاسبه موجودی (فرمت ISO: YYYY-MM-DD). پیش‌فرض: امروز")


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


class SendLoginOtpRequest(CaptchaSolve):
	identifier: str = Field(..., min_length=3, max_length=255, description="ایمیل یا شماره موبایل")
	channel: str = Field(..., description="کانال ارسال: sms, email, telegram")
	session_id: Optional[str] = Field(default=None, description="شناسه session موجود (برای تغییر کانال)")


class ResetPasswordRequest(CaptchaSolve):
	token: str = Field(..., min_length=16)
	new_password: str = Field(..., min_length=8, max_length=128)


class ChangePasswordRequest(BaseModel):
	current_password: str = Field(..., min_length=8, max_length=128)
	new_password: str = Field(..., min_length=8, max_length=128)
	confirm_password: str = Field(..., min_length=8, max_length=128)


class CreateApiKeyRequest(BaseModel):
	name: Optional[str] = Field(default=None, max_length=100, description="نام کلید API")
	scopes: Optional[str] = Field(default=None, max_length=500, description="محدوده دسترسی (JSON string)")
	expires_at: Optional[str] = Field(default=None, description="تاریخ انقضا (ISO format)")
	ip_whitelist: Optional[str] = Field(default=None, max_length=1000, description="لیست IP های مجاز (جدا شده با کاما)")


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
	signature_file_id: Optional[str] = Field(default=None, description="شناسه فایل امضای کاربر (در صورت تنظیم)")


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
	ip: Optional[str] = Field(default=None, description="لیست IP های مجاز")
	user_agent: Optional[str] = Field(default=None, description="اطلاعات مرورگر")
	expires_at: Optional[str] = Field(default=None, description="تاریخ انقضا")
	last_used_at: Optional[str] = Field(default=None, description="آخرین استفاده")
	created_at: str = Field(..., description="تاریخ ایجاد")
	revoked_at: Optional[str] = Field(default=None, description="تاریخ لغو")
	is_active: bool = Field(..., description="وضعیت فعال بودن")


class UpdateApiKeyRequest(BaseModel):
	name: Optional[str] = Field(default=None, max_length=100, description="نام کلید API")
	scopes: Optional[str] = Field(default=None, max_length=500, description="محدوده دسترسی (JSON string)")
	expires_at: Optional[str] = Field(default=None, description="تاریخ انقضا (ISO format)")
	ip_whitelist: Optional[str] = Field(default=None, max_length=1000, description="لیست IP های مجاز (جدا شده با کاما)")


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
	fiscal_years: Optional[List["FiscalYearCreate"]] = Field(default=None, description="آرایه سال‌های مالی برای ایجاد اولیه")
	default_currency_id: Optional[int] = Field(default=None, description="شناسه ارز پیشفرض")
	currency_ids: Optional[List[int]] = Field(default=None, description="لیست شناسه ارزهای قابل استفاده")
	# تنظیمات اعتبار مشتریان
	default_credit_limit: Optional[float] = Field(default=None, description="سقف اعتبار پیشفرض اشخاص")
	check_credit_enabled_by_default: Optional[bool] = Field(default=False, description="بررسی اعتبار مشتریان به صورت پیشفرض (خاموش)")


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
	# تنظیمات اعتبار مشتریان
	default_credit_limit: Optional[float] = Field(default=None, description="سقف اعتبار پیشفرض اشخاص")
	check_credit_enabled_by_default: Optional[bool] = Field(default=None, description="بررسی اعتبار مشتریان به صورت پیشفرض")


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
	logo_file_id: Optional[str] = Field(default=None, description="شناسه فایل لوگوی کسب‌وکار (در صورت تنظیم)")
	stamp_file_id: Optional[str] = Field(default=None, description="شناسه فایل مهر/امضای کسب‌وکار (در صورت تنظیم)")
	# تنظیمات اعتبار مشتریان
	default_credit_limit: Optional[float] = Field(default=None, description="سقف اعتبار پیشفرض اشخاص")
	check_credit_enabled_by_default: bool = Field(default=False, description="بررسی اعتبار مشتریان به صورت پیشفرض")
	created_at: str = Field(..., description="تاریخ ایجاد")
	updated_at: str = Field(..., description="تاریخ آخرین بروزرسانی")
	default_currency: Optional[dict] = Field(default=None, description="ارز پیشفرض")
	currencies: Optional[List[dict]] = Field(default=None, description="ارزهای فعال کسب‌وکار")


class BusinessListResponse(BaseModel):
	items: List[BusinessResponse] = Field(..., description="لیست کسب و کارها")
	pagination: PaginationInfo = Field(..., description="اطلاعات صفحه‌بندی")
	query_info: dict = Field(..., description="اطلاعات جستجو و فیلتر")


class BusinessSummaryResponse(BaseModel):
	total_businesses: int = Field(..., description="تعداد کل کسب و کارها")
	by_type: dict = Field(..., description="تعداد بر اساس نوع")
	by_field: dict = Field(..., description="تعداد بر اساس زمینه فعالیت")


class PaginatedResponse(BaseModel, Generic[T]):
	"""پاسخ صفحه‌بندی شده برای لیست‌ها"""
	items: List[T] = Field(..., description="آیتم‌های صفحه")
	total: int = Field(..., description="تعداد کل آیتم‌ها")
	page: int = Field(..., description="شماره صفحه فعلی")
	limit: int = Field(..., description="تعداد آیتم در هر صفحه")
	total_pages: int = Field(..., description="تعداد کل صفحات")

	@classmethod
	def create(cls, items: List[T], total: int, page: int, limit: int) -> 'PaginatedResponse[T]':
		"""ایجاد پاسخ صفحه‌بندی شده"""
		total_pages = (total + limit - 1) // limit
		return cls(
			items=items,
			total=total,
			page=page,
			limit=limit,
			total_pages=total_pages
		)


# Fiscal Year Schemas
class FiscalYearCreate(BaseModel):
    title: str = Field(..., min_length=1, max_length=255, description="عنوان سال مالی")
    start_date: date = Field(..., description="تاریخ شروع سال مالی")
    end_date: date = Field(..., description="تاریخ پایان سال مالی")
    is_last: bool = Field(default=True, description="آیا آخرین سال مالی فعال است؟")


# Business User Schemas
class BusinessUserSchema(BaseModel):
    id: int
    business_id: int
    user_id: int
    user_name: str
    user_email: str
    user_phone: Optional[str] = None
    role: str
    status: str
    added_at: datetime
    last_active: Optional[datetime] = None
    permissions: dict

    class Config:
        from_attributes = True


class AddUserRequest(BaseModel):
    email_or_phone: str

    class Config:
        json_schema_extra = {
            "example": {
                "email_or_phone": "user@example.com"
            }
        }


class AddUserResponse(BaseModel):
    success: bool
    message: str
    user: Optional[BusinessUserSchema] = None


class UpdatePermissionsRequest(BaseModel):
    permissions: dict

    class Config:
        json_schema_extra = {
            "example": {
                "permissions": {
                    "sales": {
                        "read": True,
                        "write": True,
                        "delete": False
                    },
                    "reports": {
                        "read": True,
                        "export": True
                    },
                    "settings": {
                        "manage_users": True
                    }
                }
            }
        }


class UpdatePermissionsResponse(BaseModel):
    success: bool
    message: str


class RemoveUserResponse(BaseModel):
    success: bool
    message: str


class BusinessUsersListResponse(BaseModel):
    success: bool
    message: str
    data: dict
    calendar_type: Optional[str] = None


# Document Numbering Settings Schemas
class DocumentNumberingSettingRequest(BaseModel):
    document_type: str = Field(..., description="نوع سند (invoice_sales, receipt, payment, ...)")
    prefix: Optional[str] = Field(default=None, max_length=20, description="پیشوند شماره سند")
    include_date: bool = Field(default=True, description="آیا تاریخ در شماره سند باشد؟")
    calendar_type: str = Field(
        default="gregorian",
        description="نوع تقویم: gregorian (میلادی) یا jalali (شمسی)"
    )
    date_format: Optional[str] = Field(
        default=None,
        max_length=20,
        description="فرمت تاریخ (YYYYMMDD, YYYY/MM/DD, ...)"
    )
    separator: str = Field(default="-", max_length=5, description="جداکننده")
    start_number: int = Field(default=1, ge=1, description="شماره شروع")
    number_padding: int = Field(default=4, ge=1, le=10, description="تعداد صفرهای پیش‌رو")
    reset_period: Optional[str] = Field(
        default=None,
        description="دوره ریست: daily, monthly, yearly, never"
    )
    custom_format: Optional[str] = Field(
        default=None,
        max_length=100,
        description="فرمت سفارشی"
    )
    is_active: bool = Field(default=True, description="فعال/غیرفعال")

    class Config:
        from_attributes = True


class DocumentNumberingSettingResponse(BaseModel):
    id: int
    business_id: int
    document_type: str
    prefix: Optional[str]
    include_date: bool
    calendar_type: str
    date_format: Optional[str]
    separator: str
    start_number: int
    number_padding: int
    reset_period: Optional[str]
    custom_format: Optional[str]
    is_active: bool
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


