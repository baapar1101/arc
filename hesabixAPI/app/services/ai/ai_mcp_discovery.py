"""MCP tool discovery helpers shared by the MCP server and in-chat tools."""
from __future__ import annotations

import re
from typing import Any, Dict, List, Optional, Tuple

from sqlalchemy.orm import Session

from app.core.auth_dependency import AuthContext
from app.services.ai.ai_write_guard import is_readonly_function

WRITE_SCOPE = "ai:tools:write"
AGENT_TOOL_NAME = "ask_hesabix_agent"
_TOKEN_RE = re.compile(r"[A-Za-z0-9_]+|[\u0600-\u06FF]+")


def mcp_readonly(name: str, registry: Any) -> bool:
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


def mcp_visible_definitions(
    db: Session,
    ctx: AuthContext,
    business_id: int,
) -> Tuple[Any, List[Dict[str, Any]]]:
    from app.services.ai.function_registry import AIRole, registry

    context = {
        "db": db,
        "user_context": ctx,
        "business_id": business_id,
        "session_business_id": business_id,
    }
    definitions = registry.get_function_definitions(context)
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
    allowed_tools = getattr(ctx, "mcp_tool_permissions", None)
    if allowed_tools is not None:
        definitions = [
            item
            for item in definitions
            if str((item.get("function") or {}).get("name", "")) in allowed_tools
        ]
    return registry, definitions


def _channel_uses_mcp_filter(ctx: AuthContext) -> bool:
    return getattr(ctx, "mcp_scopes", None) is not None


def visible_tool_catalog(
    db: Session,
    ctx: AuthContext,
    business_id: int,
    *,
    include_agent: bool = True,
) -> List[Dict[str, Any]]:
    if _channel_uses_mcp_filter(ctx):
        registry, definitions = mcp_visible_definitions(db, ctx, business_id)
    else:
        from app.services.ai.function_registry import registry

        context = {
            "db": db,
            "user_context": ctx,
            "business_id": business_id,
            "session_business_id": business_id,
        }
        definitions = registry.get_function_definitions(context)
    catalog: List[Dict[str, Any]] = []
    from app.services.ai.function_registry import registry as live_registry

    write_allowed = WRITE_SCOPE in set(getattr(ctx, "mcp_scopes", set()) or set())
    enforce_write_scope = _channel_uses_mcp_filter(ctx)
    for definition in definitions:
        fn_def = definition.get("function") or {}
        name = str(fn_def.get("name", ""))
        function = live_registry.get_function(name)
        if not function:
            continue
        read_only = mcp_readonly(name, live_registry)
        if enforce_write_scope and not read_only and not write_allowed:
            continue
        catalog.append(
            {
                "name": name,
                "description": fn_def.get("description") or function.description or "",
                "input_schema": fn_def.get("parameters") or {"type": "object", "properties": {}},
                "category": function.category or "general",
                "capability": getattr(function, "capability", "misc"),
                "read_only": read_only,
                "required_permissions": list(function.required_permissions or []),
                "aliases": list(getattr(function, "aliases", ()) or ()),
                "keywords": list(getattr(function, "keywords", ()) or ()),
            }
        )
    if include_agent and getattr(ctx, "mcp_tool_permissions", None) is None:
        catalog.append(
            {
                "name": AGENT_TOOL_NAME,
                "description": "پرسش چندمرحله‌ای از ایجنت حسابیکس در حالت فقط‌خواندنی و محدود به همین کسب‌وکار.",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "query": {
                            "type": "string",
                            "description": "درخواست یا پرسش درباره همین کسب‌وکار",
                        }
                    },
                    "required": ["query"],
                    "additionalProperties": False,
                },
                "category": "agent",
                "capability": "business_agent",
                "read_only": True,
                "required_permissions": [],
            }
        )
    return sorted(catalog, key=lambda item: item["name"])


def list_mcp_categories(
    db: Session,
    ctx: AuthContext,
    business_id: int,
) -> Dict[str, Any]:
    catalog = visible_tool_catalog(db, ctx, business_id, include_agent=False)
    grouped: Dict[str, List[str]] = {}
    for item in catalog:
        grouped.setdefault(str(item["category"] or "general"), []).append(item["name"])
    categories = [
        {
            "category": name,
            "tool_count": len(tools),
            "sample_tools": tools[:8],
        }
        for name, tools in sorted(grouped.items())
    ]
    return {
        "categories": categories,
        "total_tools": len(catalog),
        "hint": "برای یافتن ابزار از search_mcp_tools استفاده کنید. فقط همین ابزارها برای این اتصال مجازند.",
    }


def _tokens(query: str) -> List[str]:
    return [t.lower() for t in _TOKEN_RE.findall(query or "") if len(t.strip()) >= 2]


def _score_tool(item: Dict[str, Any], tokens: List[str]) -> int:
    name = str(item.get("name") or "").lower()
    desc = str(item.get("description") or "").lower()
    category = str(item.get("category") or "").lower()
    capability = str(item.get("capability") or "").lower()
    aliases = " ".join(str(a).lower() for a in (item.get("aliases") or ()))
    keywords = " ".join(str(k).lower() for k in (item.get("keywords") or ()))
    hay = f"{name} {desc} {category} {capability} {aliases} {keywords}"
    score = 0
    for token in tokens:
        if token == name or name.endswith(token) or token in name.replace("_", " "):
            score += 8
        elif token in name:
            score += 5
        if token in aliases:
            score += 6
        if token in keywords:
            score += 4
        if token == category or token in category:
            score += 3
        if token in capability:
            score += 2
        if token in desc:
            score += 1
        if token in hay:
            score += 1
    return score


def search_mcp_tools(
    db: Session,
    ctx: AuthContext,
    business_id: int,
    *,
    query: str,
    category: Optional[str] = None,
    limit: int = 20,
) -> Dict[str, Any]:
    catalog = visible_tool_catalog(db, ctx, business_id, include_agent=False)
    cat = (category or "").strip().lower() or None
    if cat:
        catalog = [item for item in catalog if str(item.get("category") or "").lower() == cat]
    tokens = _tokens(query)
    if not tokens:
        return {
            "items": [],
            "total": 0,
            "hint": "یک عبارت جستجو بفرستید؛ مثلاً «تراز آزمایشی» یا «فاکتور».",
        }
    ranked = []
    for item in catalog:
        score = _score_tool(item, tokens)
        if score <= 0:
            continue
        ranked.append((score, item))
    ranked.sort(key=lambda pair: (-pair[0], pair[1]["name"]))
    take = max(1, min(int(limit or 20), 50))
    items = []
    for score, item in ranked[:take]:
        items.append(
            {
                "name": item["name"],
                "description": item["description"],
                "category": item["category"],
                "capability": item.get("capability"),
                "read_only": item.get("read_only"),
                "required_permissions": item.get("required_permissions") or [],
                "aliases": item.get("aliases") or [],
                "input_schema": item.get("input_schema") or {"type": "object", "properties": {}},
                "score": score,
            }
        )
    return {
        "items": items,
        "total": len(ranked),
        "returned": len(items),
        "hint": "فقط همین ابزارها را صدا بزنید؛ نام ابزار غایب را حدس نزنید.",
    }
