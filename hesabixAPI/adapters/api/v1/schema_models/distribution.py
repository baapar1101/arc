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
	enable_presell: Optional[bool] = None
	enable_promotions: Optional[bool] = None
	visitor_max_discount_percent: Optional[float] = Field(None, ge=0, le=100)
	enable_suggested_order: Optional[bool] = None
	map_tile_source: Optional[Literal["osm", "memaps"]] = None
	memaps_api_key: Optional[str] = Field(None, max_length=255)
	share_live_location: Optional[bool] = None
	carry_over_missed_visits: Optional[bool] = None
	carry_over_days: Optional[int] = Field(None, ge=1, le=31)
	require_pod_signature: Optional[bool] = None
	require_pod_photo: Optional[bool] = None
	nav_provider: Optional[Literal["neshan", "google", "waze"]] = None
	setup_completed: Optional[bool] = None
	auto_apply_promotions: Optional[bool] = None
	enable_perfect_store: Optional[bool] = None
	near_expiry_days: Optional[int] = Field(None, ge=1, le=90)


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
	frequency: Optional[Literal["weekly", "biweekly", "monthly"]] = None
	cycle_offset: Optional[int] = Field(None, ge=0, le=4)
	customer_class: Optional[Literal["A", "B", "C"]] = None
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
	geofence_override_reason: Optional[str] = Field(None, max_length=500)
	supervisor_user_id: Optional[int] = Field(None, gt=0)
	is_carried_over: Optional[bool] = None
	extra_info: Optional[Dict[str, Any]] = None


class VisitCompletePayload(BaseModel):
	outcome: Literal["order", "no_order"]
	no_order_reason: Optional[str] = None
	no_order_reason_code: Optional[str] = Field(None, max_length=32)
	document_id: Optional[int] = Field(None, gt=0)
	deal_id: Optional[int] = Field(None, gt=0)
	notes: Optional[str] = None
	end_latitude: Optional[float] = None
	end_longitude: Optional[float] = None
	checklist_answers: Optional[Union[Dict[str, Any], List[Any]]] = None
	shelf_photo_file_id: Optional[int] = Field(None, gt=0)
	van_sale_lines: Optional[List[Dict[str, Any]]] = None
	extra_info: Optional[Dict[str, Any]] = None
	pod_confirmed: Optional[bool] = None
	pod_signer_name: Optional[str] = Field(None, max_length=255)
	pod_note: Optional[str] = Field(None, max_length=500)
	pod_signature_png: Optional[str] = None
	pod_photo_file_id: Optional[int] = Field(None, gt=0)
	pod_signature_file_id: Optional[int] = Field(None, gt=0)


class VisitCancelPayload(BaseModel):
	reason: Optional[str] = None


class VisitHeartbeatPayload(BaseModel):
	latitude: float
	longitude: float
	visit_id: Optional[int] = Field(None, gt=0)


class ReturnLinePayload(BaseModel):
	product_id: int = Field(..., gt=0)
	quantity: float = Field(..., gt=0)
	reason: Optional[str] = Field(None, max_length=500)
	reason_code: Optional[str] = Field(None, max_length=32)
	unit: Optional[str] = Field(None, max_length=32)
	lot_code: Optional[str] = Field(None, max_length=64)
	expiry_date: Optional[str] = None
	unit_weight_kg: Optional[float] = Field(None, ge=0)
	unit_volume_m3: Optional[float] = Field(None, ge=0)

	@field_validator("quantity")
	@classmethod
	def _qty_positive(cls, v: float) -> float:
		if v <= 0:
			raise ValueError("quantity must be positive")
		return v


class ReturnRequestCreatePayload(BaseModel):
	person_id: int = Field(..., gt=0)
	visit_id: Optional[int] = Field(None, gt=0)
	source_document_id: Optional[int] = Field(None, gt=0)
	lines: List[ReturnLinePayload] = Field(..., min_length=1)
	notes: Optional[str] = None


class ReturnResolvePayload(BaseModel):
	status: Literal["approved", "rejected"]
	resolved_document_id: Optional[int] = Field(None, gt=0)
	source_document_id: Optional[int] = Field(None, gt=0)
	restock_to_van: Optional[bool] = None


class VanCreatePayload(BaseModel):
	code: str = Field(..., min_length=1, max_length=50)
	name: str = Field(..., min_length=1, max_length=255)
	user_id: Optional[int] = Field(None, gt=0)
	is_active: bool = True
	plate_number: Optional[str] = Field(None, max_length=32)
	max_weight_kg: Optional[float] = Field(None, ge=0)
	max_volume_m3: Optional[float] = Field(None, ge=0)


class VanLoadPayload(BaseModel):
	lines: List[ReturnLinePayload] = Field(..., min_length=1)
	source_warehouse_id: Optional[int] = Field(None, gt=0)


class VanUnloadPayload(BaseModel):
	lines: List[ReturnLinePayload] = Field(..., min_length=1)
	dest_warehouse_id: Optional[int] = Field(None, gt=0)


class VanUpdatePayload(BaseModel):
	name: Optional[str] = Field(None, min_length=1, max_length=255)
	user_id: Optional[int] = Field(None, gt=0)
	is_active: Optional[bool] = None
	plate_number: Optional[str] = Field(None, max_length=32)
	max_weight_kg: Optional[float] = Field(None, ge=0)
	max_volume_m3: Optional[float] = Field(None, ge=0)


class PersonLocationPayload(BaseModel):
	latitude: float
	longitude: float


class OfflineSyncPayload(BaseModel):
	client_batch_id: Optional[str] = Field(None, max_length=64)
	actions: List[Dict[str, Any]] = Field(..., min_length=1)


class SalesTargetPayload(BaseModel):
	user_id: int = Field(..., gt=0)
	period_type: Literal["day", "month"]
	period_start: str = Field(..., description="YYYY-MM-DD")
	target_amount: float = Field(..., gt=0)
	metric: Literal["amount", "visits", "sku_qty", "coverage_pct"] = "amount"
	product_id: Optional[int] = Field(None, gt=0)
	target_value: Optional[float] = Field(None, gt=0)
	notes: Optional[str] = None


class SettlementUpsertPayload(BaseModel):
	user_id: Optional[int] = Field(None, gt=0)
	settlement_date: Optional[str] = None
	cash_collected: float = 0
	cheque_collected: float = 0
	card_collected: float = 0
	other_collected: float = 0
	expenses: float = 0
	expected_sales: Optional[float] = None
	cash_register_id: Optional[int] = Field(None, gt=0)
	notes: Optional[str] = None


class SettlementConfirmPayload(BaseModel):
	create_receipt: bool = False
	cash_register_id: Optional[int] = Field(None, gt=0)
	bank_id: Optional[int] = Field(None, gt=0)
	allow_variance: bool = False
	invoice_allocations: Optional[List[Dict[str, Any]]] = None
	cheque_items: Optional[List[Dict[str, Any]]] = None


class VisitOrderCreatePayload(BaseModel):
	person_id: int = Field(..., gt=0)
	visit_id: Optional[int] = Field(None, gt=0)
	route_id: Optional[int] = Field(None, gt=0)
	lines: List[Dict[str, Any]] = Field(..., min_length=1)
	promotion_ids: Optional[List[int]] = None
	requested_delivery_date: Optional[str] = None
	notes: Optional[str] = None
	confirm: bool = False
	extra_info: Optional[Dict[str, Any]] = None


class VisitOrderStatusPayload(BaseModel):
	status: Literal[
		"draft", "confirmed", "picking", "loaded", "out_for_delivery", "delivered", "cancelled"
	]


class PromotionUpsertPayload(BaseModel):
	code: str = Field(..., min_length=1, max_length=50)
	name: str = Field(..., min_length=1, max_length=255)
	mechanic: Literal["percent_off", "amount_off", "bxgy", "foc"] = "percent_off"
	config: Dict[str, Any] = Field(default_factory=dict)
	valid_from: str
	valid_to: Optional[str] = None
	territory_id: Optional[int] = Field(None, gt=0)
	route_id: Optional[int] = Field(None, gt=0)
	product_ids: Optional[List[int]] = None
	is_active: bool = True
	notes: Optional[str] = None


class DeliveryTripCreatePayload(BaseModel):
	driver_user_id: Optional[int] = Field(None, gt=0)
	van_id: Optional[int] = Field(None, gt=0)
	trip_date: Optional[str] = None
	order_ids: List[int] = Field(default_factory=list)
	notes: Optional[str] = None


class DeliveryStopCompletePayload(BaseModel):
	status: Literal["delivered", "partial", "failed"] = "delivered"
	pod_confirmed: Optional[bool] = None
	pod_signer_name: Optional[str] = Field(None, max_length=255)
	pod_note: Optional[str] = Field(None, max_length=500)
	pod_photo_file_id: Optional[int] = Field(None, gt=0)
	latitude: Optional[float] = None
	longitude: Optional[float] = None
	warehouse_id: Optional[int] = Field(None, gt=0)
	delivered_lines: Optional[List[Dict[str, Any]]] = None
	failure_reason: Optional[str] = Field(None, max_length=255)


class LoadPlanCreatePayload(BaseModel):
	plan_date: Optional[str] = None
	warehouse_id: Optional[int] = Field(None, gt=0)
	van_id: Optional[int] = Field(None, gt=0)
	order_ids: Optional[List[int]] = None
	notes: Optional[str] = None


class LoadPlanConfirmPayload(BaseModel):
	actual_lines: Optional[List[ReturnLinePayload]] = None


class CommissionRulePayload(BaseModel):
	name: str = Field(..., min_length=1, max_length=255)
	rule_type: str = "percent_of_sales"
	config: Dict[str, Any] = Field(default_factory=lambda: {"percent": 1})
	is_active: bool = True
	valid_from: Optional[str] = None
	valid_to: Optional[str] = None


class CommissionRunPayload(BaseModel):
	user_id: int = Field(..., gt=0)
	period_start: str
	period_end: Optional[str] = None
	rule_id: Optional[int] = Field(None, gt=0)


class ShelfAuditPayload(BaseModel):
	person_id: int = Field(..., gt=0)
	visit_id: Optional[int] = Field(None, gt=0)
	answers: Union[Dict[str, Any], List[Any]]
	photo_file_ids: Optional[List[int]] = None
	notes: Optional[str] = None


class CustomerAssetPayload(BaseModel):
	person_id: Optional[int] = Field(None, gt=0)
	asset_code: Optional[str] = Field(None, max_length=64)
	asset_type: Optional[str] = Field(None, max_length=64)
	name: Optional[str] = Field(None, max_length=255)
	status: Optional[str] = None
	placed_at: Optional[str] = None
	notes: Optional[str] = None
	check_now: Optional[bool] = None


class CustomerProfilePayload(BaseModel):
	customer_class: Optional[Literal["A", "B", "C"]] = None
	visit_frequency: Optional[Literal["weekly", "biweekly", "monthly"]] = None
	cycle_offset: Optional[int] = Field(None, ge=0, le=4)
	price_list_id: Optional[int] = Field(None, gt=0)
	outlet_type: Optional[str] = Field(None, max_length=32)
	assortment_id: Optional[int] = Field(None, gt=0)
	storefront_photo_file_id: Optional[int] = Field(None, gt=0)
	notes: Optional[str] = None


class AssortmentPayload(BaseModel):
	code: Optional[str] = Field(None, min_length=1, max_length=50)
	name: Optional[str] = Field(None, min_length=1, max_length=255)
	outlet_type: Optional[str] = Field(None, max_length=32)
	product_ids: Optional[List[int]] = None
	must_sell_product_ids: Optional[List[int]] = None
	is_active: Optional[bool] = None
	notes: Optional[str] = None


class SetupWizardPayload(BaseModel):
	enable_van_sales: bool = False
	enable_presell: bool = True
	enable_promotions: bool = True
	default_source_warehouse_id: Optional[int] = Field(None, gt=0)
	nav_provider: Optional[Literal["neshan", "google", "waze"]] = None
	territory_name: Optional[str] = None
	territory_code: Optional[str] = None
	route_name: Optional[str] = None
	route_code: Optional[str] = None
	route_id: Optional[int] = Field(None, gt=0)
	territory_id: Optional[int] = Field(None, gt=0)
	person_ids: Optional[List[int]] = None
	weekday: Optional[int] = Field(None, ge=0, le=6)
	frequency: Optional[Literal["weekly", "biweekly", "monthly"]] = None
	cycle_offset: Optional[int] = Field(None, ge=0, le=4)
	customer_class: Optional[Literal["A", "B", "C"]] = None
	visitor_user_id: Optional[int] = Field(None, gt=0)
	valid_from: Optional[str] = None


class NewOutletPayload(BaseModel):
	name: str = Field(..., min_length=1, max_length=255)
	mobile: Optional[str] = None
	phone: Optional[str] = None
	address: Optional[str] = None
	city: Optional[str] = None
	latitude: Optional[float] = None
	longitude: Optional[float] = None
	customer_class: Optional[Literal["A", "B", "C"]] = None
	frequency: Optional[Literal["weekly", "biweekly", "monthly"]] = None
	outlet_type: Optional[str] = None
	price_list_id: Optional[int] = Field(None, gt=0)
	assortment_id: Optional[int] = Field(None, gt=0)
	storefront_photo_file_id: Optional[int] = Field(None, gt=0)
	route_id: Optional[int] = Field(None, gt=0)
	weekday: Optional[int] = Field(None, ge=0, le=6)
	sort_order: Optional[int] = None
	notes: Optional[str] = None
