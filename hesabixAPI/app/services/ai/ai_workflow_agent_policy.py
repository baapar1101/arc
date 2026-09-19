"""
سیاست ابزارهای AI داخل نود ai_agent در workflow — جلوگیری از حلقه و تغییرات خطرناک.
"""
from __future__ import annotations

from typing import AbstractSet, Any, FrozenSet, Iterable, List, Optional

from app.services.ai.ai_write_guard import is_write_function

# ابزارهایی که نود ai_agent در workflow به‌طور پیش‌فرض نباید صدا بزند
WORKFLOW_AGENT_DEFAULT_DENYLIST: FrozenSet[str] = frozenset({
    "create_workflow",
    "update_workflow",
    "delete_workflow",
    "test_workflow",
    "execute_workflow",
    "validate_workflow_draft",
    "get_workflow_execution_debug",
    "list_workflow_trigger_catalog",
    "list_workflow_action_catalog",
    "list_workflow_builtin_nodes",
    "get_workflow_component_schema",
    "get_workflow_design_rules",
})


def merge_workflow_agent_denylist(
    user_denylist: AbstractSet[str] | None = None,
) -> FrozenSet[str]:
    merged = set(WORKFLOW_AGENT_DEFAULT_DENYLIST)
    if user_denylist:
        merged.update(user_denylist)
    return frozenset(merged)


def filter_workflow_agent_tools(
    tools: Optional[Iterable[Any]],
    *,
    denylist: AbstractSet[str],
    allow_writes: bool = False,
    registry=None,
) -> List[Any]:
    """حذف ابزارهای خطرناک و (به‌طور پیش‌فرض) نوشتنی از کاتالوگ نود."""
    if not tools:
        return []
    out: List[Any] = []
    for item in tools:
        if not isinstance(item, dict):
            continue
        name = (item.get("function") or {}).get("name")
        if not name or name in denylist:
            continue
        if not allow_writes and is_write_function(str(name), registry):
            continue
        out.append(item)
    return out
