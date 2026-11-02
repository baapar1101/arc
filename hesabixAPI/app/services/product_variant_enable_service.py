"""Wizard فعال‌سازی تفکیک موجودی بدون بازنویسی تاریخچه posted."""

from __future__ import annotations

from datetime import date
from decimal import Decimal
from typing import Any, Dict, List

from sqlalchemy.orm import Session

from app.core.responses import ApiError
from app.services.product_variant_service import (
    VARIANT_MODE_INVENTORY,
    VARIANT_MODE_NONE,
    _assert_bulk_product,
    _load_product,
    list_dimensions,
    list_variants,
    resolve_variant,
)
from app.services.variant_allocation_service import validate_allocation_sum
from app.services.warehouse_service import get_physical_stock, post_warehouse_document


def enable_inventory_variants(
    db: Session,
    business_id: int,
    product_id: int,
    user_id: int,
    payload: Dict[str, Any],
) -> Dict[str, Any]:
    from app.services.warehouse_service import create_manual_warehouse_document

    product = _load_product(db, business_id, product_id)
    _assert_bulk_product(product)
    if not list_dimensions(db, business_id, product_id):
        raise ApiError(
            "VARIANT_DIMENSION_REQUIRED",
            "ابتدا ویژگی‌های اثرگذار بر موجودی این کالا را انتخاب کنید",
            http_status=422,
        )
    variants = list_variants(db, business_id, product_id)
    if not variants:
        raise ApiError("VARIANT_REQUIRED", "حداقل یک ترکیب واقعی باید ساخته شود", http_status=422)

    try:
        warehouse_id = int(payload.get("warehouse_id"))
    except (TypeError, ValueError):
        raise ApiError("WAREHOUSE_REQUIRED", "انبار برای تخصیص موجودی الزامی است", http_status=422)
    splits: List[Dict[str, Any]] = list(payload.get("splits") or [])
    physical = get_physical_stock(db, business_id, int(product_id), warehouse_id)
    physical = Decimal(str(physical or 0))

    current_mode = str(getattr(product, "variant_mode", None) or VARIANT_MODE_NONE)
    if current_mode == VARIANT_MODE_INVENTORY and physical == 0 and not splits:
        return {"product_id": int(product.id), "variant_mode": VARIANT_MODE_INVENTORY, "allocated": "0"}

    if physical < 0:
        raise ApiError(
            "VARIANT_NEGATIVE_STOCK",
            "تا اصلاح مانده منفی کالا، تفکیک موجودی ممکن نیست",
            http_status=409,
        )

    items = []
    for split in splits:
        variant_id = int(split.get("variant_id"))
        qty = Decimal(str(split.get("quantity") or 0))
        resolve_variant(db, business_id, int(product_id), variant_id, require_active=True)
        items.append({"variant_id": variant_id, "quantity": qty})
    if physical == 0:
        if items:
            raise ApiError(
                "VARIANT_ALLOCATION_MISMATCH",
                "برای کالای بدون مانده نیازی به تخصیص مقدار نیست",
                http_status=422,
            )
        product.variant_mode = VARIANT_MODE_INVENTORY
        db.flush()
        return {"product_id": int(product.id), "variant_mode": VARIANT_MODE_INVENTORY, "allocated": "0"}

    if not items:
        raise ApiError(
            "VARIANT_REQUIRED",
            "برای مانده فعلی باید تخصیص ترکیب‌ها مشخص شود",
            http_status=422,
        )
    validate_allocation_sum(
        physical,
        [(int(x["variant_id"]), Decimal(str(x["quantity"])), None) for x in items],
    )

    product.variant_mode = VARIANT_MODE_INVENTORY
    db.flush()

    from app.core.business_calendar import business_today
    from app.services.inventory_lot_service import is_expiry_tracked_product, suggest_fefo
    from app.services.inventory_lot_allocation_service import slice_lots_across_quantities

    today = business_today(business_id)
    document_date = payload.get("document_date") or today.isoformat()
    out_line: Dict[str, Any] = {
        "product_id": int(product_id),
        "warehouse_id": warehouse_id,
        "quantity": str(physical),
        "movement": "out",
    }
    in_lines: List[Dict[str, Any]] = [
        {
            "product_id": int(product_id),
            "warehouse_id": warehouse_id,
            "quantity": str(physical),
            "movement": "in",
            "allocations": [
                {"variant_id": int(x["variant_id"]), "quantity": str(x["quantity"])}
                for x in items
            ],
        }
    ]
    if is_expiry_tracked_product(product):
        as_of = date.fromisoformat(str(document_date)[:10]) if document_date else today
        picked = suggest_fefo(
            db,
            business_id,
            product,
            warehouse_id,
            physical,
            as_of,
            allow_unsellable=True,
        )
        out_allocs = [{"lot_id": int(lot.id), "quantity": str(qty)} for lot, qty in picked]
        out_line["lot_allocations"] = out_allocs
        out_line["extra_info"] = {
            "lot_allocations": out_allocs,
            "allow_expired_lot_sale": True,
        }
        sliced = slice_lots_across_quantities(
            picked,
            [(int(x["variant_id"]), Decimal(str(x["quantity"]))) for x in items],
        )
        in_lines = []
        for vid, allocs in sliced:
            qty = sum((Decimal(str(a.get("quantity") or 0)) for a in allocs), Decimal("0"))
            in_lines.append(
                {
                    "product_id": int(product_id),
                    "warehouse_id": warehouse_id,
                    "quantity": str(qty),
                    "movement": "in",
                    "variant_id": vid,
                    "allocations": [{"variant_id": vid, "quantity": str(qty)}],
                    "lot_allocations": allocs,
                    "extra_info": {
                        "lot_allocations": allocs,
                        "variant_id": vid,
                        "allow_undated": True,
                        "allocations": [{"variant_id": vid, "quantity": str(qty)}],
                    },
                }
            )
    doc_payload = {
        "doc_type": "adjustment",
        "document_date": document_date,
        "warehouse_id_from": warehouse_id,
        "warehouse_id_to": warehouse_id,
        "extra_info": {
            "system_origin": "variant_allocation",
            "product_id": int(product_id),
        },
        "lines": [out_line, *in_lines],
    }
    wh = create_manual_warehouse_document(db, business_id, user_id, doc_payload)
    post_warehouse_document(db, int(wh.id))
    return {
        "product_id": int(product.id),
        "variant_mode": VARIANT_MODE_INVENTORY,
        "warehouse_document_id": int(wh.id),
        "allocated": str(physical),
    }
