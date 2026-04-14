"""
همگام‌سازی قیمت خرید/فروش پایه کالا از فاکتورهای قطعی.
قیمت‌های ذخیره‌شده روی محصول در ارز پیش‌فرض کسب‌وکار هستند؛ اگر ارز فاکتور متفاوت باشد، همگام‌سازی انجام نمی‌شود.
"""
from __future__ import annotations

import logging
from decimal import Decimal, ROUND_HALF_UP
from typing import Any, Dict, Optional

from sqlalchemy.orm import Session

from adapters.db.models.business import Business
from adapters.db.models.document import Document
from adapters.db.models.invoice_item_line import InvoiceItemLine
from adapters.db.models.product import Product

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


def _q2(d: Decimal) -> Decimal:
    return d.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)


def _normalize_basis(raw: Optional[str], default: str) -> str:
    if not raw or str(raw).strip() not in ALLOWED_BASES:
        return default
    return str(raw).strip()


def _per_unit_line_currency(
    info: Dict[str, Any],
    qty: Decimal,
    basis: str,
    invoice_type: str,
) -> Optional[Decimal]:
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
    line_unit_label: Optional[str],
) -> Decimal:
    """قیمت هر واحد را به واحد اصلی کالا می‌برد (هم‌تراز با منطق فاکتور در UI)."""
    main_u = (product.main_unit or "").strip()
    sec_u = (product.secondary_unit or "").strip()
    factor_raw = product.unit_conversion_factor
    factor = Decimal(str(factor_raw)) if factor_raw is not None else Decimal(1)
    if factor <= 0:
        factor = Decimal(1)

    lu = (line_unit_label or "").strip()
    is_secondary = sec_u and lu and lu == sec_u and main_u and lu != main_u
    if is_secondary:
        # price(secondary) = price(main) * factor  =>  price(main) = price(secondary) / factor
        return _q2(price_on_line_unit / factor)
    return _q2(price_on_line_unit)


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
        .all()
    )
    if not lines:
        return

    for row in lines:
        pid = row.product_id
        if not pid:
            continue
        qty = Decimal(str(row.quantity or 0))
        if qty <= 0:
            continue
        info = dict(row.extra_info or {})
        per_line = _per_unit_line_currency(info, qty, basis, invoice_type)
        if per_line is None or per_line < 0:
            continue

        line_unit = info.get("unit")
        if line_unit is not None:
            line_unit = str(line_unit).strip() or None

        product = (
            db.query(Product)
            .filter(Product.id == int(pid), Product.business_id == business.id)
            .first()
        )
        if not product:
            continue

        price_main = _to_main_unit_price(per_line, product, line_unit)

        if invoice_type == INVOICE_SALES and update_sales:
            product.base_sales_price = price_main
        elif invoice_type == INVOICE_PURCHASE and update_purchase:
            product.base_purchase_price = price_main

    db.flush()
