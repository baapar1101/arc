from __future__ import annotations

from typing import Any, Dict, Mapping, Optional, Tuple

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

_TAX_MODE_RECALC = "recalculate_tax_proportional"


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


def _as_float(value: Any, default: float = 0.0) -> float:
    try:
        if value is None:
            return default
        return float(value)
    except (TypeError, ValueError):
        return default


def format_smart_number(value: Any, *, max_decimals: int = 2) -> str:
    """عدد با جداکننده هزارگان؛ صفرهای اعشاری اضافی حذف می‌شوند."""
    try:
        n = float(value if value is not None else 0)
    except (TypeError, ValueError):
        return "" if value is None else str(value)
    if abs(n - round(n)) < 1e-9:
        return f"{int(round(n)):,}"
    s = f"{n:,.{max_decimals}f}"
    if "." in s:
        s = s.rstrip("0").rstrip(".")
    return s


def parse_discount_meta(
    source: Optional[Mapping[str, Any]],
) -> Tuple[Optional[str], Optional[float]]:
    """خواندن discount_type / discount_value از dict سطر یا extra_info."""
    if not isinstance(source, Mapping):
        return None, None
    raw_type = source.get("discount_type")
    dtype = str(raw_type).strip().lower() if raw_type is not None else None
    if dtype not in ("percent", "amount"):
        dtype = None
    raw_value = source.get("discount_value")
    if raw_value is None:
        return dtype, None
    try:
        dval = float(raw_value)
    except (TypeError, ValueError):
        return dtype, None
    return dtype, dval


def format_line_discount_display(
    amount: Any,
    discount_type: Any = None,
    discount_value: Any = None,
    *,
    is_fa: bool = True,
) -> str:
    """
    متن نمایش تخفیف سطری برای پرینت.
    درصدی: «۱۲٪ (۱٬۲۰۰)» ؛ مبلغی: فقط مبلغ.
    """
    amt = _as_float(amount, 0.0)
    dtype = str(discount_type or "").strip().lower()
    try:
        dval = float(discount_value) if discount_value is not None else None
    except (TypeError, ValueError):
        dval = None

    amount_text = format_smart_number(amt)
    if dtype == "percent" and dval is not None and dval != 0:
        pct_text = format_smart_number(dval)
        if is_fa:
            return f"{pct_text}٪ ({amount_text})"
        return f"{pct_text}% ({amount_text})"
    return amount_text


def should_restore_line_amounts_before_global(
    global_discount: Optional[Mapping[str, Any]],
) -> bool:
    """
    وقتی تخفیف کلی با حالت مالیات متناسب روی سطرها پخش شده،
    برای پرینت مبالغ سطر را به حالت قبل از تخفیف کلی برمی‌گردانیم
    تا کاربر حس نکند تخفیف کلی روی فیلد تخفیف سطری نشسته است.
    """
    if not isinstance(global_discount, Mapping):
        return False
    if not _is_nonzero(global_discount.get("amount")):
        return False
    tax_mode = str(global_discount.get("tax_mode") or _TAX_MODE_RECALC).strip().lower()
    if tax_mode == "keep_line_taxes":
        return False
    # پیش‌فرض سرویس تخفیف کلی: recalculate_tax_proportional
    return True


def line_amounts_before_global_discount(
    *,
    quantity: Any,
    unit_price: Any,
    line_discount: Any,
    tax_rate: Any,
) -> Dict[str, float]:
    """محاسبهٔ tax_amount و line_total قبل از تخصیص تخفیف کلی (فقط برای نمایش)."""
    qty = _as_float(quantity, 0.0)
    up = _as_float(unit_price, 0.0)
    disc = _as_float(line_discount, 0.0)
    rate = _as_float(tax_rate, 0.0)
    taxable = qty * up - disc
    if taxable < 0:
        taxable = 0.0
    tax_amount = (taxable * rate / 100.0) if rate > 0 and taxable > 0 else 0.0
    return {
        "taxable": taxable,
        "tax_amount": tax_amount,
        "line_total": taxable + tax_amount,
    }


def build_global_discount_print_info(
    extra_info: Optional[Mapping[str, Any]],
    *,
    line_discount_total: Any = 0,
    is_fa: bool = True,
) -> Dict[str, Any]:
    """فیلدهای نمایش تخفیف کلی و تفکیک از تخفیف سطری برای قالب پرینت."""
    extra = extra_info if isinstance(extra_info, Mapping) else {}
    gd_raw = extra.get("global_discount")
    gd = gd_raw if isinstance(gd_raw, Mapping) else {}

    g_type = str(gd.get("type") or "").strip().lower()
    if g_type not in ("percent", "amount"):
        g_type = None
    g_value = _as_float(gd.get("value"), 0.0) if gd.get("value") is not None else None
    g_amount = _as_float(gd.get("amount"), 0.0)
    if g_amount <= 0 and g_type == "amount" and g_value is not None:
        g_amount = float(g_value)

    line_disc = _as_float(line_discount_total, 0.0)
    totals = extra.get("totals") if isinstance(extra.get("totals"), Mapping) else {}
    discount_total = _as_float(totals.get("discount"), line_disc + max(g_amount, 0.0))

    has_global = g_amount > 0 or (g_type == "percent" and (g_value or 0) > 0)
    has_line = line_disc > 0
    show_breakdown = has_global and has_line

    global_display = ""
    if has_global:
        amount_text = format_smart_number(g_amount)
        if g_type == "percent" and g_value is not None:
            pct_text = format_smart_number(g_value)
            if is_fa:
                global_display = f"{pct_text}٪ ({amount_text})"
            else:
                global_display = f"{pct_text}% ({amount_text})"
        else:
            global_display = amount_text

    if show_breakdown:
        if is_fa:
            summary_label = "تخفیف (جمع)"
            line_label = "تخفیف سطری"
            global_label = "تخفیف کلی"
        else:
            summary_label = "Discount (total)"
            line_label = "Line discount"
            global_label = "Invoice discount"
    elif has_global:
        if is_fa:
            summary_label = "تخفیف کلی"
            line_label = "تخفیف سطری"
            global_label = "تخفیف کلی"
        else:
            summary_label = "Invoice discount"
            line_label = "Line discount"
            global_label = "Invoice discount"
    else:
        if is_fa:
            summary_label = "تخفیف"
            line_label = "تخفیف"
            global_label = "تخفیف کلی"
        else:
            summary_label = "Discount"
            line_label = "Discount"
            global_label = "Invoice discount"

    summary_display = format_smart_number(discount_total)
    if has_global and not has_line and global_display:
        summary_display = global_display

    return {
        "has_global_discount": bool(has_global),
        "has_line_discount_total": bool(has_line),
        "show_discount_breakdown": bool(show_breakdown),
        "global_discount_type": g_type,
        "global_discount_value": g_value,
        "global_discount_amount": g_amount if has_global else 0.0,
        "global_discount_tax_mode": str(gd.get("tax_mode") or "") or None,
        "global_discount_display": global_display,
        "line_discount_total": line_disc,
        "discount_total": discount_total,
        "discount_summary_label": summary_label,
        "discount_line_label": line_label,
        "discount_global_label": global_label,
        "discount_summary_display": summary_display,
        "restore_line_amounts_before_global": should_restore_line_amounts_before_global(gd)
        if has_global
        else False,
        "raw": dict(gd) if gd else None,
    }


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
    if (
        not has_summary_amount_without_tax
        and amount_without_tax is not None
        and subtotal is not None
    ):
        try:
            has_summary_amount_without_tax = (
                abs(float(amount_without_tax) - float(subtotal or 0)) > 0.0001
            )
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


def enrich_line_amount_fields(
    line: Dict[str, Any],
    *,
    is_fa: bool = True,
) -> Dict[str, Any]:
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

    dtype = out.get("discount_type")
    dval = out.get("discount_value")
    if dtype is None or dval is None:
        parsed_type, parsed_value = parse_discount_meta(out)
        if dtype is None and parsed_type is not None:
            dtype = parsed_type
            out["discount_type"] = dtype
        if dval is None and parsed_value is not None:
            dval = parsed_value
            out["discount_value"] = dval

    out["discount_display"] = format_line_discount_display(
        discount,
        dtype,
        dval,
        is_fa=is_fa,
    )
    return out
