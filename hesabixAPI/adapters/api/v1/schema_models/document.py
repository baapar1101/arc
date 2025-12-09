"""
Schema Models برای اسناد حسابداری (Documents)
"""

from __future__ import annotations

from typing import Optional, List, Any, Dict
from decimal import Decimal
from datetime import date, datetime
from pydantic import BaseModel, Field


class DocumentListFilters(BaseModel):
    """فیلترهای لیست اسناد"""
    document_type: Optional[str] = Field(default=None, description="نوع سند")
    fiscal_year_id: Optional[int] = Field(default=None, description="شناسه سال مالی")
    from_date: Optional[str] = Field(default=None, description="از تاریخ (ISO format)")
    to_date: Optional[str] = Field(default=None, description="تا تاریخ (ISO format)")
    currency_id: Optional[int] = Field(default=None, description="شناسه ارز")
    is_proforma: Optional[bool] = Field(default=None, description="پیش‌فاکتور یا قطعی")
    search: Optional[str] = Field(default=None, description="جستجو در کد سند و توضیحات")
    sort_by: Optional[str] = Field(default="document_date", description="فیلد مرتب‌سازی")
    sort_desc: bool = Field(default=True, description="ترتیب نزولی")
    take: int = Field(default=50, ge=1, le=1000, description="تعداد رکورد")
    skip: int = Field(default=0, ge=0, description="تعداد رکورد صرف‌نظر شده")


class DocumentLineResponse(BaseModel):
    """پاسخ خط سند"""
    id: int
    document_id: int
    account_id: Optional[int] = None
    person_id: Optional[int] = None
    product_id: Optional[int] = None
    bank_account_id: Optional[int] = None
    cash_register_id: Optional[int] = None
    petty_cash_id: Optional[int] = None
    check_id: Optional[int] = None
    quantity: Optional[float] = None
    debit: float
    credit: float
    description: Optional[str] = None
    extra_info: Optional[Dict[str, Any]] = None
    
    # اطلاعات مرتبط
    account_code: Optional[str] = None
    account_name: Optional[str] = None
    person_name: Optional[str] = None
    product_name: Optional[str] = None
    bank_account_name: Optional[str] = None
    cash_register_name: Optional[str] = None
    petty_cash_name: Optional[str] = None
    check_number: Optional[str] = None
    
    class Config:
        from_attributes = True


class DocumentSummaryResponse(BaseModel):
    """پاسخ خلاصه سند (برای لیست)"""
    id: int
    code: str
    business_id: int
    fiscal_year_id: int
    currency_id: int
    created_by_user_id: int
    registered_at: datetime
    document_date: date
    document_type: str
    is_proforma: bool
    description: Optional[str] = None
    created_at: datetime
    updated_at: datetime
    
    # اطلاعات مرتبط
    business_title: Optional[str] = None
    fiscal_year_title: Optional[str] = None
    currency_code: Optional[str] = None
    currency_symbol: Optional[str] = None
    created_by_name: Optional[str] = None
    
    # محاسبات
    total_debit: float
    total_credit: float
    lines_count: int
    
    class Config:
        from_attributes = True


class DocumentDetailResponse(BaseModel):
    """پاسخ جزئیات کامل سند (با سطرها)"""
    id: int
    code: str
    business_id: int
    fiscal_year_id: int
    currency_id: int
    created_by_user_id: int
    registered_at: datetime
    document_date: date
    document_type: str
    is_proforma: bool
    description: Optional[str] = None
    extra_info: Optional[Dict[str, Any]] = None
    developer_settings: Optional[Dict[str, Any]] = None
    created_at: datetime
    updated_at: datetime
    
    # اطلاعات مرتبط
    business_title: Optional[str] = None
    fiscal_year_title: Optional[str] = None
    currency_code: Optional[str] = None
    currency_symbol: Optional[str] = None
    created_by_name: Optional[str] = None
    
    # سطرهای سند
    lines: List[DocumentLineResponse]
    
    # محاسبات
    total_debit: float
    total_credit: float
    lines_count: int
    
    class Config:
        from_attributes = True


class DocumentDeleteResponse(BaseModel):
    """پاسخ حذف سند"""
    deleted: bool
    document_id: int


class BulkDeleteRequest(BaseModel):
    """درخواست حذف گروهی"""
    document_ids: List[int] = Field(..., description="لیست شناسه‌های سند")


class BulkDeleteResponse(BaseModel):
    """پاسخ حذف گروهی"""
    deleted_count: int
    total_requested: int
    errors: List[Dict[str, Any]]
    skipped_auto_documents: List[Dict[str, Any]]


class DocumentTypesSummaryResponse(BaseModel):
    """پاسخ خلاصه آماری انواع اسناد"""
    summary: Dict[str, int]
    total: int


class DocumentLineCreate(BaseModel):
    """درخواست ایجاد یک سطر سند"""
    account_id: int = Field(..., description="شناسه حساب (الزامی)")
    person_id: Optional[int] = Field(default=None, description="شناسه شخص (تفضیل)")
    product_id: Optional[int] = Field(default=None, description="شناسه کالا (تفضیل)")
    bank_account_id: Optional[int] = Field(default=None, description="شناسه حساب بانکی (تفضیل)")
    cash_register_id: Optional[int] = Field(default=None, description="شناسه صندوق (تفضیل)")
    petty_cash_id: Optional[int] = Field(default=None, description="شناسه تنخواه (تفضیل)")
    check_id: Optional[int] = Field(default=None, description="شناسه چک (تفضیل)")
    quantity: Optional[float] = Field(default=None, description="مقدار/تعداد")
    debit: float = Field(default=0, ge=0, description="بدهکار")
    credit: float = Field(default=0, ge=0, description="بستانکار")
    description: Optional[str] = Field(default=None, max_length=500, description="توضیحات سطر")
    extra_info: Optional[Dict[str, Any]] = Field(default=None, description="اطلاعات اضافی")


class DocumentLineUpdate(BaseModel):
    """درخواست ویرایش یک سطر سند"""
    id: Optional[int] = Field(default=None, description="شناسه سطر (برای ویرایش)")
    account_id: int = Field(..., description="شناسه حساب (الزامی)")
    person_id: Optional[int] = Field(default=None, description="شناسه شخص (تفضیل)")
    product_id: Optional[int] = Field(default=None, description="شناسه کالا (تفضیل)")
    bank_account_id: Optional[int] = Field(default=None, description="شناسه حساب بانکی (تفضیل)")
    cash_register_id: Optional[int] = Field(default=None, description="شناسه صندوق (تفضیل)")
    petty_cash_id: Optional[int] = Field(default=None, description="شناسه تنخواه (تفضیل)")
    check_id: Optional[int] = Field(default=None, description="شناسه چک (تفضیل)")
    quantity: Optional[float] = Field(default=None, description="مقدار/تعداد")
    debit: float = Field(default=0, ge=0, description="بدهکار")
    credit: float = Field(default=0, ge=0, description="بستانکار")
    description: Optional[str] = Field(default=None, max_length=500, description="توضیحات سطر")
    extra_info: Optional[Dict[str, Any]] = Field(default=None, description="اطلاعات اضافی")


class CreateManualDocumentRequest(BaseModel):
    """درخواست ایجاد سند حسابداری دستی"""
    code: Optional[str] = Field(default=None, max_length=50, description="کد سند (اختیاری - خودکار)")
    document_date: date = Field(..., description="تاریخ سند")
    fiscal_year_id: Optional[int] = Field(default=None, description="شناسه سال مالی (اختیاری - از header)")
    currency_id: int = Field(..., description="شناسه ارز")
    is_proforma: bool = Field(default=False, description="پیش‌فاکتور یا قطعی")
    description: Optional[str] = Field(default=None, max_length=1000, description="توضیحات سند")
    lines: List[DocumentLineCreate] = Field(..., min_items=2, description="سطرهای سند (حداقل 2)")
    extra_info: Optional[Dict[str, Any]] = Field(default=None, description="اطلاعات اضافی")
    project_id: Optional[int] = Field(default=None, description="شناسه پروژه", gt=0)


class UpdateManualDocumentRequest(BaseModel):
    """درخواست ویرایش سند حسابداری دستی"""
    code: Optional[str] = Field(default=None, max_length=50, description="کد سند")
    document_date: Optional[date] = Field(default=None, description="تاریخ سند")
    currency_id: Optional[int] = Field(default=None, description="شناسه ارز")
    is_proforma: Optional[bool] = Field(default=None, description="پیش‌فاکتور یا قطعی")
    description: Optional[str] = Field(default=None, max_length=1000, description="توضیحات سند")
    lines: Optional[List[DocumentLineUpdate]] = Field(default=None, min_items=2, description="سطرهای سند")
    extra_info: Optional[Dict[str, Any]] = Field(default=None, description="اطلاعات اضافی")
    project_id: Optional[int] = Field(default=None, description="شناسه پروژه", gt=0)

