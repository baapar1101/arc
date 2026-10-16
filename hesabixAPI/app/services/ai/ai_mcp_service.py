"""Tenant-pinned MCP tools facade over the existing Hesabix AI registry."""
from __future__ import annotations

import json
import logging
from typing import Any, Dict, Optional

from sqlalchemy.orm import Session

from app.core.auth_dependency import AuthContext
from app.services.ai.ai_write_guard import is_readonly_function

logger = logging.getLogger(__name__)
MCP_PROTOCOL_VERSION = "2025-11-25"
SERVER_NAME = "hesabix-ai"
SERVER_VERSION = "1.1.0"
WRITE_SCOPE = "ai:tools:write"
AGENT_TOOL_NAME = "ask_hesabix_agent"


def prepare_mcp_tool_arguments(arguments: Dict[str, Any], *, business_id: int) -> Dict[str, Any]:
    """Remove model-controlled tenant/approval switches and pin supported tenant args."""
    cleaned = dict(arguments or {})
    cleaned.pop("_approve_writes", None)
    cleaned.pop("approve_writes", None)
    if "business_id" in cleaned:
        cleaned["business_id"] = int(business_id)
    return cleaned


def mcp_explicit_write_approval(params: Dict[str, Any]) -> bool:
    """Kept for old callers; an RPC boolean is never an authorization signal."""
    return False


def _mcp_readonly(name: str, registry: Any) -> bool:
    """Fail closed if registry metadata is missing or internally inconsistent."""
    function = registry.get_function(name)
    if function is None:
        return False
    return bool(
        is_readonly_function(name, registry)
        and not getattr(function, "requires_approval", False)
        and not getattr(function, "intent_write", False)
        and not getattr(function, "always_confirm", False)
        and getattr(function, "side_effect", "none") in {None, "none", "read"}
    )


def _jsonrpc_result(req_id: Any, result: Any) -> Dict[str, Any]:
    return {"jsonrpc": "2.0", "id": req_id, "result": result}


def _jsonrpc_error(req_id: Any, code: int, message: str, data: Any = None) -> Dict[str, Any]:
    err: Dict[str, Any] = {"code": code, "message": message}
    if data is not None:
        err["data"] = data
    return {"jsonrpc": "2.0", "id": req_id, "error": err}


def _openai_tool_to_mcp(tool_def: Dict[str, Any], registry: Any) -> Dict[str, Any]:
    fn = tool_def.get("function") or {}
    name = str(fn.get("name", "unknown"))
    read_only = _mcp_readonly(name, registry)
    return {
        "name": name,
        "description": fn.get("description") or "",
        "inputSchema": fn.get("parameters") or {"type": "object", "properties": {}},
        "annotations": {
            "readOnlyHint": read_only,
            "destructiveHint": not read_only,
            "idempotentHint": read_only,
            "openWorldHint": False,
        },
    }


def _get_tools(db: Session, ctx: AuthContext, business_id: int) -> tuple[Any, list[dict[str, Any]]]:
    from app.services.ai.function_registry import AIRole, registry

    context = {
        "db": db,
        "user_context": ctx,
        "business_id": business_id,
        "session_business_id": business_id,
    }
    definitions = registry.get_function_definitions(context)
    # External business connections must never publish operator/system-wide tools.
    business_roles = {AIRole.USER, AIRole.BUSINESS_OWNER}
    definitions = [
        item
        for item in definitions
        if (function := registry.get_function(str((item.get("function") or {}).get("name", ""))))
        and getattr(function, "enabled", True)
        and not getattr(function, "deprecated", False)
        and function.business_context_required
        and bool(function.allowed_roles & business_roles)
    ]
    return registry, definitions


async def handle_mcp_request(
    db: Session,
    ctx: AuthContext,
    body: Dict[str, Any],
    *,
    business_id: Optional[int] = None,
) -> Dict[str, Any]:
    req_id = body.get("id")
    method = body.get("method")
    params = body.get("params") or {}
    if not isinstance(params, dict):
        return _jsonrpc_error(req_id, -32602, "Invalid params")
    if body.get("jsonrpc") != "2.0":
        return _jsonrpc_error(req_id, -32600, "Invalid Request")

    # The endpoint supplies the tenant from the authenticated MCP credential.
    eff_business = int(business_id or ctx.business_id or 0)
    if not eff_business:
        return _jsonrpc_error(req_id, -32001, "Business-bound MCP credential required")

    request_meta = params.get("_meta") if isinstance(params, dict) else None
    modern = isinstance(request_meta, dict) and request_meta.get("io.modelcontextprotocol/protocolVersion") == "2026-07-28"

    if method == "server/discover":
        if not modern:
            return _jsonrpc_error(req_id, -32601, "Method not found")
        return _jsonrpc_result(req_id, {
            "supportedVersions": ["2026-07-28", MCP_PROTOCOL_VERSION],
            "capabilities": {
                "tools": {"listChanged": False},
                "resources": {"subscribe": False, "listChanged": False},
                "prompts": {"listChanged": False},
            },
            "instructions": "Tools are restricted to the business bound to this credential. Write tools require explicit owner consent.",
            "ttlMs": 300000,
            "cacheScope": "public",
        })

    if method == "initialize":
        if modern:
            return _jsonrpc_error(req_id, -32601, "Method not found")
        requested = params.get("protocolVersion")
        supported = {"2025-11-25", "2025-03-26"}
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
                "instructions": "Tools operate only on the business bound to this credential. Read tools are available by default; write tools require a separately granted ai:tools:write connection scope.",
            },
        )

    if method in ("notifications/initialized", "notifications/cancelled", "initialized"):
        return _jsonrpc_result(req_id, {})

    if method == "ping":
        return _jsonrpc_result(req_id, {})

    if method == "resources/list":
        return _jsonrpc_result(req_id, {
            "resources": [{
                "uri": "hesabix://business/overview",
                "name": "نمای کلی کسب‌وکار",
                "description": "اطلاعات پایه کسب‌وکاری که این اتصال به آن محدود است.",
                "mimeType": "application/json",
            }],
            **({"resultType": "complete", "ttlMs": 0, "cacheScope": "private"} if modern else {}),
        })

    if method == "resources/read":
        uri = params.get("uri")
        if uri != "hesabix://business/overview":
            return _jsonrpc_error(req_id, -32602, "Resource not found")
        from adapters.db.models.business import Business

        business = db.query(Business).filter(
            Business.id == eff_business,
            Business.deleted_at.is_(None),
        ).first()
        if not business:
            return _jsonrpc_error(req_id, -32001, "Business is unavailable")
        content = json.dumps({
            "name": business.name,
            "type": business.business_type.value if hasattr(business.business_type, "value") else str(business.business_type),
            "field": business.business_field.value if hasattr(business.business_field, "value") else str(business.business_field),
        }, ensure_ascii=False)
        return _jsonrpc_result(req_id, {
            "contents": [{"uri": uri, "mimeType": "application/json", "text": content}],
            **({"resultType": "complete"} if modern else {}),
        })

    if method == "prompts/list":
        prompts = [
            {"name": "business_summary", "description": "تهیهٔ خلاصه مدیریتی از وضعیت کسب‌وکار با ابزارهای مجاز."},
            {"name": "sales_review", "description": "بررسی روند فروش و نکات قابل پیگیری در کسب‌وکار جاری."},
            {"name": "inventory_review", "description": "مرور وضعیت موجودی و شناسایی موارد نیازمند توجه."},
        ]
        return _jsonrpc_result(req_id, {
            "prompts": prompts,
            **({"resultType": "complete", "ttlMs": 0, "cacheScope": "private"} if modern else {}),
        })

    if method == "prompts/get":
        prompt_name = params.get("name")
        prompt_titles = {
            "business_summary": "خلاصه مدیریتی کسب‌وکار",
            "sales_review": "مرور فروش",
            "inventory_review": "مرور موجودی",
        }
        if prompt_name not in prompt_titles:
            return _jsonrpc_error(req_id, -32602, "Prompt not found")
        arguments = params.get("arguments") or {}
        user_request = arguments.get("request", "") if isinstance(arguments, dict) else ""
        if not isinstance(user_request, str) or len(user_request) > 2000:
            return _jsonrpc_error(req_id, -32602, "Invalid prompt arguments")
        prompt_text = (
            f"{prompt_titles[prompt_name]} برای همان کسب‌وکاری که این MCP به آن متصل است تهیه کن. "
            "فقط از ابزارهای حسابیکس در دسترس استفاده کن؛ داده‌ای از کسب‌وکار دیگری نخواه و اگر داده‌ای در دسترس نیست صریح بگو. "
            "هیچ عملیات تغییردهنده‌ای اجرا نکن مگر کاربر در همان گفتگو صریحاً درخواست کند و ابزار مربوطه مجاز باشد."
        )
        if user_request.strip():
            prompt_text += "\nدرخواست تکمیلی کاربر: " + user_request.strip()
        return _jsonrpc_result(req_id, {
            "description": prompt_titles[prompt_name],
            "messages": [{"role": "user", "content": {"type": "text", "text": prompt_text}}],
            **({"resultType": "complete"} if modern else {}),
        })

    if method == "tools/list":
        registry, definitions = _get_tools(db, ctx, eff_business)
        tools = []
        for definition in definitions:
            tool = _openai_tool_to_mcp(definition, registry)
            if tool["annotations"]["readOnlyHint"] or WRITE_SCOPE in getattr(ctx, "mcp_scopes", set()):
                tools.append(tool)
        tools.append(
            {
                "name": AGENT_TOOL_NAME,
                "description": "پرسش چندمرحله‌ای از ایجنت حسابیکس؛ ایجنت ابزارهای مجاز و فقط‌خواندنی همین کسب‌وکار را انتخاب و ترکیب می‌کند.",
                "inputSchema": {
                    "type": "object",
                    "properties": {"query": {"type": "string", "description": "درخواست یا پرسش درباره همین کسب‌وکار"}},
                    "required": ["query"],
                    "additionalProperties": False,
                },
                "annotations": {"readOnlyHint": True, "destructiveHint": False, "idempotentHint": False, "openWorldHint": False},
            }
        )
        tools.sort(key=lambda item: item["name"])
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

        registry, definitions = _get_tools(db, ctx, eff_business)
        available = {str((item.get("function") or {}).get("name")): item for item in definitions}
        if name == AGENT_TOOL_NAME:
            available[name] = {"function": {"name": name}}
        if name not in available:
            return _jsonrpc_error(req_id, -32602, "Tool not found or not permitted")
        if name != AGENT_TOOL_NAME and not _mcp_readonly(name, registry) and WRITE_SCOPE not in getattr(ctx, "mcp_scopes", set()):
            return _jsonrpc_error(req_id, -32003, "This MCP connection is read-only; create a separately authorized write connection.")

        safe_arguments = prepare_mcp_tool_arguments(arguments, business_id=eff_business)
        context = {
            "user_context": ctx,
            "business_id": eff_business,
            "session_business_id": eff_business,
        }
        try:
            if name == AGENT_TOOL_NAME:
                query = safe_arguments.get("query")
                if not isinstance(query, str) or not query.strip() or len(query) > 8000:
                    return _jsonrpc_error(req_id, -32602, "query must contain 1 to 8000 characters")
                from app.services.ai.ai_service import AIService

                service = AIService(db, ctx, eff_business)
                result = await service.chat_completion(
                    [{"role": "user", "content": query.strip()}],
                    use_function_calling=True,
                    session_business_id=eff_business,
                    user_query=query.strip(),
                    execution_mode="analyzer",
                    max_iterations=8,
                )
                message = result.get("message") if isinstance(result, dict) else None
                answer = message.get("content") if isinstance(message, dict) else None
                rendered = answer if isinstance(answer, str) and answer.strip() else "Agent task completed without a text answer."
                logger.info(
                    "MCP agent task completed connection_id=%s user_id=%s business_id=%s",
                    getattr(ctx, "mcp_connection_id", None), ctx.get_user_id(), eff_business,
                )
                return _jsonrpc_result(req_id, {"content": [{"type": "text", "text": str(rendered)}], "isError": False, **({"resultType": "complete"} if modern else {})})

            from app.services.ai.ai_db_helpers import run_ai_registry_function

            result = run_ai_registry_function(name, safe_arguments, context)
            text = result if isinstance(result, str) else json.dumps(result, ensure_ascii=False, default=str)
            logger.info(
                "MCP tool call completed connection_id=%s user_id=%s business_id=%s tool=%s",
                getattr(ctx, "mcp_connection_id", None), ctx.get_user_id(), eff_business, name,
            )
            return _jsonrpc_result(req_id, {"content": [{"type": "text", "text": text}], "isError": False, **({"resultType": "complete"} if modern else {})})
        except PermissionError:
            return _jsonrpc_result(req_id, {"content": [{"type": "text", "text": "Permission denied for this tool."}], "isError": True})
        except Exception:
            from app.services.ai.ai_db_helpers import safe_db_rollback

            safe_db_rollback(db)
            logger.exception(
                "MCP tool call failed connection_id=%s user_id=%s business_id=%s tool=%s",
                getattr(ctx, "mcp_connection_id", None), ctx.get_user_id(), eff_business, name,
            )
            return _jsonrpc_result(req_id, {"content": [{"type": "text", "text": "Tool execution failed."}], "isError": True})

    return _jsonrpc_error(req_id, -32601, "Method not found")
