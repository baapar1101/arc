"""Canonical invoice and inventory unit conversions.

Contract: ``Product.unit_conversion_factor`` is the number of secondary units
contained in one main unit. Example: main=carton, secondary=item, factor=20.

Inventory quantities are always computed in the product main unit.
Invoice lines keep the selected line-unit quantity in the database.
Warehouse lines written after this conversion layer store main-unit quantity
and set ``extra_info.inventory_quantity_unit = "main"`` so historical rows
without that flag can still be interpreted from ``extra_info.unit``.
"""

from __future__ import annotations

from decimal import Decimal
from typing import Any

from app.core.responses import ApiError

INVENTORY_QUANTITY_UNIT_MAIN = "main"
_MAIN_ALIASES = frozenset({"main", "primary", "main_unit"})
_SECONDARY_ALIASES = frozenset({"secondary", "sub", "alt", "secondary_unit"})


def _d(value: Any) -> Decimal:
    return Decimal(str(value if value is not None else 0))


def extra_info_dict(extra_info: Any) -> dict[str, Any]:
    return extra_info if isinstance(extra_info, dict) else {}


def _labels(product: Any) -> tuple[str | None, str | None]:
    if product is None:
        return None, None
    main = str(getattr(product, "main_unit", None) or "").strip() or None
    secondary = str(getattr(product, "secondary_unit", None) or "").strip() or None
    return main, secondary


def _factor(product: Any) -> Decimal:
    raw = getattr(product, "unit_conversion_factor", None) if product is not None else None
    factor = _d(raw)
    if factor <= 0:
        raise ApiError(
            "INVALID_UNIT_CONVERSION",
            "ضریب تبدیل واحد محصول باید بزرگ‌تر از صفر باشد",
            http_status=409,
        )
    return factor


def resolve_line_unit(product: Any, line_unit: str | None) -> str | None:
    """Map blank / main / secondary aliases onto the product's real unit label."""
    main, secondary = _labels(product)
    raw = str(line_unit or "").strip()
    if not raw:
        return main
    key = raw.lower()
    if key in _MAIN_ALIASES:
        return main
    if key in _SECONDARY_ALIASES:
        return secondary
    return raw


def is_secondary_line_unit(
    product: Any,
    line_unit: str | None,
    *,
    strict: bool = True,
) -> bool:
    main, secondary = _labels(product)
    selected = resolve_line_unit(product, line_unit)
    if selected is None or main is None or selected == main:
        return False
    if secondary is not None and selected == secondary:
        return True
    if strict:
        raise ApiError(
            "INVALID_LINE_UNIT",
            "واحد ردیف با واحد اصلی یا فرعی محصول مطابقت ندارد",
            http_status=409,
        )
    return False


def quantity_line_to_main(
    quantity: Any,
    product: Any,
    line_unit: str | None,
    *,
    strict: bool = True,
) -> Decimal:
    qty = _d(quantity)
    if product is None:
        return qty
    if is_secondary_line_unit(product, line_unit, strict=strict):
        return qty / _factor(product)
    return qty


def quantity_main_to_line(
    quantity_main: Any,
    product: Any,
    line_unit: str | None,
    *,
    strict: bool = True,
) -> Decimal:
    qty = _d(quantity_main)
    if product is None:
        return qty
    if is_secondary_line_unit(product, line_unit, strict=strict):
        return qty * _factor(product)
    return qty


def price_main_to_line(
    price_on_main: Any,
    product: Any,
    line_unit: str | None,
    *,
    strict: bool = True,
) -> Decimal:
    price = _d(price_on_main)
    if product is None:
        return price
    if is_secondary_line_unit(product, line_unit, strict=strict):
        return price / _factor(product)
    return price


def price_line_to_main(
    price_on_line: Any,
    product: Any,
    line_unit: str | None,
    *,
    strict: bool = True,
) -> Decimal:
    price = _d(price_on_line)
    if product is None:
        return price
    if is_secondary_line_unit(product, line_unit, strict=strict):
        return price * _factor(product)
    return price


def effective_line_unit(product: Any, line_unit: str | None) -> str | None:
    main, secondary = _labels(product)
    selected = resolve_line_unit(product, line_unit)
    if selected is None or selected == main:
        return main
    if secondary is not None and selected == secondary:
        return secondary
    raise ApiError(
        "INVALID_LINE_UNIT",
        "واحد ردیف با واحد اصلی یا فرعی محصول مطابقت ندارد",
        http_status=409,
    )


def payload_line_unit(line: dict[str, Any] | None, extra_info: Any = None) -> str | None:
    payload = line if isinstance(line, dict) else {}
    extra = extra_info_dict(extra_info if extra_info is not None else payload.get("extra_info"))
    raw = payload.get("unit")
    if raw is None:
        raw = extra.get("unit")
    if raw is None:
        return None
    text = str(raw).strip()
    return text or None


def inventory_quantity_is_already_main(extra_info: Any) -> bool:
    flag = str(extra_info_dict(extra_info).get("inventory_quantity_unit") or "").strip().lower()
    return flag in _MAIN_ALIASES


def inventory_quantity_to_main(
    quantity: Any,
    product: Any,
    extra_info: Any = None,
    line_unit: str | None = None,
    *,
    strict: bool = False,
) -> Decimal:
    """Convert a stored movement quantity into product main units.

    Warehouse rows stamped with ``inventory_quantity_unit=main`` are already
    main-unit quantities (including historical manual receipts with no unit).
    Invoice rows and legacy warehouse copies of invoice lines convert from
    ``extra_info.unit``.
    """
    if inventory_quantity_is_already_main(extra_info):
        return _d(quantity)
    unit = line_unit if line_unit is not None else extra_info_dict(extra_info).get("unit")
    return quantity_line_to_main(quantity, product, unit, strict=strict)


def inventory_price_to_main(
    price: Any,
    product: Any,
    extra_info: Any = None,
    line_unit: str | None = None,
    *,
    strict: bool = False,
) -> Decimal:
    if inventory_quantity_is_already_main(extra_info):
        return _d(price)
    unit = line_unit if line_unit is not None else extra_info_dict(extra_info).get("unit")
    return price_line_to_main(price, product, unit, strict=strict)


def stamp_inventory_quantity_as_main(
    extra_info: Any,
    product: Any,
    *,
    source_line_unit: str | None = None,
    source_line_quantity: Any = None,
) -> dict[str, Any]:
    """Mark a warehouse extra_info so later reads do not convert again."""
    extra = dict(extra_info_dict(extra_info))
    extra["inventory_quantity_unit"] = INVENTORY_QUANTITY_UNIT_MAIN
    main, _ = _labels(product)
    if source_line_unit:
        extra["source_line_unit"] = str(source_line_unit).strip()
    if source_line_quantity is not None:
        extra["source_line_quantity"] = float(_d(source_line_quantity))
    if main:
        extra["unit"] = main
    return extra


def warehouse_payload_quantity_to_main(
    product: Any,
    quantity: Any,
    extra_info: Any = None,
    line_unit: str | None = None,
) -> tuple[Decimal, dict[str, Any]]:
    """Convert an incoming warehouse line to main units and stamp extra_info."""
    extra = dict(extra_info_dict(extra_info))
    source_unit = line_unit if line_unit is not None else extra.get("unit")
    qty_main = inventory_quantity_to_main(
        quantity,
        product,
        extra,
        line_unit=source_unit,
        strict=True,
    )
    stamped = stamp_inventory_quantity_as_main(
        extra,
        product,
        source_line_unit=source_unit,
        source_line_quantity=quantity,
    )
    return qty_main, stamped
