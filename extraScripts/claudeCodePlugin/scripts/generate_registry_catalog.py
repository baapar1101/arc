#!/usr/bin/env python3
"""Build the static Hesabix MCP tool catalog from the API registry source.

Run from the repository root:
    python extraScripts/claudeCodePlugin/scripts/generate_registry_catalog.py

This source-based exporter deliberately needs no Hesabix runtime dependencies.
It extracts literal AIFunction declarations and joins them with TOOL_MANIFEST.
Dynamic/conditional runtime behavior must still be confirmed against a live MCP
connection; the generated catalog says so explicitly.
"""
from __future__ import annotations

import ast
import json
from collections import defaultdict
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[3]
API = ROOT / "hesabixAPI" / "app" / "services" / "ai"
OUT = Path(__file__).resolve().parents[1] / "docs"


def literal(node: ast.AST | None, fallback: Any = None) -> Any:
    if node is None:
        return fallback
    try:
        return ast.literal_eval(node)
    except (ValueError, TypeError):
        return fallback


def role_names(node: ast.AST | None) -> list[str]:
    names: set[str] = set()
    if node is None:
        return []  # empty list for dynamic role expressions
    for item in ast.walk(node):
        if isinstance(item, ast.Attribute) and isinstance(item.value, ast.Name) and item.value.id == "AIRole":
            names.add(item.attr)
    return sorted(names)


def load_manifest() -> dict[str, dict[str, Any]]:
    tree = ast.parse((API / "ai_tool_manifest.py").read_text(encoding="utf-8"))
    for node in tree.body:
        if isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name) and node.target.id == "TOOL_MANIFEST":
            value = literal(node.value, {})
            return value if isinstance(value, dict) else {}
    raise RuntimeError("TOOL_MANIFEST not found")


def static_tools() -> dict[str, dict[str, Any]]:
    tools: dict[str, dict[str, Any]] = {}
    for path in sorted(API.glob("*.py")):
        try:
            tree = ast.parse(path.read_text(encoding="utf-8"))
        except (SyntaxError, UnicodeDecodeError):
            continue
        for node in ast.walk(tree):
            if not isinstance(node, ast.Call):
                continue
            if not (isinstance(node.func, ast.Name) and node.func.id == "AIFunction" or
                    isinstance(node.func, ast.Attribute) and node.func.attr == "AIFunction"):
                continue
            kwargs = {kw.arg: kw.value for kw in node.keywords if kw.arg}
            name = literal(kwargs.get("name"))
            if not isinstance(name, str):
                continue
            tools[name] = {
                "name": name,
                "source": path.relative_to(ROOT).as_posix(),
                "line": node.lineno,
                "category": literal(kwargs.get("category")),
                "business_context_required": literal(kwargs.get("business_context_required"), True),
                "roles": role_names(kwargs.get("allowed_roles")),
                "required_permissions": literal(kwargs.get("required_permissions"), []) or [],
                "requires_approval": literal(kwargs.get("requires_approval"), False),
                "risk_level": literal(kwargs.get("risk_level"), "safe"),
                "is_readonly": literal(kwargs.get("is_readonly"), True),
            }
    return tools


def permission_policy(name: str, tool: dict[str, Any]) -> str:
    # Matches permission_policy_for_name() special cases; an explicit manifest
    # policy takes precedence over the built-in name groups.
    entry = tool["manifest"]
    if entry.get("permission_policy"):
        return str(entry["permission_policy"])
    special = {
        "handler": {"query_business_data", "batch_query_business_data", "list_queryable_fields"},
        "self_scoped": {"read_memory", "upsert_memory_entry", "delete_memory_entry"},
        "agent_internal": {"create_session_plan", "list_session_todos", "update_session_todo", "spawn_subagent", "await_subagent", "cancel_subagent"},
        "user_context": {"resolve_date_range", "list_my_businesses", "list_announcements", "list_user_notifications", "get_business_info"},
    }
    for policy, names in special.items():
        if name in names:
            return policy
    return "required"


def enrich(tools: dict[str, dict[str, Any]], manifest: dict[str, dict[str, Any]]) -> list[dict[str, Any]]:
    result = []
    for name, tool in tools.items():
        entry = manifest.get(name, {})
        tool["manifest"] = entry
        side_effect = str(entry.get("side_effect", "none"))
        intent_write = bool(entry.get("intent_write", False))
        always_confirm = bool(entry.get("always_confirm", False))
        tool["domains"] = list(entry.get("domains", []))
        tool["capability"] = entry.get("capability")
        tool["permission_policy"] = permission_policy(name, tool)
        tool["intent_write"] = intent_write
        tool["always_confirm"] = always_confirm
        tool["side_effect"] = side_effect
        # ai_mcp_service._mcp_readonly fails closed when any write metadata or
        # a non-read side-effect is present.
        tool["mcp_scope"] = "ai:tools:read" if (
            tool["is_readonly"] and not tool["requires_approval"] and
            not intent_write and not always_confirm and side_effect in ("none", "read")
        ) else "ai:tools:write"
        roles = set(tool["roles"])
        tool["potentially_listed_for_business_user"] = bool(
            tool["business_context_required"] and
            roles.intersection({"USER", "BUSINESS_OWNER"}) and
            entry.get("enabled", True) and not entry.get("deprecated", False)
        )
        del tool["manifest"]
        result.append(tool)
    return sorted(result, key=lambda x: x["name"])


def markdown(tools: list[dict[str, Any]], manifest_names: set[str]) -> str:
    user_tools = [t for t in tools if t["potentially_listed_for_business_user"]]
    groups: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for tool in user_tools:
        groups[tool["category"] or "uncategorized"].append(tool)
    read_count = sum(t["mcp_scope"] == "ai:tools:read" for t in user_tools)
    write_count = len(user_tools) - read_count
    lines = [
        "# Hesabix AI/MCP tool catalog (generated)", "",
        "> Generated by `scripts/generate_registry_catalog.py` from the checked-in AI registry and Tool Manifest. This is a source-level inventory, not a promise that every item appears for every account. The live MCP server additionally filters by enabled/deprecated status, business context, role, and current user permissions. The runtime is authoritative.", "",
        "## Permission model", "",
        "- `ai:tools:read`: baseline MCP scope. It exposes only tools classified read-only by `_mcp_readonly`.",
        "- `ai:tools:write`: separately consented MCP scope. OAuth users select write tools during the consent flow; manual bearer connections with write access can only be created by the business owner. Each tool still passes current Hesabix permission checks.",
        "- A direct MCP `tools/call` executes an authorized write handler without running the in-chat approval flow. The MCP client must preview the exact action and arguments and obtain transaction-specific user confirmation before sending the call; the server does not independently verify that confirmation.",
        "- MCP write-scope classification means the server does not mark the tool read-only. It does not always mean a financial record is written: session-plan/todo tools mutate conversation state, while exports, workflow execution, and generic connectors can create artifacts or external effects.",
        "- `required_permissions`: per-tool business permission keys checked by the API, such as `reports.read` or `inventory.read`. These are independent of the two MCP OAuth scopes.",
        "- The model cannot grant a scope, select a different tenant, or turn a read call into an authorized write by supplying arguments.",
        "- `ask_hesabix_agent` is analyzer-only and is hidden for credentials with an explicit per-tool allowlist, including OAuth grants. The server exposes `hesabix://business/overview` and `hesabix://mcp/capabilities`; prompt availability depends on the connection's visible tool categories. See `mcp-prompts.md`.", "",
        f"Source-declared business tools potentially visible to a business user/owner: **{len(user_tools)}** ({read_count} read-scope, {write_count} write-scope). These are potential candidates; live role/permission filtering may remove them.", "",
        "Columns: tool name, MCP scope needed, application permissions, roles in source declaration, source category, and permission policy.", "",
    ]
    for category in sorted(groups):
        lines.extend([f"## `{category}`", "", "| Tool | MCP scope | Hesabix permissions | Roles | Permission policy |", "|---|---|---|---|---|"])
        for tool in groups[category]:
            perms = ", ".join(f"`{x}`" for x in tool["required_permissions"]) or "(policy/handler)"
            roles = ", ".join(tool["roles"]) or "dynamic/unspecified"
            lines.append(f"| `{tool['name']}` | `{tool['mcp_scope']}` | {perms} | {roles} | `{tool['permission_policy']}` |")
        lines.append("")
    excluded = [t for t in tools if not t["potentially_listed_for_business_user"]]
    lines.extend(["## Not exposed by the ordinary business-user MCP filter", "",
                  "These source declarations were excluded by the MCP layer's business-context/role filter, or are not enabled/current. They may serve other product surfaces or privileged roles and are not counted above.", "",
                  "| Tool | Category | Roles | Business context |", "|---|---|---|---|"])
    for tool in excluded:
        lines.append(f"| `{tool['name']}` | `{tool['category'] or ''}` | {', '.join(tool['roles']) or 'dynamic/unspecified'} | {tool['business_context_required']} |")
    lines.extend(["", "## Coverage and refresh", "",
                  f"Static AIFunction declarations found: **{len(tools)}**. Tool Manifest entries: **{len(manifest_names)}**. Manifest-only names without a literal AIFunction declaration are not included as registered tools.",
                  "Run the generator after registry or Tool Manifest changes. A live `tools/list` using a specific user's OAuth connection is still required to prove actual runtime visibility and effective tool schemas.", ""])
    return "\n".join(lines)


def main() -> None:
    tools = enrich(static_tools(), load_manifest())
    manifest_names = set(load_manifest())
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "registry-catalog.json").write_text(json.dumps({
        "generated_from": ["hesabixAPI/app/services/ai/function_registry.py", "hesabixAPI/app/services/ai/ai_function_extensions*.py", "hesabixAPI/app/services/ai/ai_tool_manifest.py"],
        "tool_count": len(tools), "tools": tools,
    }, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (OUT / "registry-catalog.md").write_text(markdown(tools, manifest_names), encoding="utf-8")
    print(f"Generated catalog for {len(tools)} statically declared tools: {OUT}")


if __name__ == "__main__":
    main()
