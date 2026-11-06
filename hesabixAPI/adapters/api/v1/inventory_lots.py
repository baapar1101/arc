from datetime import date
from typing import Any, Dict, Optional

from fastapi import APIRouter, Depends, Query, Request
from sqlalchemy.orm import Session

from adapters.db.models.product import Product
from adapters.db.session import get_db
from app.core.auth_dependency import AuthContext, get_current_user
from app.core.permissions import require_business_access
from app.core.responses import ApiError, success_response
from app.services.inventory_lot_service import compute_lot_dates, list_lot_balances

router = APIRouter(prefix="/inventory-lots", tags=["inventory_lots"])


@router.get(
    "/business/{business_id}/products/{product_id}",
    summary="موجودی لات‌های کالا",
    description="مانده لات‌های تاریخ‌دار یک کالا در کسب‌وکار متصل با فیلتر انبار/تنوع و as_of_date. نیازمند inventory.read. ابزار MCP: `list_inventory_lots`.",
)
@require_business_access("business_id")
def list_product_lots(
    request: Request,
    business_id: int,
    product_id: int,
    warehouse_id: Optional[int] = Query(default=None),
    variant_id: Optional[int] = Query(default=None),
    sellable_only: bool = Query(default=False),
    as_of_date: Optional[str] = Query(default=None),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    if not ctx.can_read_section("inventory"):
        raise ApiError("FORBIDDEN", "Missing business permission: inventory.read", http_status=403)
    from app.services.inventory_lot_service import business_as_of

    explicit = None
    if as_of_date:
        try:
            explicit = date.fromisoformat(as_of_date[:10])
        except ValueError:
            raise ApiError("INVALID_DATE", "تاریخ نامعتبر است", http_status=400)
    as_of = business_as_of(business_id, explicit)
    items = list_lot_balances(
        db,
        business_id,
        product_id,
        warehouse_id,
        as_of,
        sellable_only=sellable_only,
        variant_id=variant_id,
    )
    return success_response(data={"items": items, "as_of_date": as_of.isoformat()}, request=request)


@router.get(
    "/business/{business_id}/products/{product_id}/preview-dates",
    summary="پیش‌نمایش تاریخ لات",
    description="تاریخ تولید و انقضا را بر اساس تنظیمات کالا محاسبه می‌کند و چیزی ثبت نمی‌کند. ابزار MCP: `preview_inventory_lot_dates`.",
)
@require_business_access("business_id")
def preview_lot_dates(
    request: Request,
    business_id: int,
    product_id: int,
    manufacturing_date: Optional[str] = Query(default=None),
    expiry_date: Optional[str] = Query(default=None),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    if not ctx.can_read_section("products"):
        raise ApiError("FORBIDDEN", "Missing business permission: products.read", http_status=403)
    product = (
        db.query(Product)
        .filter(Product.id == int(product_id), Product.business_id == int(business_id))
        .first()
    )
    if product is None:
        raise ApiError("NOT_FOUND", "کالا یافت نشد", http_status=404)
    from app.services.inventory_lot_service import _as_date

    dates = compute_lot_dates(
        product,
        manufacturing_date=_as_date(manufacturing_date),
        expiry_date=_as_date(expiry_date),
    )
    return success_response(
        data={k: (v.isoformat() if v else None) for k, v in dates.items()},
        request=request,
    )
