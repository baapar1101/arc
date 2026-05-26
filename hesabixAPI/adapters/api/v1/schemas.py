from typing import Any, Dict, List, Optional, Union, Generic, TypeVar, Literal
from pydantic import BaseModel, ConfigDict, EmailStr, Field, model_validator, validator
from enum import Enum
from datetime import datetime, date

T = TypeVar('T')


class FilterOperator(str, Enum):
	"""
	عملگرهای موجود برای فیلتر
	
	### عملگرهای مقایسه:
	- `EQUAL` (=): برابر با
	- `NOT_EQUAL` (!=): نابرابر با
	- `GREATER` (>): بزرگتر از
	- `GREATER_EQUAL` (>=): بزرگتر یا مساوی
	- `LESS` (<): کوچکتر از
	- `LESS_EQUAL` (<=): کوچکتر یا مساوی
	
	### عملگرهای رشته‌ای:
	- `CONTAINS` (*): شامل (هر جایی در متن)
	- `STARTS_WITH` (*?): شروع با
	- `ENDS_WITH` (?*): پایان با
	
	### عملگرهای آرایه:
	- `IN` (in): موجود در لیست
	- `NOT_IN` (not_in): موجود نیست در لیست
	
	### عملگرهای null:
	- `IS_NULL` (is_null): مقدار خالی است
	- `IS_NOT_NULL` (is_not_null): مقدار خالی نیست
	"""
	EQUAL = "="
	NOT_EQUAL = "!="
	GREATER = ">"
	GREATER_EQUAL = ">="
	LESS = "<"
	LESS_EQUAL = "<="
	CONTAINS = "*"
	STARTS_WITH = "*?"
	ENDS_WITH = "?*"
	IN = "in"
	NOT_IN = "not_in"
	IS_NULL = "is_null"
	IS_NOT_NULL = "is_not_null"


class FilterItem(BaseModel):
	"""
	آیتم فیلتر برای جستجوی پیشرفته
	
	### مثال‌های کاربردی:
	
	**فیلتر عددی:**
	```json
	{"property": "total_amount", "operator": ">=", "value": 1000000}
	```
	
	**فیلتر رشته‌ای:**
	```json
	{"property": "name", "operator": "*", "value": "احمد"}
	```
	
	**فیلتر آرایه:**
	```json
	{"property": "status", "operator": "in", "value": ["active", "pending"]}
	```
	
	**فیلتر null:**
	```json
	{"property": "deleted_at", "operator": "is_null", "value": null}
	```
	"""
	property: str = Field(
		..., 
		description="نام فیلد مورد نظر برای اعمال فیلتر",
		example="total_amount"
	)
	operator: str = Field(
		..., 
		description="نوع عملگر: =, !=, >, >=, <, <=, *, *?, ?*, in, not_in, is_null, is_not_null",
		example=">="
	)
	value: Any = Field(
		..., 
		description="مقدار مورد نظر - برای in و not_in باید آرایه باشد، برای is_null و is_not_null می‌تواند null باشد",
		example=1000000
	)
	
	class Config:
		json_schema_extra = {
			"examples": [
				{
					"summary": "فیلتر عددی",
					"value": {
						"property": "total_amount",
						"operator": ">=",
						"value": 1000000
					}
				},
				{
					"summary": "فیلتر رشته‌ای",
					"value": {
						"property": "description",
						"operator": "*",
						"value": "خرید"
					}
				},
				{
					"summary": "فیلتر آرایه",
					"value": {
						"property": "source_type",
						"operator": "in",
						"value": ["bank_account", "cash_register"]
					}
				}
			]
		}


class SortItem(BaseModel):
	"""یک سطح مرتب‌سازی در لیست چندستونه (کلید sort در بدنهٔ JSON)."""
	by: str = Field(..., description="نام فیلد برای مرتب‌سازی", example="document_date")
	desc: bool = Field(default=False, description="true = نزولی، false = صعودی")


class QueryInfo(BaseModel):
	"""
	پارامترهای جستجو، فیلتر، مرتب‌سازی و صفحه‌بندی
	
	### قابلیت‌ها:
	- **مرتب‌سازی**: تک‌ستونه با sort_by / sort_desc (سازگار با کلاینت قدیمی) یا چندستونه با آرایه sort
	- **صفحه‌بندی**: با take و skip
	- **جستجو**: در چندین فیلد همزمان
	- **فیلتر پیشرفته**: با عملگرهای مختلف
	
	### مثال کامل:
	```json
	{
	  "take": 20,
	  "skip": 0,
	  "sort_by": "created_at",
	  "sort_desc": true,
	  "search": "احمد",
	  "search_fields": ["first_name", "last_name", "email"],
	  "filters": [
		{"property": "is_active", "operator": "=", "value": true},
		{"property": "created_at", "operator": ">=", "value": "2024-01-01"}
	  ]
	}
	```
	"""
	model_config = ConfigDict(
		populate_by_name=True,
		json_schema_extra={
			"example": {
				"take": 20,
				"skip": 0,
				"sort_by": "created_at",
				"sort_desc": True,
				"search": "احمد",
				"search_fields": ["first_name", "last_name"],
				"filters": [
					{
						"property": "is_active",
						"operator": "=",
						"value": True,
					}
				],
			}
		},
	)
	sort_by: Optional[str] = Field(
		default=None, 
		description="نام فیلد مورد نظر برای مرتب‌سازی (مثال: created_at, name, total_amount)",
		example="created_at"
	)
	sort_desc: bool = Field(
		default=False, 
		description="نوع مرتب‌سازی: false = صعودی (A-Z, 1-9), true = نزولی (Z-A, 9-1)",
		example=True
	)
	sort: Optional[List[SortItem]] = Field(
		default=None,
		description=(
			"مرتب‌سازی چندسطحی. اگر ارسال شود و حداقل یک عضو معتبر داشته باشد، "
			"اولویت با این فهرست است؛ در غیر این صورت از sort_by / sort_desc استفاده می‌شود."
		),
	)
	take: int = Field(
		default=10, 
		ge=1, 
		le=1000, 
		description="تعداد رکورد در هر صفحه (حداقل 1، حداکثر 1000)",
		example=20
	)
	skip: int = Field(
		default=0, 
		ge=0, 
		description="تعداد رکوردی که از ابتدا رد می‌شود (برای صفحه‌بندی)",
		example=0
	)
	search: Optional[str] = Field(
		default=None, 
		description="عبارت جستجو - در تمام فیلدهای search_fields یا فیلدهای پیش‌فرض جستجو می‌شود",
		example="احمد"
	)
	search_fields: Optional[List[str]] = Field(
		default=None,
		alias="searchFields",
		description="فیلدهای مورد نظر برای جستجو. اگر ارسال نشود، فیلدهای پیش‌فرض استفاده می‌شود",
		example=["first_name", "last_name", "email"]
	)
	category_ids: Optional[List[int]] = Field(
		default=None,
		alias="categoryIds",
		description="فیلتر بر اساس شناسه دسته‌بندی کالا/خدمت (چند انتخاب با OR)",
		example=[1, 2],
	)
	filters: Optional[List[FilterItem]] = Field(
		default=None, 
		description="آرایه‌ای از فیلترهای پیشرفته. تمام فیلترها با AND به هم متصل می‌شوند",
		example=[
			{"property": "is_active", "operator": "=", "value": True},
			{"property": "total_amount", "operator": ">=", "value": 1000000}
		]
	)
	include_inventory: bool = Field(
		default=False, 
		description="محاسبه و اضافه کردن فیلدهای موجودی انبار و اطلاعات مالی (فقط برای محصولات)",
		example=False
	)
	inventory_as_of_date: Optional[str] = Field(
		default=None, 
		description="تاریخ محاسبه موجودی (فرمت: YYYY-MM-DD یا YYYY/MM/DD). پیش‌فرض: امروز",
		example="2024-01-15"
	)
	
	@validator('take')
	def validate_take(cls, v):
		if v < 1:
			raise ValueError('take باید حداقل 1 باشد')
		if v > 1000:
			raise ValueError('take نمی‌تواند بیشتر از 1000 باشد')
		return v


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


class AvailableChannelsRequest(CaptchaSolve):
	identifier: str = Field(..., min_length=3, max_length=255, description="ایمیل یا شماره موبایل")


class ResetPasswordRequest(CaptchaSolve):
	token: str = Field(..., min_length=16)
	new_password: str = Field(..., min_length=8, max_length=128)


class ChangePasswordRequest(BaseModel):
	current_password: str = Field(..., min_length=8, max_length=128)
	new_password: str = Field(..., min_length=8, max_length=128)
	confirm_password: str = Field(..., min_length=8, max_length=128)


class UpdateMobileRequest(CaptchaSolve):
	mobile: str = Field(..., min_length=10, max_length=32, description="شماره موبایل جدید")
	force_unverified: bool = Field(default=False, description="اجازه تغییر شماره ثبت شده اما تایید نشده")
	send_verification_sms: bool = Field(
		default=True,
		description="پس از ذخیرهٔ شماره، کد تایید به همان موبایل (از همان کپچا) ارسال شود",
	)


class SendMobileVerificationRequest(CaptchaSolve):
	"""همراه با کپچا (بدن درخواست JSON) — از query param خالی برای جلوگیری از سوءاستفاده"""
	mobile: str = Field(..., min_length=10, max_length=32, description="شماره موبایل برای ارسال کد تایید")


class UpdateEmailRequest(CaptchaSolve):
	email: EmailStr = Field(..., description="ایمیل جدید")
	force_unverified: bool = Field(default=False, description="اجازه تغییر ایمیل ثبت شده اما تایید نشده")


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


# Bulk Operations Request Models
class BulkActivateRequest(BaseModel):
	"""درخواست فعال‌سازی دسته‌ای کاربران"""
	user_ids: List[int] = Field(
		..., 
		min_items=1,
		description="لیست شناسه‌های کاربران برای فعال‌سازی",
		example=[1, 2, 3]
	)
	
	class Config:
		json_schema_extra = {
			"example": {
				"user_ids": [1, 2, 3, 4, 5]
			}
		}


class BulkSuspendRequest(BaseModel):
	"""درخواست تعلیق دسته‌ای کاربران"""
	user_ids: List[int] = Field(
		..., 
		min_items=1,
		description="لیست شناسه‌های کاربران برای تعلیق",
		example=[1, 2, 3]
	)
	
	class Config:
		json_schema_extra = {
			"example": {
				"user_ids": [1, 2, 3, 4, 5]
			}
		}


class BulkResetPasswordRequest(BaseModel):
	"""درخواست بازنشانی رمز عبور دسته‌ای کاربران"""
	user_ids: List[int] = Field(
		..., 
		min_items=1,
		description="لیست شناسه‌های کاربران برای بازنشانی رمز عبور",
		example=[1, 2, 3]
	)
	send_notification: bool = Field(
		default=True,
		description="برای هر کاربری که توکن ساخته شد، اعلان auth.password_reset ارسال شود",
	)
	
	class Config:
		json_schema_extra = {
			"example": {
				"user_ids": [1, 2, 3, 4, 5],
				"send_notification": True,
			}
		}


class AdminSetUserPasswordRequest(BaseModel):
	"""تنظیم رمز توسط مدیر: مستقیم (انتخابی) یا تولید تصادفی (یک‌بار نمایش)."""
	model_config = ConfigDict(extra="forbid")
	mode: Literal["direct", "random"] = Field(
		default="direct",
		description="direct: new_password + confirm_password؛ random: تولید در سرور",
	)
	new_password: Optional[str] = Field(
		default=None,
		min_length=8,
		max_length=128,
		description="الزام در حالت direct",
	)
	confirm_password: Optional[str] = Field(
		default=None,
		min_length=8,
		max_length=128,
		description="الزام در حالت direct",
	)

	@model_validator(mode="after")
	def _validate_mode(self) -> "AdminSetUserPasswordRequest":
		if self.mode == "direct":
			if not self.new_password or not self.confirm_password:
				raise ValueError("برای حالت direct، new_password و confirm_password الزامی است")
		return self


# User Detail Response Models
class UserBusinessResponse(BaseModel):
	"""اطلاعات کسب‌وکار کاربر"""
	id: int = Field(..., description="شناسه کسب‌وکار")
	name: str = Field(..., description="نام کسب‌وکار")
	field: Optional[str] = Field(default=None, description="زمینه فعالیت")
	role: str = Field(..., description="نقش کاربر در کسب‌وکار: owner, admin, operator, supervisor, user")
	status: str = Field(..., description="وضعیت کسب‌وکار")
	created_at: str = Field(..., description="تاریخ عضویت")


class UserSessionResponse(BaseModel):
	"""اطلاعات نشست کاربر"""
	id: int = Field(..., description="شناسه نشست")
	device: str = Field(..., description="نام دستگاه یا مرورگر")
	ip: Optional[str] = Field(default=None, description="آدرس IP")
	last_active_at: str = Field(..., description="آخرین زمان فعالیت")
	created_at: str = Field(..., description="تاریخ ایجاد نشست")


class UserAuditLogResponse(BaseModel):
	"""اطلاعات لاگ فعالیت کاربر"""
	id: int = Field(..., description="شناسه لاگ")
	action: str = Field(..., description="نوع عملیات")
	description: Optional[str] = Field(default=None, description="توضیحات")
	category: Optional[str] = Field(default=None, description="دسته‌بندی")
	entity_type: Optional[str] = Field(default=None, description="نوع موجودیت")
	entity_id: Optional[int] = Field(default=None, description="شناسه موجودیت")
	created_at: str = Field(..., description="تاریخ ایجاد")


class UserDetailResponse(UserResponse):
	"""اطلاعات کامل کاربر شامل کسب‌وکارها، نشست‌ها و لاگ‌ها"""
	businesses: Optional[List[UserBusinessResponse]] = Field(
		default=None, 
		description="لیست کسب‌وکارهای کاربر"
	)
	sessions: Optional[List[UserSessionResponse]] = Field(
		default=None, 
		description="لیست نشست‌های فعال کاربر"
	)
	audit_logs: Optional[List[UserAuditLogResponse]] = Field(
		default=None, 
		description="آخرین فعالیت‌های کاربر (حداکثر 50 مورد)"
	)
	
	class Config:
		json_schema_extra = {
			"example": {
				"id": 1,
				"email": "user@example.com",
				"mobile": "09123456789",
				"first_name": "احمد",
				"last_name": "احمدی",
				"is_active": True,
				"referral_code": "ABC123",
				"app_permissions": {"user_management": True},
				"created_at": "2024-01-01T00:00:00Z",
				"updated_at": "2024-01-01T00:00:00Z",
				"signature_file_id": "550e8400-e29b-41d4-a716-446655440000",
				"businesses": [
					{
						"id": 1,
						"name": "شرکت نمونه",
						"field": "بازرگانی",
						"role": "owner",
						"status": "active",
						"created_at": "2024-01-01T00:00:00Z"
					}
				],
				"sessions": [
					{
						"id": 1,
						"device": "Chrome on Windows",
						"ip": "192.168.1.1",
						"last_active_at": "2024-01-15T10:30:00Z",
						"created_at": "2024-01-01T00:00:00Z"
					}
				],
				"audit_logs": [
					{
						"id": 1,
						"action": "login",
						"description": "ورود به سیستم",
						"category": "authentication",
						"entity_type": "user",
						"entity_id": 1,
						"created_at": "2024-01-15T10:30:00Z"
					}
				]
			}
		}


# Bulk Operations Response Models
class BulkOperationResponse(BaseModel):
	"""پاسخ عملیات دسته‌ای"""
	updated_count: int = Field(..., description="تعداد رکوردهای به‌روز شده")
	total_requested: int = Field(..., description="تعداد کل درخواست‌ها")


class BulkResetPasswordResponse(BaseModel):
	"""پاسخ بازنشانی رمز عبور دسته‌ای"""
	tokens_created: int = Field(..., description="تعداد توکن‌های ایجاد شده")
	total_requested: int = Field(..., description="تعداد کل درخواست‌ها")


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
	default_currency_id: int = Field(..., description="شناسه ارز پیشفرض (الزامی)")
	currency_ids: Optional[List[int]] = Field(default=None, description="لیست شناسه ارزهای قابل استفاده")
	# تنظیمات اعتبار مشتریان
	default_credit_limit: Optional[float] = Field(default=None, description="سقف اعتبار پیشفرض اشخاص")
	check_credit_enabled_by_default: Optional[bool] = Field(default=False, description="بررسی اعتبار مشتریان به صورت پیشفرض (خاموش)")
	include_sample_data: Optional[bool] = Field(
		default=False,
		description="در صورت true، پس از ایجاد کسب‌وکار دادهٔ نمونه (مشتری، کالا، انبار، ...) درج می‌شود؛ فقط برای ایجاد معقول است نه ایمپورت پشتیبان",
	)


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
	default_currency_id: Optional[int] = Field(default=None, description="شناسه ارز پیشفرض (فقط برای کسب‌وکارهایی که ارز پیش‌فرض ندارند)")
	# تنظیمات اعتبار مشتریان
	default_credit_limit: Optional[float] = Field(default=None, description="سقف اعتبار پیشفرض اشخاص")
	check_credit_enabled_by_default: Optional[bool] = Field(default=None, description="بررسی اعتبار مشتریان به صورت پیشفرض")
	public_catalog_show_contact: Optional[bool] = Field(
		default=None,
		description="نمایش تلفن/موبایل در API عمومی کاتالوگ (شبکهٔ انتشار کالا)",
	)
	public_catalog_show_base_sales_price: Optional[bool] = Field(
		default=None,
		description="نمایش قیمت فروش پایه در API عمومی کاتالوگ",
	)
	# تنظیمات محاسبه سود فاکتور
	invoice_profit_calculation_method: Optional[str] = Field(default=None, description="روش محاسبه سود فاکتور: automatic, manual, disabled")
	invoice_profit_calculation_basis: Optional[str] = Field(
		default=None,
		description=(
			"مبنای محاسبه سود: purchase_price, cost_price, average_cost, fifo, fifo_jbfn (FIFO با پیش‌خور از خریدهای بعدی)، "
			"lifo, weighted_average, moving_weighted_average (WMA دائمی), standard_cost, actual_cost"
		),
	)
	invoice_profit_include_overhead: Optional[bool] = Field(default=None, description="آیا هزینه‌های سربار در محاسبه سود لحاظ شود؟")
	invoice_profit_overhead_type: Optional[str] = Field(default=None, description="نوع هزینه‌های سربار: none, production_overhead, all_overhead, custom_percent")
	invoice_profit_overhead_percent: Optional[float] = Field(default=None, ge=0, le=100, description="درصد هزینه‌های سربار (0-100) - فقط برای custom_percent")
	invoice_profit_calculation_type: Optional[str] = Field(default=None, description="نوع محاسبه سود: gross (ناخالص), net (خالص), both (هر دو)")
	invoice_profit_ledger_recognition_basis: Optional[str] = Field(
		default=None,
		description="زمان شناسایی بهای تمام‌شده قطعی در دفتر: warehouse_document_posting | sales_invoice_document",
	)
	invoice_profit_fifo_shortage_mode: Optional[str] = Field(
		default=None,
		description="سیاست کسری در مبنای سود FIFO/LIFO/moving_weighted_average: perpetual_mixed | average_purchase_on_shortage",
	)
	# به‌روزرسانی قیمت پایه کالا از فاکتور قطعی
	invoice_sync_update_sales_price_enabled: Optional[bool] = Field(
		default=None,
		description="به‌روزرسانی خودکار قیمت فروش پایه از فاکتور فروش قطعی",
	)
	invoice_sync_update_purchase_price_enabled: Optional[bool] = Field(
		default=None,
		description="به‌روزرسانی خودکار قیمت خرید پایه از فاکتور خرید قطعی",
	)
	invoice_sync_sales_price_basis: Optional[str] = Field(
		default=None,
		description="مبنای محاسبه: unit_price | net_after_line_discount | net_with_tax | cost_price",
	)
	invoice_sync_purchase_price_basis: Optional[str] = Field(
		default=None,
		description="مبنای محاسبه: unit_price | net_after_line_discount | net_with_tax | cost_price",
	)
	invoice_warehouse_release_mode: Optional[str] = Field(
		default=None,
		description="حواله پس از ثبت فاکتور: none (بدون حواله)، draft (پیش‌نویس)، posted (قطعی فوری)",
	)
	invoice_purchase_accounting_mode: Optional[str] = Field(
		default=None,
		description="ثبت حسابداری خرید: direct_inventory | grni_two_step | grni_legacy",
	)
	invoice_missing_line_warehouse_policy: Optional[str] = Field(
		default=None,
		description="reject (جلوگیری با پیام راهنما) | use_default_warehouse (پر کردن خودکار از انبار پیش‌فرض کسب‌وکار)",
	)
	invoice_default_warehouse_id: Optional[int] = Field(
		default=None,
		description="انبار پیش‌فرض برای ردیف‌های انبارداری بدون انبار وقتی سیاست use_default_warehouse است",
	)
	invoice_default_warehouse_fill_document_header: Optional[bool] = Field(
		default=None,
		description="هنگام پر کردن خودکار خطوط، اگر انبار سطح فاکتور خالی بود همان انبار پیش‌فرض روی سربرگ هم ست شود",
	)
	allow_negative_inventory_for_bulk: Optional[bool] = Field(
		default=None,
		description="اجازه قطعی حواله با کسری برای کالاهای فله‌ای (غیر یونیک) با کنترل موجودی",
	)
	allow_negative_inventory_for_unique: Optional[bool] = Field(
		default=None,
		description="اجازه قطعی حواله با کسری برای کالاهای یونیک با کنترل موجودی",
	)
	warehouse_transfer_require_positive_stock: Optional[bool] = Field(
		default=None,
		description="اگر true باشد، حواله انتقال همیشه کنترل کسری کامل دارد",
	)
	invoice_global_discount_percent_basis: Optional[str] = Field(
		default=None,
		description=(
			"مبنای درصد تخفیف کلی: subtotal_after_line_discount | gross_before_line_discount | "
			"total_after_lines_including_tax"
		),
	)
	invoice_global_discount_tax_mode: Optional[str] = Field(
		default=None,
		description="اثر تخفیف کلی بر مالیات: recalculate_tax_proportional | keep_line_taxes",
	)
	invoice_global_discount_max_percent: Optional[float] = Field(
		default=None,
		ge=0,
		le=100,
		description="سقف درصد تخفیف کلی نسبت به مبنا (اختیاری)",
	)
	invoice_global_discount_max_amount: Optional[float] = Field(
		default=None,
		ge=0,
		description="سقف مبلغ تخفیف کلی (اختیاری)",
	)
	# تسعیر ارز فاکتور: as_of_source، document_date_effective، when_no_rate
	fx_revaluation_policy: Optional[Dict[str, Any]] = Field(
		default=None,
		description="سیاست تسعیر ارز (JSON): document_date/registered_at، start/end of day، block یا allow_without_fx",
	)

	@validator("fx_revaluation_policy", pre=True)
	def _validate_fx_revaluation_policy_field(cls, v):  # noqa: N805
		if v is None:
			return None
		from app.services.invoice_fx_revaluation import validate_and_normalize_fx_revaluation_policy_payload
		try:
			return validate_and_normalize_fx_revaluation_policy_payload(v)
		except ValueError as e:
			raise ValueError(str(e))

	@validator("invoice_global_discount_percent_basis")
	def _validate_invoice_global_discount_percent_basis(cls, v):  # noqa: N805
		if v is None or v == "":
			return None
		allowed = {
			"subtotal_after_line_discount",
			"gross_before_line_discount",
			"total_after_lines_including_tax",
		}
		if v not in allowed:
			raise ValueError("مبنای درصد تخفیف کلی نامعتبر است")
		return v

	@validator("invoice_global_discount_tax_mode")
	def _validate_invoice_global_discount_tax_mode(cls, v):  # noqa: N805
		if v is None or v == "":
			return None
		allowed = {"recalculate_tax_proportional", "keep_line_taxes"}
		if v not in allowed:
			raise ValueError("حالت مالیات تخفیف کلی نامعتبر است")
		return v

	@validator("invoice_warehouse_release_mode")
	def _validate_invoice_warehouse_release_mode(cls, v):  # noqa: N805
		if v is None or v == "":
			return None
		s = str(v).strip().lower()
		if s in ("none", "off", "no", "disabled"):
			return "none"
		if s in ("posted", "final", "confirmed"):
			return "posted"
		if s in ("draft",):
			return "draft"
		raise ValueError("invoice_warehouse_release_mode نامعتبر است (none، draft یا posted)")

	@validator("invoice_purchase_accounting_mode")
	def _validate_invoice_purchase_accounting_mode(cls, v):  # noqa: N805
		if v is None or v == "":
			return None
		from app.services.purchase_accounting_service import PURCHASE_ACCOUNTING_MODES, normalize_purchase_accounting_mode

		n = normalize_purchase_accounting_mode(v)
		if n not in PURCHASE_ACCOUNTING_MODES:
			raise ValueError(
				"invoice_purchase_accounting_mode نامعتبر است "
				"(direct_inventory، grni_two_step یا grni_legacy)"
			)
		return n

	@validator("invoice_missing_line_warehouse_policy")
	def _validate_invoice_missing_line_warehouse_policy(cls, v):  # noqa: N805
		if v is None or v == "":
			return None
		s = str(v).strip().lower()
		if s in ("reject", "block", "deny", "forbid"):
			return "reject"
		if s in ("use_default_warehouse", "default_warehouse", "auto_default"):
			return "use_default_warehouse"
		raise ValueError("invoice_missing_line_warehouse_policy نامعتبر است (reject یا use_default_warehouse)")

	@validator("invoice_sync_sales_price_basis", "invoice_sync_purchase_price_basis")
	def _validate_invoice_sync_basis(cls, v):  # noqa: N805
		if v is None or v == "":
			return None
		allowed = {"unit_price", "net_after_line_discount", "net_with_tax", "cost_price"}
		if v not in allowed:
			raise ValueError("مبنای همگام‌سازی قیمت نامعتبر است")
		return v

	@validator("invoice_profit_calculation_method")
	def _validate_invoice_profit_calculation_method(cls, v):  # noqa: N805
		if v is None or v == "":
			return None
		allowed = {"automatic", "manual", "disabled"}
		value = str(v).strip().lower()
		if value not in allowed:
			raise ValueError("روش محاسبه سود فاکتور نامعتبر است")
		return value

	@validator("invoice_profit_calculation_basis")
	def _validate_invoice_profit_calculation_basis(cls, v):  # noqa: N805
		if v is None or v == "":
			return None
		allowed = {
			"purchase_price",
			"cost_price",
			"average_cost",
			"fifo",
			"fifo_jbfn",
			"lifo",
			"weighted_average",
			"moving_weighted_average",
			"standard_cost",
			"actual_cost",
		}
		value = str(v).strip().lower()
		if value in ("wma", "moving_wavg", "mwa"):
			value = "moving_weighted_average"
		if value not in allowed:
			raise ValueError("مبنای محاسبه سود نامعتبر است")
		return value

	@validator("invoice_profit_overhead_type")
	def _validate_invoice_profit_overhead_type(cls, v):  # noqa: N805
		if v is None or v == "":
			return None
		allowed = {"none", "production_overhead", "all_overhead", "custom_percent"}
		value = str(v).strip().lower()
		if value not in allowed:
			raise ValueError("نوع هزینه سربار نامعتبر است")
		return value

	@validator("invoice_profit_calculation_type")
	def _validate_invoice_profit_calculation_type(cls, v):  # noqa: N805
		if v is None or v == "":
			return None
		allowed = {"gross", "net", "both"}
		value = str(v).strip().lower()
		if value not in allowed:
			raise ValueError("نوع محاسبه سود نامعتبر است")
		return value

	@validator("invoice_profit_ledger_recognition_basis")
	def _validate_invoice_profit_ledger_recognition_basis(cls, v):  # noqa: N805
		if v is None or v == "":
			return None
		allowed = {"warehouse_document_posting", "sales_invoice_document"}
		value = str(v).strip().lower()
		if value not in allowed:
			raise ValueError(
				"مبنای شناسایی قطعی نامعتبر است "
				"(warehouse_document_posting یا sales_invoice_document)"
			)
		return value

	@validator("invoice_profit_fifo_shortage_mode")
	def _validate_invoice_profit_fifo_shortage_mode(cls, v):  # noqa: N805
		if v is None or v == "":
			return None
		s = str(v).strip().lower()
		if s in ("avg", "average", "avg_shortage"):
			s = "average_purchase_on_shortage"
		allowed = {"perpetual_mixed", "average_purchase_on_shortage"}
		if s not in allowed:
			raise ValueError(
				"invoice_profit_fifo_shortage_mode نامعتبر است (perpetual_mixed یا average_purchase_on_shortage)"
			)
		return s


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
	public_catalog_show_contact: bool = Field(
		default=False,
		description="نمایش تلفن/موبایل در API عمومی کاتالوگ",
	)
	public_catalog_show_base_sales_price: bool = Field(
		default=True,
		description="نمایش قیمت فروش پایه در API عمومی کاتالوگ",
	)
	# تنظیمات محاسبه سود فاکتور
	invoice_profit_calculation_method: Optional[str] = Field(default=None, description="روش محاسبه سود فاکتور")
	invoice_profit_calculation_basis: Optional[str] = Field(default=None, description="مبنای محاسبه سود")
	invoice_profit_include_overhead: Optional[bool] = Field(default=None, description="آیا هزینه‌های سربار در محاسبه سود لحاظ می‌شود")
	invoice_profit_overhead_type: Optional[str] = Field(default=None, description="نوع هزینه‌های سربار")
	invoice_profit_overhead_percent: Optional[float] = Field(default=None, description="درصد هزینه‌های سربار")
	invoice_profit_calculation_type: Optional[str] = Field(default=None, description="نوع محاسبه سود")
	invoice_profit_ledger_recognition_basis: Optional[str] = Field(
		default=None,
		description="شناسایی بهای تمام‌شده قطعی دفتر: با حواله یا با فاکتور",
	)
	invoice_profit_fifo_shortage_mode: str = Field(
		default="perpetual_mixed",
		description="سیاست کسری در محاسبه سود بر مبنای FIFO/LIFO/moving_weighted_average",
	)
	invoice_sync_update_sales_price_enabled: bool = Field(default=False, description="همگام‌سازی قیمت فروش از فاکتور")
	invoice_sync_update_purchase_price_enabled: bool = Field(default=False, description="همگام‌سازی قیمت خرید از فاکتور")
	invoice_sync_sales_price_basis: Optional[str] = Field(default=None, description="مبنای قیمت فروش")
	invoice_sync_purchase_price_basis: Optional[str] = Field(default=None, description="مبنای قیمت خرید")
	invoice_warehouse_release_mode: str = Field(
		default="draft",
		description="حواله پس از ثبت فاکتور: none، draft، posted",
	)
	invoice_purchase_accounting_mode: str = Field(
		default="direct_inventory",
		description="ثبت حسابداری خرید: direct_inventory، grni_two_step، grni_legacy",
	)
	invoice_missing_line_warehouse_policy: str = Field(
		default="reject",
		description="reject | use_default_warehouse",
	)
	invoice_default_warehouse_id: Optional[int] = Field(
		default=None,
		description="انبار پیش‌فرض برای ردیف بدون انبار",
	)
	invoice_default_warehouse_fill_document_header: bool = Field(
		default=True,
		description="پر کردن انبار سطح فاکتور هنگام حالت خودکار",
	)
	allow_negative_inventory_for_bulk: bool = Field(
		default=False,
		description="خروج با موجودی منفی برای کالاهای فله‌ای هنگام قطعی حواله",
	)
	allow_negative_inventory_for_unique: bool = Field(
		default=False,
		description="خروج با موجودی منفی برای کالاهای یونیک هنگام قطعی حواله",
	)
	warehouse_transfer_require_positive_stock: bool = Field(
		default=True,
		description="انتقال بین انبار همیشه نیاز به موجودی کافی",
	)
	invoice_global_discount_percent_basis: str = Field(
		default="subtotal_after_line_discount",
		description="مبنای درصد تخفیف کلی",
	)
	invoice_global_discount_tax_mode: str = Field(
		default="recalculate_tax_proportional",
		description="اثر تخفیف کلی بر مالیات",
	)
	invoice_global_discount_max_percent: Optional[float] = Field(
		default=None,
		description="سقف درصد تخفیف کلی",
	)
	invoice_global_discount_max_amount: Optional[float] = Field(
		default=None,
		description="سقف مبلغ تخفیف کلی",
	)
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
    membership_expires_at: Optional[datetime] = None
    membership_unlimited: bool = True
    membership_active: bool = True

    class Config:
        from_attributes = True


class AddUserRequest(BaseModel):
    email_or_phone: str
    membership_expires_at: Optional[datetime] = Field(
        default=None,
        description="پایان عضویت؛ خالی یا null یعنی نامحدود.",
    )

    @model_validator(mode="after")
    def validate_membership_expires_at(self) -> "AddUserRequest":
        if self.membership_expires_at is None:
            return self
        from app.core.business_membership import to_naive_utc

        exp = to_naive_utc(self.membership_expires_at)
        if exp <= datetime.utcnow():
            raise ValueError("membership_expires_at must be in the future")
        self.membership_expires_at = exp
        return self

    class Config:
        json_schema_extra = {
            "example": {
                "email_or_phone": "user@example.com",
                "membership_expires_at": None,
            }
        }


class AddUserResponse(BaseModel):
    success: bool
    message: str
    user: Optional[BusinessUserSchema] = None


class UpdatePermissionsRequest(BaseModel):
    permissions: dict
    apply_membership_expiry: bool = Field(
        default=False,
        description="اگر True باشد، مقدار membership_expires_at اعمال می‌شود (null = نامحدود).",
    )
    membership_expires_at: Optional[datetime] = None

    @model_validator(mode="after")
    def normalize_membership_expires_at(self) -> "UpdatePermissionsRequest":
        if not self.apply_membership_expiry or self.membership_expires_at is None:
            return self
        from app.core.business_membership import to_naive_utc

        self.membership_expires_at = to_naive_utc(self.membership_expires_at)
        return self

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
                },
                "apply_membership_expiry": False,
                "membership_expires_at": None,
            }
        }


class UpdatePermissionsResponse(BaseModel):
    success: bool
    message: str


class RemoveUserResponse(BaseModel):
    success: bool
    message: str


class LeaveBusinessResponse(BaseModel):
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


