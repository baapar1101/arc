# Removed __future__ annotations to fix OpenAPI schema generation

from typing import Dict, Any
from fastapi import APIRouter, Depends, Request
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.permissions import require_business_access
from app.core.responses import success_response, ApiError, format_datetime_fields
from adapters.api.v1.schemas import QueryInfo
from adapters.api.v1.schema_models.price_list import (
    PriceListCreateRequest,
    PriceListUpdateRequest,
    PriceItemUpsertRequest,
)
from app.services.price_list_service import (
    create_price_list,
    list_price_lists,
    get_price_list,
    update_price_list,
    delete_price_list,
    list_price_items,
    upsert_price_item,
    delete_price_item,
)


router = APIRouter(prefix="/price-lists", tags=["price-lists"])


@router.post("/business/{business_id}")
@require_business_access("business_id")
def create_price_list_endpoint(
    request: Request,
    business_id: int,
    payload: PriceListCreateRequest,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    if not ctx.has_business_permission("inventory", "write"):
        raise ApiError("FORBIDDEN", "Missing business permission: inventory.write", http_status=403)
    result = create_price_list(db, business_id, payload)
    return success_response(data=format_datetime_fields(result["data"], request), request=request, message=result.get("message"))


@router.post("/business/{business_id}/search")
@require_business_access("business_id")
def search_price_lists_endpoint(
    request: Request,
    business_id: int,
    query: QueryInfo,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    if not ctx.can_read_section("inventory"):
        raise ApiError("FORBIDDEN", "Missing business permission: inventory.read", http_status=403)
    result = list_price_lists(db, business_id, {
        "take": query.take,
        "skip": query.skip,
        "sort_by": query.sort_by,
        "sort_desc": query.sort_desc,
        "search": query.search,
    })
    return success_response(data=format_datetime_fields(result, request), request=request)


@router.get("/business/{business_id}/{price_list_id}")
@require_business_access("business_id")
def get_price_list_endpoint(
    request: Request,
    business_id: int,
    price_list_id: int,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    if not ctx.can_read_section("inventory"):
        raise ApiError("FORBIDDEN", "Missing business permission: inventory.read", http_status=403)
    item = get_price_list(db, business_id, price_list_id)
    if not item:
        raise ApiError("NOT_FOUND", "Price list not found", http_status=404)
    return success_response(data=format_datetime_fields({"item": item}, request), request=request)


@router.put("/business/{business_id}/{price_list_id}")
@require_business_access("business_id")
def update_price_list_endpoint(
    request: Request,
    business_id: int,
    price_list_id: int,
    payload: PriceListUpdateRequest,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    if not ctx.has_business_permission("inventory", "write"):
        raise ApiError("FORBIDDEN", "Missing business permission: inventory.write", http_status=403)
    result = update_price_list(db, business_id, price_list_id, payload)
    if not result:
        raise ApiError("NOT_FOUND", "Price list not found", http_status=404)
    return success_response(data=format_datetime_fields(result["data"], request), request=request, message=result.get("message"))


@router.delete("/business/{business_id}/{price_list_id}")
@require_business_access("business_id")
def delete_price_list_endpoint(
    request: Request,
    business_id: int,
    price_list_id: int,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    if not ctx.has_business_permission("inventory", "delete"):
        raise ApiError("FORBIDDEN", "Missing business permission: inventory.delete", http_status=403)
    ok = delete_price_list(db, business_id, price_list_id)
    return success_response({"deleted": ok}, request)


@router.post("/business/{business_id}/{price_list_id}/items")
@require_business_access("business_id")
def upsert_price_item_endpoint(
    request: Request,
    business_id: int,
    price_list_id: int,
    payload: PriceItemUpsertRequest,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    if not ctx.has_business_permission("inventory", "write"):
        raise ApiError("FORBIDDEN", "Missing business permission: inventory.write", http_status=403)
    result = upsert_price_item(db, business_id, price_list_id, payload)
    return success_response(data=format_datetime_fields(result["data"], request), request=request, message=result.get("message"))


@router.get("/business/{business_id}/{price_list_id}/items")
@require_business_access("business_id")
def list_price_items_endpoint(
    request: Request,
    business_id: int,
    price_list_id: int,
    product_id: int | None = None,
    currency_id: int | None = None,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    if not ctx.can_read_section("inventory"):
        raise ApiError("FORBIDDEN", "Missing business permission: inventory.read", http_status=403)
    result = list_price_items(db, business_id, price_list_id, product_id=product_id, currency_id=currency_id)
    return success_response(data=format_datetime_fields(result, request), request=request)


@router.delete("/business/{business_id}/items/{item_id}")
@require_business_access("business_id")
def delete_price_item_endpoint(
    request: Request,
    business_id: int,
    item_id: int,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    if not ctx.has_business_permission("inventory", "delete"):
        raise ApiError("FORBIDDEN", "Missing business permission: inventory.delete", http_status=403)
    ok = delete_price_item(db, business_id, item_id)
    return success_response({"deleted": ok}, request)


