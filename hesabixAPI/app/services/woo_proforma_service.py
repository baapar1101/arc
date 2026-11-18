"""Use published Woo stock units for the first posting of a proven variant proforma."""

from sqlalchemy import and_, or_

from adapters.db.models.invoice_item_line import InvoiceItemLine
from adapters.db.models.product import Product
from adapters.db.models.product_variant_allocation import (
    InvoiceItemLineVariantAllocation,
    WarehouseLineVariantAllocation,
)
from adapters.db.models.warehouse_document import WarehouseDocument
from adapters.db.models.warehouse_document_line import WarehouseDocumentLine
from app.core.responses import ApiError
from app.services.invoice_unit_conversion_service import extra_info_dict
from app.services.variant_allocation_service import (
    parse_payload_allocations,
    validate_payload_for_product,
)
from app.services.woo_return_source_service import _identity


def prepare_woo_proforma_finalization(db, document, data, invoice_type):
    previous = extra_info_dict(document.extra_info)
    if (
        document.document_type != "invoice_sales"
        or invoice_type != "invoice_sales"
        or not document.is_proforma
        or data.get("is_proforma") is not False
        or previous.get("source") != "woocommerce"
    ):
        return data

    def ambiguous():
        return ApiError(
            "WOO_PROFORMA_SOURCE_AMBIGUOUS",
            "اولین تبدیل پیش‌فاکتور ووکامرس یا انتساب ردیف Variant قابل تأیید نیست. سند و حواله را بررسی کنید.",
            http_status=409,
        )

    original_lines = db.query(InvoiceItemLine).filter_by(document_id=document.id).populate_existing().all()
    allocations = db.query(InvoiceItemLineVariantAllocation).filter(
        InvoiceItemLineVariantAllocation.invoice_item_line_id.in_([line.id for line in original_lines]),
    ).populate_existing().all()
    lines = list(data.get("lines") or [])
    if not allocations and not any(parse_payload_allocations(line) for line in lines):
        return data
    if not lines:
        raise ambiguous()
    header = extra_info_dict(data.get("extra_info"))
    if any(
        not previous.get(key) or str(header.get(key)) != str(previous[key])
        for key in ("source", "wc_order_id", "person_id")
    ):
        raise ambiguous()

    # Check actual warehouse rows as well as header links before changing any invoice state.
    linked_ids = (previous.get("links") or {}).get("warehouse_document_ids") or []
    issued = db.query(WarehouseDocument).outerjoin(
        WarehouseDocumentLine, WarehouseDocumentLine.warehouse_document_id == WarehouseDocument.id,
    ).outerjoin(
        WarehouseLineVariantAllocation,
        WarehouseLineVariantAllocation.warehouse_document_line_id == WarehouseDocumentLine.id,
    ).filter(
        WarehouseDocument.business_id == document.business_id,
        WarehouseDocument.status != "draft",
        or_(
            and_(WarehouseDocument.source_type == "invoice", WarehouseDocument.source_document_id == document.id),
            WarehouseDocument.id.in_(linked_ids),
            WarehouseLineVariantAllocation.source_document_allocation_id.in_([row.id for row in allocations]),
        ),
    ).first()
    if issued is not None:
        raise ambiguous()

    projected = []
    used = set()
    for line in lines:
        items = parse_payload_allocations(line)
        info = extra_info_dict(line.get("extra_info"))
        identity = _identity(info, line.get("product_id"))
        matches = [old for old in original_lines if _identity(extra_info_dict(old.extra_info), old.product_id) == identity]
        if not items:
            if any(row.invoice_item_line_id == old.id for old in matches for row in allocations):
                raise ambiguous()
            projected.append(line)
            continue
        if len(matches) != 1 or not all(identity) or "0" in identity or len(items) != 1:
            raise ambiguous()
        old = matches[0]
        persisted = [row for row in allocations if row.invoice_item_line_id == old.id]
        if (
            old.id in used
            or len(persisted) != 1
            or persisted[0].business_id != document.business_id
            or persisted[0].product_id != old.product_id
            or str(persisted[0].variant_id) != str(items[0].get("variant_id"))
            or persisted[0].quantity != old.quantity
            or old.quantity <= 0
        ):
            raise ambiguous()
        product = db.get(Product, old.product_id)
        if product is None or product.business_id != document.business_id:
            raise ambiguous()
        if not product.track_inventory:
            projected.append(line)
            continue
        validate_payload_for_product(db, document.business_id, product, line, line.get("quantity"))
        used.add(old.id)
        projected.append({**line, "extra_info": {**info, "unit": "main"}})
    return {**data, "lines": projected}
