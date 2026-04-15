from typing import Any, Dict

from fastapi import APIRouter, Depends, Request
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.permissions import require_business_access, require_business_permission_dep, require_business_permission_by_entity_dep
from app.core.responses import success_response, ApiError, format_datetime_fields
from adapters.api.v1.schemas import QueryInfo
from adapters.api.v1.schema_models.product_attribute import (
    ProductAttributeCreateRequest,
    ProductAttributeUpdateRequest,
)
from app.services.product_attribute_service import (
    create_attribute,
    list_attributes,
    get_attribute,
    update_attribute,
    delete_attribute,
)
from adapters.db.models.product_attribute import ProductAttribute


router = APIRouter(prefix="/product-attributes", tags=["product-attributes"])


@router.post("/business/{business_id}")
@require_business_access("business_id")
def create_product_attribute(
    request: Request,
    business_id: int,
    payload: ProductAttributeCreateRequest,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    _: None = Depends(require_business_permission_dep("product_attributes", "add")),
) -> Dict[str, Any]:
    result = create_attribute(db, business_id, payload)
    return success_response(
        data=format_datetime_fields(result["data"], request),
        request=request,
        message=result.get("message"),
    )


@router.post("/business/{business_id}/search")
@require_business_access("business_id")
def search_product_attributes(
    request: Request,
    business_id: int,
    query: QueryInfo,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    _: None = Depends(require_business_permission_dep("product_attributes", "view")),
) -> Dict[str, Any]:

    result = list_attributes(db, business_id, {
        "take": query.take,
        "skip": query.skip,
        "sort_by": query.sort_by,
        "sort_desc": query.sort_desc,
        "sort": [s.model_dump() for s in query.sort] if query.sort else None,
        "search": query.search,
        "filters": query.filters,
    })
    # Format all datetime fields in items/pagination
    formatted = format_datetime_fields(result, request)
    return success_response(data=formatted, request=request)


@router.get("/business/{business_id}/{attribute_id}")
@require_business_access("business_id")
def get_product_attribute(
    request: Request,
    business_id: int,
    attribute_id: int,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    _: None = Depends(require_business_permission_by_entity_dep("product_attributes", "view", ProductAttribute, "attribute_id")),
) -> Dict[str, Any]:
    item = get_attribute(db, attribute_id, business_id)
    if not item:
        raise ApiError("NOT_FOUND", "Attribute not found", http_status=404)
    return success_response(data=format_datetime_fields({"item": item}, request), request=request)


@router.put("/business/{business_id}/{attribute_id}")
@require_business_access("business_id")
def update_product_attribute(
    request: Request,
    business_id: int,
    attribute_id: int,
    payload: ProductAttributeUpdateRequest,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    _: None = Depends(require_business_permission_by_entity_dep("product_attributes", "edit", ProductAttribute, "attribute_id")),
) -> Dict[str, Any]:
    result = update_attribute(db, attribute_id, business_id, payload)
    if not result:
        raise ApiError("NOT_FOUND", "Attribute not found", http_status=404)
    return success_response(
        data=format_datetime_fields(result["data"], request),
        request=request,
        message=result.get("message"),
    )


@router.delete("/business/{business_id}/{attribute_id}")
@require_business_access("business_id")
def delete_product_attribute(
    request: Request,
    business_id: int,
    attribute_id: int,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    _: None = Depends(require_business_permission_by_entity_dep("product_attributes", "delete", ProductAttribute, "attribute_id")),
) -> Dict[str, Any]:
    ok = delete_attribute(db, attribute_id, business_id)
    return success_response({"deleted": ok}, request)


