"""
Schema Models برای API افزونه مدیریت تعمیرگاه
"""
from __future__ import annotations

from datetime import datetime
from typing import Optional, List
from decimal import Decimal
from pydantic import BaseModel, Field, validator


# ========== Settings ==========

class RepairShopSettingsUpdate(BaseModel):
    """به‌روزرسانی تنظیمات تعمیرگاه"""
    receipt_code_format: Optional[str] = Field(None, description="فرمت کد: random, sequential, custom")
    receipt_code_prefix: Optional[str] = Field(None, max_length=10, description="پیشوند کد رسید")
    auto_send_sms_on_receive: Optional[bool] = None
    auto_send_sms_on_status_change: Optional[bool] = None
    auto_send_email_on_receive: Optional[bool] = None
    auto_send_email_on_status_change: Optional[bool] = None
    sms_templates: Optional[dict] = None
    email_templates: Optional[dict] = None
    default_service_product_id: Optional[int] = None
    default_warehouse_id: Optional[int] = None
    extra_settings: Optional[dict] = None


class RepairShopSettingsResponse(BaseModel):
    """پاسخ تنظیمات تعمیرگاه"""
    id: int
    business_id: int
    receipt_code_format: str
    receipt_code_prefix: str
    auto_send_sms_on_receive: bool
    auto_send_sms_on_status_change: bool
    auto_send_email_on_receive: bool
    auto_send_email_on_status_change: bool
    sms_templates: dict
    email_templates: dict
    default_service_product_id: Optional[int]
    default_warehouse_id: Optional[int]
    extra_settings: dict


# ========== Technician ==========

class RepairTechnicianCreate(BaseModel):
    """ایجاد تعمیرکار"""
    person_id: int = Field(..., description="شناسه Person از جدول اشخاص")
    code: Optional[str] = Field(None, max_length=50, description="کد تعمیرکار (اختیاری - اتوماتیک تولید می‌شود)")
    commission_type: str = Field("percentage", description="نوع حق‌الزحمه: fixed, percentage, case_by_case")
    commission_value: Decimal = Field(Decimal("0"), description="مبلغ فیکس یا درصد")
    is_active: bool = Field(True, description="وضعیت فعال/غیرفعال")
    extra_info: Optional[dict] = None

    @validator('commission_type')
    def validate_commission_type(cls, v):
        valid_types = ['fixed', 'percentage', 'case_by_case']
        if v not in valid_types:
            raise ValueError(f'نوع حق‌الزحمه باید یکی از {valid_types} باشد')
        return v


class RepairTechnicianUpdate(BaseModel):
    """به‌روزرسانی تعمیرکار"""
    code: Optional[str] = Field(None, max_length=50)
    commission_type: Optional[str] = None
    commission_value: Optional[Decimal] = None
    is_active: Optional[bool] = None
    extra_info: Optional[dict] = None

    @validator('commission_type')
    def validate_commission_type(cls, v):
        if v is not None:
            valid_types = ['fixed', 'percentage', 'case_by_case']
            if v not in valid_types:
                raise ValueError(f'نوع حق‌الزحمه باید یکی از {valid_types} باشد')
        return v


class RepairTechnicianResponse(BaseModel):
    """پاسخ تعمیرکار"""
    id: int
    business_id: int
    person_id: int
    person_name: str
    code: str
    commission_type: str
    commission_value: float
    is_active: bool
    extra_info: dict


# ========== Repair Order ==========

class RepairOrderCreate(BaseModel):
    """ایجاد سفارش تعمیر"""
    customer_person_id: int = Field(..., description="شناسه مشتری (phone و email از persons دریافت می‌شود)")
    product_id: Optional[int] = Field(None, description="شناسه کالا (اگر در سیستم باشد)")
    product_name: str = Field(..., max_length=255, description="نام کالا")
    product_serial: Optional[str] = Field(None, max_length=100)
    warranty_code_id: Optional[int] = Field(None, description="کد گارانتی")
    problem_description: str = Field(..., description="شرح مشکل")
    customer_notes: Optional[str] = None
    estimated_cost: Optional[Decimal] = Field(None, description="هزینه برآوردی")
    currency_id: Optional[int] = None
    estimated_delivery_at: Optional[datetime] = None


class RepairOrderUpdate(BaseModel):
    """به‌روزرسانی سفارش تعمیر"""
    product_serial: Optional[str] = Field(None, max_length=100)
    problem_description: Optional[str] = None
    customer_notes: Optional[str] = None
    technician_notes: Optional[str] = None
    estimated_cost: Optional[Decimal] = None
    estimated_delivery_at: Optional[datetime] = None


class RepairOrderPartItem(BaseModel):
    """قطعه در پاسخ"""
    id: int
    product_id: int
    product_name: str
    quantity: float
    unit_price: float
    total_price: float
    warehouse_id: Optional[int]
    description: Optional[str]


class RepairOrderStatusItem(BaseModel):
    """وضعیت در تاریخچه"""
    id: int
    status: str
    notes: Optional[str]
    created_at: str
    sms_sent: bool
    email_sent: bool


class RepairOrderResponse(BaseModel):
    """پاسخ کامل سفارش تعمیر"""
    id: int
    code: str
    business_id: int
    customer_person_id: int
    customer_name: str
    customer_phone: Optional[str]
    customer_email: Optional[str]
    product_id: Optional[int]
    product_name: str
    product_serial: Optional[str]
    warranty_code_id: Optional[int]
    status: str
    problem_description: str
    customer_notes: Optional[str]
    technician_notes: Optional[str]
    assigned_technician_id: Optional[int]
    technician_name: Optional[str]
    estimated_cost: Optional[float]
    final_cost: float
    parts_cost: float
    labor_cost: float
    technician_commission: float
    received_at: str
    estimated_delivery_at: Optional[str]
    completed_at: Optional[str]
    delivered_at: Optional[str]
    extra_info: dict
    parts: List[RepairOrderPartItem]
    status_history: List[RepairOrderStatusItem]


class RepairOrderListItem(BaseModel):
    """آیتم در لیست سفارشات"""
    id: int
    code: str
    customer_person_id: int
    customer_name: str
    customer_phone: Optional[str]
    product_name: str
    product_serial: Optional[str]
    status: str
    problem_description: str
    assigned_technician_id: Optional[int]
    technician_name: Optional[str]
    final_cost: float
    received_at: str
    estimated_delivery_at: Optional[str]
    completed_at: Optional[str]


# ========== Operations ==========

class AssignTechnicianRequest(BaseModel):
    """اختصاص تعمیرکار"""
    technician_id: int = Field(..., description="شناسه تعمیرکار")


class UpdateStatusRequest(BaseModel):
    """تغییر وضعیت"""
    status: str = Field(..., description="وضعیت جدید")
    notes: Optional[str] = Field(None, description="یادداشت")
    send_notification: bool = Field(True, description="ارسال پیامک/ایمیل")

    @validator('status')
    def validate_status(cls, v):
        valid_statuses = [
            "received", "assigned", "in_progress", "waiting_parts", "testing",
            "completed_fixed", "completed_unfixable", "ready_for_pickup", "delivered", "cancelled"
        ]
        if v not in valid_statuses:
            raise ValueError(f'وضعیت باید یکی از {valid_statuses} باشد')
        return v


class AddPartRequest(BaseModel):
    """افزودن قطعه"""
    product_id: int = Field(..., description="شناسه قطعه")
    quantity: Decimal = Field(..., gt=0, description="تعداد")
    unit_price: Optional[Decimal] = Field(None, description="قیمت واحد (اختیاری)")
    warehouse_id: Optional[int] = Field(None, description="انبار")
    description: Optional[str] = None


class AddPartsRequest(BaseModel):
    """افزودن چند قطعه"""
    parts: List[AddPartRequest] = Field(..., min_items=1, description="لیست قطعات")


class CalculateCostsRequest(BaseModel):
    """محاسبه هزینه‌ها"""
    labor_cost: Decimal = Field(..., ge=0, description="دستمزد تعمیر")


class CalculateCostsResponse(BaseModel):
    """پاسخ محاسبه هزینه‌ها"""
    repair_order_id: int
    parts_cost: float
    labor_cost: float
    technician_commission: float
    final_cost: float


class CompleteRepairRequest(BaseModel):
    """اتمام تعمیر"""
    is_fixed: bool = Field(..., description="آیا تعمیر موفق بوده؟")
    notes: Optional[str] = Field(None, description="یادداشت")


class DeliverRepairRequest(BaseModel):
    """تحویل کالا"""
    notes: Optional[str] = Field(None, description="یادداشت تحویل")


# ========== Reports ==========

class RepairOrderFilters(BaseModel):
    """فیلترهای لیست سفارشات"""
    status: Optional[str] = None
    customer_person_id: Optional[int] = None
    assigned_technician_id: Optional[int] = None
    warranty_code_id: Optional[int] = None
    from_date: Optional[datetime] = None
    to_date: Optional[datetime] = None
    search: Optional[str] = Field(None, description="جستجو در کد، نام کالا، سریال، شماره تماس")


class RepairHistoryItem(BaseModel):
    """آیتم تاریخچه تعمیرات"""
    id: int
    code: str
    customer_name: str
    problem_description: str
    status: str
    final_cost: float
    received_at: str
    completed_at: Optional[str]

