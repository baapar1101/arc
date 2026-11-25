"""MCP discovery tools so a fully-authorized connection can find the right tool."""
from __future__ import annotations

from typing import Any, Dict

from app.services.ai.function_registry import AIRole, AIFunction

_ROLES = {AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN}


def register_mcp_discovery_functions(registry) -> None:
    def list_categories(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from app.services.ai.ai_mcp_discovery import list_mcp_categories

        return list_mcp_categories(
            context["db"],
            context["user_context"],
            int(context["business_id"]),
        )

    def search_tools(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from app.services.ai.ai_mcp_discovery import search_mcp_tools

        return search_mcp_tools(
            context["db"],
            context["user_context"],
            int(context["business_id"]),
            query=str(args.get("query") or ""),
            category=args.get("category"),
            limit=int(args.get("limit") or 20),
        )

    registry.register(
        AIFunction(
            name="list_mcp_categories",
            description=(
                "فهرست دسته‌های ابزار مجاز همین اتصال یا نشست، با تعداد و نمونه نام ابزار. "
                "بعد از آن search_mcp_tools را برای یافتن ابزار دقیق صدا بزنید."
            ),
            parameters_schema={"type": "object", "properties": {}, "additionalProperties": False},
            handler=list_categories,
            allowed_roles=_ROLES,
            required_permissions=[],
            category="query",
            is_readonly=True,
            is_agent_internal=True,
        )
    )
    registry.register(
        AIFunction(
            name="search_mcp_tools",
            description=(
                "جستجو در ابزارهای مجاز همین اتصال یا نشست. فقط ابزارهای برگشتی را صدا بزنید؛ "
                "نام ابزار غایب را حدس نزنید. query مثلاً «تراز آزمایشی» یا «فاکتور»."
            ),
            parameters_schema={
                "type": "object",
                "properties": {
                    "query": {"type": "string", "minLength": 2, "maxLength": 200},
                    "category": {"type": ["string", "null"], "maxLength": 40},
                    "limit": {"type": "integer", "minimum": 1, "maximum": 50},
                },
                "required": ["query"],
                "additionalProperties": False,
            },
            handler=search_tools,
            allowed_roles=_ROLES,
            required_permissions=[],
            category="query",
            is_readonly=True,
            is_agent_internal=True,
        )
    )
