from typing import List, Optional
from pydantic import BaseModel, Field
from enum import Enum
from datetime import datetime


class PersonType(str, Enum):
    """نوع شخص"""
    CUSTOMER = "مشتری"
    MARKETER = "بازاریاب"
    EMPLOYEE = "کارمند"
    SUPPLIER = "تامین‌کننده"
    PARTNER = "همکار"
    SELLER = "فروشنده"


class PersonBankAccountCreateRequest(BaseModel):
    """درخواست ایجاد حساب بانکی شخص"""
    bank_name: str = Field(..., min_length=1, max_length=255, description="نام بانک")
    account_number: Optional[str] = Field(default=None, max_length=50, description="شماره حساب")
    card_number: Optional[str] = Field(default=None, max_length=20, description="شماره کارت")
    sheba_number: Optional[str] = Field(default=None, max_length=30, description="شماره شبا")


class PersonBankAccountUpdateRequest(BaseModel):
    """درخواست ویرایش حساب بانکی شخص"""
    bank_name: Optional[str] = Field(default=None, min_length=1, max_length=255, description="نام بانک")
    account_number: Optional[str] = Field(default=None, max_length=50, description="شماره حساب")
    card_number: Optional[str] = Field(default=None, max_length=20, description="شماره کارت")
    sheba_number: Optional[str] = Field(default=None, max_length=30, description="شماره شبا")
    is_active: Optional[bool] = Field(default=None, description="وضعیت فعال بودن")


class PersonBankAccountResponse(BaseModel):
    """پاسخ اطلاعات حساب بانکی شخص"""
    id: int = Field(..., description="شناسه حساب بانکی")
    person_id: int = Field(..., description="شناسه شخص")
    bank_name: str = Field(..., description="نام بانک")
    account_number: Optional[str] = Field(default=None, description="شماره حساب")
    card_number: Optional[str] = Field(default=None, description="شماره کارت")
    sheba_number: Optional[str] = Field(default=None, description="شماره شبا")
    is_active: bool = Field(..., description="وضعیت فعال بودن")
    created_at: str = Field(..., description="تاریخ ایجاد")
    updated_at: str = Field(..., description="تاریخ آخرین بروزرسانی")

    class Config:
        from_attributes = True


class PersonCreateRequest(BaseModel):
    """درخواست ایجاد شخص جدید"""
    # اطلاعات پایه
    alias_name: str = Field(..., min_length=1, max_length=255, description="نام مستعار (الزامی)")
    first_name: Optional[str] = Field(default=None, max_length=100, description="نام")
    last_name: Optional[str] = Field(default=None, max_length=100, description="نام خانوادگی")
    person_type: PersonType = Field(..., description="نوع شخص")
    company_name: Optional[str] = Field(default=None, max_length=255, description="نام شرکت")
    payment_id: Optional[str] = Field(default=None, max_length=100, description="شناسه پرداخت")
    
    # اطلاعات اقتصادی
    national_id: Optional[str] = Field(default=None, max_length=20, description="شناسه ملی")
    registration_number: Optional[str] = Field(default=None, max_length=50, description="شماره ثبت")
    economic_id: Optional[str] = Field(default=None, max_length=50, description="شناسه اقتصادی")
    
    # اطلاعات تماس
    country: Optional[str] = Field(default=None, max_length=100, description="کشور")
    province: Optional[str] = Field(default=None, max_length=100, description="استان")
    city: Optional[str] = Field(default=None, max_length=100, description="شهرستان")
    address: Optional[str] = Field(default=None, description="آدرس")
    postal_code: Optional[str] = Field(default=None, max_length=20, description="کد پستی")
    phone: Optional[str] = Field(default=None, max_length=20, description="تلفن")
    mobile: Optional[str] = Field(default=None, max_length=20, description="موبایل")
    fax: Optional[str] = Field(default=None, max_length=20, description="فکس")
    email: Optional[str] = Field(default=None, max_length=255, description="پست الکترونیکی")
    website: Optional[str] = Field(default=None, max_length=255, description="وب‌سایت")
    
    # حساب‌های بانکی
    bank_accounts: Optional[List[PersonBankAccountCreateRequest]] = Field(default=[], description="حساب‌های بانکی")


class PersonUpdateRequest(BaseModel):
    """درخواست ویرایش شخص"""
    # اطلاعات پایه
    alias_name: Optional[str] = Field(default=None, min_length=1, max_length=255, description="نام مستعار")
    first_name: Optional[str] = Field(default=None, max_length=100, description="نام")
    last_name: Optional[str] = Field(default=None, max_length=100, description="نام خانوادگی")
    person_type: Optional[PersonType] = Field(default=None, description="نوع شخص")
    company_name: Optional[str] = Field(default=None, max_length=255, description="نام شرکت")
    payment_id: Optional[str] = Field(default=None, max_length=100, description="شناسه پرداخت")
    
    # اطلاعات اقتصادی
    national_id: Optional[str] = Field(default=None, max_length=20, description="شناسه ملی")
    registration_number: Optional[str] = Field(default=None, max_length=50, description="شماره ثبت")
    economic_id: Optional[str] = Field(default=None, max_length=50, description="شناسه اقتصادی")
    
    # اطلاعات تماس
    country: Optional[str] = Field(default=None, max_length=100, description="کشور")
    province: Optional[str] = Field(default=None, max_length=100, description="استان")
    city: Optional[str] = Field(default=None, max_length=100, description="شهرستان")
    address: Optional[str] = Field(default=None, description="آدرس")
    postal_code: Optional[str] = Field(default=None, max_length=20, description="کد پستی")
    phone: Optional[str] = Field(default=None, max_length=20, description="تلفن")
    mobile: Optional[str] = Field(default=None, max_length=20, description="موبایل")
    fax: Optional[str] = Field(default=None, max_length=20, description="فکس")
    email: Optional[str] = Field(default=None, max_length=255, description="پست الکترونیکی")
    website: Optional[str] = Field(default=None, max_length=255, description="وب‌سایت")
    
    # وضعیت
    is_active: Optional[bool] = Field(default=None, description="وضعیت فعال بودن")


class PersonResponse(BaseModel):
    """پاسخ اطلاعات شخص"""
    id: int = Field(..., description="شناسه شخص")
    business_id: int = Field(..., description="شناسه کسب و کار")
    
    # اطلاعات پایه
    alias_name: str = Field(..., description="نام مستعار")
    first_name: Optional[str] = Field(default=None, description="نام")
    last_name: Optional[str] = Field(default=None, description="نام خانوادگی")
    person_type: str = Field(..., description="نوع شخص")
    company_name: Optional[str] = Field(default=None, description="نام شرکت")
    payment_id: Optional[str] = Field(default=None, description="شناسه پرداخت")
    
    # اطلاعات اقتصادی
    national_id: Optional[str] = Field(default=None, description="شناسه ملی")
    registration_number: Optional[str] = Field(default=None, description="شماره ثبت")
    economic_id: Optional[str] = Field(default=None, description="شناسه اقتصادی")
    
    # اطلاعات تماس
    country: Optional[str] = Field(default=None, description="کشور")
    province: Optional[str] = Field(default=None, description="استان")
    city: Optional[str] = Field(default=None, description="شهرستان")
    address: Optional[str] = Field(default=None, description="آدرس")
    postal_code: Optional[str] = Field(default=None, description="کد پستی")
    phone: Optional[str] = Field(default=None, description="تلفن")
    mobile: Optional[str] = Field(default=None, description="موبایل")
    fax: Optional[str] = Field(default=None, description="فکس")
    email: Optional[str] = Field(default=None, description="پست الکترونیکی")
    website: Optional[str] = Field(default=None, description="وب‌سایت")
    
    # وضعیت
    is_active: bool = Field(..., description="وضعیت فعال بودن")
    
    # زمان‌بندی
    created_at: str = Field(..., description="تاریخ ایجاد")
    updated_at: str = Field(..., description="تاریخ آخرین بروزرسانی")
    
    # حساب‌های بانکی
    bank_accounts: List[PersonBankAccountResponse] = Field(default=[], description="حساب‌های بانکی")

    class Config:
        from_attributes = True


class PersonListResponse(BaseModel):
    """پاسخ لیست اشخاص"""
    items: List[PersonResponse] = Field(..., description="لیست اشخاص")
    pagination: dict = Field(..., description="اطلاعات صفحه‌بندی")
    query_info: dict = Field(..., description="اطلاعات جستجو و فیلتر")


class PersonSummaryResponse(BaseModel):
    """پاسخ خلاصه اشخاص"""
    total_persons: int = Field(..., description="تعداد کل اشخاص")
    by_type: dict = Field(..., description="تعداد بر اساس نوع")
    active_persons: int = Field(..., description="تعداد اشخاص فعال")
    inactive_persons: int = Field(..., description="تعداد اشخاص غیرفعال")
