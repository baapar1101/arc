"""
پارامترهای مشترک جست‌وجوی پیشرفته برای toolهای AI (فاز ۱۱).
هم‌تراز با QueryInfo در OpenAPI.
"""
from __future__ import annotations

from typing import Any, Dict, List, Optional

# یک FilterItem برای JSON Schema ابزارها
_FILTER_ITEM_SCHEMA = {
    "type": "object",
    "properties": {
        "property": {"type": "string", "description": "نام ستون/فیلد"},
        "operator": {
            "type": "string",
            "description": "عملگر: =, !=, >, >=, <, <=, *, *?, ?*, in, is_null, is_not_null",
        },
        "value": {"description": "مقدار؛ برای in آرایه باشد"},
    },
    "required": ["property", "operator"],
}

ADVANCED_LIST_QUERY_PROPERTIES: Dict[str, Any] = {
    "search": {
        "type": "string",
        "description": "جستجوی آزاد؛ با search_fields یا پیش‌فرض entity",
    },
    "search_fields": {
        "type": "array",
        "items": {"type": "string"},
        "description": "ستون‌های جستجو (اختیاری)",
    },
    "filters": {
        "type": "array",
        "items": _FILTER_ITEM_SCHEMA,
        "description": "فیلترهای ستونی؛ همه با AND. از list_queryable_fields(entity) راهنما بگیر.",
    },
    "from_date": {"type": "string", "format": "date", "description": "از تاریخ (اختیاری)"},
    "to_date": {"type": "string", "format": "date", "description": "تا تاریخ (اختیاری)"},
    "fiscal_year_id": {"type": "integer", "description": "شناسه سال مالی (اختیاری)"},
    "sort_by": {"type": "string", "description": "ستون مرتب‌سازی"},
    "sort_desc": {"type": "boolean", "description": "مرتب‌سازی نزولی"},
    "take": {"type": "integer", "description": "تعداد نتایج (پیش‌فرض ۵۰، حداکثر ۲۰۰)"},
    "skip": {"type": "integer", "description": "ردیف شروع (پیش‌فرض ۰)"},
}

COMMON_LIST_QUERY_PROPERTIES: Dict[str, Any] = dict(ADVANCED_LIST_QUERY_PROPERTIES)


def build_ai_list_query(
    kwargs: Dict[str, Any],
    *,
    entity: Optional[str] = None,
    extra_keys: Optional[List[str]] = None,
) -> Dict[str, Any]:
    """ساخت query dict برای سرویس list از kwargs ابزار AI."""
    from app.services.ai.ai_query_filter_service import merge_into_query_dict
    from app.services.ai.ai_query_service import _build_list_query

    raw = dict(kwargs or {})
    for k in extra_keys or []:
        if k in kwargs and kwargs[k] is not None:
            raw[k] = kwargs[k]
    merged = merge_into_query_dict(raw, entity=entity)
    return _build_list_query(merged, entity=entity)


def ai_list_parameters_schema(
    *,
    extra_properties: Optional[Dict[str, Any]] = None,
    required: Optional[List[str]] = None,
) -> Dict[str, Any]:
    """ساخت parameters_schema برای toolهای لیست."""
    props = dict(ADVANCED_LIST_QUERY_PROPERTIES)
    if extra_properties:
        props.update(extra_properties)
    return {
        "type": "object",
        "properties": props,
        "required": required or [],
    }
