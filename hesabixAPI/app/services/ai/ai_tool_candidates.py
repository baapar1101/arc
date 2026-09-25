"""Stage-1 candidate retrieval. Not ranking and not authorization.

Contract (independent control planes):

    Candidate Index     → maximize candidate recall (this module)
    Final Ranker        → maximize relevance (Phase 6)
    Adaptive K          → control final tool surface (flag off)
    Schema Loader       → control LLM context (flag off)
    Security            → authorize everything (before this module)

The index is only a Candidate Generator. Final Top-K is always the ranker.
Permissions are never stored in the index; callers pass an Authorized Set.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import AbstractSet, Iterable, Optional, Set, Tuple

from app.services.ai.ai_constants import (
    CANDIDATE_RETRIEVAL_N,
    INDEXED_CANDIDATE_FALLBACK,
    VECTOR_BRUTE_FORCE_MAX,
    VECTOR_CANDIDATE_RETRIEVAL,
)
from app.services.ai.ai_tool_retrieval_index import (
    ToolRetrievalIndex,
    get_retrieval_index,
)
from app.services.ai.ai_tool_text import tokenize_search_text


@dataclass(frozen=True)
class CandidateOffer:
    names: Tuple[str, ...]
    scores: Tuple[Tuple[str, int], ...]
    n: int
    keyword_hits: int
    domain_hits: int
    capability_hits: int
    vector_hits: int
    empty: bool
    fallback: bool
    latency_ms: float = 0.0

    def as_set(self) -> Set[str]:
        return set(self.names)


def retrieve_candidates(
    query: Optional[str],
    authorized: Iterable[str],
    *,
    n: int = CANDIDATE_RETRIEVAL_N,
    protected_names: Optional[AbstractSet[str]] = None,
    prefer_names: Optional[AbstractSet[str]] = None,
    intent_domains: Optional[AbstractSet[str]] = None,
    expects_tools: Optional[bool] = None,
    fallback_on_empty: bool = INDEXED_CANDIDATE_FALLBACK,
    include_vector: bool = VECTOR_CANDIDATE_RETRIEVAL,
    index: Optional[ToolRetrievalIndex] = None,
) -> CandidateOffer:
    """Return at most N authorized searchable names. Ranker is not invoked."""
    import time

    started = time.perf_counter()
    allowed = {name for name in authorized if name}
    store = index or get_retrieval_index()
    cap = max(1, int(n))
    protected = {name for name in (protected_names or ()) if name} & allowed
    prefer = {name for name in (prefer_names or ()) if name} & allowed
    q_tokens = tokenize_search_text(query or "")
    keyword_hits: Set[str] = set()
    overlap: dict[str, int] = {}
    for token in q_tokens:
        posting = store.lookup_token(token) & allowed
        keyword_hits |= posting
        for name in posting:
            overlap[name] = overlap.get(name, 0) + 1

    capability_hits: Set[str] = set()
    qset = set(q_tokens)
    if qset:
        from app.services.ai.ai_tool_capability import TOOL_CAPABILITIES

        for cap_key in TOOL_CAPABILITIES:
            cap_tokens = tokenize_search_text(cap_key)
            if cap_tokens and set(cap_tokens) <= qset:
                capability_hits |= store.lookup_capability(cap_key) & allowed

    domain_hits: Set[str] = set()
    for domain in intent_domains or ():
        domain_hits |= store.lookup_domain(str(domain)) & allowed

    vector_hits: Set[str] = set()
    if include_vector:
        vector_hits = _vector_candidates(query or "", allowed, limit=min(cap, 50))

    pool = set(keyword_hits) | capability_hits | vector_hits
    use_fallback = False
    if expects_tools is None:
        from app.services.ai.ai_tool_intent import query_expects_tool_use

        expects_tools = query_expects_tool_use(query)
    if expects_tools:
        pool |= domain_hits
    if not pool and expects_tools and fallback_on_empty:
        pool = set(allowed)
        use_fallback = True
    pool = {name for name in pool if _searchable(store, name)}
    pool &= allowed

    scored = []
    for name in pool:
        rec = store.get(name)
        token_score = overlap.get(name, 0)
        if rec is not None:
            token_score = max(token_score, len(set(q_tokens) & set(rec.tokens)))
        if name in capability_hits:
            token_score += 2
        if name in domain_hits and expects_tools:
            token_score += 1
        if name in prefer:
            token_score += 1
        scored.append((name, token_score))
    scored.sort(key=lambda item: (-item[1], item[0]))
    # Keep positive-overlap tools first; domain-only extras fill remaining N.
    ranked = [item for item in scored if item[1] > 0][:cap]
    if len(ranked) < cap:
        extras = [item for item in scored if item[1] <= 0]
        ranked.extend(extras[: cap - len(ranked)])
    names = {item[0] for item in ranked}
    names |= protected | prefer
    names &= allowed
    ordered = tuple(
        name for name, _score in sorted(
            ((n, dict(scored).get(n, 0)) for n in names),
            key=lambda item: (-item[1], item[0]),
        )
    )
    latency = round((time.perf_counter() - started) * 1000.0, 3)
    return CandidateOffer(
        names=ordered,
        scores=tuple(scored[:cap]),
        n=cap,
        keyword_hits=len(keyword_hits),
        domain_hits=len(domain_hits),
        capability_hits=len(capability_hits),
        vector_hits=len(vector_hits),
        empty=not ordered,
        fallback=use_fallback,
        latency_ms=latency,
    )


def retrieve_candidate_names(
    query: Optional[str],
    authorized: Iterable[str],
    **kwargs,
) -> Set[str]:
    return retrieve_candidates(query, authorized, **kwargs).as_set()


def _searchable(index: ToolRetrievalIndex, name: str) -> bool:
    rec = index.get(name)
    if rec is None:
        return True
    return rec.is_searchable()


def _vector_candidates(query: str, authorized: Set[str], *, limit: int) -> Set[str]:
    if not query.strip() or len(authorized) > VECTOR_BRUTE_FORCE_MAX:
        return set()
    from app.services.ai.ai_tool_embedding import get_tool_embedding_index

    hits = get_tool_embedding_index().query(query, authorized, limit=limit)
    return {name for name, _score in hits}
