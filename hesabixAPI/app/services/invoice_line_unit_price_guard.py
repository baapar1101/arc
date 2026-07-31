"""اعتبارسنجی قیمت واحد ردیف‌های فاکتور وقتی مجوز «تغییر فی دستی» غیرفعال است."""

from __future__ import annotations

from decimal import Decimal, ROUND_HALF_UP
from typing import Any, Dict, List, Optional

from sqlalchemy import select
from sqlalchemy.orm import Session

from adapters.db.models.price_list import PriceItem, PriceList
from adapters.db.models.product import Product, ProductItemType
from app.core.responses import ApiError
from app.services.currency_quant import get_currency_quant_and_round

# انواع فاکتوری که قیمت‌گذاری از کالا/لیست قیمت قابل کنترل است (نه تولید/ضایعات/مصرف مستقیم)
_INVOICE_TYPES_UNIT_PRICE_LOCK = frozenset(
    {
        "invoice_sales",
        "invoice_sales_return",
        "invoice_purchase",
        "invoice_purchase_return",
    }
)


def _dec(value: Any) -> Decimal:
    try:
        return Decimal(str(value if value is not None else 0))
    except Exception:
        return Decimal(0)


def _quantize_money(value: Decimal, quant: Decimal = Decimal("0.01")) -> Decimal:
    return value.quantize(quant, rounding=ROUND_HALF_UP)


def _convert_main_unit_price_to_line_unit(
    price_on_main: Decimal,
    product: Product,
    selected_unit: Optional[str],
    quant: Decimal,
) -> Decimal:
    """هم‌تراز با منطق Flutter: قیمت روی واحد اصلی → قیمت روی واحد انتخاب‌شده."""
    main_u = (product.main_unit or "").strip() or None
    sec_u = (product.secondary_unit or "").strip() or None
    factor = _dec(product.unit_conversion_factor)
    if factor <= 0:
        factor = Decimal(1)
    sel = (selected_unit or "").strip() or None
    if not sel:
        sel = main_u
    is_main = main_u is None or sel is None or sel == main_u
    if is_main:
        return _quantize_money(price_on_main, quant)
    if sec_u and sel == sec_u:
        return _quantize_money(price_on_main * factor, quant)
    return _quantize_money(price_on_main, quant)


def _base_price_on_main_for_invoice(product: Product, invoice_type: str) -> Decimal:
    if invoice_type in ("invoice_sales", "invoice_sales_return"):
        return _dec(product.base_sales_price)
    return _dec(product.base_purchase_price)


def _fx_price_on_main_for_invoice(
    product: Product,
    invoice_type: str,
    currency_id: int,
) -> Optional[Decimal]:
    """اگر ارز فاکتور با ارز قیمت ارزی کالا یکی باشد، قیمت ارزی خرید/فروش را برگردان."""
    fx_cur = getattr(product, "price_fx_currency_id", None)
    if fx_cur is None or int(fx_cur) != int(currency_id):
        return None
    if invoice_type in ("invoice_sales", "invoice_sales_return"):
        raw = getattr(product, "sales_price_fx", None)
    else:
        raw = getattr(product, "purchase_price_fx", None)
    if raw is None:
        return None
    return _dec(raw)


def _collect_allowed_unit_prices(
    db: Session,
    business_id: int,
    product: Product,
    invoice_type: str,
    currency_id: int,
    selected_unit: Optional[str],
    quant: Decimal,
    *,
    default_currency_id: Optional[int] = None,
) -> List[Decimal]:
    prices: List[Decimal] = []
    fx_main = _fx_price_on_main_for_invoice(product, invoice_type, currency_id)
    if fx_main is not None:
        prices.append(_convert_main_unit_price_to_line_unit(fx_main, product, selected_unit, quant))

    # قیمت پایه روی ارز پیش‌فرض کسب‌وکار است؛ فقط همان ارز را مجاز کن
    if default_currency_id is None or int(currency_id) == int(default_currency_id):
        base_main = _base_price_on_main_for_invoice(product, invoice_type)
        prices.append(_convert_main_unit_price_to_line_unit(base_main, product, selected_unit, quant))

    stmt = (
        select(PriceItem.price)
        .join(PriceList, PriceItem.price_list_id == PriceList.id)
        .where(
            PriceList.business_id == business_id,
            PriceItem.product_id == product.id,
            PriceItem.currency_id == int(currency_id),
            PriceItem.unit_id.is_(None),
        )
    )
    for (raw_price,) in db.execute(stmt).all():
        p_main = _dec(raw_price)
        prices.append(_convert_main_unit_price_to_line_unit(p_main, product, selected_unit, quant))

    uniq: List[Decimal] = []
    seen: set[str] = set()
    for p in prices:
        q = _quantize_money(p, quant)
        key = str(q)
        if key not in seen:
            seen.add(key)
            uniq.append(q)
    return uniq


def _price_matches_any(
    actual: Decimal,
    candidates: List[Decimal],
    quant: Decimal,
    tol: Optional[Decimal] = None,
) -> bool:
    if tol is None:
        # نیم واحد کوچک‌تر از دقت ارز
        tol = quant / Decimal(2) if quant > 0 else Decimal("0.015")
        if tol < Decimal("0.00000001"):
            tol = Decimal("0.015")
    a = _quantize_money(actual, quant)
    for c in candidates:
        if abs(a - c) <= tol:
            return True
    return False


def validate_invoice_lines_unit_price_policy(
    db: Session,
    business_id: int,
    invoice_type: str,
    currency_id: int,
    lines_input: List[Dict[str, Any]],
    user_can_change_unit_price: bool,
) -> None:
    """اگر user_can_change_unit_price نباشد، unit_price هر ردیف باید با قیمت پایه، ارزی کالا یا لیست قیمت هم‌خوان باشد."""
    if user_can_change_unit_price:
        return
    if invoice_type not in _INVOICE_TYPES_UNIT_PRICE_LOCK:
        return

    quant, _round_on = get_currency_quant_and_round(db, currency_id)
    default_currency_id: Optional[int] = None
    try:
        from adapters.db.models.business import Business

        biz = db.get(Business, int(business_id))
        if biz is not None and getattr(biz, "default_currency_id", None) is not None:
            default_currency_id = int(biz.default_currency_id)
    except Exception:
        default_currency_id = None

    for idx, line in enumerate(lines_input, start=1):
        pid = line.get("product_id")
        if not pid:
            continue
        product = db.get(Product, int(pid))
        if not product or int(product.business_id) != int(business_id):
            raise ApiError("INVALID_LINE", f"ردیف {idx}: کالا معتبر نیست", http_status=400)
        if product.item_type == ProductItemType.SERVICE:
            continue

        extra = dict(line.get("extra_info") or {})
        submitted = _quantize_money(_dec(extra.get("unit_price")), quant)
        unit_raw = extra.get("unit")
        unit_str = unit_raw.strip() if isinstance(unit_raw, str) else None
        if unit_str == "":
            unit_str = None

        allowed = _collect_allowed_unit_prices(
            db,
            business_id,
            product,
            invoice_type,
            currency_id,
            unit_str,
            quant,
            default_currency_id=default_currency_id,
        )
        if not allowed:
            allowed = [Decimal("0")]
        if not _price_matches_any(submitted, allowed, quant):
            pname = product.name or str(product.id)
            raise ApiError(
                "INVOICE_UNIT_PRICE_LOCKED",
                f"ردیف {idx} ({pname}): بدون مجوز «تغییر فی دستی در فاکتور» فقط قیمت تعریف‌شده در کالا یا لیست قیمت مجاز است.",
                http_status=403,
            )
