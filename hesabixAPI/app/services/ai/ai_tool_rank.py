"""رتبه‌بندی واژه‌ای ابزارها هنگام سقف ابزار در هر درخواست (TOOL-01).

بدون API دوم / embedding: نام ابزار + نام مستعار فارسی/انگلیسی در برابر متن سوال.
"""
from __future__ import annotations

import re
from typing import AbstractSet, Iterable, Optional, Set

from app.services.ai.ai_tool_index import get_tool_index

_TOKEN = re.compile(r"[\w\u0600-\u06FF]+", re.UNICODE)

# نام مستعار — منبع حقیقت Tool Manifest / Index
TOOL_ALIASES: dict[str, tuple[str, ...]] = dict(get_tool_index().aliases)


def tokenize_query(text: str) -> Set[str]:
    return {m.group(0).lower() for m in _TOKEN.finditer(text or "") if len(m.group(0)) >= 2}


def _name_tokens(tool_name: str) -> Set[str]:
    return {p for p in (tool_name or "").lower().replace("-", "_").split("_") if len(p) >= 2}


def score_tool_for_query(
    tool_name: str,
    user_query: str,
    *,
    prefer: bool = False,
) -> int:
    """امتیاز غیرمنفی؛ بالاتر = مرتبط‌تر با سوال."""
    q = (user_query or "").strip().lower()
    if not q or not tool_name:
        return 4 if prefer else 0
    score = 8 if prefer else 0
    q_tokens = tokenize_query(q)
    name_tokens = _name_tokens(tool_name)
    score += 2 * len(q_tokens & name_tokens)
    if tool_name.lower() in q:
        score += 6
    for alias in TOOL_ALIASES.get(tool_name, ()):
        alias_l = alias.lower()
        if not alias_l:
            continue
        if alias_l in q:
            score += 5 + min(len(alias_l), 12)
        alias_tokens = tokenize_query(alias_l)
        score += len(q_tokens & alias_tokens)
    return score


def rank_and_cap_tool_names(
    selected: Iterable[str],
    user_query: Optional[str],
    *,
    max_tools: int,
    core_names: AbstractSet[str],
    prefer_names: Optional[AbstractSet[str]] = None,
    protected_names: Optional[AbstractSet[str]] = None,
) -> Set[str]:
    """حفظ ابزارهای protected، سپس core/prefer، سپس پر کردن سقف با امتیاز واژه‌ای.

    protected هرگز به‌خاطر سقف حذف نمی‌شود (حتی اگر از max_tools بزرگ‌تر شود).
    """
    names = {n for n in selected if n}
    if len(names) <= max_tools:
        return names
    protected = set(protected_names or ()) & names
    if len(protected) >= max_tools:
        return protected
    prefer = set(prefer_names or ()) & names
    query = user_query or ""
    others = names - protected

    def sort_key(n: str) -> tuple:
        return (
            0 if n in prefer else 1,
            0 if n in core_names else 1,
            -score_tool_for_query(n, query, prefer=n in prefer),
            n,
        )

    ordered = sorted(others, key=sort_key)
    remaining = max_tools - len(protected)
    return protected | set(ordered[:remaining])
