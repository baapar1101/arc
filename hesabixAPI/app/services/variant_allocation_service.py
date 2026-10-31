"""اعتبارسنجی و ذخیره تخصیص Variant روی فاکتور و حواله."""

from __future__ import annotations

from decimal import Decimal
from typing import Any, Dict, Iterable, List, Optional, Sequence, Tuple

from sqlalchemy.orm import Session

from adapters.db.models.invoice_item_line import InvoiceItemLine
from adapters.db.models.product import Product
from adapters.db.models.product_variant_allocation import (
    InvoiceItemLineVariantAllocation,
    WarehouseLineVariantAllocation,
)
from adapters.db.models.warehouse_document import WarehouseDocument
from adapters.db.models.warehouse_document_line import WarehouseDocumentLine
from app.core.responses import ApiError
from app.services.invoice_unit_conversion_service import (
    extra_info_dict,
    quantity_line_to_main,
)
from app.services.product_variant_service import (
    VARIANT_MODE_INVENTORY,
    build_attributes_snapshot,
    is_variant_inventory_product,
    resolve_variant,
)

ZERO = Decimal("0")


def _d(value: Any) -> Decimal:
    return Decimal(str(value if value is not None else 0))


def parse_payload_allocations(payload: Dict[str, Any] | None) -> List[Dict[str, Any]]:
    data = payload if isinstance(payload, dict) else {}
    raw = data.get("allocations")
    if raw is None:
        extra = extra_info_dict(data.get("extra_info"))
        raw = extra.get("allocations")
    if not raw:
        variant_id = data.get("variant_id")
        if variant_id is None:
            extra = extra_info_dict(data.get("extra_info"))
            variant_id = extra.get("variant_id")
        if variant_id is not None:
            qty = data.get("quantity")
            return [{"variant_id": variant_id, "quantity": qty}]
        return []
    if not isinstance(raw, list):
        raise ApiError("INVALID_VARIANT_ALLOCATION", "ساختار تخصیص ویژگی نامعتبر است", http_status=422)
    return [item for item in raw if isinstance(item, dict)]


def is_migration_allocation_document(document: WarehouseDocument | None) -> bool:
    extra = extra_info_dict(getattr(document, "extra_info", None) if document is not None else None)
    return str(extra.get("system_origin") or "") == "variant_allocation"


def _normalized_items(items: Sequence[Dict[str, Any]]) -> List[Tuple[int, Decimal, Optional[Decimal]]]:
    merged: Dict[int, Tuple[Decimal, Optional[Decimal]]] = {}
    for item in items:
        try:
            variant_id = int(item.get("variant_id"))
        except (TypeError, ValueError):
            raise ApiError("INVALID_VARIANT_ALLOCATION", "شناسه ترکیب نامعتبر است", http_status=422)
        qty = _d(item.get("quantity"))
        if qty <= 0:
            raise ApiError("INVALID_VARIANT_ALLOCATION", "مقدار تخصیص باید بزرگ‌تر از صفر باشد", http_status=422)
        unit_price = None
        if item.get("unit_price") is not None:
            unit_price = _d(item.get("unit_price"))
        prev_qty, prev_price = merged.get(variant_id, (ZERO, None))
        merged[variant_id] = (prev_qty + qty, unit_price if unit_price is not None else prev_price)
    return [(vid, qty, price) for vid, (qty, price) in merged.items()]


def validate_allocation_sum(line_quantity: Decimal, allocated: Sequence[Tuple[int, Decimal, Any]]) -> None:
    total = sum((qty for _, qty, _ in allocated), ZERO)
    if total != _d(line_quantity):
        raise ApiError(
            "VARIANT_ALLOCATION_MISMATCH",
            "جمع تخصیص‌ها با مقدار ردیف برابر نیست",
            http_status=422,
            details={"line_quantity": str(_d(line_quantity)), "allocated": str(total)},
        )


def validate_payload_for_product(
    db: Session,
    business_id: int,
    product: Product,
    payload: Dict[str, Any],
    line_quantity: Decimal,
    *,
    require_active: bool = True,
    allow_missing_for_migration: bool = False,
) -> List[Tuple[int, Decimal, Optional[Decimal]]]:
    items = parse_payload_allocations(payload)
    variant_mode = str(getattr(product, "variant_mode", None) or "none")
    if variant_mode != VARIANT_MODE_INVENTORY:
        if items:
            raise ApiError(
                "VARIANT_NOT_ALLOWED",
                "برای کالای بدون تفکیک موجودی نمی‌توان تخصیص ویژگی ثبت کرد",
                http_status=422,
            )
        return []
    if str(product.inventory_mode or "bulk") == "unique":
        raise ApiError(
            "VARIANT_UNIQUE_NOT_SUPPORTED",
            "تفکیک موجودی ویژگی برای کالای یونیک پشتیبانی نمی‌شود",
            http_status=422,
        )
    if not items:
        if allow_missing_for_migration:
            return []
        raise ApiError("VARIANT_REQUIRED", "برای این کالا انتخاب ویژگی انباری الزامی است", http_status=422)
    normalized = _normalized_items(items)
    validate_allocation_sum(_d(line_quantity), normalized)
    for variant_id, _, _ in normalized:
        variant = resolve_variant(
            db,
            business_id,
            int(product.id),
            variant_id,
            require_active=require_active,
        )
        if int(variant.business_id) != int(business_id):
            raise ApiError("VARIANT_BUSINESS_MISMATCH", "ترکیب متعلق به این کسب‌وکار نیست", http_status=403)
    return normalized


def persist_invoice_allocations(
    db: Session,
    business_id: int,
    invoice_line: InvoiceItemLine,
    product: Product,
    payload: Dict[str, Any],
) -> List[InvoiceItemLineVariantAllocation]:
    items = validate_payload_for_product(
        db,
        business_id,
        product,
        payload,
        _d(invoice_line.quantity),
        require_active=True,
    )
    db.query(InvoiceItemLineVariantAllocation).filter(
        InvoiceItemLineVariantAllocation.invoice_item_line_id == int(invoice_line.id)
    ).delete(synchronize_session=False)
    rows: List[InvoiceItemLineVariantAllocation] = []
    for variant_id, qty, unit_price in items:
        variant = resolve_variant(db, business_id, int(product.id), variant_id, require_active=True)
        row = InvoiceItemLineVariantAllocation(
            business_id=int(business_id),
            invoice_item_line_id=int(invoice_line.id),
            product_id=int(product.id),
            variant_id=int(variant.id),
            quantity=qty,
            unit_price=unit_price,
            attributes_snapshot=build_attributes_snapshot(db, variant),
        )
        db.add(row)
        rows.append(row)
    db.flush()
    return rows


def convert_allocations_to_main(
    product: Product,
    allocations: Sequence[Tuple[int, Decimal, Optional[Decimal]]],
    line_unit: str | None,
) -> List[Tuple[int, Decimal, Optional[Decimal]]]:
    converted: List[Tuple[int, Decimal, Optional[Decimal]]] = []
    for variant_id, qty, price in allocations:
        qty_main = quantity_line_to_main(qty, product, line_unit, strict=True)
        if qty_main <= 0:
            raise ApiError("VARIANT_ALLOCATION_MISMATCH", "مقدار تخصیص پس از تبدیل واحد نامعتبر است", http_status=422)
        converted.append((variant_id, qty_main, price))
    return converted


def persist_warehouse_allocations(
    db: Session,
    business_id: int,
    warehouse_line: WarehouseDocumentLine,
    product: Product,
    allocations_main: Sequence[Tuple[int, Decimal, Optional[Decimal]]],
    *,
    source_by_variant: Optional[Dict[int, int]] = None,
) -> List[WarehouseLineVariantAllocation]:
    db.query(WarehouseLineVariantAllocation).filter(
        WarehouseLineVariantAllocation.warehouse_document_line_id == int(warehouse_line.id)
    ).delete(synchronize_session=False)
    if not allocations_main:
        db.flush()
        return []
    validate_allocation_sum(_d(warehouse_line.quantity), allocations_main)
    rows: List[WarehouseLineVariantAllocation] = []
    for variant_id, qty, _price in allocations_main:
        variant = resolve_variant(
            db, business_id, int(product.id), variant_id, require_active=False
        )
        row = WarehouseLineVariantAllocation(
            business_id=int(business_id),
            warehouse_document_line_id=int(warehouse_line.id),
            product_id=int(product.id),
            variant_id=int(variant.id),
            source_document_allocation_id=(source_by_variant or {}).get(int(variant_id)),
            quantity=qty,
        )
        db.add(row)
        rows.append(row)
    db.flush()
    return rows


def attach_warehouse_line_from_payload(
    db: Session,
    business_id: int,
    warehouse_line: WarehouseDocumentLine,
    product: Product,
    payload: Dict[str, Any],
    *,
    document: Optional[WarehouseDocument] = None,
    source_line_unit: str | None = None,
) -> List[WarehouseLineVariantAllocation]:
    allow_missing = is_migration_allocation_document(document) and str(warehouse_line.movement) == "out"
    items = validate_payload_for_product(
        db,
        business_id,
        product,
        payload,
        _d(payload.get("quantity") or warehouse_line.quantity),
        require_active=True,
        allow_missing_for_migration=allow_missing,
    )
    if not items:
        persist_warehouse_allocations(db, business_id, warehouse_line, product, [])
        return []
    converted = convert_allocations_to_main(product, items, source_line_unit)
    validate_allocation_sum(_d(warehouse_line.quantity), converted)
    return persist_warehouse_allocations(db, business_id, warehouse_line, product, converted)


def copy_invoice_allocations_to_warehouse_line(
    db: Session,
    business_id: int,
    warehouse_line: WarehouseDocumentLine,
    product: Product,
    invoice_line: InvoiceItemLine,
) -> List[WarehouseLineVariantAllocation]:
    src_rows = (
        db.query(InvoiceItemLineVariantAllocation)
        .filter(InvoiceItemLineVariantAllocation.invoice_item_line_id == int(invoice_line.id))
        .all()
    )
    extra = extra_info_dict(invoice_line.extra_info)
    unit = extra.get("unit")
    converted: List[Tuple[int, Decimal, Optional[Decimal]]] = []
    source_map: Dict[int, int] = {}
    for row in src_rows:
        qty_main = quantity_line_to_main(row.quantity, product, unit, strict=True)
        converted.append((int(row.variant_id), qty_main, row.unit_price))
        source_map[int(row.variant_id)] = int(row.id)
    if is_variant_inventory_product(product) and not converted:
        raise ApiError("VARIANT_REQUIRED", "برای این کالا انتخاب ویژگی انباری الزامی است", http_status=422)
    if converted:
        validate_allocation_sum(_d(warehouse_line.quantity), converted)
    return persist_warehouse_allocations(
        db,
        business_id,
        warehouse_line,
        product,
        converted,
        source_by_variant=source_map,
    )


def copy_warehouse_allocations_to_reverse_line(
    db: Session,
    business_id: int,
    source_line: WarehouseDocumentLine,
    reverse_line: WarehouseDocumentLine,
) -> None:
    rows = (
        db.query(WarehouseLineVariantAllocation)
        .filter(WarehouseLineVariantAllocation.warehouse_document_line_id == int(source_line.id))
        .all()
    )
    for row in rows:
        db.add(
            WarehouseLineVariantAllocation(
                business_id=int(business_id),
                warehouse_document_line_id=int(reverse_line.id),
                product_id=int(row.product_id),
                variant_id=int(row.variant_id),
                source_document_allocation_id=row.source_document_allocation_id,
                quantity=row.quantity,
            )
        )
    db.flush()


def list_warehouse_line_allocations(
    db: Session, warehouse_document_line_id: int
) -> List[WarehouseLineVariantAllocation]:
    return (
        db.query(WarehouseLineVariantAllocation)
        .filter(
            WarehouseLineVariantAllocation.warehouse_document_line_id == int(warehouse_document_line_id)
        )
        .all()
    )


def assert_transfer_allocations_match(
    db: Session,
    out_line: WarehouseDocumentLine,
    in_line: WarehouseDocumentLine,
) -> None:
    out_rows = {
        int(r.variant_id): _d(r.quantity)
        for r in list_warehouse_line_allocations(db, int(out_line.id))
    }
    in_rows = {
        int(r.variant_id): _d(r.quantity)
        for r in list_warehouse_line_allocations(db, int(in_line.id))
    }
    if out_rows != in_rows:
        raise ApiError(
            "TRANSFER_VARIANT_MISMATCH",
            "تخصیص ویژگی دو سمت حواله انتقال یکسان نیست",
            http_status=422,
        )


def allocations_as_payload(rows: Iterable[WarehouseLineVariantAllocation]) -> List[Dict[str, Any]]:
    return [
        {"variant_id": int(row.variant_id), "quantity": str(row.quantity)}
        for row in rows
    ]
