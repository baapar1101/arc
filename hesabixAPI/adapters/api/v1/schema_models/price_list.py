from __future__ import annotations

from typing import Optional, List
from decimal import Decimal
from pydantic import BaseModel, Field


class PriceListCreateRequest(BaseModel):
    name: str = Field(..., min_length=1, max_length=255)
    currency_id: Optional[int] = None
    default_unit_id: Optional[int] = None
    is_active: bool = True


class PriceListUpdateRequest(BaseModel):
    name: Optional[str] = Field(default=None, min_length=1, max_length=255)
    currency_id: Optional[int] = None
    default_unit_id: Optional[int] = None
    is_active: Optional[bool] = None


class PriceItemUpsertRequest(BaseModel):
    product_id: int
    unit_id: Optional[int] = None
    currency_id: Optional[int] = None
    tier_name: str = Field(..., min_length=1, max_length=64)
    min_qty: Decimal = Field(default=0)
    price: Decimal


class PriceListResponse(BaseModel):
    id: int
    business_id: int
    name: str
    currency_id: Optional[int] = None
    default_unit_id: Optional[int] = None
    is_active: bool
    created_at: str
    updated_at: str

    class Config:
        from_attributes = True


class PriceItemResponse(BaseModel):
    id: int
    price_list_id: int
    product_id: int
    unit_id: Optional[int] = None
    currency_id: Optional[int] = None
    tier_name: str
    min_qty: Decimal
    price: Decimal
    created_at: str
    updated_at: str

    class Config:
        from_attributes = True


