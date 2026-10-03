from __future__ import annotations

from decimal import Decimal

from pydantic import BaseModel, Field, field_validator


class ProductBundleItemRequest(BaseModel):
    product_id: int = Field(..., gt=0)
    quantity: Decimal = Field(..., gt=0, max_digits=18, decimal_places=6)


class ProductBundleCreateRequest(BaseModel):
    name: str = Field(..., min_length=1, max_length=255)
    description: str | None = Field(default=None, max_length=5000)
    is_active: bool = True
    items: list[ProductBundleItemRequest] = Field(..., min_length=1, max_length=500)

    @field_validator("name")
    @classmethod
    def normalize_name(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("نام باندل نمی‌تواند خالی باشد")
        return value


class ProductBundleUpdateRequest(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=255)
    description: str | None = Field(default=None, max_length=5000)
    is_active: bool | None = None
    items: list[ProductBundleItemRequest] | None = Field(default=None, min_length=1, max_length=500)

    @field_validator("name")
    @classmethod
    def normalize_name(cls, value: str | None) -> str | None:
        if value is None:
            return None
        value = value.strip()
        if not value:
            raise ValueError("نام باندل نمی‌تواند خالی باشد")
        return value


class ProductBundleExpandRequest(BaseModel):
    quantity: Decimal = Field(default=Decimal("1"), gt=0, max_digits=18, decimal_places=6)
