from __future__ import annotations

from typing import Optional, List
from decimal import Decimal
from pydantic import BaseModel, Field
from enum import Enum


class ProductItemType(str, Enum):
    PRODUCT = "کالا"
    SERVICE = "خدمت"


class ProductCreateRequest(BaseModel):
    item_type: ProductItemType = Field(default=ProductItemType.PRODUCT)
    code: Optional[str] = Field(default=None, max_length=64)
    name: str = Field(..., min_length=1, max_length=255)
    description: Optional[str] = Field(default=None, max_length=2000)
    category_id: Optional[int] = None

    main_unit: Optional[str] = Field(default=None, max_length=32, description="واحد اصلی شمارش")
    secondary_unit: Optional[str] = Field(default=None, max_length=32, description="واحد فرعی شمارش")
    unit_conversion_factor: Optional[Decimal] = None

    base_sales_price: Optional[Decimal] = None
    base_sales_note: Optional[str] = None
    base_purchase_price: Optional[Decimal] = None
    base_purchase_note: Optional[str] = None

    track_inventory: bool = Field(default=False)
    reorder_point: Optional[int] = None
    min_order_qty: Optional[int] = None
    lead_time_days: Optional[int] = None

    is_sales_taxable: bool = Field(default=False)
    is_purchase_taxable: bool = Field(default=False)
    sales_tax_rate: Optional[Decimal] = None
    purchase_tax_rate: Optional[Decimal] = None
    tax_type_id: Optional[int] = None
    tax_code: Optional[str] = Field(default=None, max_length=100)
    tax_unit_id: Optional[int] = None

    attribute_ids: Optional[List[int]] = Field(default=None, description="ویژگی‌های انتخابی برای لینک شدن")
    
    image_file_id: Optional[str] = Field(default=None, description="شناسه فایل عکس کالا")
    
    default_warehouse_id: Optional[int] = Field(default=None, description="شناسه انبار پیش‌فرض برای کالا")


class ProductUpdateRequest(BaseModel):
    item_type: Optional[ProductItemType] = None
    code: Optional[str] = Field(default=None, max_length=64)
    name: Optional[str] = Field(default=None, min_length=1, max_length=255)
    description: Optional[str] = Field(default=None, max_length=2000)
    category_id: Optional[int] = None

    main_unit: Optional[str] = Field(default=None, max_length=32, description="واحد اصلی شمارش")
    secondary_unit: Optional[str] = Field(default=None, max_length=32, description="واحد فرعی شمارش")
    unit_conversion_factor: Optional[Decimal] = None

    base_sales_price: Optional[Decimal] = None
    base_sales_note: Optional[str] = None
    base_purchase_price: Optional[Decimal] = None
    base_purchase_note: Optional[str] = None

    track_inventory: Optional[bool] = None
    reorder_point: Optional[int] = None
    min_order_qty: Optional[int] = None
    lead_time_days: Optional[int] = None

    is_sales_taxable: Optional[bool] = None
    is_purchase_taxable: Optional[bool] = None
    sales_tax_rate: Optional[Decimal] = None
    purchase_tax_rate: Optional[Decimal] = None
    tax_type_id: Optional[int] = None
    tax_code: Optional[str] = Field(default=None, max_length=100)
    tax_unit_id: Optional[int] = None

    attribute_ids: Optional[List[int]] = None
    
    image_file_id: Optional[str] = Field(default=None, description="شناسه فایل عکس کالا")
    
    default_warehouse_id: Optional[int] = Field(default=None, description="شناسه انبار پیش‌فرض برای کالا")


class ProductResponse(BaseModel):
    id: int
    business_id: int
    item_type: str
    code: str
    name: str
    description: Optional[str] = None
    category_id: Optional[int] = None
    main_unit: Optional[str] = None
    secondary_unit: Optional[str] = None
    unit_conversion_factor: Optional[Decimal] = None
    base_sales_price: Optional[Decimal] = None
    base_sales_note: Optional[str] = None
    base_purchase_price: Optional[Decimal] = None
    base_purchase_note: Optional[str] = None
    track_inventory: bool
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
    image_file_id: Optional[str] = None
    image_url: Optional[str] = Field(default=None, description="URL برای نمایش عکس")
    default_warehouse_id: Optional[int] = None
    created_at: str
    updated_at: str

    class Config:
        from_attributes = True


class BulkPriceUpdateType(str, Enum):
    PERCENTAGE = "percentage"
    AMOUNT = "amount"


class BulkPriceUpdateDirection(str, Enum):
    INCREASE = "increase"
    DECREASE = "decrease"


class BulkPriceUpdateTarget(str, Enum):
    SALES_PRICE = "sales_price"
    PURCHASE_PRICE = "purchase_price"
    BOTH = "both"


class BulkPriceUpdateRequest(BaseModel):
    """درخواست تغییر قیمت‌های گروهی"""
    update_type: BulkPriceUpdateType = Field(..., description="نوع تغییر: درصدی یا مقداری")
    direction: BulkPriceUpdateDirection = Field(default=BulkPriceUpdateDirection.INCREASE, description="جهت تغییر: افزایش یا کاهش")
    target: BulkPriceUpdateTarget = Field(..., description="هدف تغییر: قیمت فروش، خرید یا هر دو")
    value: Decimal = Field(..., description="مقدار تغییر (درصد یا مبلغ)")
    
    # فیلترهای انتخاب کالاها
    category_ids: Optional[List[int]] = Field(default=None, description="شناسه‌های دسته‌بندی")
    currency_ids: Optional[List[int]] = Field(default=None, description="شناسه‌های ارز")
    price_list_ids: Optional[List[int]] = Field(default=None, description="شناسه‌های لیست قیمت")
    item_types: Optional[List[ProductItemType]] = Field(default=None, description="نوع آیتم‌ها")
    product_ids: Optional[List[int]] = Field(default=None, description="شناسه‌های کالاهای خاص")
    
    # گزینه‌های اضافی
    only_products_with_inventory: Optional[bool] = Field(default=None, description="فقط کالاهای با موجودی")
    only_products_with_base_price: Optional[bool] = Field(default=True, description="فقط کالاهای با قیمت پایه")


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
    """پاسخ پیش‌نمایش تغییرات قیمت"""
    total_products: int
    affected_products: List[BulkPriceUpdatePreview]
    summary: dict = Field(..., description="خلاصه تغییرات")


