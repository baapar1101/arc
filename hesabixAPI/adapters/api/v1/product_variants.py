from typing import Any, Dict

from fastapi import APIRouter, Depends, Request
from sqlalchemy.orm import Session

from adapters.api.v1.schema_models.product_variant import (
    ProductVariantCreateRequest,
    ProductVariantUpdateRequest,
    VariantDimensionsReplaceRequest,
    VariantEnableInventoryRequest,
)
from adapters.db.models.product import Product
from adapters.db.session import get_db
from app.core.auth_dependency import AuthContext, get_current_user
from app.core.permissions import (
    require_business_access,
    require_business_permission_by_entity_dep,
    require_business_permission_dep,
)
from app.core.responses import ApiError, format_datetime_fields, success_response
from app.services.product_variant_service import (
    create_variant,
    deactivate_variant,
    list_dimensions,
    list_variant_balances,
    list_variants,
    replace_dimensions,
    resolve_barcode_token,
    update_variant,
)
from app.services.product_variant_enable_service import enable_inventory_variants

router = APIRouter(prefix="/products", tags=["تنوع کالا", "انبارداری"])


@router.get("/business/{business_id}/barcode-resolve")
@require_business_access("business_id")
def get_barcode_resolve(
    request: Request,
    business_id: int,
    token: str,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    _: None = Depends(require_business_permission_dep("products", "view")),
) -> Dict[str, Any]:
    data = format_datetime_fields(resolve_barcode_token(db, business_id, token), request)
    return success_response(data=data, request=request)


@router.put("/business/{business_id}/{product_id}/variant-dimensions")
@require_business_access("business_id")
def put_variant_dimensions(
    request: Request,
    business_id: int,
    product_id: int,
    payload: VariantDimensionsReplaceRequest,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    _: None = Depends(require_business_permission_by_entity_dep("products", "edit", Product, "product_id")),
) -> Dict[str, Any]:
    data = replace_dimensions(
        db,
        business_id,
        product_id,
        [item.model_dump() for item in payload.dimensions],
    )
    db.commit()
    return success_response(data=data, request=request, message="VARIANT_DIMENSIONS_UPDATED")


@router.get("/business/{business_id}/{product_id}/variant-dimensions")
@require_business_access("business_id")
def get_variant_dimensions(
    request: Request,
    business_id: int,
    product_id: int,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    _: None = Depends(require_business_permission_dep("products", "view")),
) -> Dict[str, Any]:
    rows = list_dimensions(db, business_id, product_id)
    data = [
        {
            "id": int(row.id),
            "attribute_id": int(row.attribute_id),
            "is_required": bool(row.is_required),
            "sort_order": int(row.sort_order or 0),
        }
        for row in rows
    ]
    return success_response(data=data, request=request)


@router.get("/business/{business_id}/{product_id}/variants")
@require_business_access("business_id")
def get_product_variants(
    request: Request,
    business_id: int,
    product_id: int,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    _: None = Depends(require_business_permission_dep("products", "view")),
) -> Dict[str, Any]:
    data = format_datetime_fields(list_variants(db, business_id, product_id), request)
    return success_response(data=data, request=request)


@router.get("/business/{business_id}/{product_id}/variant-balances")
@require_business_access("business_id")
def get_product_variant_balances(
    request: Request,
    business_id: int,
    product_id: int,
    warehouse_id: int | None = None,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    _: None = Depends(require_business_permission_dep("products", "view")),
) -> Dict[str, Any]:
    data = list_variant_balances(db, business_id, product_id, warehouse_id=warehouse_id)
    return success_response(data=data, request=request)


@router.post("/business/{business_id}/{product_id}/variants")
@require_business_access("business_id")
def post_product_variant(
    request: Request,
    business_id: int,
    product_id: int,
    payload: ProductVariantCreateRequest,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    _: None = Depends(require_business_permission_by_entity_dep("products", "edit", Product, "product_id")),
) -> Dict[str, Any]:
    data = create_variant(db, business_id, product_id, payload.model_dump())
    db.commit()
    return success_response(
        data=format_datetime_fields(data, request),
        request=request,
        message="VARIANT_CREATED",
    )


@router.put("/business/{business_id}/{product_id}/variants/{variant_id}")
@require_business_access("business_id")
def put_product_variant(
    request: Request,
    business_id: int,
    product_id: int,
    variant_id: int,
    payload: ProductVariantUpdateRequest,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    _: None = Depends(require_business_permission_by_entity_dep("products", "edit", Product, "product_id")),
) -> Dict[str, Any]:
    data = update_variant(db, business_id, product_id, variant_id, payload.model_dump(exclude_unset=True))
    db.commit()
    return success_response(
        data=format_datetime_fields(data, request),
        request=request,
        message="VARIANT_UPDATED",
    )


@router.post("/business/{business_id}/{product_id}/variants/{variant_id}/deactivate")
@require_business_access("business_id")
def post_deactivate_variant(
    request: Request,
    business_id: int,
    product_id: int,
    variant_id: int,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    _: None = Depends(require_business_permission_by_entity_dep("products", "edit", Product, "product_id")),
) -> Dict[str, Any]:
    data = deactivate_variant(db, business_id, product_id, variant_id)
    db.commit()
    return success_response(
        data=format_datetime_fields(data, request),
        request=request,
        message="VARIANT_DEACTIVATED",
    )


@router.post("/business/{business_id}/{product_id}/enable-inventory-variants")
@require_business_access("business_id")
def post_enable_inventory_variants(
    request: Request,
    business_id: int,
    product_id: int,
    payload: VariantEnableInventoryRequest,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    _: None = Depends(require_business_permission_by_entity_dep("products", "edit", Product, "product_id")),
) -> Dict[str, Any]:
    data = enable_inventory_variants(
        db,
        business_id,
        product_id,
        int(ctx.get_user_id()),
        payload.model_dump(),
    )
    db.commit()
    return success_response(data=data, request=request, message="VARIANT_INVENTORY_ENABLED")
