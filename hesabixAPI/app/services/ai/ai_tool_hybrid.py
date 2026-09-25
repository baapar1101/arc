"""Hybrid ranker: lexical/intent first, semantic add-on, then fusion.

Existing `score_tool_for_query` is preserved. Semantic search only runs on
the authorized candidate universe. Weights must be eval-calibrated.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import AbstractSet, Dict, Iterable, Optional, Set, Tuple

from app.services.ai.ai_tool_embedding import get_tool_embedding_index
from app.services.ai.ai_tool_index import get_tool_index
from app.services.ai.ai_tool_intent import ranking_intent_domains
from app.services.ai.ai_tool_manifest import get_manifest_entry
from app.services.ai.ai_tool_rank import rank_and_cap_tool_names, score_all_tools
from app.services.ai.ai_tool_security import QueryMutation, classify_query_mutation

WEIGHT_LEXICAL_DOMINANT = {
    "name": "lexical_dominant",
    "lexical": 0.75,
    "semantic": 0.15,
    "intent": 0.07,
    "capability": 0.03,
}
WEIGHT_BALANCED = {
    "name": "balanced",
    "lexical": 0.50,
    "semantic": 0.30,
    "intent": 0.12,
    "capability": 0.08,
}
WEIGHT_SEMANTIC_DOMINANT = {
    "name": "semantic_dominant",
    "lexical": 0.30,
    "semantic": 0.50,
    "intent": 0.12,
    "capability": 0.08,
}

# Winner on Gold 2026-08-19.v1 — overwritten if eval disagrees.
DEFAULT_HYBRID_WEIGHTS = dict(WEIGHT_LEXICAL_DOMINANT)

_OPERATION_PREFIXES = (
    "delete",
    "update",
    "create",
    "get",
    "search",
    "list",
    "execute",
    "restore",
)


def query_operation(query: Optional[str], mutation: Optional[str] = None) -> Optional[str]:
    q = (query or "").lower()
    mut = (mutation or "").lower()
    if mut == QueryMutation.DESTRUCTIVE.value or "حذف" in q or "delete" in q:
        return "delete"
    if mut == QueryMutation.EXECUTE.value or "execute" in q:
        return "execute"
    if "ویرایش" in q or "update" in q or "اصلاح" in q:
        return "update"
    if "ایجاد" in q or "ثبت" in q or "create" in q or "بساز" in q:
        return "create"
    if "جستجو" in q or "search" in q:
        return "search"
    if "لیست" in q or "list" in q:
        return "list"
    return None


def tool_operation(name: str) -> str:
    prefix = (name or "").split("_", 1)[0].lower()
    return prefix if prefix in _OPERATION_PREFIXES else ""


def protect_semantic_score(
    name: str,
    *,
    query: Optional[str],
    mutation: Optional[str],
    semantic: float,
) -> float:
    """Damp cross-family similarity and same-prefix twins without entity overlap."""
    op = query_operation(query, mutation)
    tool_op = tool_operation(name)
    if op and tool_op and tool_op != op:
        return semantic * 0.12
    if not op or tool_op != op:
        return semantic
    q = (query or "").lower()
    entity_tokens = [p for p in (name or "").split("_")[1:] if len(p) >= 3]
    entry = get_manifest_entry(name)
    phrases = list(entity_tokens)
    if entry:
        phrases.extend(a.lower() for a in entry.aliases if a)
        phrases.extend(k.lower() for k in entry.keywords if k)
    if not phrases:
        return semantic
    if any(p and p in q for p in phrases):
        return semantic
    return semantic * 0.22


@dataclass(frozen=True)
class HybridScores:
    lexical: float
    semantic: float
    intent: float
    capability: float
    fused: float


class HybridRanker:
    def __init__(self, weights: Optional[dict] = None) -> None:
        self.weights = dict(weights or DEFAULT_HYBRID_WEIGHTS)

    def fuse(
        self,
        *,
        lexical: float,
        semantic: float,
        intent: float,
        capability: float,
    ) -> float:
        w = self.weights
        return (
            float(w.get("lexical", 0.0)) * lexical
            + float(w.get("semantic", 0.0)) * semantic
            + float(w.get("intent", 0.0)) * intent
            + float(w.get("capability", 0.0)) * capability
        )

    def score_authorized(
        self,
        authorized: Iterable[str],
        query: Optional[str],
        *,
        prefer_names: Optional[AbstractSet[str]] = None,
        history_messages: Optional[list] = None,
    ) -> Dict[str, HybridScores]:
        names = [n for n in authorized if n]
        allowed = set(names)
        domains = ranking_intent_domains(query, history_messages)
        mutation = classify_query_mutation(query, history_messages).value
        lexical = score_all_tools(
            allowed, query, prefer_names=prefer_names, intent_domains=domains
        )
        max_lex = max(lexical.values()) if lexical else 1
        sem_hits = {
            n: s
            for n, s in get_tool_embedding_index().query(
                query or "", allowed, limit=max(32, len(allowed))
            )
        }
        out: Dict[str, HybridScores] = {}
        idx = get_tool_index()
        q_cap = set((query or "").lower().replace(".", " ").split())
        for name in allowed:
            lex_n = (lexical.get(name, 0) or 0) / max(1, max_lex)
            raw_sem = float(sem_hits.get(name, 0.0))
            sem_n = protect_semantic_score(
                name, query=query, mutation=mutation, semantic=raw_sem
            )
            entry = get_manifest_entry(name)
            intent_n = 1.0 if entry and set(entry.domains) & set(domains) else 0.0
            cap = (idx.capabilities.get(name) or "").lower().replace(".", " ")
            cap_n = 1.0 if cap and any(tok and tok in cap for tok in q_cap if len(tok) > 3) else 0.0
            fused = self.fuse(
                lexical=lex_n,
                semantic=sem_n,
                intent=intent_n,
                capability=cap_n,
            )
            out[name] = HybridScores(lex_n, sem_n, intent_n, cap_n, fused)
        return out


def hybrid_select_names(
    authorized: AbstractSet[str],
    query: Optional[str],
    *,
    limit: int,
    prefer_names: AbstractSet[str],
    protected_names: AbstractSet[str],
    history_messages: Optional[list] = None,
    weights: Optional[dict] = None,
) -> Set[str]:
    """Rank authorized names only. Security already applied by caller."""
    allowed = {n for n in authorized if n}
    if not allowed:
        return set()
    protected = {n for n in protected_names if n} & allowed
    if not (query or "").strip():
        return rank_and_cap_tool_names(
            allowed,
            query,
            max_tools=limit,
            core_names=get_tool_index().core_names,
            prefer_names=prefer_names,
            protected_names=protected,
        )
    ranker = HybridRanker(weights)
    scored = ranker.score_authorized(
        allowed,
        query,
        prefer_names=prefer_names,
        history_messages=history_messages,
    )
    prefer = {n for n in prefer_names if n} & allowed
    core = get_tool_index().core_names

    def sort_key(name: str) -> tuple:
        item = scored[name]
        return (
            -item.fused,
            0 if name in prefer else 1,
            0 if name in core else 1,
            name,
        )

    ordered = sorted(
        (n for n, item in scored.items() if item.fused > 0.0 or n in protected),
        key=sort_key,
    )
    if len(protected) >= limit:
        return set(protected)
    remaining = limit - len(protected)
    picked = [n for n in ordered if n not in protected][:remaining]
    return protected | set(picked)
