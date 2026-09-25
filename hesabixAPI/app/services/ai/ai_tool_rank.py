"""رتبه‌بندی واژه‌ای ابزارها هنگام سقف ابزار در هر درخواست (TOOL-01).

Core is a ranking signal, not a reserved capacity.
Every authorized candidate is scored before Top-K truncation.

بدون embedding / LLM rerank: نام + alias + keyword + intent domain.
"""
from __future__ import annotations

import re
from typing import AbstractSet, Iterable, Optional, Sequence, Set, Tuple

from app.services.ai.ai_tool_index import get_tool_index
from app.services.ai.ai_tool_manifest import get_manifest_entry

_TOKEN = re.compile(r"[\w\u0600-\u06FF]+", re.UNICODE)

# Intent domain overlap — بخشی از امتیاز، نه bypass.
INTENT_DOMAIN_BONUS = 5
# Core هرگز به امتیاز اضافه نمی‌شود؛ فقط tie-break است.
PREFER_BONUS = 8


def _alias_map() -> dict:
    return dict(get_tool_index().aliases)


# سازگاری با تست‌هایی که TOOL_ALIASES را به‌صورت mapping می‌خوانند.
class _LiveAliases(dict):
    def __getitem__(self, key):
        return _alias_map()[key]

    def get(self, key, default=()):
        return _alias_map().get(key, default)

    def __contains__(self, key):
        return key in _alias_map()


TOOL_ALIASES = _LiveAliases()


def tokenize_query(text: str) -> Set[str]:
    return {m.group(0).lower() for m in _TOKEN.finditer(text or "") if len(m.group(0)) >= 2}


def _name_tokens(tool_name: str) -> Set[str]:
    return {p for p in (tool_name or "").lower().replace("-", "_").split("_") if len(p) >= 2}


def _phrases_for(tool_name: str) -> Tuple[str, ...]:
    entry = get_manifest_entry(tool_name)
    if entry is None:
        return tuple(_alias_map().get(tool_name) or ())
    seen: list[str] = []
    for item in entry.aliases + entry.keywords + entry.examples:
        text = (item or "").strip()
        if text and text not in seen:
            seen.append(text)
    return tuple(seen)


def _tool_domains(tool_name: str) -> Tuple[str, ...]:
    entry = get_manifest_entry(tool_name)
    if entry is not None:
        return entry.domains
    return ()


def _capability_tokens(tool_name: str) -> Set[str]:
    entry = get_manifest_entry(tool_name)
    if entry is None or not entry.capability:
        return set()
    parts = entry.capability.lower().replace(".", "_").split("_")
    return {p for p in parts if len(p) >= 3}


def score_tool_for_query(
    tool_name: str,
    user_query: str,
    *,
    prefer: bool = False,
    intent_domains: Optional[AbstractSet[str]] = None,
) -> int:
    """امتیاز غیرمنفی؛ بالاتر = مرتبط‌تر با سوال.

    core_bonus در امتیاز نیست. prefer فقط bonus امتیازی است نه reservation.
    """
    q = (user_query or "").strip().lower()
    if not q or not tool_name:
        return PREFER_BONUS if prefer else 0
    score = PREFER_BONUS if prefer else 0
    q_tokens = tokenize_query(q)
    name_tokens = _name_tokens(tool_name)
    score += 2 * len(q_tokens & name_tokens)
    if tool_name.lower() in q:
        score += 6
    for phrase in _phrases_for(tool_name):
        phrase_l = phrase.lower()
        if not phrase_l:
            continue
        if phrase_l in q:
            score += 5 + min(len(phrase_l), 12)
        phrase_tokens = tokenize_query(phrase_l)
        score += len(q_tokens & phrase_tokens)
    if intent_domains:
        if set(_tool_domains(tool_name)) & set(intent_domains):
            score += INTENT_DOMAIN_BONUS
    cap_tokens = _capability_tokens(tool_name)
    if cap_tokens:
        score += len(q_tokens & cap_tokens)
    return score


def rank_and_cap_tool_names(
    selected: Iterable[str],
    user_query: Optional[str],
    *,
    max_tools: int,
    core_names: AbstractSet[str],
    prefer_names: Optional[AbstractSet[str]] = None,
    protected_names: Optional[AbstractSet[str]] = None,
    intent_domains: Optional[AbstractSet[str]] = None,
) -> Set[str]:
    """Score every candidate, then take Top-K.

    protected (forced / mutation ایمنی) هرگز به‌خاطر سقف حذف نمی‌شود.
    prefer و core فقط tie-break هستند؛ ظرفیت Top-K را reserve نمی‌کنند.
    """
    names = {n for n in selected if n}
    protected = set(protected_names or ()) & names
    prefer = set(prefer_names or ()) & names
    query = user_query or ""
    domains = set(intent_domains or ())

    if len(protected) >= max_tools:
        return protected
    others = names - protected
    scored = {
        n: score_tool_for_query(
            n, query, prefer=n in prefer, intent_domains=domains
        )
        for n in others
    }

    def sort_key(n: str) -> tuple:
        return (
            -scored[n],
            0 if n in prefer else 1,
            0 if n in core_names else 1,
            n,
        )

    remaining = max_tools - len(protected)
    # امتیاز ۰ یعنی هیچ سیگنال relevance نیست — ظرفیت Top-K را پر نکن.
    ordered = sorted((n for n, s in scored.items() if s > 0), key=sort_key)
    return protected | set(ordered[:remaining])


def score_all_tools(
    names: Iterable[str],
    user_query: Optional[str],
    *,
    prefer_names: Optional[AbstractSet[str]] = None,
    intent_domains: Optional[AbstractSet[str]] = None,
) -> dict:
    prefer = set(prefer_names or ())
    domains = set(intent_domains or ())
    query = user_query or ""
    return {
        n: score_tool_for_query(
            n, query, prefer=n in prefer, intent_domains=domains
        )
        for n in names
        if n
    }
