from __future__ import annotations

from typing import Optional
from decimal import Decimal
from pydantic import BaseModel, Field


class DocumentLineCreateRequest(BaseModel):
    """درخواست ایجاد خط سند جدید"""
    account_id: Optional[int] = Field(default=None, description="شناسه حساب")
    person_id: Optional[int] = Field(default=None, description="شناسه شخص")
    product_id: Optional[int] = Field(default=None, description="شناسه محصول")
    bank_account_id: Optional[int] = Field(default=None, description="شناسه حساب بانکی")
    cash_register_id: Optional[int] = Field(default=None, description="شناسه صندوق")
    petty_cash_id: Optional[int] = Field(default=None, description="شناسه تنخواه گردان")
    check_id: Optional[int] = Field(default=None, description="شناسه چک")
    quantity: Optional[Decimal] = Field(default=0, description="تعداد کالا")
    debit: Decimal = Field(default=0, description="مبلغ بدهکار")
    credit: Decimal = Field(default=0, description="مبلغ بستانکار")
    description: Optional[str] = Field(default=None, description="توضیحات")
    extra_info: Optional[dict] = Field(default=None, description="اطلاعات اضافی")


class DocumentLineUpdateRequest(BaseModel):
    """درخواست به‌روزرسانی خط سند"""
    account_id: Optional[int] = None
    person_id: Optional[int] = None
    product_id: Optional[int] = None
    bank_account_id: Optional[int] = None
    cash_register_id: Optional[int] = None
    petty_cash_id: Optional[int] = None
    check_id: Optional[int] = None
    quantity: Optional[Decimal] = None
    debit: Optional[Decimal] = None
    credit: Optional[Decimal] = None
    description: Optional[str] = None
    extra_info: Optional[dict] = None


class DocumentLineResponse(BaseModel):
    """پاسخ خط سند"""
    id: int
    document_id: int
    account_id: Optional[int]
    person_id: Optional[int]
    product_id: Optional[int]
    bank_account_id: Optional[int]
    cash_register_id: Optional[int]
    petty_cash_id: Optional[int]
    check_id: Optional[int]
    quantity: Optional[Decimal]
    debit: Decimal
    credit: Decimal
    description: Optional[str]
    extra_info: Optional[dict]
    created_at: str
    updated_at: str
    
    # اطلاعات مرتبط
    account_name: Optional[str] = None
    person_name: Optional[str] = None
    product_name: Optional[str] = None
    bank_account_name: Optional[str] = None
    cash_register_name: Optional[str] = None
    petty_cash_name: Optional[str] = None
    check_number: Optional[str] = None

    class Config:
        from_attributes = True
