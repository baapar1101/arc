"""
فاز ۱۰ AI — جست‌وجوی پیشرفته QueryInfo (filters, search_fields).
"""
from __future__ import annotations

from typing import Any, Dict, TYPE_CHECKING

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
