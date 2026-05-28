"""
فاز ۶ AI — کاتالوگ گزارش‌ها و list_available_reports.
"""
from __future__ import annotations

from typing import Any, Dict, TYPE_CHECKING

from app.services.ai.function_registry import AIRole, AIFunction

if TYPE_CHECKING:
    from app.services.ai.function_registry import AIFunctionRegistry


def register_phase6_business_functions(registry: "AIFunctionRegistry") -> None:
    def list_available_reports_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from app.services.ai.ai_reports_service import list_available_reports

        ctx = context["user_context"]
        business_id = int(args.get("business_id") or context.get("business_id"))
        return list_available_reports(
            ctx,
            business_id=business_id,
            category=args.get("category"),
        )

    registry.register(
        AIFunction(
            name="list_available_reports",
            description=(
                "لیست گزارش‌هایی که کاربر مجاز به دریافت آن‌هاست. "
                "category اختیاری: financial, sales, warehouse, accounting, integration. "
                "سپس از get_report با report_type استفاده کنید."
            ),
            parameters_schema={
                "type": "object",
                "properties": {
                    "category": {
                        "type": "string",
                        "enum": [
                            "financial",
                            "sales",
                            "warehouse",
                            "accounting",
                            "integration",
                        ],
                    },
                },
            },
            handler=list_available_reports_handler,
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["reports.read"],
            category="reports",
            is_readonly=True,
        )
    )
