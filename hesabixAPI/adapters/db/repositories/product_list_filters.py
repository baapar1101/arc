"""فیلترهای ستونی لیست کالا — سازگار با عملگرهای استاندارد DataTable.

این ماژول جدا از product_repository نگه داشته می‌شود تا:
- وابستگی چرخشی با API/service ایجاد نشود
- تست واحد بدون بالا آوردن کل stack ممکن باشد
"""
from __future__ import annotations

import re
from typing import Any, List, Optional

from sqlalchemy import select, and_, or_, exists

from adapters.db.models.product import Product
from adapters.db.models.product_general_barcode_alias import ProductGeneralBarcodeAlias
from adapters.db.models.category import BusinessCategory

# فاصله، خط جدید، انواع خط تیره (بدون نیم‌فاصلهٔ ZWNJ که در فارسی پیوند واژه است)
_SEARCH_SPLIT_RE = re.compile(r"(?:\s+|(?:[\-‐‑–—])+)+")


def _search_query_tokens(search: str) -> List[str]:
    """جدا کردن عبارت جستجو به توکن‌های غیرخالی (فاصله، خط تیره و مشابه)."""
    s = str(search).strip()
    if not s:
        return []
    parts = [p for p in _SEARCH_SPLIT_RE.split(s) if p]
    if parts:
        return parts
    return [s]


def _like_escape(s: str) -> str:
    """ایمن‌سازی متن ورودی برای الگوهای ILIKE (PostgreSQL با escape '\\')."""
    return s.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")


def _column_contains_all_tokens(column, tokens: List[str]):
    """هر توکن باید به‌صورت زیررشته‌ای در مقدار ستون باشد (AND بین توکن‌ها)."""
    if not tokens:
        return True
    if len(tokens) == 1:
        return column.ilike(f"%{_like_escape(tokens[0])}%", escape="\\")
    return and_(*[column.ilike(f"%{_like_escape(t)}%", escape="\\") for t in tokens])


def _filter_parts(f: Any) -> tuple[Optional[str], Optional[str], Any]:
    """استخراج property/operator/value از dict یا FilterItem."""
    if isinstance(f, dict):
        field = f.get("property")
        operator = f.get("operator")
        value = f.get("value")
    else:
        field = getattr(f, "property", None)
        operator = getattr(f, "operator", None)
        value = getattr(f, "value", None)
    field_s = str(field).strip() if field is not None else None
    op_s = str(operator).strip() if operator is not None else None
    return field_s or None, op_s or None, value


def _as_str(value: Any) -> str:
    if value is None:
        return ""
    return str(value).strip()


def _text_condition(column, operator: str, value: Any):
    """
    شرط متنی سازگار با عملگرهای استاندارد DataTable / QueryBuilder:
    * contains | *? starts with | ?* ends with | = exact | in
    همچنین contains/ilike برای سازگاری با کلاینت‌های قدیمی.
    """
    op = (operator or "").strip()
    if op == "in":
        if isinstance(value, (list, tuple)):
            vals = [v for v in value if v is not None and str(v).strip() != ""]
            if vals:
                return column.in_(list(vals))
        return None

    text = _as_str(value)
    if text == "" and op != "=":
        return None
    esc = _like_escape(text)

    if op in {"*", "contains", "ilike"}:
        # contains قدیمی: چندتوکنی؛ * استاندارد DataTable: یک الگوی ILIKE
        if op in {"contains", "ilike"}:
            tokens = _search_query_tokens(text)
            if tokens:
                return _column_contains_all_tokens(column, tokens)
            return None
        return column.ilike(f"%{esc}%", escape="\\")
    if op == "*?":
        return column.ilike(f"{esc}%", escape="\\")
    if op == "?*":
        return column.ilike(f"%{esc}", escape="\\")
    if op == "=":
        return column == value if not isinstance(value, str) else column == text
    if op == "!=":
        return column != (text if isinstance(value, str) else value)
    return None


def _numeric_condition(column, operator: str, value: Any):
    """شرط عددی؛ برای * / *? / ?* روی نمایش متنی عدد هم جستجو می‌کند (UI عدد را متنی می‌فرستد)."""
    from decimal import Decimal, InvalidOperation
    from sqlalchemy import cast, String

    op = (operator or "").strip()
    if op in {"*", "*?", "?*", "contains", "ilike"}:
        return _text_condition(cast(column, String), op, value)

    if op == "in" and isinstance(value, (list, tuple)):
        nums = []
        for v in value:
            try:
                nums.append(Decimal(str(v).strip().replace(",", "")))
            except (InvalidOperation, ValueError, TypeError):
                continue
        if nums:
            return column.in_(nums)
        return None

    raw = _as_str(value).replace(",", "")
    if raw == "":
        return None
    try:
        num = Decimal(raw)
    except (InvalidOperation, ValueError):
        # اگر عدد نبود، به‌صورت متنی روی cast جستجو کن
        return _text_condition(cast(column, String), "*", value)

    if op == "=":
        return column == num
    if op == "!=":
        return column != num
    if op == ">":
        return column > num
    if op == ">=":
        return column >= num
    if op == "<":
        return column < num
    if op == "<=":
        return column <= num
    return None


def _parse_bool_filter_value(value: Any) -> Optional[bool]:
    s = _as_str(value).lower()
    if not s:
        return None
    if s in {"1", "true", "yes", "y", "بله", "آری", "اری"}:
        return True
    if s in {"0", "false", "no", "n", "خیر", "نه"}:
        return False
    # جستجوی جزئی روی برچسب‌های رایج UI
    labels_true = ("بله", "آری", "true", "yes")
    labels_false = ("خیر", "نه", "false", "no")
    if any(s in lab.lower() or lab.lower() in s for lab in labels_true):
        return True
    if any(s in lab.lower() or lab.lower() in s for lab in labels_false):
        return False
    return None


def _bool_condition(column, operator: str, value: Any):
    op = (operator or "").strip()
    if op == "in" and isinstance(value, (list, tuple)):
        flags = []
        for v in value:
            parsed = _parse_bool_filter_value(v)
            if parsed is not None:
                flags.append(parsed)
        if flags:
            return column.in_(list(set(flags)))
        return None
    parsed = _parse_bool_filter_value(value)
    if parsed is None:
        return None
    if op in {"=", "*", "contains", "ilike", "*?", "?*"}:
        return column.is_(parsed)
    if op == "!=":
        return column.is_(not parsed)
    return None


def _parse_item_type_filter_value(value: Any):
    """فقط تطبیق دقیق برای عملگر = (مقادیر API و برچسب enum)."""
    from adapters.db.models.product import ProductItemType

    s = _as_str(value)
    if not s:
        return None
    low = s.lower()
    if low in {"product", "کالا"} or s == ProductItemType.PRODUCT.value:
        return ProductItemType.PRODUCT
    if low in {"service", "خدمت"} or s == ProductItemType.SERVICE.value:
        return ProductItemType.SERVICE
    return None


def _item_type_condition(operator: str, value: Any):
    from adapters.db.models.product import ProductItemType
    from sqlalchemy import cast, String

    op = (operator or "").strip()
    if op == "in" and isinstance(value, (list, tuple)):
        types = []
        for v in value:
            parsed = _parse_item_type_filter_value(v)
            if parsed is not None:
                types.append(parsed)
        if types:
            return Product.item_type.in_(list(set(types)))
        return None

    if op == "=":
        parsed = _parse_item_type_filter_value(value)
        if parsed is not None:
            return Product.item_type == parsed
        return None

    if op == "!=":
        parsed = _parse_item_type_filter_value(value)
        if parsed is not None:
            return Product.item_type != parsed
        return None

    # contains / starts / ends روی مقدار نمایشی enum (کالا/خدمت) و aliasهای لاتین
    text = _as_str(value)
    if not text:
        return None
    # اگر کاربر product/service تایپ کرد، به برچسب فارسی map کن تا ILIKE روی enum درست کار کند
    mapped = _parse_item_type_filter_value(text)
    needle = mapped.value if mapped is not None else text
    return _text_condition(cast(Product.item_type, String), op, needle)


def _category_ids_from_value(value: Any) -> List[int]:
    raw_list = value if isinstance(value, (list, tuple)) else [value]
    out: List[int] = []
    for v in raw_list:
        if v is None or str(v).strip() == "":
            continue
        try:
            out.append(int(v))
        except (TypeError, ValueError):
            continue
    return out


def _apply_product_list_filters(stmt, filters: Any, *, business_id: int):
    """
    اعمال فیلترهای ستونی DataTable روی کوئری لیست کالا.
    فقط فیلدهای شناخته‌شدهٔ کالا؛ فیلدهای ناشناخته نادیده گرفته می‌شوند
    تا رفتار بقیهٔ سیستم/کلاینت‌ها مختل نشود.
    """
    from sqlalchemy import cast, String
    from adapters.db.models.warehouse import Warehouse

    if not filters:
        return stmt

    for f in filters:
        field, operator, value = _filter_parts(f)
        if not field or not operator:
            continue

        cond = None

        if field == "code":
            cond = _text_condition(Product.code, operator, value)
        elif field == "name":
            cond = _text_condition(Product.name, operator, value)
        elif field == "description":
            cond = _text_condition(Product.description, operator, value)
        elif field == "tax_code":
            cond = _text_condition(Product.tax_code, operator, value)
        elif field == "main_unit":
            cond = _text_condition(Product.main_unit, operator, value)
        elif field == "secondary_unit":
            cond = _text_condition(Product.secondary_unit, operator, value)
        elif field == "inventory_mode":
            cond = _text_condition(Product.inventory_mode, operator, value)
        elif field == "general_barcodes":
            text_cond = _text_condition(Product.general_barcodes, operator, value)
            # برای جستجوی متنی، ایندکس alias را هم در نظر بگیر
            text_val = _as_str(value)
            if text_val and operator in {"*", "contains", "ilike", "*?", "?*", "="}:
                esc = _like_escape(text_val)
                if operator == "=":
                    alias_cond = exists(
                        select(1).select_from(ProductGeneralBarcodeAlias).where(
                            ProductGeneralBarcodeAlias.product_id == Product.id,
                            ProductGeneralBarcodeAlias.business_id == business_id,
                            ProductGeneralBarcodeAlias.token_normalized == text_val.lower(),
                        )
                    )
                elif operator == "*?":
                    alias_cond = exists(
                        select(1).select_from(ProductGeneralBarcodeAlias).where(
                            ProductGeneralBarcodeAlias.product_id == Product.id,
                            ProductGeneralBarcodeAlias.business_id == business_id,
                            ProductGeneralBarcodeAlias.token_normalized.ilike(f"{esc}%", escape="\\"),
                        )
                    )
                elif operator == "?*":
                    alias_cond = exists(
                        select(1).select_from(ProductGeneralBarcodeAlias).where(
                            ProductGeneralBarcodeAlias.product_id == Product.id,
                            ProductGeneralBarcodeAlias.business_id == business_id,
                            ProductGeneralBarcodeAlias.token_normalized.ilike(f"%{esc}", escape="\\"),
                        )
                    )
                else:
                    alias_cond = exists(
                        select(1).select_from(ProductGeneralBarcodeAlias).where(
                            ProductGeneralBarcodeAlias.product_id == Product.id,
                            ProductGeneralBarcodeAlias.business_id == business_id,
                            ProductGeneralBarcodeAlias.token_normalized.ilike(f"%{esc}%", escape="\\"),
                        )
                    )
                if text_cond is not None:
                    cond = or_(text_cond, alias_cond)
                else:
                    cond = alias_cond
            else:
                cond = text_cond
        elif field == "item_type":
            cond = _item_type_condition(operator, value)
        elif field == "category_id":
            ids = _category_ids_from_value(value if operator == "in" else [value])
            if operator == "in" and ids:
                cond = Product.category_id.in_(ids)
            elif operator in {"=", "=="} and ids:
                cond = Product.category_id == ids[0]
            elif operator == "!=" and ids:
                cond = or_(Product.category_id.is_(None), Product.category_id.notin_(ids))
        elif field == "category_name":
            # فیلتر متنی روی عنوان دسته (فیلتر درختی از category_id استفاده می‌کند)
            cat_text = cast(BusinessCategory.title_translations, String)
            text_cond = _text_condition(cat_text, operator, value)
            if text_cond is not None:
                cond = exists(
                    select(1).select_from(BusinessCategory).where(
                        BusinessCategory.id == Product.category_id,
                        BusinessCategory.business_id == business_id,
                        text_cond,
                    )
                )
        elif field in {"default_warehouse_name", "default_warehouse_code"}:
            wh_col = Warehouse.name if field == "default_warehouse_name" else Warehouse.code
            text_cond = _text_condition(wh_col, operator, value)
            if text_cond is not None:
                cond = exists(
                    select(1).select_from(Warehouse).where(
                        Warehouse.id == Product.default_warehouse_id,
                        Warehouse.business_id == business_id,
                        text_cond,
                    )
                )
        elif field == "default_warehouse_id":
            try:
                wid = int(value) if not isinstance(value, (list, tuple)) else None
            except (TypeError, ValueError):
                wid = None
            if operator == "in" and isinstance(value, (list, tuple)):
                wids = _category_ids_from_value(value)
                if wids:
                    cond = Product.default_warehouse_id.in_(wids)
            elif operator in {"=", "=="} and wid is not None:
                cond = Product.default_warehouse_id == wid
        elif field in {
            "base_sales_price",
            "base_purchase_price",
            "reorder_point",
            "min_order_qty",
            "lead_time_days",
            "sales_tax_rate",
            "purchase_tax_rate",
            "unit_conversion_factor",
            "sales_price_fx",
            "purchase_price_fx",
        }:
            col = getattr(Product, field, None)
            if col is not None:
                cond = _numeric_condition(col, operator, value)
        elif field in {
            "track_inventory",
            "track_serial",
            "track_barcode",
            "is_active",
            "is_sales_taxable",
            "is_purchase_taxable",
            "is_public_catalog",
            "auto_update_base_from_fx",
        }:
            col = getattr(Product, field, None)
            if col is not None:
                cond = _bool_condition(col, operator, value)
        elif field in {"created_at", "updated_at"}:
            col = getattr(Product, field, None)
            if col is not None:
                # بازهٔ تاریخ از DataTable معمولاً با >= و < می‌آید
                if operator in {">=", ">", "<=", "<", "=", "!="}:
                    try:
                        if operator == ">=":
                            cond = col >= value
                        elif operator == ">":
                            cond = col > value
                        elif operator == "<=":
                            cond = col <= value
                        elif operator == "<":
                            cond = col < value
                        elif operator == "=":
                            cond = col == value
                        elif operator == "!=":
                            cond = col != value
                    except Exception:
                        cond = _text_condition(cast(col, String), "*", value)
                else:
                    cond = _text_condition(cast(col, String), operator, value)

        if cond is not None:
            stmt = stmt.where(cond)

    return stmt


