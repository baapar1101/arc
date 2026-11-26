"""موجودی Variant روی دو دفتر فعلی حسابیکس؛ کالای none دست نمی‌خورد."""

from __future__ import annotations

from collections import defaultdict
from datetime import date, datetime
from decimal import Decimal
from typing import Any, Dict, Iterable, List, Optional, Sequence, Tuple

from sqlalchemy import and_, case, func, or_
from sqlalchemy.orm import Session, aliased

from adapters.db.models.document import Document
from adapters.db.models.document_line import DocumentLine
from adapters.db.models.inventory_variant_balance import InventoryVariantBalance
from adapters.db.models.invoice_item_line import InvoiceItemLine
from adapters.db.models.product import Product
from adapters.db.models.product_variant_allocation import (
    InvoiceItemLineVariantAllocation,
    WarehouseLineVariantAllocation,
)
from adapters.db.models.warehouse_document import WarehouseDocument
from adapters.db.models.warehouse_document_line import WarehouseDocumentLine
from app.core.transaction_lock import acquire_transaction_lock
from app.services.invoice_unit_conversion_service import extra_info_dict, inventory_quantity_to_main
from app.services.product_variant_service import is_variant_inventory_product

_INVOICE_DOC_TYPES_WITH_ITEM_LINES = {
    "invoice_sales",
    "invoice_sales_return",
    "invoice_purchase",
    "invoice_purchase_return",
    "invoice_waste",
    "invoice_direct_consumption",
    "invoice_production",
}

ZERO = Decimal("0")
StockKey = Tuple[int, int, int, int]  # business, warehouse, product, variant


def _d(value: Any) -> Decimal:
    return Decimal(str(value if value is not None else 0))


def _warehouse_doc_is_cancel_reversal_of_cancelled(
    db: Session,
    business_id: int,
    wh_doc: WarehouseDocument,
) -> bool:
    extra = extra_info_dict(wh_doc.extra_info)
    src_id = extra.get("cancels_warehouse_document_id") or wh_doc.source_document_id
    if not src_id:
        return False
    try:
        src_id_int = int(src_id)
    except (TypeError, ValueError):
        return False
    src = (
        db.query(WarehouseDocument.status)
        .filter(
            WarehouseDocument.id == src_id_int,
            WarehouseDocument.business_id == int(business_id),
        )
        .first()
    )
    if not src:
        return False
    return str(src[0] or "").strip().lower() == "cancelled"


def acquire_variant_stock_locks(
    db: Session,
    business_id: int,
    keys: Sequence[Tuple[int, int, int]],
) -> None:
    """اول قفل کالایی فعلی، بعد قفل Variant؛ همه کلیدها sort می‌شوند."""
    product_keys = sorted({(int(wh), int(pid)) for wh, pid, _vid in keys})
    for warehouse_id, product_id in product_keys:
        acquire_transaction_lock(
            db,
            f"inventory_stock:{int(business_id)}:{warehouse_id}:{product_id}",
        )
    variant_keys = sorted({(int(wh), int(pid), int(vid)) for wh, pid, vid in keys})
    for warehouse_id, product_id, variant_id in variant_keys:
        acquire_transaction_lock(
            db,
            f"inventory_stock:{int(business_id)}:{warehouse_id}:{product_id}:{variant_id}",
        )


def compute_available_variant_stock(
    db: Session,
    business_id: int,
    product_id: int,
    warehouse_id: Optional[int],
    variant_id: int,
    up_to_date: date,
    exclude_document_id: Optional[int] = None,
    *,
    exclude_invoice_source_document_id: Optional[int] = None,
    exclude_warehouse_document_ids: Optional[List[int]] = None,
) -> Decimal:
    product = (
        db.query(Product)
        .filter(Product.id == int(product_id), Product.business_id == int(business_id))
        .first()
    )
    bal = ZERO

    iil_q = (
        db.query(InvoiceItemLineVariantAllocation, InvoiceItemLine, Document)
        .join(InvoiceItemLine, InvoiceItemLine.id == InvoiceItemLineVariantAllocation.invoice_item_line_id)
        .join(Document, Document.id == InvoiceItemLine.document_id)
        .filter(
            InvoiceItemLineVariantAllocation.business_id == int(business_id),
            InvoiceItemLineVariantAllocation.product_id == int(product_id),
            InvoiceItemLineVariantAllocation.variant_id == int(variant_id),
            Document.business_id == int(business_id),
            Document.is_proforma == False,  # noqa: E712
            Document.document_date <= up_to_date,
        )
    )
    if exclude_document_id is not None:
        iil_q = iil_q.filter(Document.id != int(exclude_document_id))
    for alloc, line, doc in iil_q.all():
        info = extra_info_dict(line.extra_info)
        if info.get("inventory_posted") is False or info.get("inventory_tracked") is False:
            continue
        movement = info.get("movement")
        if movement not in ("in", "out"):
            doc_type = str(doc.document_type or "")
            if doc_type in ("invoice_sales", "invoice_purchase_return", "invoice_waste", "invoice_direct_consumption"):
                movement = "out"
            elif doc_type in ("invoice_purchase", "invoice_sales_return"):
                movement = "in"
            else:
                continue
        if movement not in ("in", "out"):
            continue
        try:
            wh_id = int(info.get("warehouse_id")) if info.get("warehouse_id") is not None else None
        except (TypeError, ValueError):
            wh_id = None
        if warehouse_id is not None:
            if wh_id is None or int(wh_id) != int(warehouse_id):
                continue
        qty = inventory_quantity_to_main(alloc.quantity, product, info, strict=False)
        if qty <= 0:
            continue
        if movement == "in":
            bal += qty
        else:
            bal -= qty

    # Opening stock is financial stock, like the product-level reader; its warehouse mirror is excluded below.
    if product is not None and is_variant_inventory_product(product) and product.track_inventory:
        from app.services.legacy_opening_variant_service import require_converted_legacy_openings
        from app.services.variant_allocation_service import opening_allocations_in_main_units

        opening_q = db.query(Document.id).filter(
            Document.business_id == int(business_id), Document.document_type == "opening_balance",
            Document.is_proforma == False, Document.document_date <= up_to_date,  # noqa: E712
        )
        if exclude_document_id is not None:
            opening_q = opening_q.filter(Document.id != int(exclude_document_id))
        opening_ids = [row.id for row in opening_q]
        opening_lines = db.query(DocumentLine).filter(
            DocumentLine.document_id.in_(opening_ids), DocumentLine.product_id == int(product_id),
        ).all() if opening_ids else []
        legacy_openings: dict[tuple[int | None, int], Decimal] = defaultdict(Decimal)
        for line in opening_lines:
            info = extra_info_dict(line.extra_info)
            if (info.get("movement") or "in") != "in" or info.get("inventory_posted") is False or info.get("inventory_tracked") is False:
                continue
            try:
                opening_warehouse = int(info.get("warehouse_id"))
            except (TypeError, ValueError):
                opening_warehouse = None
            if warehouse_id is not None and opening_warehouse != int(warehouse_id):
                continue
            if _d(line.quantity) <= 0:
                continue
            if info.get("allocations") in (None, []) and info.get("variant_id") is None:
                legacy_openings[(opening_warehouse, line.document_id)] += inventory_quantity_to_main(
                    line.quantity, product, info,
                )
                continue
            for vid, qty, _price in opening_allocations_in_main_units(db, business_id, product, line.quantity, info):
                if vid == int(variant_id):
                    bal += qty
        if legacy_openings:
            # The posted conversion contributes through its warehouse allocations below.
            require_converted_legacy_openings(
                db, business_id, product, legacy_openings, up_to_date,
                excluded_warehouse_documents=exclude_warehouse_document_ids,
            )

    wh_q = (
        db.query(WarehouseLineVariantAllocation, WarehouseDocumentLine, WarehouseDocument)
        .join(
            WarehouseDocumentLine,
            WarehouseDocumentLine.id == WarehouseLineVariantAllocation.warehouse_document_line_id,
        )
        .join(WarehouseDocument, WarehouseDocument.id == WarehouseDocumentLine.warehouse_document_id)
        .filter(
            WarehouseLineVariantAllocation.business_id == int(business_id),
            WarehouseLineVariantAllocation.product_id == int(product_id),
            WarehouseLineVariantAllocation.variant_id == int(variant_id),
            WarehouseDocument.business_id == int(business_id),
            WarehouseDocument.status == "posted",
            WarehouseDocument.document_date <= up_to_date,
        )
    )
    if warehouse_id is not None:
        wh_q = wh_q.filter(WarehouseDocumentLine.warehouse_id == int(warehouse_id))
    _wh_src_doc = aliased(Document)
    wh_q = wh_q.outerjoin(
        _wh_src_doc,
        and_(
            WarehouseDocument.source_document_id == _wh_src_doc.id,
            _wh_src_doc.business_id == int(business_id),
        ),
    ).filter(
        ~or_(
            func.lower(func.coalesce(WarehouseDocument.source_type, "")).in_(("invoice", "opening_balance")),
            and_(
                WarehouseDocument.source_document_id.isnot(None),
                _wh_src_doc.id.isnot(None),
                _wh_src_doc.document_type.in_((*_INVOICE_DOC_TYPES_WITH_ITEM_LINES, "opening_balance")),
            ),
        )
    )
    if exclude_warehouse_document_ids:
        ids = sorted({int(x) for x in exclude_warehouse_document_ids if x is not None})
        if ids:
            wh_q = wh_q.filter(~WarehouseDocument.id.in_(ids))
    if exclude_invoice_source_document_id is not None:
        inv_doc_id = int(exclude_invoice_source_document_id)
        if inv_doc_id:
            wh_q = wh_q.filter(
                or_(
                    WarehouseDocument.source_document_id.is_(None),
                    WarehouseDocument.source_document_id != inv_doc_id,
                )
            )
    for alloc, line, wh_doc in wh_q.all():
        if _warehouse_doc_is_cancel_reversal_of_cancelled(db, business_id, wh_doc):
            continue
        qty = _d(alloc.quantity)
        if qty <= 0:
            continue
        if line.movement == "in":
            bal += qty
        elif line.movement == "out":
            bal -= qty
    return bal


def rebuild_variant_balances(
    db: Session,
    business_id: int,
    keys: Iterable[Tuple[int, int, int]],
) -> None:
    from app.services.warehouse_service import counts_toward_physical_stock

    unique_keys = sorted({(int(wh), int(pid), int(vid)) for wh, pid, vid in keys})
    if not unique_keys:
        return
    now = datetime.utcnow()
    for warehouse_id, product_id, variant_id in unique_keys:
        qty = (
            db.query(
                func.coalesce(
                    func.sum(
                        case(
                            (WarehouseDocumentLine.movement == "in", WarehouseLineVariantAllocation.quantity),
                            else_=-WarehouseLineVariantAllocation.quantity,
                        )
                    ),
                    0,
                )
            )
            .select_from(WarehouseLineVariantAllocation)
            .join(
                WarehouseDocumentLine,
                WarehouseDocumentLine.id == WarehouseLineVariantAllocation.warehouse_document_line_id,
            )
            .join(WarehouseDocument, WarehouseDocument.id == WarehouseDocumentLine.warehouse_document_id)
            .filter(
                WarehouseLineVariantAllocation.business_id == int(business_id),
                WarehouseLineVariantAllocation.product_id == int(product_id),
                WarehouseLineVariantAllocation.variant_id == int(variant_id),
                WarehouseDocumentLine.warehouse_id == int(warehouse_id),
                WarehouseDocument.status == "posted",
                counts_toward_physical_stock(),
            )
            .scalar()
        )
        qty_dec = _d(qty)
        row = db.get(
            InventoryVariantBalance,
            {
                "business_id": int(business_id),
                "warehouse_id": int(warehouse_id),
                "product_id": int(product_id),
                "variant_id": int(variant_id),
            },
        )
        if row is None:
            if qty_dec == 0:
                continue
            db.add(
                InventoryVariantBalance(
                    business_id=int(business_id),
                    warehouse_id=int(warehouse_id),
                    product_id=int(product_id),
                    variant_id=int(variant_id),
                    quantity=qty_dec,
                    version=1,
                    updated_at=now,
                )
            )
        else:
            row.quantity = qty_dec
            row.version = int(row.version or 0) + 1
            row.updated_at = now
    db.flush()


def rebuild_balances_for_warehouse_document(db: Session, document: WarehouseDocument) -> None:
    lines = (
        db.query(WarehouseDocumentLine)
        .filter(WarehouseDocumentLine.warehouse_document_id == int(document.id))
        .all()
    )
    keys: List[Tuple[int, int, int]] = []
    for line in lines:
        if line.warehouse_id is None:
            continue
        allocs = (
            db.query(WarehouseLineVariantAllocation)
            .filter(WarehouseLineVariantAllocation.warehouse_document_line_id == int(line.id))
            .all()
        )
        for alloc in allocs:
            keys.append((int(line.warehouse_id), int(alloc.product_id), int(alloc.variant_id)))
    rebuild_variant_balances(db, int(document.business_id), keys)


def expand_outgoing_shortage_requirements(
    db: Session,
    business_id: int,
    outgoing_lines: List[Dict[str, Any]],
    product_units: Dict[int, Any],
) -> Tuple[Dict[Tuple[int, Optional[int], Optional[int]], Decimal], List[Tuple[int, int, int]]]:
    """کلید: (product_id, warehouse_id, variant_id|None). None یعنی موجودی سطح کالا."""
    required: Dict[Tuple[int, Optional[int], Optional[int]], Decimal] = {}
    lock_keys: List[Tuple[int, int, int]] = []
    for ln in outgoing_lines:
        pid = int(ln.get("product_id"))
        info = extra_info_dict(ln.get("extra_info"))
        wh_id = info.get("warehouse_id")
        wh_int = int(wh_id) if wh_id is not None else None
        qty = _d(ln.get("quantity", 0) or 0)
        qty_main = inventory_quantity_to_main(qty, product_units.get(pid), info, strict=False)
        allocs = ln.get("allocations")
        if not allocs and info.get("allocations"):
            allocs = info.get("allocations")
        product = product_units.get(pid)
        if is_variant_inventory_product(product) and allocs:
            for item in allocs:
                try:
                    variant_id = int(item.get("variant_id"))
                except (TypeError, ValueError):
                    continue
                aqty = inventory_quantity_to_main(
                    item.get("quantity"),
                    product,
                    info,
                    strict=False,
                )
                key = (pid, wh_int, variant_id)
                required[key] = required.get(key, ZERO) + aqty
                if wh_int is not None:
                    lock_keys.append((wh_int, pid, variant_id))
        else:
            key = (pid, wh_int, None)
            required[key] = required.get(key, ZERO) + qty_main
    return required, lock_keys
