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


@router.get(
    "/business/{business_id}/barcode-resolve",
    summary="تطبیق بارکد کالا یا تنوع",
    description="token بارکد را به کالا یا ترکیب تنوع همین کسب‌وکار نگاشت می‌کند. ابزار MCP: resolve_product_barcode.",
)
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


@router.put(
    "/business/{business_id}/{product_id}/variant-dimensions",
    summary="جایگزینی ابعاد تنوع کالا",
    description="تعریف ویژگی‌های انباری کالا. پس از گردش موجودی تنوع‌دار جایگزینی رد می‌شود. ابزار MCP: replace_product_variant_dimensions.",
)
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


@router.get(
    "/business/{business_id}/{product_id}/variant-dimensions",
    summary="لیست ابعاد تنوع کالا",
    description="ویژگی‌های تنوع تعریف‌شده برای کالا. ابزار MCP: list_product_variant_dimensions.",
)
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


@router.get(
    "/business/{business_id}/{product_id}/variants",
    summary="لیست ترکیب‌های تنوع کالا",
    description="SKUهای تنوع کالا شامل قیمت و بارکد. ابزار MCP: list_product_variants.",
)
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


@router.get(
    "/business/{business_id}/{product_id}/variant-balances",
    summary="مانده موجودی تنوع کالا",
    description="مانده هر ترکیب تنوع، اختیاری فیلتر انبار. ابزار MCP: list_product_variant_balances.",
)
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


@router.post(
    "/business/{business_id}/{product_id}/variants",
    summary="ایجاد ترکیب تنوع کالا",
    description="ساخت SKU از مقادیر ویژگی. سقف تعداد ترکیب اعمال می‌شود. ابزار MCP: create_product_variant.",
)
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


@router.put(
    "/business/{business_id}/{product_id}/variants/{variant_id}",
    summary="ویرایش ترکیب تنوع کالا",
    description="به‌روزرسانی کد، بارکد، قیمت یا مقادیر ویژگی. ابزار MCP: update_product_variant.",
)
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


@router.post(
    "/business/{business_id}/{product_id}/variants/{variant_id}/deactivate",
    summary="غیرفعال‌سازی ترکیب تنوع",
    description="ترکیب از فروش/انبار جدید خارج می‌شود. ابزار MCP: deactivate_product_variant.",
)
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


@router.post(
    "/business/{business_id}/{product_id}/enable-inventory-variants",
    summary="فعال‌سازی تفکیک موجودی تنوع",
    description="تقسیم موجودی انبار به ترکیب‌ها و صدور حواله. تاریخچه posted بازنویسی نمی‌شود. ابزار MCP: enable_product_inventory_variants.",
)
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
