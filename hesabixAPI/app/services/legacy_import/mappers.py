from __future__ import annotations

import json
import re
from datetime import date, datetime
from decimal import Decimal, InvalidOperation
from typing import Any, Dict, List, Optional, Tuple

import jdatetime

from adapters.api.v1.schemas import BusinessField, BusinessType
from app.services.legacy_import.constants import DEFAULT_LEGACY_PERSON_TYPE_ID_MAP


def normalize_server_url(url: str) -> str:
    raw = (url or "").strip()
    if not raw:
        from app.services.legacy_import.constants import DEFAULT_LEGACY_SERVER_URL

        return DEFAULT_LEGACY_SERVER_URL
    if not raw.startswith(("http://", "https://")):
        raw = f"https://{raw}"
    return raw.rstrip("/")


def split_person_name(name: str | None) -> Tuple[str | None, str | None]:
    if not name or not str(name).strip():
        return None, None
    parts = str(name).strip().split()
    if len(parts) == 1:
        return parts[0], None
    return parts[0], " ".join(parts[1:])


def person_alias(nikename: Any, name: Any) -> str:
    for val in (nikename, name):
        if val and str(val).strip():
            return str(val).strip()
    return "شخص بدون نام"


def map_legacy_person_types(
    type_ids: List[int] | None,
    *,
    type_id_to_label: Dict[int, str] | None = None,
) -> List[str]:
    mapping = type_id_to_label or DEFAULT_LEGACY_PERSON_TYPE_ID_MAP
    labels: List[str] = []
    for tid in type_ids or []:
        label = mapping.get(int(tid))
        if label and label not in labels:
            labels.append(label)
    if not labels:
        labels = ["مشتری"]
    return labels


def safe_int(value: Any, default: int | None = None) -> int | None:
    if value is None or value == "":
        return default
    try:
        iv = int(value)
        if iv > 2147483647 or iv < -2147483648:
            return default
        return iv
    except (TypeError, ValueError):
        return default


def safe_decimal(value: Any, default: Decimal = Decimal("0")) -> Decimal:
    if value is None or value == "":
        return default
    try:
        return Decimal(str(value).replace(",", ""))
    except (InvalidOperation, ValueError):
        return default


def parse_legacy_date(value: Any) -> date:
    """Parse Jalali YYYY/MM/DD, epoch seconds, or ISO date."""
    if isinstance(value, date) and not isinstance(value, datetime):
        return value
    if isinstance(value, datetime):
        return value.date()
    if value is None:
        return datetime.utcnow().date()

    s = str(value).strip()
    if not s:
        return datetime.utcnow().date()

    # Unix timestamp (legacy dateSubmit)
    if s.isdigit() and len(s) >= 9:
        try:
            return datetime.utcfromtimestamp(int(s)).date()
        except (OSError, ValueError, OverflowError):
            pass

    if len(s) == 10 and s.count("/") == 2:
        parts = s.split("/")
        try:
            y, m, d = int(parts[0]), int(parts[1]), int(parts[2])
            if y > 1500:
                return jdatetime.date(y, m, d).togregorian()
            return date(y, m, d)
        except (ValueError, jdatetime.JalaliDateError):
            pass

    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00")).date()
    except ValueError:
        return datetime.utcnow().date()


def epoch_to_date(value: Any) -> date | None:
    if value is None or value == "":
        return None
    try:
        return datetime.utcfromtimestamp(int(str(value).strip())).date()
    except (OSError, ValueError, OverflowError, TypeError):
        return None


def map_business_type(old_type: str | None) -> BusinessType:
    mapping = {
        "فروشگاه": BusinessType.STORE,
        "مغازه": BusinessType.SHOP,
        "شخصی": BusinessType.INDIVIDUAL,
        "شرکت": BusinessType.COMPANY,
        "موسسه": BusinessType.INSTITUTE,
        "باشگاه": BusinessType.CLUB,
        "اتحادیه": BusinessType.UNION,
    }
    if old_type and old_type in mapping:
        return mapping[old_type]
    return BusinessType.SHOP


def map_business_field(old_field: str | None) -> BusinessField:
    if not old_field:
        return BusinessField.OTHER
    low = old_field.lower().strip()
    if any(k in low for k in ("تولید", "ساخت")):
        return BusinessField.MANUFACTURING
    if any(k in low for k in ("بازرگانی", "فروش", "خرید", "تجارت")):
        return BusinessField.TRADING
    if any(k in low for k in ("خدمات", "خدماتی", "مشاوره", "آموزش")):
        return BusinessField.SERVICE
    return BusinessField.OTHER


def khadamat_to_item_type(khadamat: Any) -> str:
    if khadamat in (True, 1, "1", "true"):
        return "service"
    return "product"


def legacy_money_code_to_currency_query(code: str | None) -> str:
    c = (code or "IRR").strip().upper()
    return c if c else "IRR"


def sanitize_business_name(name: str, *, suffix: str = "") -> str:
    base = (name or "کسب‌وکار منتقل‌شده").strip()[:240]
    if suffix and suffix not in base:
        return f"{base}{suffix}"[:255]
    return base[:255]


def person_types_json(types: List[str]) -> str:
    return json.dumps(types, ensure_ascii=False)


def extract_archive_counts(data_files: Dict[str, list]) -> Dict[str, int]:
    return {
        "persons": len(data_files.get("persons.json") or []),
        "commodities": len(data_files.get("commodities.json") or []),
        "documents": len(data_files.get("hesabdari_docs.json") or []),
        "document_rows": len(data_files.get("hesabdari_rows.json") or []),
        "storerooms": len(data_files.get("storerooms.json") or []),
        "bank_accounts": len(data_files.get("bank_accounts.json") or []),
        "fiscal_years": len(data_files.get("years.json") or []),
    }


def mask_api_key(key: str) -> str:
    k = (key or "").strip()
    if len(k) <= 8:
        return "****"
    return f"{k[:4]}...{k[-4:]}"
