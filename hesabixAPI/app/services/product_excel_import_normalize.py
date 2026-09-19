"""نرمال‌سازی ردیف ایمپورت کالا: سلول خالی، تطبیق نام، ارز، حالت موجودی."""
from __future__ import annotations

import re
from decimal import Decimal
from typing import Any, Dict, List, Optional, Sequence, Set, Tuple

from openpyxl.workbook.workbook import Workbook
from openpyxl.worksheet.worksheet import Worksheet
from pydantic import ValidationError
from sqlalchemy import and_, func
from sqlalchemy.orm import Session

from adapters.db.models.currency import BusinessCurrency, Currency
from adapters.db.models.product import Product
from app.core.responses import ApiError
from app.services.product_excel_import_spec import (
    CREATE_UPDATE_SCHEMA_KEYS,
    DATA_SHEET_NAMES,
    EXCEL_ONLY_RESOLVE_KEYS,
    HEADER_ALIASES,
    HELPER_KEYS,
    LOOKUP_SHEET_NAMES,
    SAMPLE_PRODUCT_CODE,
    SAMPLE_PRODUCT_NAMES,
    normalize_header,
)


def select_products_import_worksheet(wb: Workbook) -> Worksheet:
    """شیت داده را پیدا می‌کند و شیت راهنما/مراجع را نادیده می‌گیرد."""
    ranked: List[Tuple[int, Worksheet]] = []
    for ws in wb.worksheets:
        title_norm = normalize_header(ws.title)
        if title_norm in LOOKUP_SHEET_NAMES:
            continue
        rows = list(ws.iter_rows(min_row=1, max_row=1, values_only=True))
        headers = [normalize_header(h) for h in (rows[0] if rows else ())]
        mapped = {HEADER_ALIASES.get(h, h) for h in headers if h}
        score = 0
        if title_norm in DATA_SHEET_NAMES or title_norm == "template":
            score += 10
        if "name" in mapped:
            score += 5
        if "code" in mapped:
            score += 1
        if score:
            ranked.append((score, ws))
    if ranked:
        ranked.sort(key=lambda item: item[0], reverse=True)
        return ranked[0][1]
    return wb.active


def is_sample_import_row(item: Dict[str, Any]) -> bool:
    code = str(item.get("code") or "").strip()
    name = normalize_header(item.get("name"))
    description = str(item.get("description") or "")
    if code == SAMPLE_PRODUCT_CODE and name in SAMPLE_PRODUCT_NAMES:
        return True
    if "ردیف نمونه" in description or "sample row" in description.lower():
        return True
    return False


def collapse_spaces(value: object) -> str:
    if value is None:
        return ""
    s = str(value).replace("\u200c", " ")
    return " ".join(s.split()).strip()


def name_match_key(value: object) -> str:
    return collapse_spaces(value).casefold()


def parse_bool_strict(value: object) -> Optional[bool]:
    if value is None:
        return None
    if isinstance(value, bool):
        return value
    s = collapse_spaces(value).lower()
    if s == "":
        return None
    if s in ("true", "1", "yes", "on", "بله", "هست"):
        return True
    if s in ("false", "0", "no", "off", "خیر", "نیست"):
        return False
    raise ValueError("مقدار بله/خیر نامعتبر است")


def parse_inventory_mode(value: object) -> Optional[str]:
    s = collapse_spaces(value).lower().replace("ي", "ی")
    if not s:
        return None
    if s in ("bulk", "فله‌ای", "فله ای", "فله", "عمده"):
        return "bulk"
    if s in ("unique", "یونیک", "سریال", "سریالی"):
        return "unique"
    raise ValueError("حالت موجودی باید فله‌ای یا یونیک باشد")


def provided_keys_from_raw(item: Dict[str, Any]) -> Set[str]:
    out: Set[str] = set()
    for key, val in item.items():
        if key in HELPER_KEYS:
            continue
        if val is None:
            continue
        if isinstance(val, str) and val.strip() == "":
            continue
        out.add(key)
    return out


def drop_empty_values(item: Dict[str, Any]) -> None:
    for key, val in list(item.items()):
        if key in HELPER_KEYS:
            continue
        if val is None:
            item.pop(key, None)
            continue
        if isinstance(val, str) and val.strip() == "":
            item.pop(key, None)


def pop_non_schema_keys(item: Dict[str, Any]) -> None:
    for key in list(item.keys()):
        if key in HELPER_KEYS or key in EXCEL_ONLY_RESOLVE_KEYS:
            item.pop(key, None)
            continue
        if key not in CREATE_UPDATE_SCHEMA_KEYS:
            item.pop(key, None)


def build_create_payload(item: Dict[str, Any]) -> Dict[str, Any]:
    data = {k: v for k, v in item.items() if k not in HELPER_KEYS}
    pop_non_schema_keys(data)
    drop_empty_values(data)
    return data


def build_update_payload(item: Dict[str, Any], provided: Set[str]) -> Dict[str, Any]:
    data = {k: v for k, v in item.items() if k not in HELPER_KEYS}
    pop_non_schema_keys(data)
    # سلول خالی یعنی دست نزن — فقط کلیدهایی که کاربر مقدار داده
    schema_provided = (provided - EXCEL_ONLY_RESOLVE_KEYS - HELPER_KEYS) | (
        {"opening_balance"} if "opening_balance" in data else set()
    )
    if "category_path" in provided or "category" in provided:
        schema_provided.add("category_id")
    if "warehouse_code" in provided or "warehouse_name" in provided:
        schema_provided.add("default_warehouse_id")
    if "tax_type_code" in provided or "tax_type_title" in provided:
        schema_provided.add("tax_type_id")
    if "tax_unit_code" in provided or "tax_unit_name" in provided:
        schema_provided.add("tax_unit_id")
    if "attribute_titles" in provided:
        schema_provided.add("attribute_ids")
    if "price_fx_currency_code" in provided:
        schema_provided.add("price_fx_currency_id")
    return {k: v for k, v in data.items() if k in schema_provided and k in CREATE_UPDATE_SCHEMA_KEYS}


def format_pydantic_errors(exc: ValidationError) -> List[str]:
    out: List[str] = []
    try:
        for err in exc.errors():
            loc = ".".join(str(x) for x in err.get("loc", ()) if isinstance(x, (str, int)))
            msg = str(err.get("msg", "خطای اعتبارسنجی"))
            prefix = f"{loc}: " if loc else ""
            out.append(f"{prefix}{msg}")
    except Exception:
        out.append("خطای اعتبارسنجی داده کالا")
    return out


def api_error_message(exc: ApiError) -> str:
    detail = getattr(exc, "detail", None)
    if isinstance(detail, dict):
        err = detail.get("error")
        if isinstance(err, dict) and err.get("message"):
            return str(err["message"])
        if detail.get("message"):
            return str(detail["message"])
    return str(exc.detail if detail is not None else exc)


def find_existing_product(
    session: Session,
    business_id: int,
    match_by: str,
    data: Dict[str, Any],
) -> Tuple[Optional[Product], Optional[str]]:
    if match_by == "code":
        code = collapse_spaces(data.get("code"))
        if not code:
            return None, None
        found = (
            session.query(Product)
            .filter(and_(Product.business_id == business_id, Product.code == code))
            .first()
        )
        return found, None

    if match_by == "name":
        key = name_match_key(data.get("name"))
        if not key:
            return None, None
        rows = (
            session.query(Product)
            .filter(
                Product.business_id == business_id,
                func.lower(func.trim(Product.name)) == key,
            )
            .all()
        )
        if len(rows) > 1:
            return None, "چند کالا با این نام وجود دارد؛ برای به‌روزرسانی از تطبیق بر اساس کد استفاده کنید"
        if len(rows) == 1:
            return rows[0], None
        return None, None
    return None, None


def resolve_fx_currency(
    item: Dict[str, Any],
    db: Session,
    business_id: int,
    row_errors: List[str],
) -> None:
    currency_id = item.get("price_fx_currency_id")
    if isinstance(currency_id, int):
        exists = (
            db.query(BusinessCurrency.id)
            .filter(
                BusinessCurrency.business_id == business_id,
                BusinessCurrency.currency_id == currency_id,
            )
            .first()
        )
        if not exists:
            row_errors.append(f"ارز با شناسه {currency_id} برای این کسب‌وکار تعریف نشده است")
        return
    code = collapse_spaces(item.get("price_fx_currency_code"))
    if not code:
        return
    row = (
        db.query(Currency)
        .join(BusinessCurrency, BusinessCurrency.currency_id == Currency.id)
        .filter(
            BusinessCurrency.business_id == business_id,
            func.lower(Currency.code) == code.lower(),
        )
        .first()
    )
    if not row:
        row_errors.append(f"ارز با کد «{code}» برای این کسب‌وکار یافت نشد")
        return
    item["price_fx_currency_id"] = row.id


def map_headers(raw_headers: Sequence[object]) -> List[str]:
    mapped: List[str] = []
    for h in raw_headers:
        key = HEADER_ALIASES.get(normalize_header(h), normalize_header(h) if h else "")
        mapped.append(key)
    return mapped
