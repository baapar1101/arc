from __future__ import annotations

from typing import List, Optional

from pydantic import BaseModel, Field


class VariantDimensionInput(BaseModel):
    attribute_id: int = Field(..., gt=0)
    is_required: bool = True
    sort_order: Optional[int] = Field(default=None, ge=0)


class VariantDimensionsReplaceRequest(BaseModel):
    dimensions: List[VariantDimensionInput] = Field(default_factory=list)


class VariantAttributeValueInput(BaseModel):
    attribute_id: int = Field(..., gt=0)
    option_id: int = Field(..., gt=0)


class ProductVariantCreateRequest(BaseModel):
    code: Optional[str] = Field(default=None, max_length=64)
    barcode: Optional[str] = Field(default=None, max_length=128)
    display_title: Optional[str] = Field(default=None, max_length=255)
    is_active: Optional[bool] = True
    sales_price: Optional[str] = None
    purchase_price: Optional[str] = None
    attribute_values: List[VariantAttributeValueInput]


class ProductVariantUpdateRequest(BaseModel):
    code: Optional[str] = Field(default=None, max_length=64)
    barcode: Optional[str] = Field(default=None, max_length=128)
    display_title: Optional[str] = Field(default=None, max_length=255)
    is_active: Optional[bool] = None
    sales_price: Optional[str] = None
    purchase_price: Optional[str] = None
    row_version: Optional[int] = None
    attribute_values: Optional[List[VariantAttributeValueInput]] = None


class VariantStockSplitItem(BaseModel):
    variant_id: int = Field(..., gt=0)
    quantity: str = Field(..., description="مقدار به واحد اصلی کالا")


class VariantEnableInventoryRequest(BaseModel):
    warehouse_id: int = Field(..., gt=0)
    splits: List[VariantStockSplitItem] = Field(default_factory=list)
    document_date: Optional[str] = None
