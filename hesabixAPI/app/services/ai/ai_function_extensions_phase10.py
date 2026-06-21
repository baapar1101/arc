"""
فاز ۱۰ AI — جست‌وجوی پیشرفته QueryInfo (filters, search_fields) + resolve_date_range.
"""
from __future__ import annotations

from typing import Any, Dict, TYPE_CHECKING

from app.services.ai.ai_date_resolver import (
    calendar_type_from_context,
    resolve_date_range_for_ai,
)
from app.services.ai.ai_query_filter_catalog import list_catalog_entities
from app.services.ai.ai_query_filter_service import entity_query_schema_for_ai
from app.services.ai.function_registry import AIRole, AIFunction

if TYPE_CHECKING:
    from app.services.ai.function_registry import AIFunctionRegistry


def register_phase10_business_functions(registry: "AIFunctionRegistry") -> None:
    def list_queryable_fields_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        entity = str(args.get("entity", "")).strip().lower()
        if not entity:
            return {
                "entities": list_catalog_entities(),
                "hint": "پارامتر entity را بدهید، مثلاً invoice, person, check",
            }
        return entity_query_schema_for_ai(entity)

    registry.register(
        AIFunction(
            name="list_queryable_fields",
            description=(
                "کاتالوگ فیلدهای قابل فیلتر و جستجو برای یک entity "
                "(invoice, person, document, check, transfer, expense_income, …). "
                "قبل از ساخت filters[] در query_business_data از این tool استفاده کن."
            ),
            parameters_schema={
                "type": "object",
                "properties": {
                    "entity": {
                        "type": "string",
                        "description": "نام entity؛ خالی = لیست entityهای پشتیبانی‌شده",
                    },
                },
            },
            handler=list_queryable_fields_handler,
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=[],
            category="query",
            is_readonly=True,
        )
    )

    def resolve_date_range_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from sqlalchemy.orm import Session

        db: Session = context["db"]
        calendar_type = calendar_type_from_context(context)
        business_id = (
            context.get("session_business_id")
            or context.get("business_id")
            or args.get("business_id")
        )
        return resolve_date_range_for_ai(
            db,
            int(business_id) if business_id else None,
            args,
            calendar_type=calendar_type,
        )

    registry.register(
        AIFunction(
            name="resolve_date_range",
            description=(
                "تبدیل بازهٔ تاریخ (نسبی، ماه شمسی/میلادی، سال مالی) به from_date/to_date میلادی ISO "
                "برای استفاده در search_invoices، query_business_data و گزارش‌ها. "
                "قبل از فیلتر تاریخ مبهم این ابزار را صدا بزن."
            ),
            parameters_schema={
                "type": "object",
                "properties": {
                    "relative": {
                        "type": "string",
                        "enum": [
                            "today",
                            "yesterday",
                            "this_week",
                            "last_week",
                            "last_7_days",
                            "last_30_days",
                            "this_month",
                            "last_month",
                            "this_year",
                            "last_year",
                        ],
                        "description": "بازهٔ نسبی (اختیاری)",
                    },
                    "from_date": {
                        "type": "string",
                        "description": "از تاریخ صریح (شمسی YYYY/MM/DD یا میلادی YYYY-MM-DD)",
                    },
                    "to_date": {"type": "string", "description": "تا تاریخ صریح"},
                    "jalali_year": {"type": "integer", "description": "سال شمسی (با jalali_month)"},
                    "jalali_month": {"type": "integer", "description": "ماه شمسی ۱–۱۲"},
                    "gregorian_year": {"type": "integer", "description": "سال میلادی (با gregorian_month)"},
                    "gregorian_month": {"type": "integer", "description": "ماه میلادی ۱–۱۲"},
                    "fiscal_year_id": {"type": "integer", "description": "شناسه سال مالی کسب‌وکار"},
                },
            },
            handler=resolve_date_range_handler,
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=[],
            category="query",
            is_readonly=True,
        )
    )
