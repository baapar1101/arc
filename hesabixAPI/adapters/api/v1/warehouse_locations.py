from typing import Dict, Any, Optional

from fastapi import APIRouter, Depends, Request, Body, Query
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from adapters.db.models.warehouse import Warehouse
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.permissions import require_business_access, require_business_permission_by_entity_dep
from app.core.responses import success_response, ApiError, format_datetime_fields
from adapters.api.v1.schema_models.warehouse_location import (
	WarehouseLocationCreateRequest,
	WarehouseLocationUpdateRequest,
	WarehousePlacementCreateRequest,
	WarehousePlacementUpdateRequest,
)
from app.services.warehouse_location_service import (
	list_locations_tree,
	create_location,
	update_location,
	delete_location,
	list_placements,
	create_placement,
	update_placement,
	delete_placement,
)
from app.services.warehouse_placement_sync import placement_reconciliation_for_warehouse


router = APIRouter(prefix="/warehouses", tags=["چیدمان انبار"])


@router.get("/business/{business_id}/{warehouse_id}/locations")
@require_business_access("business_id")
def list_locations_endpoint(
	request: Request,
	business_id: int,
	warehouse_id: int,
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
	_: None = Depends(require_business_permission_by_entity_dep("warehouses", "view", Warehouse, "warehouse_id")),
) -> Dict[str, Any]:
	data = list_locations_tree(db, business_id, warehouse_id)
	return success_response(data=data, request=request)


@router.post("/business/{business_id}/{warehouse_id}/locations")
@require_business_access("business_id")
def create_location_endpoint(
	request: Request,
	business_id: int,
	warehouse_id: int,
	payload: WarehouseLocationCreateRequest = Body(...),
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
	_: None = Depends(require_business_permission_by_entity_dep("warehouses", "add", Warehouse, "warehouse_id")),
) -> Dict[str, Any]:
	result = create_location(db, business_id, warehouse_id, payload.model_dump(exclude_unset=True))
	return success_response(data=format_datetime_fields(result, request), request=request)


@router.put("/business/{business_id}/{warehouse_id}/locations/{location_id}")
@require_business_access("business_id")
def update_location_endpoint(
	request: Request,
	business_id: int,
	warehouse_id: int,
	location_id: int,
	payload: WarehouseLocationUpdateRequest = Body(...),
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
	_: None = Depends(require_business_permission_by_entity_dep("warehouses", "edit", Warehouse, "warehouse_id")),
) -> Dict[str, Any]:
	result = update_location(db, business_id, warehouse_id, location_id, payload.model_dump(exclude_unset=True))
	if not result:
		raise ApiError("NOT_FOUND", "محل یافت نشد", http_status=404)
	return success_response(data=format_datetime_fields(result, request), request=request)


@router.delete("/business/{business_id}/{warehouse_id}/locations/{location_id}")
@require_business_access("business_id")
def delete_location_endpoint(
	request: Request,
	business_id: int,
	warehouse_id: int,
	location_id: int,
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
	_: None = Depends(require_business_permission_by_entity_dep("warehouses", "delete", Warehouse, "warehouse_id")),
) -> Dict[str, Any]:
	ok = delete_location(db, business_id, warehouse_id, location_id)
	return success_response({"deleted": ok}, request=request)


@router.get("/business/{business_id}/{warehouse_id}/placement-reconciliation")
@require_business_access("business_id")
def placement_reconciliation_endpoint(
	request: Request,
	business_id: int,
	warehouse_id: int,
	as_of_date: Optional[str] = Query(None),
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
	_: None = Depends(require_business_permission_by_entity_dep("warehouses", "view", Warehouse, "warehouse_id")),
) -> Dict[str, Any]:
	"""مجموع قرارگیری‌های ثبت‌شده در مقابل موجودی حسابداری (کالاهایی که حداقل یک رکورد قرارگیری دارند)."""
	data = placement_reconciliation_for_warehouse(
		db, business_id, warehouse_id, as_of_date=as_of_date
	)
	return success_response(data=data, request=request)


@router.get("/business/{business_id}/{warehouse_id}/placements")
@require_business_access("business_id")
def list_placements_endpoint(
	request: Request,
	business_id: int,
	warehouse_id: int,
	product_id: Optional[int] = Query(None),
	location_id: Optional[int] = Query(None),
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
	_: None = Depends(require_business_permission_by_entity_dep("warehouses", "view", Warehouse, "warehouse_id")),
) -> Dict[str, Any]:
	data = list_placements(db, business_id, warehouse_id, product_id=product_id, location_id=location_id)
	return success_response(data=data, request=request)


@router.post("/business/{business_id}/{warehouse_id}/placements")
@require_business_access("business_id")
def create_placement_endpoint(
	request: Request,
	business_id: int,
	warehouse_id: int,
	payload: WarehousePlacementCreateRequest = Body(...),
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
	_: None = Depends(require_business_permission_by_entity_dep("warehouses", "edit", Warehouse, "warehouse_id")),
) -> Dict[str, Any]:
	result = create_placement(db, business_id, warehouse_id, payload.model_dump(exclude_unset=True))
	return success_response(data=format_datetime_fields(result, request), request=request)


@router.put("/business/{business_id}/{warehouse_id}/placements/{placement_id}")
@require_business_access("business_id")
def update_placement_endpoint(
	request: Request,
	business_id: int,
	warehouse_id: int,
	placement_id: int,
	payload: WarehousePlacementUpdateRequest = Body(...),
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
	_: None = Depends(require_business_permission_by_entity_dep("warehouses", "edit", Warehouse, "warehouse_id")),
) -> Dict[str, Any]:
	result = update_placement(db, business_id, warehouse_id, placement_id, payload.model_dump(exclude_unset=True))
	if not result:
		raise ApiError("NOT_FOUND", "رکورد قرارگیری یافت نشد", http_status=404)
	return success_response(data=format_datetime_fields(result, request), request=request)


@router.delete("/business/{business_id}/{warehouse_id}/placements/{placement_id}")
@require_business_access("business_id")
def delete_placement_endpoint(
	request: Request,
	business_id: int,
	warehouse_id: int,
	placement_id: int,
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
	_: None = Depends(require_business_permission_by_entity_dep("warehouses", "edit", Warehouse, "warehouse_id")),
) -> Dict[str, Any]:
	ok = delete_placement(db, business_id, warehouse_id, placement_id)
	return success_response({"deleted": ok}, request=request)
