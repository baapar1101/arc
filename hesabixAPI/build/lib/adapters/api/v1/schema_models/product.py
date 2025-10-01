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

    main_unit_id: Optional[int] = None
    secondary_unit_id: Optional[int] = None
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


class ProductUpdateRequest(BaseModel):
    item_type: Optional[ProductItemType] = None
    code: Optional[str] = Field(default=None, max_length=64)
    name: Optional[str] = Field(default=None, min_length=1, max_length=255)
    description: Optional[str] = Field(default=None, max_length=2000)
    category_id: Optional[int] = None

    main_unit_id: Optional[int] = None
    secondary_unit_id: Optional[int] = None
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


class ProductResponse(BaseModel):
    id: int
    business_id: int
    item_type: str
    code: str
    name: str
    description: Optional[str] = None
    category_id: Optional[int] = None
    main_unit_id: Optional[int] = None
    secondary_unit_id: Optional[int] = None
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
    created_at: str
    updated_at: str

    class Config:
        from_attributes = True


