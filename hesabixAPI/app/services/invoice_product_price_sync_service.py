"""
همگام‌سازی قیمت خرید/فروش پایه کالا از فاکتورهای قطعی.
قیمت‌های ذخیره‌شده روی محصول در ارز پیش‌فرض کسب‌وکار هستند؛ اگر ارز فاکتور متفاوت باشد، همگام‌سازی انجام نمی‌شود.
"""
from __future__ import annotations

import logging
from datetime import datetime
from decimal import ROUND_HALF_UP, Decimal
from typing import Any

from sqlalchemy.orm import Session

from adapters.db.models.business import Business
from adapters.db.models.document import Document
from adapters.db.models.invoice_item_line import InvoiceItemLine
from adapters.db.models.product import Product
from app.services.invoice_unit_conversion_service import (
    price_line_to_main,
    quantity_line_to_main,
)

logger = logging.getLogger(__name__)

INVOICE_SALES = "invoice_sales"
INVOICE_PURCHASE = "invoice_purchase"

BASIS_UNIT_PRICE = "unit_price"
BASIS_NET_AFTER_LINE_DISCOUNT = "net_after_line_discount"
BASIS_NET_WITH_TAX = "net_with_tax"
BASIS_COST_PRICE = "cost_price"

ALLOWED_BASES = frozenset({
    BASIS_UNIT_PRICE,
    BASIS_NET_AFTER_LINE_DISCOUNT,
    BASIS_NET_WITH_TAX,
    BASIS_COST_PRICE,
})

POLICY_WEIGHTED_AVERAGE = "weighted_average"
POLICY_LAST_LINE = "last_line"
POLICY_HIGHEST_PRICE = "highest_price"
POLICY_LOWEST_PRICE = "lowest_price"
ALLOWED_MULTI_LINE_POLICIES = frozenset({
    POLICY_WEIGHTED_AVERAGE,
    POLICY_LAST_LINE,
    POLICY_HIGHEST_PRICE,
    POLICY_LOWEST_PRICE,
})


def _q2(d: Decimal) -> Decimal:
    return d.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)


def _normalize_basis(raw: str | None, default: str) -> str:
    if not raw or str(raw).strip() not in ALLOWED_BASES:
        return default
    return str(raw).strip()


def _normalize_multi_line_policy(raw: str | None) -> str:
    value = str(raw or POLICY_WEIGHTED_AVERAGE).strip().lower()
    return value if value in ALLOWED_MULTI_LINE_POLICIES else POLICY_WEIGHTED_AVERAGE


def _per_unit_line_currency(
    info: dict[str, Any],
    qty: Decimal,
    basis: str,
    invoice_type: str,
) -> Decimal | None:
    if qty <= 0:
        return None
    unit_price = Decimal(str(info.get("unit_price", 0) or 0))
    line_discount = Decimal(str(info.get("line_discount", 0) or 0))
    tax_amount = Decimal(str(info.get("tax_amount", 0) or 0))
    if info.get("line_total") is not None:
        line_total = Decimal(str(info.get("line_total")))
    else:
        line_total = qty * unit_price - line_discount + tax_amount

    if basis == BASIS_UNIT_PRICE:
        return unit_price

    if basis == BASIS_NET_AFTER_LINE_DISCOUNT:
        net = qty * unit_price - line_discount
        return _q2(net / qty)

    if basis == BASIS_NET_WITH_TAX:
        return _q2(line_total / qty)

    if basis == BASIS_COST_PRICE:
        cp = info.get("cost_price")
        if invoice_type == INVOICE_PURCHASE and cp is not None:
            return Decimal(str(cp))
        return unit_price

    return unit_price


def _to_main_unit_price(
    price_on_line_unit: Decimal,
    product: Product,
    line_unit_label: str | None,
) -> Decimal:
    """Convert a line-unit price to the product main-unit price."""
    return _q2(price_line_to_main(price_on_line_unit, product, line_unit_label))


def _select_multi_line_price(
    candidates: list[tuple[int, Decimal, Decimal]],
    policy: str,
) -> Decimal:
    if policy == POLICY_LAST_LINE:
        return max(candidates, key=lambda item: item[0])[1]
    if policy == POLICY_HIGHEST_PRICE:
        return max(candidates, key=lambda item: item[1])[1]
    if policy == POLICY_LOWEST_PRICE:
        return min(candidates, key=lambda item: item[1])[1]
    total_qty = sum((item[2] for item in candidates), Decimal(0))
    if total_qty <= 0:
        return max(candidates, key=lambda item: item[0])[1]
    return _q2(sum((item[1] * item[2] for item in candidates), Decimal(0)) / total_qty)


def _document_order_key(document: Document) -> tuple[str, str, int]:
    document_date = getattr(document, "document_date", None)
    registered_at = getattr(document, "registered_at", None)
    return (
        document_date.isoformat() if document_date is not None else "",
        registered_at.isoformat() if registered_at is not None else "",
        int(getattr(document, "id", 0) or 0),
    )


def _source_is_newer_than_document(product: Product, document: Document) -> bool:
    """Prevent editing an older purchase invoice from replacing a newer synced price."""
    meta = dict(getattr(product, "base_purchase_price_sync_meta", None) or {})
    source_id = meta.get("document_id")
    if source_id is None or int(source_id) == int(document.id):
        return False
    source_key = (
        str(meta.get("document_date") or ""),
        str(meta.get("registered_at") or ""),
        int(source_id),
    )
    return source_key > _document_order_key(document)


def mark_deleted_purchase_price_source(
    db: Session,
    *,
    business_id: int,
    document_id: int,
    product_ids: list[int],
) -> int:
    """Mark prices whose originating purchase invoice was deleted for explicit review."""
    if not product_ids:
        return 0
    products = db.query(Product).filter(
        Product.business_id == int(business_id),
        Product.id.in_(sorted({int(pid) for pid in product_ids})),
    ).all()
    marked = 0
    for product in products:
        meta = dict(product.base_purchase_price_sync_meta or {})
        if int(meta.get("document_id") or 0) != int(document_id):
            continue
        meta["source_document_deleted"] = True
        meta["needs_review"] = True
        meta["source_deleted_at"] = datetime.utcnow().isoformat()
        product.base_purchase_price_sync_meta = meta
        marked += 1
    db.flush()
    return marked


def apply_invoice_product_price_sync(
    db: Session,
    business: Business,
    document: Document,
    invoice_type: str,
) -> None:
    if document.is_proforma:
        return
    if invoice_type not in (INVOICE_SALES, INVOICE_PURCHASE):
        return

    update_sales = bool(getattr(business, "invoice_sync_update_sales_price_enabled", False))
    update_purchase = bool(getattr(business, "invoice_sync_update_purchase_price_enabled", False))
    if invoice_type == INVOICE_SALES and not update_sales:
        return
    if invoice_type == INVOICE_PURCHASE and not update_purchase:
        return

    default_cur = business.default_currency_id
    if default_cur is None:
        logger.warning(
            "invoice_product_price_sync skipped: business %s has no default_currency_id",
            business.id,
        )
        return
    if int(document.currency_id) != int(default_cur):
        logger.info(
            "invoice_product_price_sync skipped: invoice currency %s != default %s (document %s)",
            document.currency_id,
            default_cur,
            document.id,
        )
        return

    sales_basis = _normalize_basis(
        getattr(business, "invoice_sync_sales_price_basis", None),
        BASIS_NET_AFTER_LINE_DISCOUNT,
    )
    purchase_basis = _normalize_basis(
        getattr(business, "invoice_sync_purchase_price_basis", None),
        BASIS_NET_AFTER_LINE_DISCOUNT,
    )
    basis = sales_basis if invoice_type == INVOICE_SALES else purchase_basis

    lines = (
        db.query(InvoiceItemLine)
        .filter(InvoiceItemLine.document_id == document.id)
        .order_by(InvoiceItemLine.id.asc())
        .all()
    )
    if not lines:
        return

    product_ids = sorted({int(row.product_id) for row in lines if row.product_id})
    products = {
        int(product.id): product
        for product in db.query(Product).filter(
            Product.business_id == business.id,
            Product.id.in_(product_ids),
        ).all()
    }
    candidates_by_product: dict[int, list[tuple[int, Decimal, Decimal]]] = {}

    for row in lines:
        pid = row.product_id
        if not pid:
            continue
        qty = Decimal(str(row.quantity or 0))
        if qty <= 0:
            continue
        info = dict(row.extra_info or {})
        per_line = _per_unit_line_currency(
            info,
            qty,
            basis,
            invoice_type,
        )
        if per_line is None or per_line < 0:
            continue

        line_unit = info.get("unit")
        if line_unit is not None:
            line_unit = str(line_unit).strip() or None

        product = products.get(int(pid))
        if not product:
            continue

        price_main = _to_main_unit_price(per_line, product, line_unit)
        qty_main = quantity_line_to_main(qty, product, line_unit)
        candidates_by_product.setdefault(int(pid), []).append(
            (int(row.id), price_main, qty_main)
        )

    purchase_policy = _normalize_multi_line_policy(
        getattr(business, "invoice_sync_purchase_price_multi_line_policy", None)
    )
    for pid, candidates in candidates_by_product.items():
        product = products[pid]
        if invoice_type == INVOICE_SALES and update_sales:
            product.base_sales_price = _select_multi_line_price(candidates, POLICY_LAST_LINE)
        elif invoice_type == INVOICE_PURCHASE and update_purchase:
            if _source_is_newer_than_document(product, document):
                logger.info(
                    "invoice_product_price_sync skipped older purchase document %s for product %s",
                    document.id,
                    product.id,
                )
                continue
            product.base_purchase_price = _select_multi_line_price(candidates, purchase_policy)
            product.base_purchase_price_sync_meta = {
                "document_id": int(document.id),
                "document_date": document.document_date.isoformat(),
                "registered_at": (
                    document.registered_at.isoformat()
                    if document.registered_at is not None
                    else None
                ),
                "line_ids": [int(item[0]) for item in candidates],
                "basis": basis,
                "multi_line_policy": purchase_policy,
                "synced_at": datetime.utcnow().isoformat(),
            }

    db.flush()
