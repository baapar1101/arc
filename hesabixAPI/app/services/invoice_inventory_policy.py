"""تفکیک کالای دارای موجودی از خدمت / کالای بدون کنترل موجودی در ثبت دفتر کل."""
from __future__ import annotations

from typing import Any, Mapping, Optional

_SERVICE_ITEM_TYPES = frozenset({"خدمت", "service"})


def extra_info_mapping(extra: Any) -> Mapping[str, Any]:
    return extra if isinstance(extra, Mapping) else {}


def _truthy_inventory_flag(value: Any) -> Optional[bool]:
    if value is True or value == 1:
        return True
    if value is False or value == 0:
        return False
    if isinstance(value, str):
        raw = value.strip().lower()
        if raw in {"1", "true", "yes"}:
            return True
        if raw in {"0", "false", "no"}:
            return False
    return None


def _is_service_item_type(value: Any) -> bool:
    if value is None:
        return False
    raw = getattr(value, "value", value)
    return str(raw or "").strip().lower() in _SERVICE_ITEM_TYPES


def invoice_line_posts_to_inventory(extra: Any, product: Any = None) -> bool:
    """آیا این سطر باید موجودی کالا / GRNI / بهای تمام‌شده موجودی را لمس کند؟

    خدمت و کالای بدون کنترل موجودی به موجودی نمی‌روند.
    سطر سرمایه‌ای جداگانه به دارایی می‌رود.
    اگر پرچم ``inventory_tracked`` روی سطر نباشد، کالای دارای موجودی فرض می‌شود
    مگر این‌که خود محصول خدمت یا بدون موجودی باشد.
    """
    from app.services.fixed_asset_capital_purchase import is_capital_invoice_line

    info = extra_info_mapping(extra)
    if is_capital_invoice_line(info):
        return False
    if _is_service_item_type(info.get("item_type")):
        return False
    flag = _truthy_inventory_flag(info.get("inventory_tracked"))
    if flag is False:
        return False
    if flag is True:
        return True
    if product is not None:
        if _is_service_item_type(getattr(product, "item_type", None)):
            return False
        return bool(getattr(product, "track_inventory", False))
    return True
