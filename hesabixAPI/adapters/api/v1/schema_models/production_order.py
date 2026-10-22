from __future__ import annotations

from datetime import date
from decimal import Decimal
from typing import Optional

from pydantic import BaseModel, Field


class ProductionOrderCreateRequest(BaseModel):
	product_id: int = Field(gt=0)
	bom_id: int = Field(gt=0)
	quantity: Decimal = Field(gt=0, max_digits=18, decimal_places=6)
	warehouse_id: int = Field(gt=0, description="انبار مصرف مواد")
	output_warehouse_id: int = Field(gt=0, description="انبار دریافت محصول")
	planned_start_date: Optional[date] = None
	due_date: Optional[date] = None
	priority: int = Field(default=3, ge=1, le=5)
	notes: Optional[str] = Field(default=None, max_length=5000)
	
	class Config:
		json_schema_extra = {
			"examples": [{
				"product_id": 1,
				"bom_id": 1,
				"quantity": "100",
				"warehouse_id": 1,
				"output_warehouse_id": 1,
				"priority": 3,
			}]
		}


class ProductionOrderUpdateRequest(BaseModel):
	version: int = Field(ge=1, description="Optimistic concurrency version")
	quantity: Optional[Decimal] = Field(default=None, gt=0, max_digits=18, decimal_places=6)
	warehouse_id: Optional[int] = Field(default=None, gt=0)
	output_warehouse_id: Optional[int] = Field(default=None, gt=0)
	planned_start_date: Optional[date] = None
	due_date: Optional[date] = None
	priority: Optional[int] = Field(default=None, ge=1, le=5)
	notes: Optional[str] = Field(default=None, max_length=5000)
	
class ProductionOrderActionRequest(BaseModel):
	version: int = Field(ge=1, description="Optimistic concurrency version")
	close_reason: Optional[str] = Field(default=None, max_length=2000, description="Required to close an order below planned output")


class ProductionOrderLotLine(BaseModel):
	id: int = Field(gt=0)
	lot_code: Optional[str] = Field(default=None, max_length=64)
	scrap_quantity: Optional[Decimal] = Field(default=None, ge=0, max_digits=18, decimal_places=6)


class ProductionOrderLotsUpdateRequest(BaseModel):
	version: int = Field(ge=1, description="Optimistic concurrency version")
	materials: Optional[list[ProductionOrderLotLine]] = None
	outputs: Optional[list[ProductionOrderLotLine]] = None
