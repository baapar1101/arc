"""Permission policy for AI tools — جدا از side_effect.

Permission = آیا این کاربر مجاز است؟
Security metadata = این Tool چه اثری دارد؟

لیست خالی required_permissions دیگر به معنی ALLOW نیست مگر سیاست صریح.
"""
from __future__ import annotations

from typing import Any, Optional, Sequence

PERMISSION_POLICY_REQUIRED = "required"
PERMISSION_POLICY_HANDLER = "handler"
PERMISSION_POLICY_SELF_SCOPED = "self_scoped"
PERMISSION_POLICY_AGENT_INTERNAL = "agent_internal"
PERMISSION_POLICY_USER_CONTEXT = "user_context"
PERMISSION_POLICY_UNSPECIFIED = "unspecified"

ALLOWED_EMPTY_PERMISSION_POLICIES = frozenset({
    PERMISSION_POLICY_HANDLER,
    PERMISSION_POLICY_SELF_SCOPED,
    PERMISSION_POLICY_AGENT_INTERNAL,
    PERMISSION_POLICY_USER_CONTEXT,
})

HANDLER_PERMISSION_TOOLS = frozenset({
    "query_business_data",
    "batch_query_business_data",
    "list_queryable_fields",
})
SELF_SCOPED_PERMISSION_TOOLS = frozenset({
    "read_memory",
    "upsert_memory_entry",
    "delete_memory_entry",
})
AGENT_INTERNAL_PERMISSION_TOOLS = frozenset({
    "create_session_plan",
    "list_session_todos",
    "update_session_todo",
    "spawn_subagent",
    "await_subagent",
    "cancel_subagent",
})
USER_CONTEXT_PERMISSION_TOOLS = frozenset({
    "resolve_date_range",
    "list_my_businesses",
    "list_announcements",
    "list_user_notifications",
    "get_business_info",
})


def permission_policy_for_name(
    name: str,
    *,
    required_permissions: Optional[Sequence[str]] = None,
    explicit: Optional[str] = None,
) -> str:
    if explicit:
        return explicit
    if name in HANDLER_PERMISSION_TOOLS:
        return PERMISSION_POLICY_HANDLER
    if name in SELF_SCOPED_PERMISSION_TOOLS:
        return PERMISSION_POLICY_SELF_SCOPED
    if name in AGENT_INTERNAL_PERMISSION_TOOLS:
        return PERMISSION_POLICY_AGENT_INTERNAL
    if name in USER_CONTEXT_PERMISSION_TOOLS:
        return PERMISSION_POLICY_USER_CONTEXT
    if required_permissions:
        return PERMISSION_POLICY_REQUIRED
    # پیش‌فرض: Permission باید روی AIFunction باشد. خالی + بدون سیاست صریح = fail-closed.
    return PERMISSION_POLICY_REQUIRED


def catalog_permission_allows(func: Any, user_context: Any, business_id: Optional[int]) -> bool:
    """Fail-closed: empty perms + unspecified policy → deny."""
    from app.services.ai.ai_permission_map import has_any_ai_tool_permission

    perms = list(getattr(func, "required_permissions", None) or [])
    policy = (
        getattr(func, "permission_policy", None)
        or permission_policy_for_name(getattr(func, "name", ""), required_permissions=perms)
    )
    if perms:
        return has_any_ai_tool_permission(user_context, perms, business_id=business_id)
    return policy in ALLOWED_EMPTY_PERMISSION_POLICIES
