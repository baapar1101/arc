from __future__ import annotations

from typing import Optional, List
from decimal import Decimal
from pydantic import BaseModel, Field


class BomStatus(str):
    DRAFT = "draft"
    APPROVED = "approved"
    ARCHIVED = "archived"


class BomItem(BaseModel):
    line_no: int
    component_product_id: int
    qty_per: Decimal = Field(..., description="مقدار برای تولید 1 واحد")
    uom: Optional[str] = Field(default=None, max_length=32)
    wastage_percent: Optional[Decimal] = Field(default=None)
    is_optional: bool = Field(default=False)
    substitute_group: Optional[str] = Field(default=None, max_length=64)
    suggested_warehouse_id: Optional[int] = Field(default=None)


class BomOutput(BaseModel):
    line_no: int
    output_product_id: int
    ratio: Decimal
    uom: Optional[str] = Field(default=None, max_length=32)


class BomOperation(BaseModel):
    line_no: int
    operation_name: str
    cost_fixed: Optional[Decimal] = None
    cost_per_unit: Optional[Decimal] = None
    cost_uom: Optional[str] = Field(default=None, max_length=32)
    work_center: Optional[str] = Field(default=None, max_length=128)


class ProductBOMCreateRequest(BaseModel):
    product_id: int
    version: str = Field(..., max_length=64)
    name: str = Field(..., max_length=255)
    is_default: bool = Field(default=False)
    effective_from: Optional[str] = Field(default=None)
    effective_to: Optional[str] = Field(default=None)
    yield_percent: Optional[Decimal] = None
    wastage_percent: Optional[Decimal] = None
    status: str = Field(default=BomStatus.DRAFT)
    notes: Optional[str] = Field(default=None, max_length=5000)

    items: List[BomItem] = Field(default_factory=list)
    outputs: List[BomOutput] = Field(default_factory=list)
    operations: List[BomOperation] = Field(default_factory=list)


class ProductBOMUpdateRequest(BaseModel):
    version: Optional[str] = Field(default=None, max_length=64)
    name: Optional[str] = Field(default=None, max_length=255)
    is_default: Optional[bool] = Field(default=None)
    effective_from: Optional[str] = Field(default=None)
    effective_to: Optional[str] = Field(default=None)
    yield_percent: Optional[Decimal] = None
    wastage_percent: Optional[Decimal] = None
    status: Optional[str] = Field(default=None)
    notes: Optional[str] = Field(default=None, max_length=5000)

    items: Optional[List[BomItem]] = None
    outputs: Optional[List[BomOutput]] = None
    operations: Optional[List[BomOperation]] = None


class ProductBOMResponse(BaseModel):
    id: int
    business_id: int
    product_id: int
    version: str
    name: str
    is_default: bool
    effective_from: Optional[str] = None
    effective_to: Optional[str] = None
    yield_percent: Optional[Decimal] = None
    wastage_percent: Optional[Decimal] = None
    status: str
    notes: Optional[str] = None
    created_at: str
    updated_at: str

    items: List[BomItem] = Field(default_factory=list)
    outputs: List[BomOutput] = Field(default_factory=list)
    operations: List[BomOperation] = Field(default_factory=list)

    class Config:
        from_attributes = True


class BOMExplosionRequest(BaseModel):
    product_id: Optional[int] = None
    bom_id: Optional[int] = None
    quantity: Decimal = Field(..., description="مقدار تولید")
    date: Optional[str] = None

    class Config:
        json_schema_extra = {
            "examples": [
                {"product_id": 1, "quantity": 100},
            ]
        }


class BOMExplosionItem(BaseModel):
    component_product_id: int
    required_qty: Decimal
    uom: Optional[str] = None
    suggested_warehouse_id: Optional[int] = None
    is_optional: bool
    substitute_group: Optional[str] = None


class BOMExplosionResult(BaseModel):
    items: List[BOMExplosionItem]
    outputs: List[BomOutput]
    notes: Optional[str] = None


