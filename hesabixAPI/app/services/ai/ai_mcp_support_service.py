"""Platform support-desk MCP facade. Not bound to a business tenant."""
from __future__ import annotations

import json
import logging
from typing import Any, Dict, Optional

from sqlalchemy.orm import Session

from app.core.auth_dependency import AuthContext
from app.services.ai.ai_mcp_discovery import mcp_readonly as _mcp_readonly
from app.services.ai.ai_mcp_discovery import mcp_support_visible_definitions, support_tool_catalog
from app.services.ai.ai_mcp_service import (
    MCP_PROTOCOL_VERSION,
    _jsonrpc_error,
    _jsonrpc_result,
    _openai_tool_to_mcp,
    _validate_tool_arguments,
)

logger = logging.getLogger(__name__)
SERVER_NAME = "hesabix-support"
SERVER_VERSION = "1.0.0"
SUPPORT_MCP_INSTRUCTIONS = (
    "You are connected to the Hesabix support desk. "
    "Tools operate on platform support tickets for the authenticated operator or superadmin. "
    "They are not bound to a customer business and must not invent accounting data. "
    "Read hesabix://mcp/capabilities for the live tool list. "
    "Use only those tool names and parameters. "
    "Public replies are sent to the end user; internal notes are not. "
    "Identify tickets by id from search; do not guess ids. "
    "Keep customer emails and internal notes out of unrelated answers."
)
_PROMPT_CATALOG = {
    "support_inbox_review": (
        "مرور صف پشتیبانی",
        "تیکت‌های باز، نخوانده و تأخیری را از ابزارهای همین اتصال بخوان و اولویت پاسخ را مشخص کن.",
    ),
    "support_ticket_reply": (
        "پاسخ به تیکت پشتیبانی",
        "جزئیات و پیام‌های تیکت را بخوان، خلاصه کن و در صورت درخواست صریح کاربر یک پاسخ عمومی یا یادداشت داخلی بفرست.",
    ),
}


def prepare_support_mcp_tool_arguments(arguments: Dict[str, Any]) -> Dict[str, Any]:
    cleaned = dict(arguments or {})
    if cleaned.get("ticket_user_id") is None and cleaned.get("user_id") is not None:
        cleaned["ticket_user_id"] = cleaned["user_id"]
    for key in ("_approve_writes", "approve_writes", "user_id", "business_id", "confirmation_id"):
        cleaned.pop(key, None)
    return cleaned


def _prompt_content(title: str, goal: str, user_request: str, catalog: list[dict[str, Any]]) -> str:
    tool_names = ", ".join(item["name"] for item in catalog[:80]) or "هیچ ابزار پشتیبانی در این اتصال مجاز نیست"
    text = (
        f"{title}. {goal}\n"
        "فقط به میز پشتیبانی حسابیکس و ابزارهای همین اتصال محدود هستی. "
        "فهرست ابزارها را از منبع hesabix://mcp/capabilities بخوان و فقط همان نام‌ها را صدا بزن. "
        "داده حسابداری کسب‌وکار مشتری را حدس نزن و از MCP کسب‌وکار استفاده نکن.\n"
        f"ابزارهای قابل مشاهده: {tool_names}.\n"
        "شناسه تیکت را با جستجو به‌دست بیاور. پاسخ عمومی برای مشتری ارسال می‌شود؛ یادداشت داخلی فقط برای اپراتورهاست. "
        "اگر ابزار یا داده کافی نیست صریح بگو."
    )
    if user_request.strip():
        text += "\nدرخواست تکمیلی کاربر: " + user_request.strip()
    return text


def _inbox_resource(db: Session, ctx: AuthContext) -> str:
    from app.services.support.support_dashboard_service import SupportDashboardService

    stats = SupportDashboardService(db).get_stats(ctx.get_user_id())
    overdue = SupportDashboardService(db).get_overdue_tickets(limit=10)
    return json.dumps(
        {
            "operator_id": ctx.get_user_id(),
            "stats": stats,
            "overdue_preview": overdue,
        },
        ensure_ascii=False,
        default=str,
    )


async def handle_support_mcp_request(
    db: Session,
    ctx: AuthContext,
    body: Dict[str, Any],
    *,
    diagnostic_id: Optional[str] = None,
) -> Dict[str, Any]:
    req_id = body.get("id")
    method = body.get("method")
    params = body.get("params") or {}
    if not isinstance(params, dict):
        return _jsonrpc_error(req_id, -32602, "Invalid params")
    if body.get("jsonrpc") != "2.0":
        return _jsonrpc_error(req_id, -32600, "Invalid Request")

    request_meta = params.get("_meta") if isinstance(params, dict) else None
    modern = isinstance(request_meta, dict) and request_meta.get("io.modelcontextprotocol/protocolVersion") == "2026-07-28"

    if method == "server/discover":
        if not modern:
            return _jsonrpc_error(req_id, -32601, "Method not found")
        return _jsonrpc_result(req_id, {
            "supportedVersions": ["2026-07-28", MCP_PROTOCOL_VERSION, "2025-06-18", "2025-03-26"],
            "capabilities": {
                "tools": {"listChanged": False},
                "resources": {"subscribe": False, "listChanged": False},
                "prompts": {"listChanged": False},
            },
            "instructions": SUPPORT_MCP_INSTRUCTIONS,
            "ttlMs": 300000,
            "cacheScope": "private",
        })

    if method == "initialize":
        if modern:
            return _jsonrpc_error(req_id, -32601, "Method not found")
        requested = params.get("protocolVersion")
        supported = {"2025-11-25", "2025-06-18", "2025-03-26"}
        version = requested if requested in supported else MCP_PROTOCOL_VERSION
        return _jsonrpc_result(
            req_id,
            {
                "protocolVersion": version,
                "capabilities": {
                    "tools": {"listChanged": False},
                    "resources": {"subscribe": False, "listChanged": False},
                    "prompts": {"listChanged": False},
                },
                "serverInfo": {"name": SERVER_NAME, "version": SERVER_VERSION},
                "instructions": SUPPORT_MCP_INSTRUCTIONS,
            },
        )

    if method in ("notifications/initialized", "notifications/cancelled", "initialized"):
        return _jsonrpc_result(req_id, {})

    if method == "ping":
        return _jsonrpc_result(req_id, {})

    if method == "resources/list":
        return _jsonrpc_result(req_id, {
            "resources": [
                {
                    "uri": "hesabix://support/inbox",
                    "name": "صف پشتیبانی",
                    "description": "آمار میز پشتیبانی و پیش‌نمایش تیکت‌های تأخیری برای اپراتور متصل.",
                    "mimeType": "application/json",
                },
                {
                    "uri": "hesabix://mcp/capabilities",
                    "name": "قابلیت‌های مجاز اتصال پشتیبانی",
                    "description": "فهرست ابزارهای میز پشتیبانی که برای همین اپراتور قابل استفاده‌اند.",
                    "mimeType": "application/json",
                },
            ],
            **({"resultType": "complete", "ttlMs": 0, "cacheScope": "private"} if modern else {}),
        })

    if method == "resources/read":
        uri = params.get("uri")
        if uri == "hesabix://mcp/capabilities":
            catalog = support_tool_catalog(db, ctx)
            categories: Dict[str, int] = {}
            for item in catalog:
                categories[item["category"]] = categories.get(item["category"], 0) + 1
            content = json.dumps({
                "channel": "support",
                "operator_id": ctx.get_user_id(),
                "tool_count": len(catalog),
                "categories": categories,
                "tools": catalog,
            }, ensure_ascii=False)
        elif uri == "hesabix://support/inbox":
            content = _inbox_resource(db, ctx)
        else:
            return _jsonrpc_error(req_id, -32602, "Resource not found")
        return _jsonrpc_result(req_id, {
            "contents": [{"uri": uri, "mimeType": "application/json", "text": content}],
            **({"resultType": "complete"} if modern else {}),
        })

    if method == "prompts/list":
        prompts = [
            {
                "name": name,
                "description": f"{title} با اتکا به ابزارهای میز پشتیبانی.",
                "arguments": [{"name": "request", "description": "درخواست تکمیلی کاربر (اختیاری)", "required": False}],
            }
            for name, (title, _goal) in _PROMPT_CATALOG.items()
        ]
        return _jsonrpc_result(req_id, {
            "prompts": prompts,
            **({"resultType": "complete", "ttlMs": 0, "cacheScope": "private"} if modern else {}),
        })

    if method == "prompts/get":
        prompt_name = params.get("name")
        prompt_config = _PROMPT_CATALOG.get(prompt_name)
        if not prompt_config:
            return _jsonrpc_error(req_id, -32602, "Prompt not found")
        arguments = params.get("arguments") or {}
        if not isinstance(arguments, dict) or set(arguments) - {"request"}:
            return _jsonrpc_error(req_id, -32602, "Invalid prompt arguments")
        user_request = arguments.get("request", "")
        if not isinstance(user_request, str) or len(user_request) > 2000:
            return _jsonrpc_error(req_id, -32602, "Invalid prompt arguments")
        prompt_title, prompt_goal = prompt_config
        catalog = support_tool_catalog(db, ctx)
        prompt_text = _prompt_content(prompt_title, prompt_goal, user_request.strip(), catalog)
        return _jsonrpc_result(req_id, {
            "description": prompt_title,
            "messages": [{"role": "user", "content": {"type": "text", "text": prompt_text}}],
            **({"resultType": "complete"} if modern else {}),
        })

    if method == "tools/list":
        registry, definitions = mcp_support_visible_definitions(db, ctx)
        tools = [_openai_tool_to_mcp(definition, registry) for definition in definitions]
        cursor = params.get("cursor")
        try:
            offset = max(0, int(cursor)) if cursor is not None else 0
        except (TypeError, ValueError):
            return _jsonrpc_error(req_id, -32602, "Invalid cursor")
        page_size = 50
        page = tools[offset : offset + page_size]
        result: Dict[str, Any] = {"tools": page}
        if modern:
            result.update({"resultType": "complete", "ttlMs": 0, "cacheScope": "private"})
        if offset + page_size < len(tools):
            result["nextCursor"] = str(offset + page_size)
        return _jsonrpc_result(req_id, result)

    if method == "tools/call":
        name = params.get("name")
        arguments = params.get("arguments") or {}
        if not isinstance(name, str) or not name or not isinstance(arguments, dict):
            return _jsonrpc_error(req_id, -32602, "Invalid tool name or arguments")
        registry, definitions = mcp_support_visible_definitions(db, ctx)
        available = {str((item.get("function") or {}).get("name")): item for item in definitions}
        if name not in available:
            return _jsonrpc_error(req_id, -32602, "Tool not found or not permitted")
        safe_arguments = prepare_support_mcp_tool_arguments(arguments)
        tool_schema = (available[name].get("function") or {}).get("parameters") or {"type": "object"}
        schema_error = _validate_tool_arguments(safe_arguments, tool_schema)
        if schema_error:
            return _jsonrpc_error(req_id, -32602, "Invalid tool arguments", {"reason": schema_error})
        logger.info(
            "support_mcp_tool_call_started diagnostic_id=%s tool=%s connection_id=%s user_id=%s",
            diagnostic_id,
            name,
            getattr(ctx, "mcp_connection_id", None),
            ctx.get_user_id(),
        )
        context = {
            "user_context": ctx,
            "business_id": None,
            "session_business_id": None,
        }
        try:
            from app.services.ai.ai_db_helpers import run_ai_registry_function

            result = run_ai_registry_function(name, safe_arguments, context)
            text = result if isinstance(result, str) else json.dumps(result, ensure_ascii=False, default=str)
            logger.info(
                "support_mcp_tool_call_completed diagnostic_id=%s connection_id=%s user_id=%s tool=%s readonly=%s result_chars=%s",
                diagnostic_id,
                getattr(ctx, "mcp_connection_id", None),
                ctx.get_user_id(),
                name,
                _mcp_readonly(name, registry),
                len(text),
            )
            return _jsonrpc_result(
                req_id,
                {"content": [{"type": "text", "text": text}], "isError": False, **({"resultType": "complete"} if modern else {})},
            )
        except PermissionError:
            logger.warning(
                "support_mcp_tool_call_denied diagnostic_id=%s connection_id=%s user_id=%s tool=%s",
                diagnostic_id,
                getattr(ctx, "mcp_connection_id", None),
                ctx.get_user_id(),
                name,
            )
            return _jsonrpc_result(req_id, {"content": [{"type": "text", "text": "Permission denied for this tool."}], "isError": True})
        except ValueError as exc:
            from app.services.ai.ai_db_helpers import safe_db_rollback

            safe_db_rollback(db)
            message = str(exc).strip() or "Tool execution failed."
            logger.warning(
                "support_mcp_tool_call_invalid diagnostic_id=%s connection_id=%s user_id=%s tool=%s",
                diagnostic_id,
                getattr(ctx, "mcp_connection_id", None),
                ctx.get_user_id(),
                name,
            )
            return _jsonrpc_result(req_id, {"content": [{"type": "text", "text": message}], "isError": True})
        except Exception:
            from app.services.ai.ai_db_helpers import safe_db_rollback

            safe_db_rollback(db)
            logger.exception(
                "support_mcp_tool_call_failed diagnostic_id=%s connection_id=%s user_id=%s tool=%s",
                diagnostic_id,
                getattr(ctx, "mcp_connection_id", None),
                ctx.get_user_id(),
                name,
            )
            return _jsonrpc_result(req_id, {"content": [{"type": "text", "text": "Tool execution failed."}], "isError": True})

    return _jsonrpc_error(req_id, -32601, "Method not found")
