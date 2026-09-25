"""
پارامترهای مشترک جست‌وجوی پیشرفته برای toolهای AI (فاز ۱۱).
هم‌تراز با QueryInfo در OpenAPI.
"""
from __future__ import annotations

from typing import Any, Dict, List, Optional

from app.core.calendar import CalendarType
from app.services.ai.ai_constants import AI_LIST_TAKE_DEFAULT, AI_LIST_TAKE_MAX

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
    "from_date": {
        "type": "string",
        "format": "date",
        "description": "از تاریخ — ISO میلادی YYYY-MM-DD یا شمسی YYYY/MM/DD؛ برای عبارات نسبی از resolve_date_range استفاده کن",
    },
    "to_date": {
        "type": "string",
        "format": "date",
        "description": "تا تاریخ — ISO میلادی YYYY-MM-DD یا شمسی YYYY/MM/DD",
    },
    "fiscal_year_id": {"type": "integer", "description": "شناسه سال مالی (اختیاری)"},
    "sort_by": {"type": "string", "description": "ستون مرتب‌سازی"},
    "sort_desc": {"type": "boolean", "description": "مرتب‌سازی نزولی"},
    "take": {
        "type": "integer",
        "description": "تعداد نتایج (پیش‌فرض ۵۰، حداکثر ۱۰۰ — بیشتر نفرست)",
        "minimum": 1,
        "maximum": 100,
    },
    "skip": {"type": "integer", "description": "ردیف شروع (پیش‌فرض ۰)"},
}

COMMON_LIST_QUERY_PROPERTIES: Dict[str, Any] = dict(ADVANCED_LIST_QUERY_PROPERTIES)


def _clamp_take_in_dict(raw: Dict[str, Any]) -> None:
    for key in ("take", "limit"):
        if key not in raw or raw[key] is None:
            continue
        try:
            raw[key] = max(1, min(int(raw[key]), AI_LIST_TAKE_MAX))
        except (TypeError, ValueError):
            raw[key] = AI_LIST_TAKE_DEFAULT


def build_ai_list_query(
    kwargs: Dict[str, Any],
    *,
    entity: Optional[str] = None,
    extra_keys: Optional[List[str]] = None,
    calendar_type: CalendarType = "jalali",
) -> Dict[str, Any]:
    """ساخت query dict برای سرویس list از kwargs ابزار AI."""
    from app.services.ai.ai_query_filter_service import merge_into_query_dict
    from app.services.ai.ai_query_service import _build_list_query

    raw = dict(kwargs or {})
    for k in extra_keys or []:
        if k in kwargs and kwargs[k] is not None:
            raw[k] = kwargs[k]
    _clamp_take_in_dict(raw)
    merged = merge_into_query_dict(raw, entity=entity, calendar_type=calendar_type)
    return _build_list_query(merged, entity=entity)


def filter_property_hint(entity: str) -> str:
    from app.services.ai.ai_query_filter_catalog import get_entity_query_spec

    spec = get_entity_query_spec(entity)
    if not spec:
        return ""
    names = [f.property for f in spec.filterable_fields]
    return ", ".join(names)


def ai_list_parameters_schema(
    *,
    extra_properties: Optional[Dict[str, Any]] = None,
    required: Optional[List[str]] = None,
    entity: Optional[str] = None,
) -> Dict[str, Any]:
    """ساخت parameters_schema برای toolهای لیست."""
    props = dict(ADVANCED_LIST_QUERY_PROPERTIES)
    if extra_properties:
        props.update(extra_properties)
    if entity:
        hint = filter_property_hint(entity)
        if hint:
            filt = dict(props.get("filters") or {})
            filt["description"] = (
                f"فیلترهای ستونی AND. برای {entity} فقط propertyهای مجاز: {hint}. "
                "id یا نام نمایشی را در filters نگذار؛ برای نام از search استفاده کن. "
                "اگر نامشخص است list_queryable_fields را صدا بزن."
            )
            props["filters"] = filt
    return {
        "type": "object",
        "properties": props,
        "required": required or [],
    }
