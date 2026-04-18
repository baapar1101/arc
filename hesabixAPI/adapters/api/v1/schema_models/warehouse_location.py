from __future__ import annotations

from typing import Optional
from decimal import Decimal

from pydantic import BaseModel, Field, model_validator


ALLOWED_LOCATION_KINDS = frozenset({"zone", "aisle", "rack", "shelf", "bin", "other"})


class WarehouseLocationCreateRequest(BaseModel):
	code: Optional[str] = Field(default=None, max_length=64)
	name: str = Field(..., min_length=1, max_length=255)
	parent_id: Optional[int] = Field(default=None)
	location_kind: str = Field(default="zone", max_length=32)
	sort_order: int = Field(default=0)
	is_active: bool = Field(default=True)
	notes: Optional[str] = Field(default=None, max_length=4000)
	auto_generate_code: bool = Field(default=False, description="تولید کد با سامانهٔ شماره‌گذاری warehouse_location")

	@model_validator(mode="after")
	def validate_code_or_auto(self) -> "WarehouseLocationCreateRequest":
		if not self.auto_generate_code:
			c = (self.code or "").strip()
			if not c:
				raise ValueError("کد محل الزامی است یا گزینهٔ تولید خودکار را فعال کنید")
		return self


class WarehouseLocationUpdateRequest(BaseModel):
	code: Optional[str] = Field(default=None, max_length=64)
	name: Optional[str] = Field(default=None, max_length=255)
	parent_id: Optional[int] = Field(default=None)
	location_kind: Optional[str] = Field(default=None, max_length=32)
	sort_order: Optional[int] = Field(default=None)
	is_active: Optional[bool] = Field(default=None)
	notes: Optional[str] = Field(default=None, max_length=4000)


class WarehousePlacementCreateRequest(BaseModel):
	product_id: int = Field(..., gt=0)
	warehouse_location_id: int = Field(..., gt=0)
	quantity: Decimal = Field(default=Decimal("0"))
	notes: Optional[str] = Field(default=None, max_length=4000)


class WarehousePlacementUpdateRequest(BaseModel):
	quantity: Optional[Decimal] = None
	notes: Optional[str] = Field(default=None, max_length=4000)
	warehouse_location_id: Optional[int] = Field(default=None)
