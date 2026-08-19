"""Security-first candidate filter — hard boundary, not a ranking signal.

Permission/tenant در Registry اعمال می‌شود.
این ماژول روی مجموعهٔ از قبل مجاز، side_effect و execution_mode را اعمال می‌کند
تا Tool خطرناک با Intent عمومی وارد Candidate نشود.

UNKNOWN → NOT CANDIDATE (fail-closed) مگر نام در Manifest نباشد و
unknown_policy=allow (فقط برای fillerهای تست ranking).
"""
from __future__ import annotations

import re
from enum import Enum
from typing import AbstractSet, Iterable, List, Optional, Set

from app.services.ai.ai_execution_policy import (
    EXECUTION_MODE_ANALYZER,
    resolve_execution_mode,
)
from app.services.ai.ai_tool_index import get_tool_index
from app.services.ai.ai_tool_manifest import get_manifest_entry
from app.services.ai.ai_tool_spec import ToolSideEffect


class QueryMutation(str, Enum):
    READ = "read"
    WRITE = "write"
    DESTRUCTIVE = "destructive"
    EXPORT = "export"
    EXECUTE = "execute"
    UNKNOWN = "unknown"


class ToolSecurityClass(str, Enum):
    READ_ONLY = "read_only"
    WRITE = "write"
    DESTRUCTIVE = "destructive"
    HIGH_RISK = "high_risk"
    UNKNOWN = "unknown"


_DESTRUCTIVE_QUERY = re.compile(
    r"حذف|پاک(?:\s*کن)?|delete\b|remove\b|فراموش(?:ش)?\s*کن|forget\b",
    re.IGNORECASE,
)
_EXPORT_QUERY = re.compile(
    r"خروجی|export\b|اکسل|excel|دانلود\s*لیست",
    re.IGNORECASE,
)
_EXECUTE_QUERY = re.compile(
    r"اجرای\s*(?:workflow|اتوماسیون)|execute_workflow|اتوماسیون\s*را\s*اجرا|"
    r"workflow\s*را\s*اجرا",
    re.IGNORECASE,
)
# بدون «حذف» — آن Destructive است
_WRITE_QUERY = re.compile(
    r"ثبت|ایجاد|اضافه|بساز|بزن|ویرایش|create|update|\badd\b|new\s+invoice|"
    r"مشتری\s+جدید|کالای\s+جدید|به\s*خاطر\s*بسپار|یادت\s*باشه|remember\b",
    re.IGNORECASE,
)
_LEADING_GREETING = re.compile(
    r"^(سلام|درود|صبح\s*بخیر|عصر\s*بخیر|وقت\s*بخیر|hello|hi|hey)[\s,،!؛:.]*",
    re.IGNORECASE,
)


def _strip_greeting(text: str) -> str:
    stripped = _LEADING_GREETING.sub("", (text or "").strip(), count=1).strip()
    return stripped or (text or "").strip()


def classify_query_mutation(
    user_query: Optional[str],
    history_messages: Optional[List[dict]] = None,
) -> QueryMutation:
    """کلاس جهش مورد نیاز کاربر — جدا از دامنهٔ مالی/انبار."""
    text = _strip_greeting(user_query or "")
    classified = _classify_text(text)
    if classified != QueryMutation.UNKNOWN and classified != QueryMutation.READ:
        return classified
    short = len(text) < 40
    if not history_messages or (classified == QueryMutation.READ and not short):
        return classified
    for msg in reversed(history_messages[-8:]):
        if msg.get("role") != "user":
            continue
        prior = _strip_greeting(str(msg.get("content") or ""))
        if len(prior) < 8:
            continue
        prior_class = _classify_text(prior)
        if prior_class in (
            QueryMutation.DESTRUCTIVE,
            QueryMutation.EXECUTE,
            QueryMutation.EXPORT,
            QueryMutation.WRITE,
        ):
            return prior_class
    return classified


def _classify_text(text: str) -> QueryMutation:
    q = (text or "").strip()
    if len(q) < 2:
        return QueryMutation.UNKNOWN
    if _DESTRUCTIVE_QUERY.search(q):
        return QueryMutation.DESTRUCTIVE
    if _EXECUTE_QUERY.search(q):
        return QueryMutation.EXECUTE
    if _EXPORT_QUERY.search(q):
        return QueryMutation.EXPORT
    if _WRITE_QUERY.search(q):
        return QueryMutation.WRITE
    return QueryMutation.READ


def classify_tool_security(name: str) -> ToolSecurityClass:
    """طبقه‌بندی از Manifest — prefix نام فقط از طریق side_effect ذخیره‌شده."""
    if not name:
        return ToolSecurityClass.UNKNOWN
    entry = get_manifest_entry(name)
    if entry is None or not entry.enabled:
        return ToolSecurityClass.UNKNOWN
    side = entry.side_effect or ToolSideEffect.NONE.value
    if side == ToolSideEffect.DELETE.value:
        return ToolSecurityClass.DESTRUCTIVE
    if side in (ToolSideEffect.EXECUTE.value, ToolSideEffect.EXPORT.value):
        return ToolSecurityClass.HIGH_RISK
    if side == ToolSideEffect.WRITE.value or entry.intent_write:
        return ToolSecurityClass.WRITE
    if side == ToolSideEffect.NONE.value:
        return ToolSecurityClass.READ_ONLY
    return ToolSecurityClass.UNKNOWN


def tool_side_effect(name: str) -> str:
    idx = get_tool_index()
    if name in idx.side_effects:
        return idx.side_effects[name]
    entry = get_manifest_entry(name)
    if entry is None:
        return ""
    return entry.side_effect


def mutation_allows_tool(
    name: str,
    mutation: QueryMutation,
    *,
    execution_mode: Optional[str] = None,
) -> bool:
    """Hard filter: True فقط اگر Tool برای این mutation و mode مجاز باشد."""
    mode = resolve_execution_mode(execution_mode) if execution_mode else None
    cls = classify_tool_security(name)
    if cls == ToolSecurityClass.UNKNOWN:
        return False
    if mode == EXECUTION_MODE_ANALYZER:
        return cls == ToolSecurityClass.READ_ONLY
    if cls == ToolSecurityClass.READ_ONLY:
        return True
    if mutation in (QueryMutation.READ, QueryMutation.UNKNOWN):
        return False
    if mutation == QueryMutation.WRITE:
        return cls == ToolSecurityClass.WRITE
    if mutation == QueryMutation.DESTRUCTIVE:
        return cls == ToolSecurityClass.DESTRUCTIVE
    if mutation == QueryMutation.EXPORT:
        return tool_side_effect(name) == ToolSideEffect.EXPORT.value
    if mutation == QueryMutation.EXECUTE:
        return tool_side_effect(name) == ToolSideEffect.EXECUTE.value
    return False


def filter_security_candidates(
    names: Iterable[str],
    user_query: Optional[str],
    *,
    execution_mode: Optional[str] = None,
    forced_names: Optional[AbstractSet[str]] = None,
    history_messages: Optional[List[dict]] = None,
    unknown_policy: str = "deny",
) -> Set[str]:
    """مجموعهٔ مجاز برای Discovery/Ranking. Security score وجود ندارد.

    unknown_policy:
      deny — نام خارج از Manifest حذف می‌شود (مسیر production)
      allow — نام ناشناخته نگه داشته می‌شود (filler تست ranking)
    """
    forced = {n for n in (forced_names or ()) if n}
    mutation = classify_query_mutation(user_query, history_messages)
    allowed: Set[str] = set()
    for name in names:
        if not name:
            continue
        if name in forced:
            allowed.add(name)
            continue
        cls = classify_tool_security(name)
        if cls == ToolSecurityClass.UNKNOWN:
            if unknown_policy == "allow":
                allowed.add(name)
            continue
        if mutation_allows_tool(name, mutation, execution_mode=execution_mode):
            allowed.add(name)
    return allowed
