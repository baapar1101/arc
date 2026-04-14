"""
Schema models برای پروژه‌ها
"""

from pydantic import BaseModel, Field, validator
from typing import Optional, List
from datetime import date, datetime
from decimal import Decimal


class ProjectCreateRequest(BaseModel):
	"""درخواست ایجاد پروژه"""
	code: str = Field(..., description="کد یکتا پروژه", min_length=1, max_length=50)
	name: str = Field(..., description="نام پروژه", min_length=1, max_length=255)
	description: Optional[str] = Field(None, description="توضیحات پروژه")
	status: str = Field(default="active", description="وضعیت: active, completed, on_hold, cancelled")
	start_date: Optional[date] = Field(None, description="تاریخ شروع")
	end_date: Optional[date] = Field(None, description="تاریخ پایان")
	budget: Optional[Decimal] = Field(None, description="بودجه پروژه", ge=0)
	currency_id: Optional[int] = Field(None, description="شناسه ارز")
	manager_user_id: Optional[int] = Field(None, description="مدیر پروژه")
	person_id: Optional[int] = Field(None, description="شخص مرتبط")
	extra_info: Optional[dict] = Field(None, description="اطلاعات اضافی")
	is_active: bool = Field(default=True, description="فعال/غیرفعال")
	
	@validator('status')
	def validate_status(cls, v):
		allowed = ['active', 'completed', 'on_hold', 'cancelled']
		if v not in allowed:
			raise ValueError(f'وضعیت باید یکی از {allowed} باشد')
		return v
	
	class Config:
		json_schema_extra = {
			"example": {
				"code": "PRJ-001",
				"name": "پروژه ساخت ساختمان",
				"description": "پروژه ساخت ساختمان مسکونی 5 طبقه",
				"status": "active",
				"start_date": "2025-01-01",
				"end_date": "2025-12-31",
				"budget": 1000000000,
				"currency_id": 1,
				"manager_user_id": 5,
				"person_id": 10
			}
		}


class ProjectUpdateRequest(BaseModel):
	"""درخواست به‌روزرسانی پروژه"""
	code: Optional[str] = Field(None, min_length=1, max_length=50)
	name: Optional[str] = Field(None, min_length=1, max_length=255)
	description: Optional[str] = None
	status: Optional[str] = None
	start_date: Optional[date] = None
	end_date: Optional[date] = None
	budget: Optional[Decimal] = Field(None, ge=0)
	currency_id: Optional[int] = None
	manager_user_id: Optional[int] = None
	person_id: Optional[int] = None
	extra_info: Optional[dict] = None
	is_active: Optional[bool] = None
	
	@validator('status')
	def validate_status(cls, v):
		if v is not None:
			allowed = ['active', 'completed', 'on_hold', 'cancelled']
			if v not in allowed:
				raise ValueError(f'وضعیت باید یکی از {allowed} باشد')
		return v


class ProjectResponse(BaseModel):
	"""پاسخ پروژه"""
	id: int = Field(..., description="شناسه پروژه")
	business_id: int = Field(..., description="شناسه کسب‌وکار")
	code: str = Field(..., description="کد پروژه")
	name: str = Field(..., description="نام پروژه")
	description: Optional[str] = Field(None, description="توضیحات")
	status: str = Field(..., description="وضعیت")
	status_name: str = Field(..., description="نام فارسی وضعیت")
	start_date: Optional[str] = Field(None, description="تاریخ شروع")
	end_date: Optional[str] = Field(None, description="تاریخ پایان")
	budget: Optional[Decimal] = Field(None, description="بودجه")
	currency_id: Optional[int] = Field(None, description="شناسه ارز")
	currency_code: Optional[str] = Field(None, description="کد ارز")
	currency_symbol: Optional[str] = Field(None, description="نماد ارز")
	manager_user_id: Optional[int] = Field(None, description="شناسه مدیر")
	manager_name: Optional[str] = Field(None, description="نام مدیر")
	person_id: Optional[int] = Field(None, description="شناسه شخص")
	person_name: Optional[str] = Field(None, description="نام شخص")
	is_active: bool = Field(..., description="فعال/غیرفعال")
	created_at: str = Field(..., description="تاریخ ایجاد")
	updated_at: str = Field(..., description="تاریخ به‌روزرسانی")
	created_by_id: int = Field(..., description="شناسه کاربر ایجادکننده")
	created_by_name: str = Field(..., description="نام کاربر ایجادکننده")
	
	class Config:
		from_attributes = True


class ProjectListResponse(BaseModel):
	"""پاسخ لیست پروژه‌ها"""
	items: List[ProjectResponse]
	total: int = Field(..., description="تعداد کل رکوردها")
	page: int = Field(..., description="شماره صفحه")
	limit: int = Field(..., description="تعداد در هر صفحه")


class ProjectStatisticsResponse(BaseModel):
	"""پاسخ آمار پروژه"""
	total_documents: int = Field(..., description="تعداد کل اسناد")
	documents_by_type: dict = Field(..., description="تعداد اسناد به تفکیک نوع")
	total_debit: Decimal = Field(..., description="مجموع بدهکار")
	total_credit: Decimal = Field(..., description="مجموع بستانکار")
	balance: Decimal = Field(..., description="مانده")


class ProjectFilterRequest(BaseModel):
	"""فیلترهای جستجوی پروژه"""
	search: Optional[str] = Field(None, description="عبارت جستجو")
	status: Optional[List[str]] = Field(None, description="فیلتر وضعیت")
	is_active: Optional[bool] = Field(None, description="فعال/غیرفعال")
	person_id: Optional[int] = Field(None, description="شخص مرتبط")
	manager_user_id: Optional[int] = Field(None, description="مدیر پروژه")
	currency_id: Optional[int] = Field(None, description="ارز")
	start_date_from: Optional[date] = Field(None, description="تاریخ شروع از")
	start_date_to: Optional[date] = Field(None, description="تاریخ شروع تا")
	end_date_from: Optional[date] = Field(None, description="تاریخ پایان از")
	end_date_to: Optional[date] = Field(None, description="تاریخ پایان تا")

