"""Canonical invoice unit conversions.

Contract: ``Product.unit_conversion_factor`` is the number of secondary units
contained in one main unit. Example: main=carton, secondary=item, factor=20.
"""

from __future__ import annotations

from decimal import Decimal
from typing import Any

from app.core.responses import ApiError


def _d(value: Any) -> Decimal:
    return Decimal(str(value if value is not None else 0))


def _labels(product: Any) -> tuple[str | None, str | None]:
    main = str(getattr(product, "main_unit", None) or "").strip() or None
    secondary = str(getattr(product, "secondary_unit", None) or "").strip() or None
    return main, secondary


def _factor(product: Any) -> Decimal:
    raw = getattr(product, "unit_conversion_factor", None)
    factor = _d(raw)
    if factor <= 0:
        raise ApiError(
            "INVALID_UNIT_CONVERSION",
            "ضریب تبدیل واحد محصول باید بزرگ‌تر از صفر باشد",
            http_status=409,
        )
    return factor


def is_secondary_line_unit(product: Any, line_unit: str | None) -> bool:
    main, secondary = _labels(product)
    selected = str(line_unit or "").strip() or main
    if selected is None or main is None or selected == main:
        return False
    if secondary is not None and selected == secondary:
        return True
    raise ApiError(
        "INVALID_LINE_UNIT",
        "واحد ردیف با واحد اصلی یا فرعی محصول مطابقت ندارد",
        http_status=409,
    )


def quantity_line_to_main(quantity: Any, product: Any, line_unit: str | None) -> Decimal:
    qty = _d(quantity)
    if is_secondary_line_unit(product, line_unit):
        return qty / _factor(product)
    return qty


def price_main_to_line(price_on_main: Any, product: Any, line_unit: str | None) -> Decimal:
    price = _d(price_on_main)
    if is_secondary_line_unit(product, line_unit):
        return price / _factor(product)
    return price


def price_line_to_main(price_on_line: Any, product: Any, line_unit: str | None) -> Decimal:
    price = _d(price_on_line)
    if is_secondary_line_unit(product, line_unit):
        return price * _factor(product)
    return price


def effective_line_unit(product: Any, line_unit: str | None) -> str | None:
    main, secondary = _labels(product)
    selected = str(line_unit or "").strip() or main
    if selected is None or selected == main:
        return main
    if secondary is not None and selected == secondary:
        return secondary
    raise ApiError(
        "INVALID_LINE_UNIT",
        "واحد ردیف با واحد اصلی یا فرعی محصول مطابقت ندارد",
        http_status=409,
    )
