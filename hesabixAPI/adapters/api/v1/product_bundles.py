from __future__ import annotations

from typing import Annotated, Any

from fastapi import APIRouter, Depends, Request
from sqlalchemy.orm import Session

from adapters.api.v1.schema_models.product_bundle import (
    ProductBundleCreateRequest,
    ProductBundleExpandRequest,
    ProductBundleUpdateRequest,
)
from adapters.api.v1.schemas import QueryInfo
from adapters.db.session import get_db
from app.core.auth_dependency import AuthContext, get_current_user
from app.core.permissions import require_business_access, require_business_permission_dep
from app.core.responses import ApiError, format_datetime_fields, success_response
from app.services.product_bundle_service import (
    create_bundle,
    delete_bundle,
    expand_bundle,
    get_bundle,
    search_bundles,
    update_bundle,
)

router = APIRouter(prefix="/product-bundles", tags=["product-bundles"])


@router.post("/business/{business_id}/search")
@require_business_access("business_id")
def search_product_bundles(
    request: Request,
    business_id: int,
    query: QueryInfo,
    ctx: Annotated[AuthContext, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
    _: Annotated[None, Depends(require_business_permission_dep("products", "view"))],
) -> dict[str, Any]:
    result = search_bundles(
        db,
        business_id,
        {
            "take": query.take,
            "skip": query.skip,
            "sort_by": query.sort_by,
            "sort_desc": query.sort_desc,
            "search": query.search,
            "filters": [item.model_dump() for item in query.filters] if query.filters else None,
        },
    )
    return success_response(format_datetime_fields(result, request), request)


@router.post("/business/{business_id}")
@require_business_access("business_id")
def create_product_bundle(
    request: Request,
    business_id: int,
    payload: ProductBundleCreateRequest,
    ctx: Annotated[AuthContext, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
    _: Annotated[None, Depends(require_business_permission_dep("products", "add"))],
) -> dict[str, Any]:
    result = create_bundle(db, business_id, payload)
    return success_response(
        format_datetime_fields(result, request), request, message="BUNDLE_CREATED"
    )


@router.get("/business/{business_id}/{bundle_id}")
@require_business_access("business_id")
def get_product_bundle(
    request: Request,
    business_id: int,
    bundle_id: int,
    ctx: Annotated[AuthContext, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
    _: Annotated[None, Depends(require_business_permission_dep("products", "view"))],
) -> dict[str, Any]:
    result = get_bundle(db, business_id, bundle_id)
    if result is None:
        raise ApiError("BUNDLE_NOT_FOUND", "باندل یافت نشد.", http_status=404)
    return success_response(format_datetime_fields(result, request), request)


@router.put("/business/{business_id}/{bundle_id}")
@require_business_access("business_id")
def update_product_bundle(
    request: Request,
    business_id: int,
    bundle_id: int,
    payload: ProductBundleUpdateRequest,
    ctx: Annotated[AuthContext, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
    _: Annotated[None, Depends(require_business_permission_dep("products", "edit"))],
) -> dict[str, Any]:
    result = update_bundle(db, business_id, bundle_id, payload)
    if result is None:
        raise ApiError("BUNDLE_NOT_FOUND", "باندل یافت نشد.", http_status=404)
    return success_response(
        format_datetime_fields(result, request), request, message="BUNDLE_UPDATED"
    )


@router.delete("/business/{business_id}/{bundle_id}")
@require_business_access("business_id")
def delete_product_bundle(
    request: Request,
    business_id: int,
    bundle_id: int,
    ctx: Annotated[AuthContext, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
    _: Annotated[None, Depends(require_business_permission_dep("products", "delete"))],
) -> dict[str, Any]:
    deleted = delete_bundle(db, business_id, bundle_id)
    if not deleted:
        raise ApiError("BUNDLE_NOT_FOUND", "باندل یافت نشد.", http_status=404)
    return success_response({"deleted": True, "id": bundle_id}, request, message="BUNDLE_DELETED")


@router.post("/business/{business_id}/{bundle_id}/expand")
@require_business_access("business_id")
def expand_product_bundle(
    request: Request,
    business_id: int,
    bundle_id: int,
    payload: ProductBundleExpandRequest,
    ctx: Annotated[AuthContext, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
    _: Annotated[None, Depends(require_business_permission_dep("products", "view"))],
) -> dict[str, Any]:
    result = expand_bundle(db, business_id, bundle_id, payload.quantity)
    return success_response(format_datetime_fields(result, request), request)
