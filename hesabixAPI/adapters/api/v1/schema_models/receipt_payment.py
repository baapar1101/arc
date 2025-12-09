"""
Schema models برای دریافت و پرداخت (Receipts & Payments)
"""
from typing import Optional, List, Literal
from pydantic import BaseModel, Field, validator
from datetime import datetime
from decimal import Decimal


class ReceiptPaymentCreateRequest(BaseModel):
    """درخواست ایجاد سند دریافت/پرداخت"""
    document_type: Literal["receipt", "payment"] = Field(
        ...,
        description="نوع سند: receipt (دریافت), payment (پرداخت)",
        example="receipt"
    )
    person_id: int = Field(..., description="شناسه شخص (مشتری/تامین‌کننده)", example=1, gt=0)
    
    amount: Decimal = Field(..., description="مبلغ کل", example=1000000, gt=0)
    
    payment_method: Literal["cash", "check", "card", "online", "other"] = Field(
        ...,
        description="روش پرداخت: cash (نقد), check (چک), card (کارت), online (آنلاین), other (سایر)",
        example="cash"
    )
    
    # اطلاعات حساب مقصد/مبدا
    account_type: Literal["bank_account", "cash_register", "petty_cash"] = Field(
        ...,
        description="نوع حساب: bank_account (حساب بانکی), cash_register (صندوق), petty_cash (تنخواه)",
        example="cash_register"
    )
    account_id: int = Field(..., description="شناسه حساب", example=1, gt=0)
    
    # اطلاعات چک (در صورت انتخاب payment_method=check)
    check_number: Optional[str] = Field(None, description="شماره چک", max_length=50)
    check_date: Optional[str] = Field(None, description="تاریخ چک")
    check_bank: Optional[str] = Field(None, description="بانک چک", max_length=100)
    check_account_number: Optional[str] = Field(None, description="شماره حساب چک", max_length=50)
    
    # اطلاعات کارت (در صورت انتخاب payment_method=card)
    card_number: Optional[str] = Field(None, description="شماره کارت (4 رقم آخر)", max_length=4)
    card_reference: Optional[str] = Field(None, description="شماره پیگیری/مرجع", max_length=100)
    
    document_date: str = Field(..., description="تاریخ سند (ISO: YYYY-MM-DD یا جلالی: YYYY/MM/DD)", example="2024-01-15")
    
    description: Optional[str] = Field(None, description="توضیحات", max_length=1000)
    reference_code: Optional[str] = Field(None, description="شماره مرجع", max_length=50)
    
    # ارتباط با فاکتور
    invoice_id: Optional[int] = Field(None, description="شناسه فاکتور مرتبط", gt=0)
    
    fiscal_year_id: Optional[int] = Field(None, description="شناسه سال مالی", gt=0)
    project_id: Optional[int] = Field(None, description="شناسه پروژه", gt=0)
    
    @validator('check_number')
    def validate_check_info(cls, v, values):
        payment_method = values.get('payment_method')
        if payment_method == 'check' and not v:
            raise ValueError('برای روش پرداخت چک، وارد کردن شماره چک الزامی است')
        return v
    
    class Config:
        json_schema_extra = {
            "examples": [
                {
                    "summary": "دریافت نقدی",
                    "value": {
                        "document_type": "receipt",
                        "person_id": 1,
                        "amount": 1000000,
                        "payment_method": "cash",
                        "account_type": "cash_register",
                        "account_id": 1,
                        "document_date": "2024-01-15",
                        "description": "دریافت وجه بابت فاکتور 1001"
                    }
                },
                {
                    "summary": "دریافت چکی",
                    "value": {
                        "document_type": "receipt",
                        "person_id": 1,
                        "amount": 5000000,
                        "payment_method": "check",
                        "account_type": "bank_account",
                        "account_id": 1,
                        "check_number": "1234567",
                        "check_date": "2024-02-15",
                        "check_bank": "بانک ملت",
                        "document_date": "2024-01-15",
                        "invoice_id": 123
                    }
                }
            ]
        }


class ReceiptPaymentResponse(BaseModel):
    """پاسخ سند دریافت/پرداخت"""
    id: int = Field(..., description="شناسه سند")
    code: str = Field(..., description="کد سند", example="REC-1001")
    document_type: str = Field(..., description="نوع سند")
    document_type_name: str = Field(..., description="نام نوع سند")
    
    business_id: int
    person_id: int
    person_name: str = Field(..., description="نام شخص")
    
    amount: Decimal = Field(..., description="مبلغ")
    
    payment_method: str = Field(..., description="روش پرداخت")
    payment_method_name: str = Field(..., description="نام روش پرداخت")
    
    account_type: str
    account_id: int
    account_name: str = Field(..., description="نام حساب")
    
    # اطلاعات چک
    check_number: Optional[str]
    check_date: Optional[str]
    check_bank: Optional[str]
    check_status: Optional[str] = Field(None, description="وضعیت چک: pending, cashed, bounced")
    
    # اطلاعات کارت
    card_number: Optional[str]
    card_reference: Optional[str]
    
    document_date: str
    
    description: Optional[str]
    reference_code: Optional[str]
    
    invoice_id: Optional[int]
    invoice_code: Optional[str]
    
    status: str = Field(..., description="وضعیت سند: draft, confirmed, cancelled")
    status_name: str
    
    created_by_id: int
    created_by_name: str
    created_at: Optional[str]
    updated_at: Optional[str]
    
    class Config:
        json_schema_extra = {
            "example": {
                "id": 123,
                "code": "REC-1001",
                "document_type": "receipt",
                "document_type_name": "دریافت",
                "person_name": "شرکت نمونه",
                "amount": 1000000,
                "payment_method": "cash",
                "payment_method_name": "نقدی",
                "account_name": "صندوق اصلی",
                "document_date": "1403/10/15",
                "status": "confirmed",
                "status_name": "تایید شده"
            }
        }


class ReceiptPaymentListResponse(BaseModel):
    """پاسخ لیست اسناد"""
    items: List[ReceiptPaymentResponse]
    total_count: int
    has_more: bool


