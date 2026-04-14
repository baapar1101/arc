"""
Schema models برای اسناد انتقال (Transfers)
"""
from typing import Optional, List
from pydantic import BaseModel, Field, validator
from datetime import datetime
from decimal import Decimal


class TransferCreateRequest(BaseModel):
    """درخواست ایجاد سند انتقال"""
    source_type: str = Field(
        ..., 
        description="نوع مبدا: bank_account (حساب بانکی), cash_register (صندوق), petty_cash (تنخواه)",
        example="bank_account"
    )
    source_id: int = Field(
        ..., 
        description="شناسه مبدا (بسته به source_type)",
        example=1,
        gt=0
    )
    destination_type: str = Field(
        ..., 
        description="نوع مقصد: bank_account (حساب بانکی), cash_register (صندوق), petty_cash (تنخواه)",
        example="cash_register"
    )
    destination_id: int = Field(
        ..., 
        description="شناسه مقصد (بسته به destination_type)",
        example=2,
        gt=0
    )
    total_amount: Decimal = Field(
        ..., 
        description="مبلغ کل انتقال (باید بزرگتر از صفر باشد)",
        example=1000000,
        gt=0
    )
    commission: Optional[Decimal] = Field(
        None, 
        description="کارمزد انتقال (اختیاری)",
        example=5000,
        ge=0
    )
    document_date: str = Field(
        ..., 
        description="تاریخ سند (فرمت ISO: YYYY-MM-DD یا جلالی: YYYY/MM/DD)",
        example="2024-01-15"
    )
    currency_id: int = Field(
        ..., 
        description="شناسه ارز",
        example=1,
        gt=0
    )
    description: Optional[str] = Field(
        None, 
        description="توضیحات سند (حداکثر 1000 کاراکتر)",
        example="انتقال وجه بابت خرید مواد اولیه",
        max_length=1000
    )
    fiscal_year_id: Optional[int] = Field(
        None,
        description="شناسه سال مالی (اگر ارسال نشود، سال مالی فعال استفاده می‌شود)",
        example=1,
        gt=0
    )
    
    @validator('source_type', 'destination_type')
    def validate_account_type(cls, v):
        allowed_types = ['bank_account', 'cash_register', 'petty_cash']
        if v not in allowed_types:
            raise ValueError(f'نوع حساب باید یکی از {allowed_types} باشد')
        return v
    
    class Config:
        json_schema_extra = {
            "example": {
                "source_type": "bank_account",
                "source_id": 1,
                "destination_type": "cash_register",
                "destination_id": 2,
                "total_amount": 1000000,
                "commission": 5000,
                "document_date": "2024-01-15",
                "currency_id": 1,
                "description": "انتقال وجه بابت خرید مواد اولیه"
            }
        }


class TransferUpdateRequest(BaseModel):
    """درخواست ویرایش سند انتقال"""
    source_type: Optional[str] = Field(
        None, 
        description="نوع مبدا"
    )
    source_id: Optional[int] = Field(
        None, 
        description="شناسه مبدا",
        gt=0
    )
    destination_type: Optional[str] = Field(
        None, 
        description="نوع مقصد"
    )
    destination_id: Optional[int] = Field(
        None, 
        description="شناسه مقصد",
        gt=0
    )
    total_amount: Optional[Decimal] = Field(
        None, 
        description="مبلغ کل",
        gt=0
    )
    commission: Optional[Decimal] = Field(
        None, 
        description="کارمزد",
        ge=0
    )
    document_date: Optional[str] = Field(
        None, 
        description="تاریخ سند"
    )
    description: Optional[str] = Field(
        None, 
        description="توضیحات",
        max_length=1000
    )
    
    @validator('source_type', 'destination_type')
    def validate_account_type(cls, v):
        if v is not None:
            allowed_types = ['bank_account', 'cash_register', 'petty_cash']
            if v not in allowed_types:
                raise ValueError(f'نوع حساب باید یکی از {allowed_types} باشد')
        return v


class AccountLineResponse(BaseModel):
    """آیتم حساب در سند انتقال"""
    id: int = Field(..., description="شناسه آیتم")
    account_code: str = Field(..., description="کد حساب")
    account_name: str = Field(..., description="نام حساب")
    debit: Decimal = Field(..., description="بدهکار")
    credit: Decimal = Field(..., description="بستانکار")
    description: Optional[str] = Field(None, description="توضیحات")


class TransferResponse(BaseModel):
    """پاسخ سند انتقال"""
    id: int = Field(..., description="شناسه سند")
    code: str = Field(..., description="کد سند", example="T-1001")
    business_id: int = Field(..., description="شناسه کسب‌وکار")
    document_type_name: str = Field(..., description="نوع سند", example="انتقال")
    
    source_type: str = Field(..., description="نوع مبدا")
    source_id: int = Field(..., description="شناسه مبدا")
    source_name: str = Field(..., description="نام مبدا", example="بانک ملت - 1234567890")
    source_type_name: str = Field(..., description="نام نوع مبدا", example="حساب بانکی")
    
    destination_type: str = Field(..., description="نوع مقصد")
    destination_id: int = Field(..., description="شناسه مقصد")
    destination_name: str = Field(..., description="نام مقصد", example="صندوق اصلی")
    destination_type_name: str = Field(..., description="نام نوع مقصد", example="صندوق")
    
    total_amount: Decimal = Field(..., description="مبلغ کل")
    commission: Optional[Decimal] = Field(None, description="کارمزد")
    
    document_date: str = Field(..., description="تاریخ سند")
    registered_at: Optional[str] = Field(None, description="تاریخ ثبت")
    
    description: Optional[str] = Field(None, description="توضیحات")
    
    created_by_id: int = Field(..., description="شناسه ایجادکننده")
    created_by_name: str = Field(..., description="نام ایجادکننده")
    
    fiscal_year_id: Optional[int] = Field(None, description="شناسه سال مالی")
    fiscal_year_name: Optional[str] = Field(None, description="نام سال مالی")
    
    account_lines: Optional[List[AccountLineResponse]] = Field(
        None, 
        description="آیتم‌های حساب (در صورت درخواست)"
    )
    
    created_at: Optional[str] = Field(None, description="تاریخ ایجاد")
    updated_at: Optional[str] = Field(None, description="تاریخ آخرین ویرایش")
    
    class Config:
        json_schema_extra = {
            "example": {
                "id": 123,
                "code": "T-1001",
                "business_id": 1,
                "document_type_name": "انتقال",
                "source_type": "bank_account",
                "source_id": 1,
                "source_name": "بانک ملت - 1234567890",
                "source_type_name": "حساب بانکی",
                "destination_type": "cash_register",
                "destination_id": 2,
                "destination_name": "صندوق اصلی",
                "destination_type_name": "صندوق",
                "total_amount": 1000000,
                "commission": 5000,
                "document_date": "1403/10/15",
                "registered_at": "1403/10/15",
                "description": "انتقال وجه بابت خرید مواد اولیه",
                "created_by_id": 1,
                "created_by_name": "احمد احمدی",
                "fiscal_year_id": 1,
                "fiscal_year_name": "سال مالی 1403",
                "created_at": "1403/10/15 14:30:00",
                "updated_at": "1403/10/15 14:30:00"
            }
        }


class TransferListResponse(BaseModel):
    """پاسخ لیست اسناد انتقال"""
    items: List[TransferResponse] = Field(..., description="لیست اسناد")
    total_count: int = Field(..., description="تعداد کل اسناد")
    has_more: bool = Field(..., description="آیا رکورد بیشتری وجود دارد")
    
    class Config:
        json_schema_extra = {
            "example": {
                "items": [
                    {
                        "id": 123,
                        "code": "T-1001",
                        "source_name": "بانک ملت",
                        "destination_name": "صندوق اصلی",
                        "total_amount": 1000000,
                        "document_date": "1403/10/15"
                    }
                ],
                "total_count": 45,
                "has_more": True
            }
        }


class TransferExportRequest(BaseModel):
    """درخواست خروجی اسناد انتقال"""
    take: int = Field(default=1000, description="تعداد رکورد", ge=1, le=10000)
    skip: int = Field(default=0, description="تعداد رکورد رد شده", ge=0)
    sort_by: Optional[str] = Field(None, description="فیلد مرتب‌سازی")
    sort_desc: bool = Field(default=False, description="مرتب‌سازی نزولی")
    search: Optional[str] = Field(None, description="عبارت جستجو")
    from_date: Optional[str] = Field(None, description="از تاریخ")
    to_date: Optional[str] = Field(None, description="تا تاریخ")
    selected_only: bool = Field(default=False, description="فقط موارد انتخاب شده")
    selected_indices: Optional[List[int]] = Field(None, description="ایندکس‌های انتخاب شده")
    template_id: Optional[int] = Field(None, description="شناسه قالب سفارشی")
    
    class Config:
        json_schema_extra = {
            "example": {
                "take": 100,
                "skip": 0,
                "sort_by": "document_date",
                "sort_desc": True,
                "from_date": "2024-01-01",
                "to_date": "2024-12-31"
            }
        }


