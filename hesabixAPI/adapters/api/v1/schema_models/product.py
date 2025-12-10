"""
Schema models کامل برای محصولات (Products)

این ماژول شامل تمام schema های مورد نیاز برای مدیریت محصولات است.
"""
from typing import Optional, List, Literal
from pydantic import BaseModel, Field, validator
from datetime import datetime
from decimal import Decimal
from enum import Enum


class ProductItemType(str, Enum):
    """نوع آیتم محصول"""
    PRODUCT = "کالا"
    SERVICE = "خدمت"


class ProductAttributeValue(BaseModel):
    """مقدار ویژگی محصول"""
    attribute_id: int = Field(..., description="شناسه ویژگی", gt=0)
    value: str = Field(..., description="مقدار ویژگی", max_length=200)


class ProductCreateRequest(BaseModel):
    """درخواست ایجاد محصول جدید"""
    code: Optional[str] = Field(
        None, 
        description="کد محصول (اگر ارسال نشود، خودکار تولید می‌شود)",
        max_length=50,
        example="P1001"
    )
    name: str = Field(
        ..., 
        description="نام محصول",
        max_length=200,
        example="لپ‌تاپ Asus Vivobook"
    )
    item_type: Literal["کالا", "خدمت"] = Field(
        default="کالا",
        description="نوع آیتم: کالا یا خدمت",
        example="کالا"
    )
    
    description: Optional[str] = Field(
        None, 
        description="توضیحات کامل محصول",
        max_length=2000
    )
    
    # دسته‌بندی
    category_id: Optional[int] = Field(
        None,
        description="شناسه دسته‌بندی",
        gt=0
    )
    
    # واحدها
    main_unit: Optional[str] = Field(
        None,
        description="واحد اصلی (مثال: عدد، کیلوگرم، متر)",
        max_length=50,
        example="عدد"
    )
    secondary_unit: Optional[str] = Field(
        None,
        description="واحد فرعی (اختیاری)",
        max_length=50,
        example="بسته"
    )
    unit_conversion_factor: Optional[Decimal] = Field(
        None,
        description="ضریب تبدیل واحد فرعی به اصلی (مثال: 1 بسته = 12 عدد)",
        gt=0,
        example=12
    )
    
    # قیمت‌گذاری
    base_sales_price: Optional[Decimal] = Field(
        None,
        description="قیمت فروش پایه",
        ge=0,
        example=15000000
    )
    base_purchase_price: Optional[Decimal] = Field(
        None,
        description="قیمت خرید پایه",
        ge=0,
        example=12000000
    )
    
    # موجودی و انبارداری
    track_inventory: bool = Field(
        default=False,
        description="آیا موجودی این محصول کنترل شود؟"
    )
    default_warehouse_id: Optional[int] = Field(
        None,
        description="شناسه انبار پیش‌فرض",
        gt=0
    )
    reorder_point: Optional[int] = Field(
        None,
        description="نقطه سفارش مجدد (حداقل موجودی)",
        ge=0
    )
    min_order_qty: Optional[int] = Field(
        None,
        description="حداقل تعداد سفارش",
        ge=0
    )
    lead_time_days: Optional[int] = Field(
        None,
        description="زمان تحویل (روز)",
        ge=0
    )
    
    # حالت موجودی (فله‌ای/یونیک)
    inventory_mode: Optional[Literal["bulk", "unique"]] = Field(
        default="bulk",
        description="حالت موجودی: bulk (فله‌ای) یا unique (یونیک)"
    )
    track_serial: bool = Field(
        default=False,
        description="ردیابی سریال نامبر برای کالاهای یونیک"
    )
    track_barcode: bool = Field(
        default=False,
        description="ردیابی بارکد برای کالاهای یونیک"
    )
    
    # مالیات
    is_sales_taxable: bool = Field(
        default=False,
        description="آیا در فروش مشمول مالیات است؟"
    )
    is_purchase_taxable: bool = Field(
        default=False,
        description="آیا در خرید مشمول مالیات است؟"
    )
    sales_tax_rate: Optional[Decimal] = Field(
        None,
        description="نرخ مالیات فروش (درصد)",
        ge=0,
        le=100,
        example=9
    )
    purchase_tax_rate: Optional[Decimal] = Field(
        None,
        description="نرخ مالیات خرید (درصد)",
        ge=0,
        le=100
    )
    tax_type_id: Optional[int] = Field(
        None,
        description="شناسه نوع مالیات",
        gt=0
    )
    tax_code: Optional[str] = Field(
        None,
        description="کد مالیاتی محصول",
        max_length=50
    )
    tax_unit_id: Optional[int] = Field(
        None,
        description="شناسه واحد مالیاتی",
        gt=0
    )
    
    # یادداشت‌های پیش‌فرض
    base_sales_note: Optional[str] = Field(
        None,
        description="یادداشت پیش‌فرض فروش",
        max_length=500
    )
    base_purchase_note: Optional[str] = Field(
        None,
        description="یادداشت پیش‌فرض خرید",
        max_length=500
    )
    
    # تصویر
    image_file_id: Optional[str] = Field(
        None,
        description="شناسه فایل تصویر محصول (UUID)"
    )
    
    # ویژگی‌ها
    attribute_ids: Optional[List[int]] = Field(
        None,
        description="لیست شناسه‌های ویژگی‌های محصول"
    )
    
    # بارکد
    barcode: Optional[str] = Field(
        None,
        description="بارکد محصول",
        max_length=50
    )
    
    # وضعیت
    is_active: bool = Field(
        default=True,
        description="آیا محصول فعال است؟"
    )
    
    class Config:
        json_schema_extra = {
            "example": {
                "code": "P1001",
                "name": "لپ‌تاپ Asus Vivobook 15",
                "item_type": "کالا",
                "description": "لپ‌تاپ 15.6 اینچی با پردازنده Core i5",
                "category_id": 1,
                "main_unit": "عدد",
                "base_sales_price": 15000000,
                "base_purchase_price": 12000000,
                "track_inventory": True,
                "default_warehouse_id": 1,
                "reorder_point": 5,
                "is_sales_taxable": True,
                "sales_tax_rate": 9,
                "barcode": "1234567890123"
            }
        }


class ProductUpdateRequest(BaseModel):
    """درخواست ویرایش محصول"""
    code: Optional[str] = Field(None, max_length=50)
    name: Optional[str] = Field(None, max_length=200)
    item_type: Optional[Literal["کالا", "خدمت"]] = None
    description: Optional[str] = Field(None, max_length=2000)
    category_id: Optional[int] = Field(None, gt=0)
    
    main_unit: Optional[str] = Field(None, max_length=50)
    secondary_unit: Optional[str] = Field(None, max_length=50)
    unit_conversion_factor: Optional[Decimal] = Field(None, gt=0)
    
    base_sales_price: Optional[Decimal] = Field(None, ge=0)
    base_purchase_price: Optional[Decimal] = Field(None, ge=0)
    
    track_inventory: Optional[bool] = None
    default_warehouse_id: Optional[int] = Field(None, gt=0)
    reorder_point: Optional[int] = Field(None, ge=0)
    min_order_qty: Optional[int] = Field(None, ge=0)
    lead_time_days: Optional[int] = Field(None, ge=0)
    
    inventory_mode: Optional[Literal["bulk", "unique"]] = None
    track_serial: Optional[bool] = None
    track_barcode: Optional[bool] = None
    
    is_sales_taxable: Optional[bool] = None
    is_purchase_taxable: Optional[bool] = None
    sales_tax_rate: Optional[Decimal] = Field(None, ge=0, le=100)
    purchase_tax_rate: Optional[Decimal] = Field(None, ge=0, le=100)
    tax_type_id: Optional[int] = Field(None, gt=0)
    tax_code: Optional[str] = Field(None, max_length=50)
    tax_unit_id: Optional[int] = Field(None, gt=0)
    
    base_sales_note: Optional[str] = Field(None, max_length=500)
    base_purchase_note: Optional[str] = Field(None, max_length=500)
    
    image_file_id: Optional[str] = None
    attribute_ids: Optional[List[int]] = None
    barcode: Optional[str] = Field(None, max_length=50)
    is_active: Optional[bool] = None


class ProductInventoryInfo(BaseModel):
    """اطلاعات موجودی محصول"""
    warehouse_id: Optional[int]
    warehouse_name: Optional[str]
    quantity: Decimal
    reserved_quantity: Decimal
    available_quantity: Decimal
    unit_cost: Optional[Decimal]
    total_value: Optional[Decimal]


class ProductResponse(BaseModel):
    """پاسخ اطلاعات محصول"""
    id: int = Field(..., description="شناسه محصول")
    code: str = Field(..., description="کد محصول")
    name: str = Field(..., description="نام محصول")
    item_type: str = Field(..., description="نوع آیتم")
    
    description: Optional[str] = None
    
    business_id: int
    
    category_id: Optional[int] = None
    category_name: Optional[str] = None
    
    main_unit: Optional[str] = None
    secondary_unit: Optional[str] = None
    unit_conversion_factor: Optional[Decimal] = None
    
    base_sales_price: Optional[Decimal] = None
    base_purchase_price: Optional[Decimal] = None
    
    track_inventory: bool
    default_warehouse_id: Optional[int] = None
    default_warehouse_name: Optional[str] = None
    reorder_point: Optional[int] = None
    min_order_qty: Optional[int] = None
    lead_time_days: Optional[int] = None
    
    is_sales_taxable: bool
    is_purchase_taxable: bool
    sales_tax_rate: Optional[Decimal] = None
    purchase_tax_rate: Optional[Decimal] = None
    tax_type_id: Optional[int] = None
    tax_code: Optional[str] = None
    tax_unit_id: Optional[int] = None
    
    base_sales_note: Optional[str] = None
    base_purchase_note: Optional[str] = None
    
    image_file_id: Optional[str] = None
    image_url: Optional[str] = None
    thumbnail_url: Optional[str] = None
    
    barcode: Optional[str] = None
    is_active: bool
    
    # اطلاعات موجودی (اختیاری - بسته به درخواست)
    inventory: Optional[List[ProductInventoryInfo]] = Field(
        None,
        description="اطلاعات موجودی در انبارها (فقط در صورت درخواست)"
    )
    total_quantity: Optional[Decimal] = Field(
        None,
        description="موجودی کل در تمام انبارها"
    )
    total_value: Optional[Decimal] = Field(
        None,
        description="ارزش کل موجودی"
    )
    
    # ویژگی‌ها
    attributes: Optional[List[dict]] = None
    
    created_at: Optional[str] = None
    updated_at: Optional[str] = None
    created_by_name: Optional[str] = None
    
    class Config:
        json_schema_extra = {
            "example": {
                "id": 1,
                "code": "P1001",
                "name": "لپ‌تاپ Asus Vivobook 15",
                "item_type": "کالا",
                "category_name": "لپ‌تاپ",
                "main_unit": "عدد",
                "base_sales_price": 15000000,
                "base_purchase_price": 12000000,
                "track_inventory": True,
                "total_quantity": 25,
                "total_value": 300000000,
                "is_active": True
            }
        }


class ProductListResponse(BaseModel):
    """پاسخ لیست محصولات"""
    items: List[ProductResponse] = Field(..., description="لیست محصولات")
    total_count: int = Field(..., description="تعداد کل")
    has_more: bool = Field(..., description="آیا رکورد بیشتری وجود دارد")


class BulkPriceUpdateRequest(BaseModel):
    """درخواست تغییر گروهی قیمت"""
    product_ids: List[int] = Field(
        ...,
        description="لیست شناسه‌های محصولات",
        min_items=1
    )
    price_type: Literal["sales", "purchase"] = Field(
        ...,
        description="نوع قیمت: sales (فروش) یا purchase (خرید)"
    )
    change_type: Literal["percent", "amount", "set"] = Field(
        ...,
        description="نوع تغییر: percent (درصد), amount (مبلغ ثابت), set (تنظیم مقدار)"
    )
    value: Decimal = Field(
        ...,
        description="مقدار تغییر (بسته به change_type)"
    )
    
    @validator('value')
    def validate_value(cls, v, values):
        change_type = values.get('change_type')
        if change_type == 'percent' and (v < -100 or v > 1000):
            raise ValueError('درصد باید بین -100 تا 1000 باشد')
        if change_type == 'set' and v < 0:
            raise ValueError('قیمت نمی‌تواند منفی باشد')
        return v
    
    class Config:
        json_schema_extra = {
            "examples": [
                {
                    "summary": "افزایش 10 درصدی قیمت",
                    "value": {
                        "product_ids": [1, 2, 3],
                        "price_type": "sales",
                        "change_type": "percent",
                        "value": 10
                    }
                },
                {
                    "summary": "کاهش 50000 تومانی قیمت",
                    "value": {
                        "product_ids": [4, 5],
                        "price_type": "purchase",
                        "change_type": "amount",
                        "value": -50000
                    }
                },
                {
                    "summary": "تنظیم قیمت به 100000",
                    "value": {
                        "product_ids": [5],
                        "price_type": "purchase",
                        "change_type": "set",
                        "value": 100000
                    }
                }
            ]
        }


class BulkPriceUpdateType(str, Enum):
    """نوع تغییر قیمت گروهی"""
    PERCENTAGE = "percentage"
    AMOUNT = "amount"


class BulkPriceUpdateDirection(str, Enum):
    """جهت تغییر قیمت"""
    INCREASE = "increase"
    DECREASE = "decrease"


class BulkPriceUpdateTarget(str, Enum):
    """هدف تغییر قیمت"""
    SALES_PRICE = "sales_price"
    PURCHASE_PRICE = "purchase_price"
    BOTH = "both"


class BulkPriceUpdatePreview(BaseModel):
    """پیش‌نمایش تغییرات قیمت"""
    product_id: int
    product_name: str
    product_code: str
    category_name: Optional[str] = None
    current_sales_price: Optional[Decimal] = None
    current_purchase_price: Optional[Decimal] = None
    new_sales_price: Optional[Decimal] = None
    new_purchase_price: Optional[Decimal] = None
    sales_price_change: Optional[Decimal] = None
    purchase_price_change: Optional[Decimal] = None


class BulkPriceUpdatePreviewResponse(BaseModel):
    """پیش‌نمایش تغییر قیمت گروهی"""
    affected_count: int = Field(..., description="تعداد محصولات تحت تأثیر")
    preview: List[dict] = Field(
        ...,
        description="پیش‌نمایش تغییرات - شامل: product_id, name, old_price, new_price"
    )
    
    class Config:
        json_schema_extra = {
            "example": {
                "affected_count": 3,
                "preview": [
                    {
                        "product_id": 1,
                        "name": "محصول A",
                        "old_price": 100000,
                        "new_price": 110000
                    }
                ]
            }
        }
