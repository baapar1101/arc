from __future__ import annotations

from typing import Any, Dict, Mapping, Optional

DISPLAY_SMART = "smart"
DISPLAY_ALWAYS = "always"
DISPLAY_NEVER = "never"

VALID_DISPLAY_MODES = frozenset({DISPLAY_SMART, DISPLAY_ALWAYS, DISPLAY_NEVER})

TAX_DISCOUNT_DISPLAY_SETTING_KEYS = (
    "line_discount_display",
    "line_tax_display",
    "line_amount_before_discount_display",
    "line_amount_before_tax_display",
    "summary_discount_display",
    "summary_tax_display",
    "summary_amount_without_tax_display",
)

DEFAULT_TAX_DISCOUNT_DISPLAY_SETTINGS: Dict[str, str] = {
    key: DISPLAY_SMART for key in TAX_DISCOUNT_DISPLAY_SETTING_KEYS
}


def normalize_display_mode(value: Any, default: str = DISPLAY_SMART) -> str:
    if value is None:
        return default if default in VALID_DISPLAY_MODES else DISPLAY_SMART
    mode = str(value).strip().lower()
    if mode in VALID_DISPLAY_MODES:
        return mode
    return default if default in VALID_DISPLAY_MODES else DISPLAY_SMART


def resolve_display(mode: Any, has_data: bool) -> bool:
    normalized = normalize_display_mode(mode)
    if normalized == DISPLAY_NEVER:
        return False
    if normalized == DISPLAY_ALWAYS:
        return True
    return bool(has_data)


def _is_nonzero(value: Any) -> bool:
    try:
        return float(value or 0) != 0.0
    except (TypeError, ValueError):
        return False


def tax_discount_settings_from_print_settings(
    print_settings: Optional[Mapping[str, Any]],
) -> Dict[str, str]:
    src = print_settings or {}
    return {
        key: normalize_display_mode(src.get(key), DISPLAY_SMART)
        for key in TAX_DISCOUNT_DISPLAY_SETTING_KEYS
    }


def build_invoice_tax_discount_display_flags(
    print_settings: Optional[Mapping[str, Any]],
    *,
    has_line_discount: bool,
    has_line_tax: bool,
    discount_total: Any = None,
    tax_total: Any = None,
    amount_without_tax: Any = None,
    subtotal: Any = None,
) -> Dict[str, Any]:
    settings = tax_discount_settings_from_print_settings(print_settings)

    has_summary_discount = _is_nonzero(discount_total)
    has_summary_tax = _is_nonzero(tax_total)
    has_summary_amount_without_tax = has_summary_discount or has_summary_tax
    if not has_summary_amount_without_tax and amount_without_tax is not None and subtotal is not None:
        try:
            has_summary_amount_without_tax = abs(
                float(amount_without_tax) - float(subtotal or 0)
            ) > 0.0001
        except (TypeError, ValueError):
            has_summary_amount_without_tax = False

    def _flag(setting_key: str, has_data: bool) -> bool:
        return resolve_display(settings.get(setting_key), has_data)

    return {
        "show_line_discount_column": _flag("line_discount_display", has_line_discount),
        "show_line_tax_column": _flag("line_tax_display", has_line_tax),
        "show_line_amount_before_discount_column": _flag(
            "line_amount_before_discount_display", has_line_discount
        ),
        "show_line_amount_before_tax_column": _flag(
            "line_amount_before_tax_display", has_line_tax
        ),
        "show_summary_discount": _flag("summary_discount_display", has_summary_discount),
        "show_summary_tax": _flag("summary_tax_display", has_summary_tax),
        "show_summary_amount_without_tax": _flag(
            "summary_amount_without_tax_display", has_summary_amount_without_tax
        ),
        # سازگاری با قالب‌های قدیمی
        "has_line_discount": has_line_discount,
        "has_line_tax": has_line_tax,
    }


def enrich_line_amount_fields(line: Dict[str, Any]) -> Dict[str, Any]:
    """مقادیر مشتق‌شده برای ستون‌های جدول اقلام در قالب‌های سفارشی."""
    out = dict(line)
    try:
        line_total = float(out.get("line_total") or 0)
        discount = float(out.get("discount") or 0)
        tax_amount = float(out.get("tax_amount") or 0)
    except (TypeError, ValueError):
        line_total = 0.0
        discount = 0.0
        tax_amount = 0.0
    out["amount_before_discount"] = line_total + discount - tax_amount
    out["amount_before_tax"] = line_total - tax_amount
    return out
