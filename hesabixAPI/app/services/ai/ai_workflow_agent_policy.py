"""
سیاست ابزارهای AI داخل نود ai_agent در workflow — جلوگیری از حلقه و تغییرات خطرناک.
"""
from __future__ import annotations

from typing import AbstractSet, FrozenSet

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
