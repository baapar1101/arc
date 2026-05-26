"""
سرور MCP (JSON-RPC 2.0) — expose کردن ابزارهای Hesabix AI به کلاینت‌های MCP.
"""
from __future__ import annotations

import json
import logging
from typing import Any, Dict, List, Optional

from sqlalchemy.orm import Session

from app.core.auth_dependency import AuthContext
from app.services.ai.function_registry import registry

logger = logging.getLogger(__name__)

MCP_PROTOCOL_VERSION = "2024-11-05"
SERVER_NAME = "hesabix-ai"
SERVER_VERSION = "1.0.0"


def _jsonrpc_result(req_id: Any, result: Any) -> Dict[str, Any]:
    return {"jsonrpc": "2.0", "id": req_id, "result": result}


def _jsonrpc_error(req_id: Any, code: int, message: str, data: Any = None) -> Dict[str, Any]:
    err: Dict[str, Any] = {"code": code, "message": message}
    if data is not None:
        err["data"] = data
    return {"jsonrpc": "2.0", "id": req_id, "error": err}


def _openai_tool_to_mcp(tool_def: Dict[str, Any]) -> Dict[str, Any]:
    fn = tool_def.get("function") or {}
    return {
        "name": fn.get("name", "unknown"),
        "description": fn.get("description") or "",
        "inputSchema": fn.get("parameters") or {"type": "object", "properties": {}},
    }


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

    if body.get("jsonrpc") != "2.0":
        return _jsonrpc_error(req_id, -32600, "Invalid Request")

    eff_business = business_id or ctx.business_id or params.get("business_id")
    if method == "initialize":
        return _jsonrpc_result(
            req_id,
            {
                "protocolVersion": MCP_PROTOCOL_VERSION,
                "capabilities": {"tools": {"listChanged": False}},
                "serverInfo": {"name": SERVER_NAME, "version": SERVER_VERSION},
            },
        )

    if method in ("notifications/initialized", "initialized"):
        return _jsonrpc_result(req_id, {})

    if method == "tools/list":
        context = {
            "db": db,
            "user_context": ctx,
            "business_id": eff_business,
            "session_business_id": eff_business,
        }
        tools = registry.get_function_definitions(context)
        mcp_tools = [_openai_tool_to_mcp(t) for t in tools]
        return _jsonrpc_result(req_id, {"tools": mcp_tools})

    if method == "tools/call":
        tool_name = params.get("name")
        arguments = params.get("arguments") or {}
        if not tool_name:
            return _jsonrpc_error(req_id, -32602, "Missing tool name")
        if not eff_business:
            return _jsonrpc_error(req_id, -32602, "business_id required for tools/call")
        context = {
            "user_context": ctx,
            "business_id": int(eff_business),
            "session_business_id": int(eff_business),
        }
        try:
            from app.services.ai.ai_db_helpers import run_ai_registry_function

            result = run_ai_registry_function(str(tool_name), arguments, context)
            text = result if isinstance(result, str) else json.dumps(result, ensure_ascii=False, default=str)
            return _jsonrpc_result(
                req_id,
                {
                    "content": [{"type": "text", "text": text}],
                    "isError": False,
                },
            )
        except PermissionError as exc:
            return _jsonrpc_result(
                req_id,
                {"content": [{"type": "text", "text": str(exc)}], "isError": True},
            )
        except Exception as exc:
            from app.services.ai.ai_db_helpers import safe_db_rollback

            safe_db_rollback(db)
            logger.error("MCP tools/call error: %s", exc, exc_info=True)
            return _jsonrpc_result(
                req_id,
                {"content": [{"type": "text", "text": str(exc)}], "isError": True},
            )

    if method == "ping":
        return _jsonrpc_result(req_id, {})

    return _jsonrpc_error(req_id, -32601, f"Method not found: {method}")
