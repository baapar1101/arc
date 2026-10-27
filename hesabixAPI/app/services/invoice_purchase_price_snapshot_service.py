"""Snapshot and resolve the purchase-price profit basis in base currency."""
from __future__ import annotations

from datetime import datetime
from decimal import Decimal
from typing import Any

from sqlalchemy.orm import Session

from adapters.db.models.business import Business
from adapters.db.models.document import Document
from adapters.db.models.invoice_item_line import InvoiceItemLine
from adapters.db.models.product import Product
from app.core.responses import ApiError
from app.services.invoice_unit_conversion_service import (
    effective_line_unit,
    is_secondary_line_unit,
    price_main_to_line,
)

POLICY_ZERO_COST = "zero_cost"
POLICY_USE_LINE_COST = "use_line_cost_price"
POLICY_BLOCK = "block_calculation"
ALLOWED_MISSING_PURCHASE_PRICE_POLICIES = frozenset(
    {POLICY_ZERO_COST, POLICY_USE_LINE_COST, POLICY_BLOCK}
)


def normalize_missing_purchase_price_policy(value: str | None) -> str:
    policy = str(value or POLICY_ZERO_COST).strip().lower()
    return policy if policy in ALLOWED_MISSING_PURCHASE_PRICE_POLICIES else POLICY_ZERO_COST


def _missing_cost_for_line(line: Any, policy: str) -> tuple[Decimal, str]:
    normalized = normalize_missing_purchase_price_policy(policy)
    info = dict(getattr(line, "extra_info", None) or {})
    if normalized == POLICY_USE_LINE_COST:
        # قرارداد این گزینه: extra_info.cost_price بهای واحد ردیف در ارز پایه است.
        raw = info.get("cost_price")
        if raw is not None:
            return Decimal(str(raw)), "line_cost_price"
        raise ApiError(
            "PURCHASE_PRICE_AND_LINE_COST_REQUIRED",
            "قیمت خرید محصول و بهای ثبت‌شده روی ردیف هر دو نامشخص هستند",
            http_status=409,
        )
    if normalized == POLICY_BLOCK:
        raise ApiError(
            "PURCHASE_PRICE_REQUIRED",
            "برای محاسبه سود، قیمت خرید محصول باید تعیین شود",
            http_status=409,
        )
    return Decimal(0), "zero_cost_policy"


def resolve_missing_purchase_price_unit_cost(line: Any, policy: str) -> Decimal:
    return _missing_cost_for_line(line, policy)[0]


def _snapshot_value_for_line(
    product: Product,
    line: InvoiceItemLine,
    policy: str,
) -> tuple[Decimal, str, str | None, Decimal]:
    info = dict(line.extra_info or {})
    line_unit = effective_line_unit(product, info.get("unit"))
    raw_factor = product.unit_conversion_factor
    factor = Decimal(str(raw_factor if raw_factor is not None else 1))
    if is_secondary_line_unit(product, line_unit):
        if factor <= 0:
            raise ApiError(
                "INVALID_UNIT_CONVERSION",
                "ضریب تبدیل واحد محصول باید بزرگ‌تر از صفر باشد",
                http_status=409,
            )
    else:
        factor = Decimal(1)

    if product.base_purchase_price is None:
        value, source = _missing_cost_for_line(line, policy)
        return value, source, line_unit, factor

    value = price_main_to_line(product.base_purchase_price, product, line_unit)
    return value, "product_base_purchase_price", line_unit, factor


def stamp_document_purchase_price_snapshots(
    db: Session,
    document: Document,
    *,
    overwrite: bool = False,
) -> int:
    """Capture base-currency unit costs for finalized sales/production lines."""
    if document.is_proforma or document.document_type not in {"invoice_sales", "invoice_production"}:
        return 0
    business = db.get(Business, int(document.business_id))
    if not business or str(business.invoice_profit_calculation_basis or "purchase_price") != "purchase_price":
        return 0
    if business.default_currency_id is None:
        raise ApiError(
            "BASE_CURRENCY_REQUIRED",
            "برای ثبت snapshot قیمت خرید، ارز پایه کسب‌وکار باید تعیین شده باشد",
            http_status=409,
        )
    policy = normalize_missing_purchase_price_policy(
        getattr(business, "invoice_profit_missing_purchase_price_policy", None)
    )
    lines = (
        db.query(InvoiceItemLine)
        .filter(InvoiceItemLine.document_id == int(document.id))
        .order_by(InvoiceItemLine.id.asc())
        .all()
    )
    products = {
        int(p.id): p
        for p in db.query(Product).filter(
            Product.business_id == int(document.business_id),
            Product.id.in_([int(x.product_id) for x in lines if x.product_id]),
        ).all()
    }
    captured = 0
    captured_at = datetime.utcnow()
    for line in lines:
        if document.document_type == "invoice_production" and (line.extra_info or {}).get("movement") != "out":
            continue
        if not overwrite and line.purchase_price_snapshot_unit_cost_base is not None:
            continue
        product = products.get(int(line.product_id))
        if product is None:
            raise ApiError("PRODUCT_NOT_FOUND", "محصول ردیف فاکتور یافت نشد", http_status=409)
        value, source, unit, factor = _snapshot_value_for_line(product, line, policy)
        line.purchase_price_snapshot_unit_cost_base = value
        line.purchase_price_snapshot_currency_id = int(business.default_currency_id)
        line.purchase_price_snapshot_unit = unit
        line.purchase_price_snapshot_factor = factor
        line.purchase_price_snapshot_source = source
        line.purchase_price_snapshot_at = captured_at
        captured += 1
    db.flush()
    return captured


def purchase_price_unit_cost_base_from_snapshot(
    line: Any,
    *,
    missing_policy: str,
    allow_legacy_ledger: bool = True,
    expected_base_currency_id: int | None = None,
) -> Decimal:
    raw = getattr(line, "purchase_price_snapshot_unit_cost_base", None)
    if raw is not None:
        snapshot_currency_id = getattr(line, "purchase_price_snapshot_currency_id", None)
        if expected_base_currency_id is not None and snapshot_currency_id is None:
            raise ApiError(
                "PURCHASE_PRICE_SNAPSHOT_CURRENCY_MISSING",
                "ارز snapshot قیمت خرید ثبت نشده است",
                http_status=409,
            )
        if (
            expected_base_currency_id is not None
            and int(snapshot_currency_id) != int(expected_base_currency_id)
        ):
            raise ApiError(
                "PURCHASE_PRICE_SNAPSHOT_CURRENCY_MISMATCH",
                "ارز snapshot قیمت خرید با ارز پایه فعلی کسب‌وکار یکسان نیست",
                http_status=409,
            )
        return Decimal(str(raw))
    if allow_legacy_ledger:
        legacy = getattr(line, "ledger_unit_cogs", None)
        if legacy is not None:
            return Decimal(str(legacy))
    return resolve_missing_purchase_price_unit_cost(line, missing_policy)


def preview_purchase_price_unit_cost_base(
    product: Product,
    line: Any,
    *,
    missing_policy: str,
) -> Decimal:
    if product.base_purchase_price is None:
        return resolve_missing_purchase_price_unit_cost(line, missing_policy)
    info = dict(getattr(line, "extra_info", None) or {})
    return price_main_to_line(product.base_purchase_price, product, info.get("unit"))
