"""Prove that legacy opening stock is represented by a warehouse conversion."""

from __future__ import annotations

from collections import defaultdict
from datetime import date
from decimal import Decimal
from itertools import groupby

from sqlalchemy import func
from sqlalchemy.orm import Session

from adapters.db.models.product import Product
from adapters.db.models.product_variant_allocation import WarehouseLineVariantAllocation
from adapters.db.models.warehouse_document import WarehouseDocument
from adapters.db.models.warehouse_document_line import WarehouseDocumentLine
from app.core.responses import ApiError
from app.services.invoice_unit_conversion_service import extra_info_dict, inventory_quantity_to_main
from app.services.variant_allocation_service import is_migration_allocation_document


def require_converted_legacy_openings(
    db: Session,
    business_id: int,
    product: Product,
    opening_quantities: dict[tuple[int | None, int], Decimal],
    up_to_date: date,
    *,
    excluded_warehouse_documents: list[int] | None,
) -> None:
    """Accept only linked opening mirrors whose unallocated stock was fully converted."""
    from app.services.warehouse_service import counts_toward_physical_stock

    doc = WarehouseDocument
    line = WarehouseDocumentLine
    allocation = WarehouseLineVariantAllocation
    allocated = (
        db.query(func.coalesce(func.sum(allocation.quantity), 0))
        .filter(
            allocation.warehouse_document_line_id == line.id,
            allocation.business_id == business_id,
            allocation.product_id == product.id,
        )
        .correlate(line)
        .scalar_subquery()
    )
    opening_by_warehouse = defaultdict(dict)
    for (warehouse_id, opening_id), quantity in opening_quantities.items():
        opening_by_warehouse[warehouse_id][opening_id] = quantity

    history = (
        db.query(doc, line, allocated)
        .join(line, line.warehouse_document_id == doc.id)
        .filter(
            doc.business_id == business_id,
            doc.status == "posted",
            doc.document_date <= up_to_date,
            line.product_id == product.id,
            line.warehouse_id.in_([wh for wh in opening_by_warehouse if wh is not None]),
            line.movement.in_(("in", "out")),
            counts_toward_physical_stock(),
        )
        .order_by(doc.document_date, doc.id, line.warehouse_id, line.id)
    )
    if excluded_warehouse_documents:
        history = history.filter(doc.id.not_in(excluded_warehouse_documents))

    mirrors = defaultdict(Decimal)
    unallocated = defaultdict(Decimal)
    checked_conversions = set()
    converted_openings = defaultdict(set)
    for (_doc_id, warehouse_id), rows in groupby(
        history, key=lambda row: (row[0].id, row[1].warehouse_id)
    ):
        movements = list(rows)
        document = movements[0][0]
        lines = [
            (
                line.movement,
                inventory_quantity_to_main(line.quantity, product, line.extra_info),
                assigned,
            )
            for _, line, assigned in movements
        ]

        if (
            document.doc_type == "adjustment"
            and document.source_type == "manual"
            and document.source_document_id is None
            and document.warehouse_id_from == document.warehouse_id_to == warehouse_id
            and is_migration_allocation_document(document)
            and str(extra_info_dict(document.extra_info).get("product_id")) == str(product.id)
        ):
            # Start from the physical unallocated ledger just before the adjustment.
            outgoing = [(qty, assigned) for movement, qty, assigned in lines if movement == "out"]
            incoming = [(qty, assigned) for movement, qty, assigned in lines if movement == "in"]
            if (
                warehouse_id not in checked_conversions
                and unallocated[warehouse_id] > 0
                and outgoing == [(unallocated[warehouse_id], Decimal(0))]
                and all(qty > 0 and qty == assigned for qty, assigned in incoming)
                and sum(qty for qty, _ in incoming) == unallocated[warehouse_id]
            ):
                converted_openings[warehouse_id] = {
                    opening_id
                    for opening_id, quantity in opening_by_warehouse[warehouse_id].items()
                    if mirrors[(warehouse_id, opening_id)] == quantity
                }
            else:
                converted_openings[warehouse_id].clear()
            checked_conversions.add(warehouse_id)

        delta = sum(
            (qty - assigned if movement == "in" else assigned - qty)
            for movement, qty, assigned in lines
        )
        unallocated[warehouse_id] += delta
        if document.source_type == "opening_balance":
            mirrors[(warehouse_id, document.source_document_id)] += delta

    for warehouse_id, opening_id in opening_quantities:
        if opening_id not in converted_openings[warehouse_id]:
            raise ApiError(
                "LEGACY_OPENING_VARIANT_UNRESOLVED",
                "تبدیل موجودی افتتاحیهٔ قدیمی به ترکیب‌ها برای این کالا و انبار قابل تأیید نیست",
                http_status=409,
                details={
                    "product_id": product.id,
                    "warehouse_id": warehouse_id,
                    "opening_document_id": opening_id,
                },
            )
