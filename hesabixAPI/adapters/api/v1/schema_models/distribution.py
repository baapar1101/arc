"""Schemaهای افزونه پخش مویرگی."""

from __future__ import annotations

from typing import Any, Dict, List, Literal, Optional, Union

from pydantic import BaseModel, Field, field_validator


class DistributionSettingsPayload(BaseModel):
	shared_routing_catalog: Optional[bool] = None
	require_visit_in_daily_plan: Optional[bool] = None
	geofence_radius_meters: Optional[int] = Field(None, ge=0, le=50000)
	require_geofence: Optional[bool] = None
	visit_checklist_template: Optional[List[Dict[str, Any]]] = None
	enable_van_sales: Optional[bool] = None
	default_source_warehouse_id: Optional[int] = Field(None, gt=0)


class TerritoryCreatePayload(BaseModel):
	code: str = Field(..., min_length=1, max_length=50)
	name: str = Field(..., min_length=1, max_length=255)
	description: Optional[str] = None
	is_active: bool = True


class TerritoryUpdatePayload(BaseModel):
	name: Optional[str] = Field(None, max_length=255)
	description: Optional[str] = None
	is_active: Optional[bool] = None


class RouteCreatePayload(BaseModel):
	code: str = Field(..., min_length=1, max_length=50)
	name: str = Field(..., min_length=1, max_length=255)
	description: Optional[str] = None
	territory_id: Optional[int] = None
	is_active: bool = True


class RouteUpdatePayload(BaseModel):
	name: Optional[str] = Field(None, max_length=255)
	description: Optional[str] = None
	territory_id: Optional[int] = None
	is_active: Optional[bool] = None


class RouteStopPayload(BaseModel):
	id: Optional[int] = None
	person_id: int = Field(..., gt=0)
	sort_order: int = 0
	weekday: Optional[int] = Field(None, ge=0, le=6)
	notes: Optional[str] = None


class AssignmentCreatePayload(BaseModel):
	route_id: int = Field(..., gt=0)
	user_id: int = Field(..., gt=0)
	valid_from: str = Field(..., description="YYYY-MM-DD")
	valid_to: Optional[str] = None


class VisitStartPayload(BaseModel):
	person_id: int = Field(..., gt=0)
	route_id: Optional[int] = None
	route_stop_id: Optional[int] = None
	notes: Optional[str] = None
	start_latitude: Optional[float] = None
	start_longitude: Optional[float] = None
	geofence_override: Optional[bool] = None
	extra_info: Optional[Dict[str, Any]] = None


class VisitCompletePayload(BaseModel):
	outcome: Literal["order", "no_order"]
	no_order_reason: Optional[str] = None
	document_id: Optional[int] = Field(None, gt=0)
	deal_id: Optional[int] = Field(None, gt=0)
	notes: Optional[str] = None
	end_latitude: Optional[float] = None
	end_longitude: Optional[float] = None
	checklist_answers: Optional[Union[Dict[str, Any], List[Any]]] = None
	shelf_photo_file_id: Optional[int] = Field(None, gt=0)
	van_sale_lines: Optional[List[Dict[str, Any]]] = None
	extra_info: Optional[Dict[str, Any]] = None


class VisitCancelPayload(BaseModel):
	reason: Optional[str] = None


class ReturnLinePayload(BaseModel):
	product_id: int = Field(..., gt=0)
	quantity: float = Field(..., gt=0)
	reason: Optional[str] = Field(None, max_length=500)
	unit: Optional[str] = Field(None, max_length=32)

	@field_validator("quantity")
	@classmethod
	def _qty_positive(cls, v: float) -> float:
		if v <= 0:
			raise ValueError("quantity must be positive")
		return v


class ReturnRequestCreatePayload(BaseModel):
	person_id: int = Field(..., gt=0)
	visit_id: Optional[int] = Field(None, gt=0)
	lines: List[ReturnLinePayload] = Field(..., min_length=1)
	notes: Optional[str] = None


class ReturnResolvePayload(BaseModel):
	status: Literal["approved", "rejected"]
	resolved_document_id: Optional[int] = Field(None, gt=0)


class VanCreatePayload(BaseModel):
	code: str = Field(..., min_length=1, max_length=50)
	name: str = Field(..., min_length=1, max_length=255)
	user_id: Optional[int] = Field(None, gt=0)
	is_active: bool = True


class VanLoadPayload(BaseModel):
	lines: List[ReturnLinePayload] = Field(..., min_length=1)
	source_warehouse_id: Optional[int] = Field(None, gt=0)


class PersonLocationPayload(BaseModel):
	latitude: float
	longitude: float


class OfflineSyncPayload(BaseModel):
	client_batch_id: Optional[str] = Field(None, max_length=64)
	actions: List[Dict[str, Any]] = Field(..., min_length=1)
