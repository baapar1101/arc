"""
نرمال‌سازی و اعتبارسنجی filters/search برای ابزارهای AI.
"""
from __future__ import annotations

from typing import Any, Dict, List, Optional

from app.services.ai.ai_query_filter_catalog import (
    STANDARD_OPERATORS,
    get_entity_query_spec,
)

_MAX_FILTER_ITEMS = 12
_ALLOWED_OPS = frozenset(STANDARD_OPERATORS) | frozenset({"is_null", "is_not_null", "not_in"})


def normalize_filter_items(
    raw_filters: Any,
    *,
    entity: Optional[str] = None,
) -> List[Dict[str, Any]]:
    """تبدیل filters ورودی AI به لیست dict استاندارد FilterItem."""
    if not raw_filters:
        return []
    if not isinstance(raw_filters, list):
        raise ValueError("filters باید آرایه‌ای از {property, operator, value} باشد")

    spec = get_entity_query_spec(entity) if entity else None
    allowed_props = (
        {f.property for f in spec.filterable_fields} if spec else None
    )

    out: List[Dict[str, Any]] = []
    for i, item in enumerate(raw_filters[:_MAX_FILTER_ITEMS]):
        if not isinstance(item, dict):
            raise ValueError(f"filters[{i}] باید object باشد")
        prop = str(item.get("property") or "").strip()
        op = str(item.get("operator") or "").strip()
        if not prop or not op:
            raise ValueError(f"filters[{i}]: property و operator الزامی است")
        if op not in _ALLOWED_OPS:
            raise ValueError(
                f"عملگر نامعتبر: {op}. مجاز: {', '.join(sorted(_ALLOWED_OPS))}"
            )
        if allowed_props is not None and prop not in allowed_props:
            raise ValueError(
                f"فیلتر '{prop}' برای entity '{entity}' مجاز نیست. "
                f"از list_queryable_fields کمک بگیرید."
            )
        out.append({"property": prop, "operator": op, "value": item.get("value")})
    return out


def merge_into_query_dict(
    filters: Dict[str, Any],
    *,
    entity: Optional[str] = None,
) -> Dict[str, Any]:
    """
    غنی‌سازی dict فیلتر AI برای ارسال به سرویس‌های list:
    - forward filters[], search_fields, sort
    - نرمال‌سازی advanced filters
    """
    q = dict(filters or {})
    if "filters" in q and q["filters"] is not None:
        q["filters"] = normalize_filter_items(q["filters"], entity=entity)

    if q.get("search") and not q.get("search_fields"):
        spec = get_entity_query_spec(entity) if entity else None
        if spec:
            q["search_fields"] = list(spec.search_fields_default)

    if q.get("sort") and isinstance(q["sort"], list):
        pass  # multi-sort — سرویس‌های پشتیبان
    return q


def entity_query_schema_for_ai(entity: str) -> Dict[str, Any]:
    """خروجی list_queryable_fields."""
    spec = get_entity_query_spec(entity)
    if not spec:
        raise ValueError(f"entity '{entity}' در کاتالوگ جستجوی پیشرفته نیست")
    return {
        "entity": spec.entity,
        "label_fa": spec.label_fa,
        "search_fields_default": list(spec.search_fields_default),
        "flat_filters": list(spec.flat_filters),
        "operators": list(STANDARD_OPERATORS),
        "filterable_fields": [
            {
                "property": f.property,
                "label_fa": f.label_fa,
                "type": f.type,
                "operators": list(f.operators),
                "enum_values": list(f.enum_values) if f.enum_values else None,
                "notes": f.notes or None,
            }
            for f in spec.filterable_fields
        ],
        "example": {
            "search": "علی",
            "search_fields": list(spec.search_fields_default[:3]),
            "filters": [
                {"property": spec.filterable_fields[0].property, "operator": "*", "value": "نمونه"},
            ],
            "take": 20,
            "skip": 0,
        },
    }
