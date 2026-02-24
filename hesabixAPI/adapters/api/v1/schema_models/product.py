"""
Schema models کامل برای محصولات (Products)

این ماژول شامل تمام schema های مورد نیاز برای مدیریت محصولات است.
"""
from typing import Optional, List, Literal, Dict, Any
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


class BulkDefaultWarehouseApplyScope(str, Enum):
    """دامنه اعمال تغییر انبار پیش‌فرض به صورت گروهی"""
    TRACK_INVENTORY_TRUE = "track_inventory_true"
    TRACK_INVENTORY_FALSE = "track_inventory_false"
    ALL = "all"


class BulkDefaultWarehouseRequest(BaseModel):
    """درخواست تغییر گروهی انبار پیش‌فرض کالاها"""
    ids: List[int] = Field(..., description="لیست شناسه کالاها", min_length=1)
    default_warehouse_id: Optional[int] = Field(
        None,
        description="شناسه انبار پیش‌فرض جدید (اگر null باشد یعنی پاک‌سازی)",
        gt=0
    )
    apply_scope: BulkDefaultWarehouseApplyScope = Field(
        default=BulkDefaultWarehouseApplyScope.ALL,
        description="اعمال روی کالاهای انبارداری/غیرانبارداری/همه"
    )


class BulkDefaultWarehouseSkippedItem(BaseModel):
    id: int
    reason: str
    code: Optional[str] = None
    name: Optional[str] = None


class BulkDefaultWarehousePreviewResponse(BaseModel):
    total_requested: int
    found_count: int
    will_update_count: int
    forced_service_null_count: int = 0
    skipped: List[BulkDefaultWarehouseSkippedItem] = Field(default_factory=list)
    notes: List[str] = Field(default_factory=list)


class BulkDefaultWarehouseApplyResponse(BaseModel):
    total_requested: int
    found_count: int
    updated_count: int
    forced_service_null_count: int = 0
    skipped: List[BulkDefaultWarehouseSkippedItem] = Field(default_factory=list)
    notes: List[str] = Field(default_factory=list)


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
    default_warehouse_code: Optional[str] = None
    reorder_point: Optional[int] = None
    min_order_qty: Optional[int] = None
    lead_time_days: Optional[int] = None
    
    # حالت موجودی و ردیابی
    inventory_mode: Optional[str] = None
    track_serial: bool = False
    track_barcode: bool = False
    
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
    attribute_ids: Optional[List[int]] = None
    
    # موجودی (برای جستجو با include_inventory)
    inventory_stock_accounting: Optional[Decimal] = None
    inventory_stock_warehouse: Optional[Decimal] = None
    
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


class ProductListPagination(BaseModel):
    """اطلاعات صفحه‌بندی لیست (هم‌شکل با پاسخ لیست اشخاص برای DataTable)"""
    total: int = Field(..., description="تعداد کل رکوردها")
    page: int = Field(..., description="شماره صفحه فعلی (از ۱)")
    per_page: int = Field(..., description="تعداد در هر صفحه")
    total_pages: int = Field(..., description="تعداد کل صفحات")
    has_next: bool = Field(..., description="آیا صفحه بعدی وجود دارد")
    has_prev: bool = Field(..., description="آیا صفحه قبلی وجود دارد")


class ProductListResponse(BaseModel):
    """پاسخ لیست محصولات (هم‌شکل با لیست اشخاص برای DataTable و pagination)"""
    items: List[ProductResponse] = Field(..., description="لیست محصولات")
    total_count: int = Field(..., description="تعداد کل")
    has_more: bool = Field(..., description="آیا رکورد بیشتری وجود دارد")
    pagination: Optional[ProductListPagination] = Field(
        None,
        description="اطلاعات صفحه‌بندی برای نمایش دکمه‌های صفحه بعدی/قبلی در DataTable",
    )


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


class BulkPriceUpdateRequest(BaseModel):
    """
    درخواست تغییر گروهی قیمت (نسخه جدید)

    نکته: این مدل باید با فرانت (`BulkPriceUpdateRequest.toJson`) و سرویس
    `app/services/bulk_price_update_service.py` هم‌خوان باشد.
    """
    update_type: BulkPriceUpdateType = Field(
        ...,
        description="نوع تغییر: percentage (درصدی) یا amount (مبلغی)"
    )
    direction: BulkPriceUpdateDirection = Field(
        default=BulkPriceUpdateDirection.INCREASE,
        description="جهت تغییر: increase (افزایش) یا decrease (کاهش)"
    )
    target: BulkPriceUpdateTarget = Field(
        ...,
        description="هدف تغییر: sales_price / purchase_price / both"
    )
    value: Decimal = Field(
        ...,
        description="مقدار تغییر (همیشه غیرمنفی؛ جهت از طریق direction تعیین می‌شود)",
        ge=0
    )

    # فیلترهای انتخاب کالاها (اختیاری)
    category_ids: Optional[List[int]] = Field(None, description="فیلتر بر اساس دسته‌بندی", min_items=1)
    currency_ids: Optional[List[int]] = Field(None, description="فیلتر بر اساس ارز", min_items=1)
    price_list_ids: Optional[List[int]] = Field(None, description="فیلتر بر اساس لیست قیمت", min_items=1)
    item_types: Optional[List[ProductItemType]] = Field(None, description="فیلتر بر اساس نوع آیتم", min_items=1)
    product_ids: Optional[List[int]] = Field(None, description="شناسه‌های کالاهای خاص", min_items=1)

    # گزینه‌های اضافی
    only_products_with_inventory: Optional[bool] = Field(
        default=None,
        description="اگر true باشد فقط کالاهای دارای کنترل موجودی؛ اگر false باشد فقط کالاهای بدون کنترل موجودی؛ اگر null باشد بدون فیلتر"
    )
    only_products_with_base_price: bool = Field(
        default=True,
        description="فقط کالاهایی که قیمت پایه (متناسب با target) دارند"
    )

    @validator("value")
    def validate_value(cls, v: Decimal, values: dict):
        update_type = values.get("update_type")
        # محدودیت منطقی برای درصد
        if update_type == BulkPriceUpdateType.PERCENTAGE and v > Decimal("1000"):
            raise ValueError("درصد نمی‌تواند بیشتر از 1000 باشد")
        return v

    class Config:
        json_schema_extra = {
            "examples": [
                {
                    "summary": "افزایش 10 درصدی قیمت فروش (با فیلتر دسته)",
                    "value": {
                        "update_type": "percentage",
                        "direction": "increase",
                        "target": "sales_price",
                        "value": 10,
                        "category_ids": [1],
                        "only_products_with_base_price": True
                    }
                },
                {
                    "summary": "کاهش 50000 تومانی قیمت خرید (برای محصولات انتخاب‌شده)",
                    "value": {
                        "update_type": "amount",
                        "direction": "decrease",
                        "target": "purchase_price",
                        "value": 50000,
                        "product_ids": [4, 5]
                    }
                }
            ]
        }


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
    """پیش‌نمایش تغییر قیمت گروهی (مطابق خروجی سرویس bulk_price_update_service و فرانت)"""
    total_products: int = Field(..., description="تعداد کل محصولات مطابق فیلترها")
    affected_products: List[BulkPriceUpdatePreview] = Field(
        ...,
        description="لیست محصولات و پیش‌نمایش تغییرات قیمت"
    )
    summary: Dict[str, Any] = Field(..., description="خلاصه آماری تغییرات")

    class Config:
        json_schema_extra = {
            "example": {
                "total_products": 3,
                "affected_products": [
                    {
                        "product_id": 1,
                        "product_name": "محصول A",
                        "product_code": "P-001",
                        "category_name": "دسته ۱",
                        "current_sales_price": 100000,
                        "current_purchase_price": 80000,
                        "new_sales_price": 110000,
                        "new_purchase_price": 88000,
                        "sales_price_change": 10000,
                        "purchase_price_change": 8000,
                    }
                ],
                "summary": {
                    "total_products": 3,
                    "affected_products": 3,
                    "products_with_sales_change": 3,
                    "products_with_purchase_change": 3,
                    "total_sales_change": 30000,
                    "total_purchase_change": 24000,
                    "update_type": "amount",
                    "direction": "increase",
                    "target": "both",
                    "value": 1000,
                },
            }
        }
