from typing import Dict, Any, Optional
from fastapi import APIRouter, Depends, Request, Query
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.permissions import require_business_access
from app.core.responses import success_response, ApiError, format_datetime_fields
from adapters.api.v1.schema_models.product_bom import (
    ProductBOMCreateRequest,
    ProductBOMUpdateRequest,
    BOMExplosionRequest,
    ProductionDraftRequest,
)
from app.services.bom_service import (
    create_bom,
    get_bom,
    list_boms,
    update_bom,
    delete_bom,
    explode_bom,
    produce_draft,
)


router = APIRouter(prefix="/boms", tags=["boms"])


@router.post("/business/{business_id}")
@require_business_access("business_id")
def create_bom_endpoint(
    request: Request,
    business_id: int,
    payload: ProductBOMCreateRequest,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    if not ctx.has_business_permission("inventory", "write"):
        raise ApiError("FORBIDDEN", "Missing business permission: inventory.write", http_status=403)
    result = create_bom(db, business_id, payload)
    return success_response(data=format_datetime_fields(result["data"], request), request=request, message=result.get("message"))


@router.get("/business/{business_id}")
@require_business_access("business_id")
def list_boms_endpoint(
    request: Request,
    business_id: int,
    product_id: int | None = Query(default=None),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    if not ctx.can_read_section("inventory"):
        raise ApiError("FORBIDDEN", "Missing business permission: inventory.read", http_status=403)
    result = list_boms(db, business_id, product_id)
    return success_response(data=format_datetime_fields(result, request), request=request)


@router.get("/business/{business_id}/{bom_id}")
@require_business_access("business_id")
def get_bom_endpoint(
    request: Request,
    business_id: int,
    bom_id: int,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    if not ctx.can_read_section("inventory"):
        raise ApiError("FORBIDDEN", "Missing business permission: inventory.read", http_status=403)
    item = get_bom(db, business_id, bom_id)
    if not item:
        raise ApiError("NOT_FOUND", "BOM not found", http_status=404)
    return success_response(data=format_datetime_fields({"item": item}, request), request=request)


@router.put("/business/{business_id}/{bom_id}")
@require_business_access("business_id")
def update_bom_endpoint(
    request: Request,
    business_id: int,
    bom_id: int,
    payload: ProductBOMUpdateRequest,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    if not ctx.has_business_permission("inventory", "write"):
        raise ApiError("FORBIDDEN", "Missing business permission: inventory.write", http_status=403)
    result = update_bom(db, business_id, bom_id, payload)
    if not result:
        raise ApiError("NOT_FOUND", "BOM not found", http_status=404)
    return success_response(data=format_datetime_fields(result["data"], request), request=request, message=result.get("message"))


@router.delete("/business/{business_id}/{bom_id}")
@require_business_access("business_id")
def delete_bom_endpoint(
    request: Request,
    business_id: int,
    bom_id: int,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    if not ctx.has_business_permission("inventory", "delete"):
        raise ApiError("FORBIDDEN", "Missing business permission: inventory.delete", http_status=403)
    ok = delete_bom(db, business_id, bom_id)
    return success_response({"deleted": ok}, request)


@router.post("/business/{business_id}/explode")
@require_business_access("business_id")
def explode_bom_endpoint(
    request: Request,
    business_id: int,
    payload: BOMExplosionRequest,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    if not ctx.can_read_section("inventory"):
        raise ApiError("FORBIDDEN", "Missing business permission: inventory.read", http_status=403)
    result = explode_bom(db, business_id, payload)
    return success_response(data=format_datetime_fields(result, request), request=request)


@router.post("/business/{business_id}/produce_draft")
@require_business_access("business_id")
def produce_draft_endpoint(
    request: Request,
    business_id: int,
    payload: ProductionDraftRequest,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    if not ctx.has_business_permission("inventory", "write"):
        raise ApiError("FORBIDDEN", "Missing business permission: inventory.write", http_status=403)
    result = produce_draft(db, business_id, payload)
    return success_response(data=format_datetime_fields(result, request), request=request)
