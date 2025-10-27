from __future__ import annotations

from typing import Dict, Any
from fastapi import APIRouter, Depends, Request
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.permissions import require_business_access
from app.core.responses import success_response, ApiError, format_datetime_fields
from adapters.api.v1.schema_models.warehouse import (
    WarehouseCreateRequest,
    WarehouseUpdateRequest,
)
from app.services.warehouse_service import (
    create_warehouse,
    list_warehouses,
    get_warehouse,
    update_warehouse,
    delete_warehouse,
)


router = APIRouter(prefix="/warehouses", tags=["warehouses"])


@router.post("/business/{business_id}")
@require_business_access("business_id")
def create_warehouse_endpoint(
    request: Request,
    business_id: int,
    payload: WarehouseCreateRequest,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    if not ctx.has_business_permission("inventory", "write"):
        raise ApiError("FORBIDDEN", "Missing business permission: inventory.write", http_status=403)
    result = create_warehouse(db, business_id, payload)
    return success_response(data=format_datetime_fields(result["data"], request), request=request, message=result.get("message"))


@router.get("/business/{business_id}")
@require_business_access("business_id")
def list_warehouses_endpoint(
    request: Request,
    business_id: int,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    if not ctx.can_read_section("inventory"):
        raise ApiError("FORBIDDEN", "Missing business permission: inventory.read", http_status=403)
    result = list_warehouses(db, business_id)
    return success_response(data=format_datetime_fields(result, request), request=request)


@router.get("/business/{business_id}/{warehouse_id}")
@require_business_access("business_id")
def get_warehouse_endpoint(
    request: Request,
    business_id: int,
    warehouse_id: int,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    if not ctx.can_read_section("inventory"):
        raise ApiError("FORBIDDEN", "Missing business permission: inventory.read", http_status=403)
    item = get_warehouse(db, business_id, warehouse_id)
    if not item:
        raise ApiError("NOT_FOUND", "Warehouse not found", http_status=404)
    return success_response(data=format_datetime_fields({"item": item}, request), request=request)


@router.put("/business/{business_id}/{warehouse_id}")
@require_business_access("business_id")
def update_warehouse_endpoint(
    request: Request,
    business_id: int,
    warehouse_id: int,
    payload: WarehouseUpdateRequest,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    if not ctx.has_business_permission("inventory", "write"):
        raise ApiError("FORBIDDEN", "Missing business permission: inventory.write", http_status=403)
    result = update_warehouse(db, business_id, warehouse_id, payload)
    if not result:
        raise ApiError("NOT_FOUND", "Warehouse not found", http_status=404)
    return success_response(data=format_datetime_fields(result["data"], request), request=request, message=result.get("message"))


@router.delete("/business/{business_id}/{warehouse_id}")
@require_business_access("business_id")
def delete_warehouse_endpoint(
    request: Request,
    business_id: int,
    warehouse_id: int,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    if not ctx.has_business_permission("inventory", "delete"):
        raise ApiError("FORBIDDEN", "Missing business permission: inventory.delete", http_status=403)
    ok = delete_warehouse(db, business_id, warehouse_id)
    return success_response({"deleted": ok}, request)


