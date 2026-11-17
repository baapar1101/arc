"""Resolve the physical quantity of a WooCommerce variant return before recording it."""

from decimal import ROUND_HALF_UP, Decimal, DecimalException

from sqlalchemy import String, cast, or_

from adapters.db.models.document import Document
from adapters.db.models.invoice_item_line import InvoiceItemLine
from adapters.db.models.product_variant_allocation import (
    InvoiceItemLineVariantAllocation,
    WarehouseLineVariantAllocation,
)
from adapters.db.models.warehouse_document import WarehouseDocument
from adapters.db.models.warehouse_document_line import WarehouseDocumentLine
from app.core.responses import ApiError
from app.services.invoice_unit_conversion_service import extra_info_dict
from app.services.variant_allocation_service import parse_payload_allocations

SOURCE_FIELDS = ("returned_from_invoice_id", "source_invoice_id", "copy_from_invoice_id")
STOCK_KEY = "woo_return_stock"
QUANT = Decimal("0.000001")


def _ambiguous():
    return ApiError(
        "WOO_RETURN_SOURCE_AMBIGUOUS",
        "ردیف و تخصیص قطعی فروش مبدأ برگشت ووکامرس قابل تطبیق نیست.",
        http_status=409,
    )


def _number(value):
    try:
        number = Decimal(str(value))
        if number.is_finite() and number > 0:
            return number
    except DecimalException:
        pass
    raise _ambiguous()


def _identity(line, product_id):
    return (
        str(line.get("wc_item_id") or ""),
        str(line.get("wc_product_id") or ""),
        str(line.get("wc_variation_id") or ""),
        str(product_id or ""),
    )


def _posted_rows(db, business_id, document_id, kind, movement):
    return (
        db.query(WarehouseDocumentLine, WarehouseLineVariantAllocation)
        .join(WarehouseDocument, WarehouseDocument.id == WarehouseDocumentLine.warehouse_document_id)
        .outerjoin(
            WarehouseLineVariantAllocation,
            WarehouseLineVariantAllocation.warehouse_document_line_id == WarehouseDocumentLine.id,
        )
        .filter(
            WarehouseDocument.business_id == business_id,
            WarehouseDocument.source_type == "invoice",
            WarehouseDocument.source_document_id == document_id,
            WarehouseDocument.status == "posted",
            WarehouseDocument.doc_type == kind,
            WarehouseDocumentLine.movement == movement,
        )
        .all()
    )


def prepare_woo_return_stock(db, business_id, data, lines, invoice_type):
    """Return a server-generated projection aligned with the input invoice lines."""
    if invoice_type != "invoice_sales_return":
        return {}
    header = extra_info_dict(data.get("extra_info"))
    if header.get("source") != "woocommerce":
        return {}
    selected = [(i, row, parse_payload_allocations(row)) for i, row in enumerate(lines)]
    selected = [(i, row, allocs) for i, row, allocs in selected if allocs]
    if not selected:
        return {}
    if data.get("is_proforma") or not header.get("post_inventory", True):
        raise _ambiguous()

    refs = {str(header[name]) for name in SOURCE_FIELDS if header.get(name) is not None}
    if len(refs) != 1 or not (source_ref := next(iter(refs))).isdigit() or not header.get("wc_order_id"):
        raise _ambiguous()
    origin = (
        db.query(Document)
        .filter_by(id=int(source_ref), business_id=business_id, document_type="invoice_sales", is_proforma=False)
        .with_for_update()
        .populate_existing()
        .first()
    )
    if origin is None:
        raise _ambiguous()
    origin_header = extra_info_dict(origin.extra_info)
    if (
        origin_header.get("source") != "woocommerce"
        or str(origin_header.get("wc_order_id")) != str(header["wc_order_id"])
        or not origin_header.get("person_id")
        or str(origin_header["person_id"]) != str(header.get("person_id"))
    ):
        raise _ambiguous()

    source_lines = db.query(InvoiceItemLine).filter_by(document_id=origin.id).all()
    issued = _posted_rows(db, business_id, origin.id, "issue", "out")
    prior = (
        db.query(InvoiceItemLine, Document)
        .join(Document, Document.id == InvoiceItemLine.document_id)
        .filter(
            Document.business_id == business_id,
            Document.document_type == "invoice_sales_return",
            or_(*(cast(Document.extra_info[field].as_string(), String) == source_ref for field in SOURCE_FIELDS)),
        )
        .all()
    )
    projected = {}
    used_lines = set()
    for index, row, allocations in selected:
        info = extra_info_dict(row.get("extra_info"))
        identity = _identity(info, row.get("product_id"))
        matches = [ln for ln in source_lines if _identity(extra_info_dict(ln.extra_info), ln.product_id) == identity]
        if len(matches) != 1 or not all(identity) or "0" in identity or len(allocations) != 1:
            raise _ambiguous()
        source = matches[0]
        if source.id in used_lines:
            raise _ambiguous()
        used_lines.add(source.id)
        variant = str(allocations[0].get("variant_id"))
        ordered = _number(source.quantity)
        take = _number(row.get("quantity"))
        if take != take.quantize(QUANT) or _number(allocations[0].get("quantity")) != take:
            raise _ambiguous()
        source_allocs = db.query(InvoiceItemLineVariantAllocation).filter_by(
            invoice_item_line_id=source.id, business_id=business_id, product_id=source.product_id,
        ).all()
        if len(source_allocs) != 1 or str(source_allocs[0].variant_id) != variant or source_allocs[0].quantity != ordered:
            raise _ambiguous()

        posted = [
            (line, alloc) for line, alloc in issued
            if str(extra_info_dict(line.extra_info).get("invoice_item_line_id")) == str(source.id)
        ]
        if len(posted) != 1:
            raise _ambiguous()
        issue, issued_alloc = posted[0]
        issue_info = extra_info_dict(issue.extra_info)
        if (
            issued_alloc is None
            or issued_alloc.source_document_allocation_id != source_allocs[0].id
            or issued_alloc.business_id != business_id
            or issue.product_id != source.product_id
            or issued_alloc.product_id != source.product_id
            or str(issued_alloc.variant_id) != variant
            or issue.quantity != issued_alloc.quantity
            or issue_info.get("inventory_quantity_unit") != "main"
            or _number(issue_info.get("source_line_quantity")) != ordered
            or not issue.warehouse_id
            or str(info.get("warehouse_id")) != str(issue.warehouse_id)
        ):
            raise _ambiguous()

        returned_lines = Decimal(0)
        returned_main = Decimal(0)
        for earlier, previous in prior:
            if earlier.product_id != source.product_id:
                continue
            earlier_info = extra_info_dict(earlier.extra_info)
            if _identity(earlier_info, earlier.product_id) != identity:
                # A different proven Woo item does not consume this source line.
                if earlier_info.get("wc_item_id") and earlier_info["wc_item_id"] != info["wc_item_id"]:
                    continue
                raise _ambiguous()
            reserved = extra_info_dict(previous.developer_settings).get(STOCK_KEY, {}).get(str(earlier.id))
            if reserved is not None:
                if reserved["source_allocation_id"] != issued_alloc.id:
                    raise _ambiguous()
                returned_main += _number(reserved["quantity_main"])
            else:
                receipts = [
                    (line, alloc) for line, alloc in _posted_rows(db, business_id, previous.id, "receipt", "in")
                    if str(extra_info_dict(line.extra_info).get("invoice_item_line_id")) == str(earlier.id)
                ]
                if len(receipts) != 1:
                    raise _ambiguous()
                receipt, alloc = receipts[0]
                if (
                    alloc is None or str(alloc.variant_id) != variant or receipt.quantity != alloc.quantity
                    or receipt.product_id != source.product_id or alloc.product_id != source.product_id
                    or alloc.business_id != business_id or receipt.warehouse_id != issue.warehouse_id
                ):
                    raise _ambiguous()
                returned_main += _number(alloc.quantity)
            returned_lines += _number(earlier.quantity)

        main = issued_alloc.quantity
        if returned_lines + take > ordered or returned_main >= main:
            raise ApiError("WOO_RETURN_EXCEEDS_ISSUE", "مقدار برگشت از ماندهٔ خروج قطعی فروش بیشتر است.", http_status=409)
        cumulative = (main * (returned_lines + take) / ordered).quantize(QUANT, rounding=ROUND_HALF_UP)
        expected_prior = (main * returned_lines / ordered).quantize(QUANT, rounding=ROUND_HALF_UP)
        if returned_main != expected_prior or cumulative <= returned_main:
            raise _ambiguous()
        projected[index] = {
            "quantity_main": str(cumulative - returned_main),
            "source_allocation_id": int(issued_alloc.id),
            "variant_id": int(issued_alloc.variant_id),
            "product_id": int(issue.product_id),
            "warehouse_id": int(issue.warehouse_id),
        }
    return projected


def return_quantity_main(document, line_id):
    if document.document_type != "invoice_sales_return":
        return None
    row = extra_info_dict(getattr(document, "developer_settings", None)).get(STOCK_KEY, {}).get(str(line_id))
    return Decimal(row["quantity_main"]) if row is not None else None


def validate_woo_return_receipt(db, document, warehouse_document, lines):
    """A delayed or manually edited receipt may only post the reserved allocation."""
    reserved = extra_info_dict(document.developer_settings).get(STOCK_KEY, {})
    if not reserved:
        return
    previous = _posted_rows(db, document.business_id, document.id, "receipt", "in")
    already_posted = {str(extra_info_dict(line.extra_info).get("invoice_item_line_id")) for line, _ in previous}
    allocations = {
        line.id: []
        for line in lines
    }
    for row in db.query(WarehouseLineVariantAllocation).filter(
        WarehouseLineVariantAllocation.warehouse_document_line_id.in_(allocations)
    ).all():
        allocations[row.warehouse_document_line_id].append(row)
    seen = set()
    for line in lines:
        invoice_line_id = str(extra_info_dict(line.extra_info).get("invoice_item_line_id"))
        expected = reserved.get(invoice_line_id)
        if not expected:
            if allocations[line.id]:
                raise _ambiguous()
            continue
        rows = allocations[line.id]
        if (
            invoice_line_id in seen
            or invoice_line_id in already_posted
            or warehouse_document.doc_type != "receipt"
            or line.movement != "in"
            or line.product_id != expected["product_id"]
            or line.warehouse_id != expected["warehouse_id"]
            or line.quantity != Decimal(expected["quantity_main"])
            or len(rows) != 1
            or rows[0].variant_id != expected["variant_id"]
            or rows[0].quantity != line.quantity
        ):
            raise _ambiguous()
        seen.add(invoice_line_id)
