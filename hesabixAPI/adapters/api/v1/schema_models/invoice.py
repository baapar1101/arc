"""
Schema models برای فاکتورها (Invoices)
"""
from typing import Any, Dict, List, Literal, Optional
from pydantic import BaseModel, Field, validator
from datetime import datetime
from decimal import Decimal


class InvoiceItemRequest(BaseModel):
    """آیتم فاکتور"""
    product_id: int = Field(..., description="شناسه محصول/خدمت", example=1, gt=0)
    quantity: Decimal = Field(..., description="تعداد/مقدار", example=10, gt=0)
    unit_price: Decimal = Field(..., description="قیمت واحد", example=50000, ge=0)
    discount_percent: Optional[Decimal] = Field(None, description="درصد تخفیف", example=5, ge=0, le=100)
    discount_amount: Optional[Decimal] = Field(None, description="مبلغ تخفیف", example=25000, ge=0)
    tax_percent: Optional[Decimal] = Field(None, description="درصد مالیات", example=9, ge=0)
    description: Optional[str] = Field(None, description="توضیحات", max_length=500)
    warehouse_id: Optional[int] = Field(None, description="شناسه انبار (برای کالاها)", gt=0)
    
    class Config:
        json_schema_extra = {
            "example": {
                "product_id": 1,
                "quantity": 10,
                "unit_price": 50000,
                "discount_percent": 5,
                "tax_percent": 9,
                "warehouse_id": 1
            }
        }


class InvoiceCreateRequest(BaseModel):
    """درخواست ایجاد فاکتور"""
    invoice_type: Literal["sale", "purchase", "sale_return", "purchase_return"] = Field(
        ...,
        description="نوع فاکتور: sale (فروش), purchase (خرید), sale_return (برگشت از فروش), purchase_return (برگشت از خرید)",
        example="sale"
    )
    person_id: int = Field(..., description="شناسه مشتری/تامین‌کننده", example=1, gt=0)
    invoice_date: str = Field(..., description="تاریخ فاکتور (ISO: YYYY-MM-DD یا جلالی: YYYY/MM/DD)", example="2024-01-15")
    due_date: Optional[str] = Field(None, description="تاریخ سررسید", example="2024-02-15")
    
    items: List[InvoiceItemRequest] = Field(..., description="لیست اقلام فاکتور", min_items=1)
    
    discount_amount: Optional[Decimal] = Field(None, description="تخفیف کلی", ge=0)
    shipping_cost: Optional[Decimal] = Field(None, description="هزینه حمل", ge=0)
    other_costs: Optional[Decimal] = Field(None, description="سایر هزینه‌ها", ge=0)
    
    description: Optional[str] = Field(None, description="توضیحات فاکتور", max_length=1000)
    reference_code: Optional[str] = Field(None, description="شماره مرجع/سفارش", max_length=50)
    
    currency_id: Optional[int] = Field(None, description="شناسه ارز (پیش‌فرض: ریال)", gt=0)
    exchange_rate: Optional[Decimal] = Field(None, description="نرخ تبدیل ارز", gt=0)
    
    payment_method: Optional[str] = Field(None, description="روش پرداخت: cash, card, check, credit, online")
    payment_amount: Optional[Decimal] = Field(None, description="مبلغ پرداختی", ge=0)
    
    fiscal_year_id: Optional[int] = Field(None, description="شناسه سال مالی", gt=0)
    project_id: Optional[int] = Field(None, description="شناسه پروژه", gt=0)
    
    @validator('items')
    def validate_items(cls, v):
        if not v or len(v) == 0:
            raise ValueError('فاکتور باید حداقل یک آیتم داشته باشد')
        return v
    
    class Config:
        json_schema_extra = {
            "example": {
                "invoice_type": "sale",
                "person_id": 1,
                "invoice_date": "2024-01-15",
                "due_date": "2024-02-15",
                "items": [
                    {
                        "product_id": 1,
                        "quantity": 10,
                        "unit_price": 50000,
                        "discount_percent": 5,
                        "tax_percent": 9,
                        "warehouse_id": 1
                    }
                ],
                "discount_amount": 10000,
                "shipping_cost": 20000,
                "description": "فاکتور فروش محصولات",
                "payment_method": "cash",
                "payment_amount": 500000
            }
        }


class InvoiceItemResponse(BaseModel):
    """آیتم فاکتور در پاسخ"""
    id: int
    product_id: int
    product_code: str
    product_name: str
    quantity: Decimal
    unit_price: Decimal
    discount_percent: Optional[Decimal]
    discount_amount: Optional[Decimal]
    tax_percent: Optional[Decimal]
    tax_amount: Optional[Decimal]
    total_amount: Decimal
    description: Optional[str]
    warehouse_id: Optional[int]
    warehouse_name: Optional[str]


class InvoiceResponse(BaseModel):
    """پاسخ فاکتور"""
    id: int = Field(..., description="شناسه فاکتور")
    code: str = Field(..., description="کد فاکتور", example="INV-1001")
    invoice_type: str = Field(..., description="نوع فاکتور")
    invoice_type_name: str = Field(..., description="نام نوع فاکتور به فارسی")
    
    business_id: int
    person_id: int
    person_name: str = Field(..., description="نام مشتری/تامین‌کننده")
    
    invoice_date: str
    due_date: Optional[str]
    
    subtotal: Decimal = Field(..., description="جمع اقلام قبل از تخفیف")
    total_discount: Decimal = Field(..., description="جمع تخفیفات")
    total_tax: Decimal = Field(..., description="جمع مالیات")
    shipping_cost: Optional[Decimal]
    other_costs: Optional[Decimal]
    final_amount: Decimal = Field(..., description="مبلغ نهایی")
    
    paid_amount: Decimal = Field(..., description="مبلغ پرداخت شده")
    remaining_amount: Decimal = Field(..., description="مبلغ باقیمانده")
    
    status: str = Field(..., description="وضعیت: draft, confirmed, paid, cancelled")
    status_name: str = Field(..., description="نام وضعیت به فارسی")
    
    items: Optional[List[InvoiceItemResponse]] = Field(None, description="لیست اقلام")
    
    description: Optional[str]
    reference_code: Optional[str]
    project_id: Optional[int]
    
    created_by_id: int
    created_by_name: str
    created_at: Optional[str]
    updated_at: Optional[str]
    
    # فیلدهای سود (اختیاری - فقط در صورت فعال بودن محاسبه سود)
    gross_profit: Optional[Decimal] = Field(None, description="سود ناخالص فاکتور")
    gross_profit_percent: Optional[Decimal] = Field(None, description="درصد سود ناخالص")
    net_profit: Optional[Decimal] = Field(None, description="سود خالص فاکتور")
    net_profit_percent: Optional[Decimal] = Field(None, description="درصد سود خالص")
    total_profit: Optional[Decimal] = Field(None, description="سود کل فاکتور (ناخالص یا خالص بر اساس تنظیمات)")
    total_profit_percent: Optional[Decimal] = Field(None, description="درصد سود کل")
    total_overhead: Optional[Decimal] = Field(None, description="هزینه‌های سربار")
    line_profits: Optional[List[Dict[str, Any]]] = Field(None, description="سود هر ردیف")
    
    class Config:
        json_schema_extra = {
            "example": {
                "id": 123,
                "code": "INV-1001",
                "invoice_type": "sale",
                "invoice_type_name": "فاکتور فروش",
                "person_name": "شرکت نمونه",
                "invoice_date": "1403/10/15",
                "subtotal": 500000,
                "total_discount": 25000,
                "total_tax": 45000,
                "final_amount": 520000,
                "paid_amount": 300000,
                "remaining_amount": 220000,
                "status": "confirmed",
                "status_name": "تایید شده"
            }
        }


class InvoiceListResponse(BaseModel):
    """پاسخ لیست فاکتورها"""
    items: List[InvoiceResponse]
    total_count: int
    has_more: bool


class InvoiceUpdateRequest(BaseModel):
    """درخواست ویرایش فاکتور"""
    person_id: Optional[int] = Field(None, gt=0)
    invoice_date: Optional[str] = None
    due_date: Optional[str] = None
    items: Optional[List[InvoiceItemRequest]] = None
    discount_amount: Optional[Decimal] = Field(None, ge=0)
    shipping_cost: Optional[Decimal] = Field(None, ge=0)
    other_costs: Optional[Decimal] = Field(None, ge=0)
    description: Optional[str] = Field(None, max_length=1000)
    reference_code: Optional[str] = Field(None, max_length=50)
    status: Optional[Literal["draft", "confirmed", "paid", "cancelled"]] = None
    project_id: Optional[int] = Field(None, description="شناسه پروژه", gt=0)


class InvoiceShareLinkCreateRequest(BaseModel):
    """ایجاد/تمدید لینک مشاهده عمومی فاکتور"""
    expires_in_hours: Optional[int] = Field(
        default=None,
        ge=1,
        le=720,
        description="مدت اعتبار (ساعت). خالی: پیش‌فرض سامانه",
    )
    max_view_count: Optional[int] = Field(
        default=None,
        ge=1,
        le=1000,
        description="حداکثر بازدید؛ خالی = نامحدود",
    )
    replace_existing: bool = Field(
        default=True,
        description="در صورت وجود لینک فعال، ابتدا لغو و لینک جدید",
    )

