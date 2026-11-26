"""Wizard فعال‌سازی تفکیک موجودی بدون بازنویسی تاریخچه posted."""

from __future__ import annotations

from datetime import date
from decimal import Decimal, InvalidOperation
from typing import Any

from sqlalchemy import case, func
from sqlalchemy.orm import Session, selectinload

from adapters.db.models.product_variant_allocation import WarehouseLineVariantAllocation
from adapters.db.models.warehouse import Warehouse
from adapters.db.models.warehouse_document import WarehouseDocument
from adapters.db.models.warehouse_document_line import WarehouseDocumentLine
from app.core.business_calendar import business_today
from app.core.responses import ApiError
from app.core.transaction_lock import acquire_transaction_lock
from app.services.inventory_lot_allocation_service import slice_lots_across_quantities
from app.services.inventory_lot_service import is_expiry_tracked_product, suggest_fefo
from app.services.product_variant_service import (
    VARIANT_MODE_INVENTORY,
    _assert_bulk_product,
    _load_product,
    list_dimensions,
    list_variants,
    resolve_variant,
)
from app.services.variant_allocation_service import validate_allocation_sum
from app.services.warehouse_service import (
    counts_toward_physical_stock,
    get_physical_stock,
    post_warehouse_document,
)


def _prior_conversion(
    db: Session, business_id: int, product_id: int, warehouse_id: int
) -> tuple[int, Decimal] | None:
    candidates = (
        db.query(WarehouseDocument)
        .options(selectinload(WarehouseDocument.lines))
        .filter_by(
            business_id=business_id,
            doc_type="adjustment",
            source_type="manual",
            source_document_id=None,
            warehouse_id_from=warehouse_id,
            warehouse_id_to=warehouse_id,
        )
        .filter(
            WarehouseDocument.status.in_(("posted", "cancelled")),
            WarehouseDocument.extra_info["system_origin"].as_string() == "variant_allocation",
            WarehouseDocument.extra_info["product_id"].as_string() == str(product_id),
        )
        .order_by(WarehouseDocument.id)
        .all()
    )
    if not candidates:
        return None

    allocation = WarehouseLineVariantAllocation
    allocated = dict(
        db.query(allocation.warehouse_document_line_id, func.sum(allocation.quantity))
        .filter_by(business_id=business_id, product_id=product_id)
        .filter(
            allocation.warehouse_document_line_id.in_(
                [line.id for doc in candidates for line in doc.lines]
            )
        )
        .group_by(allocation.warehouse_document_line_id)
        .all()
    )
    ambiguous_conversion = False
    for document in candidates:
        # The origin tag is only a search hint. Require a complete physical conversion.
        if any(
            line.product_id != product_id or line.warehouse_id != warehouse_id or line.quantity <= 0
            for line in document.lines
        ):
            continue
        outgoing = [line for line in document.lines if line.movement == "out"]
        incoming = [line for line in document.lines if line.movement == "in"]
        if (
            len(outgoing) != 1
            or len(incoming) + 1 != len(document.lines)
            or sum(line.quantity for line in incoming) != outgoing[0].quantity
        ):
            continue
        if (
            document.status == "posted"
            and outgoing[0].id not in allocated
            and all(allocated.get(line.id) == line.quantity for line in incoming)
        ):
            return document.id, outgoing[0].quantity
        ambiguous_conversion = True

    if ambiguous_conversion:
        raise ApiError(
            "VARIANT_ALLOCATION_HISTORY_CONFLICT",
            "تخصیص قبلی این کالا در انبار کامل یا مؤثر نیست و نیاز به بررسی دارد",
            http_status=409,
        )
    return None


def _allocated_physical_stock(
    db: Session, business_id: int, product_id: int, warehouse_id: int, today: date
) -> Decimal:
    allocation = WarehouseLineVariantAllocation
    line = WarehouseDocumentLine
    return db.query(
        func.sum(case((line.movement == "in", allocation.quantity), else_=-allocation.quantity))
    ).select_from(allocation).join(line, line.id == allocation.warehouse_document_line_id).join(
        WarehouseDocument, WarehouseDocument.id == line.warehouse_document_id
    ).filter(
        allocation.business_id == business_id,
        allocation.product_id == product_id,
        line.product_id == product_id,
        line.warehouse_id == warehouse_id,
        line.movement.in_(("in", "out")),
        WarehouseDocument.business_id == business_id,
        WarehouseDocument.status == "posted",
        WarehouseDocument.document_date <= today,
        counts_toward_physical_stock(),
    ).scalar() or Decimal(0)


def enable_inventory_variants(
    db: Session,
    business_id: int,
    product_id: int,
    user_id: int,
    payload: dict[str, Any],
) -> dict[str, Any]:
    from app.services.warehouse_service import create_manual_warehouse_document

    try:
        warehouse_id = int(payload.get("warehouse_id"))
    except (TypeError, ValueError):
        raise ApiError(
            "WAREHOUSE_REQUIRED", "انبار برای تخصیص موجودی الزامی است", http_status=422
        ) from None

    # Only the enable path takes the product-wide lock, because variant_mode is global.
    # Take the existing stock lock before reading stock or flushing the product update.
    acquire_transaction_lock(db, f"product_variant_enable:{business_id}:{product_id}")
    product = _load_product(db, business_id, product_id)
    if not db.query(Warehouse.id).filter_by(id=warehouse_id, business_id=business_id).first():
        raise ApiError("WAREHOUSE_NOT_FOUND", "انبار یافت نشد", http_status=404)
    acquire_transaction_lock(db, f"inventory_stock:{business_id}:{warehouse_id}:{product_id}")
    db.refresh(product)
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

    items = []
    for split in payload.get("splits") or []:
        try:
            variant_id = int(split.get("variant_id"))
            qty = Decimal(str(split.get("quantity") or 0))
            if not qty.is_finite() or qty <= 0:
                raise ValueError
        except (TypeError, ValueError, InvalidOperation):
            raise ApiError(
                "INVALID_VARIANT_ALLOCATION", "شناسه یا مقدار تخصیص نامعتبر است", http_status=422
            ) from None
        resolve_variant(db, business_id, int(product_id), variant_id, require_active=True)
        items.append({"variant_id": variant_id, "quantity": qty})

    previous = _prior_conversion(db, business_id, product_id, warehouse_id)
    if previous:
        if product.variant_mode != VARIANT_MODE_INVENTORY:
            raise ApiError(
                "VARIANT_ALLOCATION_HISTORY_CONFLICT",
                "وضعیت کالا با تخصیص قبلی انبار سازگار نیست و نیاز به بررسی دارد",
                http_status=409,
            )
        document_id, quantity = previous
        return {
            "product_id": int(product.id),
            "variant_mode": VARIANT_MODE_INVENTORY,
            "warehouse_document_id": document_id,
            "allocated": str(quantity),
        }

    today = business_today(business_id)
    physical = get_physical_stock(db, business_id, product_id, warehouse_id, today)

    if physical < 0:
        raise ApiError(
            "VARIANT_NEGATIVE_STOCK",
            "تا اصلاح مانده منفی کالا، تفکیک موجودی ممکن نیست",
            http_status=409,
        )

    if product.variant_mode == VARIANT_MODE_INVENTORY:
        allocated = _allocated_physical_stock(db, business_id, product_id, warehouse_id, today)
        # An empty warehouse produces no adjustment on enable. Subsequent receipts
        # with variants can already cover its full physical stock.
        if allocated == physical and (physical > 0 or not items):
            return {
                "product_id": int(product.id),
                "variant_mode": VARIANT_MODE_INVENTORY,
                "allocated": "0",
            }
        if allocated:
            raise ApiError(
                "VARIANT_ALLOCATION_HISTORY_CONFLICT",
                "ماندهٔ کالا و تخصیص‌های قبلی این انبار سازگار نیستند و نیاز به بررسی دارند",
                http_status=409,
            )

    if physical == 0:
        if items:
            raise ApiError(
                "VARIANT_ALLOCATION_MISMATCH",
                "برای کالای بدون مانده نیازی به تخصیص مقدار نیست",
                http_status=422,
            )
        product.variant_mode = VARIANT_MODE_INVENTORY
        db.flush()
        return {
            "product_id": int(product.id),
            "variant_mode": VARIANT_MODE_INVENTORY,
            "allocated": "0",
        }

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

    document_date = payload.get("document_date") or today.isoformat()
    out_line: dict[str, Any] = {
        "product_id": int(product_id),
        "warehouse_id": warehouse_id,
        "quantity": str(physical),
        "movement": "out",
    }
    in_lines: list[dict[str, Any]] = [
        {
            "product_id": int(product_id),
            "warehouse_id": warehouse_id,
            "quantity": str(physical),
            "movement": "in",
            "allocations": [
                {"variant_id": int(x["variant_id"]), "quantity": str(x["quantity"])} for x in items
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
