"""Unified Tool Discovery API — keyword/intent backend, no schemas.

Permission/tenant در Registry است. این ماژول Security موجود را صدا می‌زند
و فقط روی مجموعهٔ permissioned جستجو می‌کند.

Discovery ≠ Schema loading. خروجی فقط نام + metadata سبک است.
"""
from __future__ import annotations

import time
from dataclasses import dataclass
from typing import (
    AbstractSet,
    Iterable,
    List,
    Optional,
    Protocol,
    Set,
    Tuple,
)

from app.services.ai.ai_constants import (
    ADAPTIVE_DISCOVERY_K,
    DISCOVERY_HARD_MAX,
    HYBRID_TOOL_DISCOVERY,
    INDEXED_CANDIDATE_FALLBACK,
    INDEXED_CANDIDATE_RETRIEVAL,
    MAX_TOOLS_AUTONOMOUS,
    MAX_TOOLS_PER_REQUEST,
)
from app.services.ai.ai_execution_policy import (
    exposes_write_tools,
    resolve_execution_mode,
)
from app.services.ai.ai_ops_metrics import log_ai_event
from app.services.ai.ai_tool_index import get_tool_index
from app.services.ai.ai_tool_intent import (
    query_expects_tool_use,
    ranking_intent_domains,
    select_catalog_tool_names,
    select_tool_names,
)
from app.services.ai.ai_tool_manifest import get_manifest_entry
from app.services.ai.ai_tool_rank import score_tool_for_query
from app.services.ai.ai_tool_security import (
    classify_query_mutation,
    filter_security_candidates,
)

DISCOVERY_STRATEGY_KEYWORD = "keyword"


def resolve_discovery_limit(
    requested: Optional[int],
    *,
    default: int,
    hard_max: int = DISCOVERY_HARD_MAX,
) -> int:
    """requested_limit → effective_limit؛ هرگز از hard_max بالاتر نمی‌رود."""
    cap = max(1, int(hard_max))
    fallback = max(1, min(int(default), cap))
    if requested is None:
        return fallback
    try:
        value = int(requested)
    except (TypeError, ValueError):
        return fallback
    if value < 1:
        return fallback
    return min(value, cap)


@dataclass(frozen=True)
class ToolCandidate:
    """نتیجهٔ سبک Discovery — بدون JSON Schema."""

    name: str
    score: int = 0
    match_reason: str = "authorized"
    capability: str = ""
    namespace: str = ""
    domains: Tuple[str, ...] = ()
    side_effect: str = ""

    def to_dict(self) -> dict:
        return {
            "name": self.name,
            "score": self.score,
            "match_reason": self.match_reason,
            "capability": self.capability,
            "namespace": self.namespace,
            "domains": list(self.domains),
            "side_effect": self.side_effect,
        }


@dataclass(frozen=True)
class DiscoveryOffer:
    candidates: Tuple[ToolCandidate, ...] = ()
    strategy: str = DISCOVERY_STRATEGY_KEYWORD
    channel: str = "chat"
    execution_mode: str = ""
    mutation: str = ""
    requested_limit: Optional[int] = None
    effective_limit: int = 0
    authorized_count: int = 0
    latency_ms: float = 0.0
    ranked: bool = False
    capability: Optional[str] = None
    top_score: int = 0
    second_score: int = 0
    score_gap: int = 0
    low_confidence: bool = False
    fallback_names: Tuple[str, ...] = ()
    confidence_level: str = ""
    confidence_score: float = 0.0
    confidence_reason: str = ""
    recommended_k: int = 0
    adaptive_enabled: bool = False
    indexed_enabled: bool = False
    indexed_fallback: bool = False
    indexed_fallback_reason: str = ""
    candidate_count: int = 0
    candidate_pool: Tuple[str, ...] = ()
    index_success: Optional[bool] = None
    index_latency_ms: float = 0.0
    rank_latency_ms: float = 0.0
    effective_candidate_retrieval: str = "full_authorized"
    expects_tools: bool = False

    def names(self) -> Set[str]:
        return {item.name for item in self.candidates}

    def __len__(self) -> int:
        return len(self.candidates)


class DiscoveryStrategy(Protocol):
    name: str

    def select(
        self,
        authorized: AbstractSet[str],
        query: Optional[str],
        *,
        limit: int,
        catalog: bool,
        history_messages: Optional[List[dict]],
        prefer_names: AbstractSet[str],
        protected_names: AbstractSet[str],
    ) -> Set[str]:
        ...


class KeywordIntentStrategy:
    """Backend فعلی: دامنهٔ کلیدواژه‌ای + rank واژه‌ای. بدون embedding."""

    name = DISCOVERY_STRATEGY_KEYWORD

    def select(
        self,
        authorized: AbstractSet[str],
        query: Optional[str],
        *,
        limit: int,
        catalog: bool,
        history_messages: Optional[List[dict]],
        prefer_names: AbstractSet[str],
        protected_names: AbstractSet[str],
    ) -> Set[str]:
        protected = {n for n in (protected_names or ()) if n} & authorized
        if catalog:
            return select_catalog_tool_names(
                authorized,
                query,
                max_tools=limit,
                protected_names=protected,
                prefer_names=prefer_names,
                history_messages=history_messages,
            )
        return select_tool_names(
            authorized,
            query,
            max_tools=limit,
            history_messages=history_messages,
            prefer_names=prefer_names,
            protected_names=protected,
        )


class SemanticStrategy:
    """Semantic add-on over authorized names only. Not the default engine."""

    name = "semantic"

    def select(
        self,
        authorized: AbstractSet[str],
        query: Optional[str],
        *,
        limit: int,
        catalog: bool,
        history_messages: Optional[List[dict]],
        prefer_names: AbstractSet[str],
        protected_names: AbstractSet[str],
    ) -> Set[str]:
        from app.services.ai.ai_tool_hybrid import (
            WEIGHT_SEMANTIC_DOMINANT,
            hybrid_select_names,
        )

        return hybrid_select_names(
            authorized,
            query,
            limit=limit,
            prefer_names=prefer_names,
            protected_names=protected_names,
            history_messages=history_messages,
            weights=WEIGHT_SEMANTIC_DOMINANT,
        )


class HybridStrategy:
    """Lexical/intent ranker + semantic fusion. Security already applied."""

    name = "hybrid"

    def select(
        self,
        authorized: AbstractSet[str],
        query: Optional[str],
        *,
        limit: int,
        catalog: bool,
        history_messages: Optional[List[dict]],
        prefer_names: AbstractSet[str],
        protected_names: AbstractSet[str],
    ) -> Set[str]:
        from app.services.ai.ai_tool_hybrid import hybrid_select_names

        return hybrid_select_names(
            authorized,
            query,
            limit=limit,
            prefer_names=prefer_names,
            protected_names=protected_names,
            history_messages=history_messages,
        )


def _default_strategy() -> DiscoveryStrategy:
    if HYBRID_TOOL_DISCOVERY:
        return HybridStrategy()
    return KeywordIntentStrategy()


class DiscoveryEngine:
    def __init__(self, strategy: Optional[DiscoveryStrategy] = None) -> None:
        self.strategy: DiscoveryStrategy = strategy or _default_strategy()

    def discover(
        self,
        query: Optional[str] = None,
        *,
        permissioned_names: Iterable[str],
        execution_mode: Optional[str] = None,
        limit: Optional[int] = None,
        history_messages: Optional[List[dict]] = None,
        forced_names: Optional[AbstractSet[str]] = None,
        prefer_names: Optional[AbstractSet[str]] = None,
        protected_names: Optional[AbstractSet[str]] = None,
        channel: str = "chat",
        capability: Optional[str] = None,
        rank: Optional[bool] = None,
        unknown_policy: str = "deny",
        apply_adaptive: Optional[bool] = None,
        apply_indexed: Optional[bool] = None,
    ) -> DiscoveryOffer:
        started = time.perf_counter()
        mode = resolve_execution_mode(execution_mode)
        should_rank = bool(query and str(query).strip()) if rank is None else bool(rank)
        catalog = exposes_write_tools(mode)
        default_limit = (
            MAX_TOOLS_AUTONOMOUS
            if catalog
            else MAX_TOOLS_PER_REQUEST
        )
        if not should_rank:
            default_limit = DISCOVERY_HARD_MAX
        effective_limit = resolve_discovery_limit(limit, default=default_limit)
        permissioned = {n for n in permissioned_names if n}
        forced = {n for n in (forced_names or ()) if n} & permissioned
        prefer = {n for n in (prefer_names or ()) if n} & permissioned
        hist = history_messages if isinstance(history_messages, list) else None
        mutation = classify_query_mutation(query, hist)

        authorized = filter_security_candidates(
            permissioned,
            query,
            execution_mode=mode,
            forced_names=forced,
            history_messages=hist,
            unknown_policy=unknown_policy,
        )
        prefer &= authorized
        cap_filter = (capability or "").strip()
        if cap_filter:
            from app.services.ai.ai_tool_capability import capability_matches

            idx = get_tool_index()
            cap_names = {
                name
                for name in authorized
                if capability_matches(idx.capabilities.get(name, ""), cap_filter)
            }
            prefer |= cap_names

        selected: Set[str]
        indexed_on = (
            INDEXED_CANDIDATE_RETRIEVAL if apply_indexed is None else bool(apply_indexed)
        )
        indexed_fallback = False
        indexed_fallback_reason = ""
        candidate_pool: Set[str] = set(authorized)
        index_latency_ms = 0.0
        rank_latency_ms = 0.0
        index_success: Optional[bool] = None
        effective_candidate_retrieval = "full_authorized"
        if not authorized:
            selected = set()
            candidate_pool = set()
        elif not should_rank:
            selected = set(sorted(authorized)[:effective_limit])
        else:
            protected = {n for n in (protected_names or ()) if n} & authorized
            rank_universe = authorized
            if indexed_on:
                from app.services.ai.ai_tool_candidates import retrieve_candidates
                from app.services.ai.ai_tool_discovery_telemetry import (
                    EVENT_INDEX_CONSISTENCY,
                    EVENT_UNAUTHORIZED_CANDIDATE,
                    record_counter,
                    record_indexed_fallback,
                    record_indexed_stage_outcome,
                )
                from app.services.ai.ai_tool_index_health import (
                    FALLBACK_CONSISTENCY,
                    FALLBACK_DISABLED,
                    FALLBACK_EMPTY,
                    FALLBACK_ERROR,
                    FALLBACK_LOW,
                    FALLBACK_NORMALIZATION,
                    FALLBACK_STALE,
                    canonical_fallback_reason,
                    disabled_authorized_in_index,
                    index_consistency_ok,
                    last_refresh_epoch,
                    normalization_blocked,
                    refresh_stale_authorized,
                )
                from app.services.ai.ai_tool_retrieval_index import get_retrieval_index

                store = get_retrieval_index()
                expects = query_expects_tool_use(query, hist)
                reason = ""
                index_success = False
                index_t0 = time.perf_counter()
                try:
                    if not last_refresh_epoch(store):
                        reason = FALLBACK_STALE
                    elif not index_consistency_ok(authorized, store):
                        reason = FALLBACK_CONSISTENCY
                        record_counter(
                            EVENT_INDEX_CONSISTENCY,
                            {"channel": channel or "chat", "mode": mode},
                        )
                    else:
                        _refreshed, stale_err = refresh_stale_authorized(authorized, store)
                        if stale_err:
                            reason = FALLBACK_STALE
                    if not reason:
                        cand = retrieve_candidates(
                            query,
                            authorized,
                            protected_names=protected | forced,
                            prefer_names=prefer,
                            intent_domains=ranking_intent_domains(query, hist),
                            expects_tools=expects,
                            fallback_on_empty=False,
                            include_vector=False,
                            index=store,
                        )
                        leaked = cand.as_set() - authorized
                        if leaked:
                            record_counter(
                                EVENT_UNAUTHORIZED_CANDIDATE,
                                {"channel": channel or "chat", "count": len(leaked)},
                            )
                            cand_names = cand.as_set() & authorized
                        else:
                            cand_names = cand.as_set()
                        if not cand_names:
                            if normalization_blocked(query) and expects:
                                reason = FALLBACK_NORMALIZATION
                            elif disabled_authorized_in_index(authorized, store) and expects:
                                reason = FALLBACK_DISABLED
                            else:
                                reason = FALLBACK_EMPTY
                        elif (
                            expects
                            and cand.keyword_hits == 0
                            and cand.capability_hits == 0
                        ):
                            reason = FALLBACK_LOW
                        else:
                            rank_universe = cand_names | protected | forced | prefer
                            rank_universe &= authorized
                            candidate_pool = set(rank_universe)
                except Exception:
                    reason = FALLBACK_ERROR
                index_latency_ms = round((time.perf_counter() - index_t0) * 1000.0, 3)
                if reason:
                    reason = canonical_fallback_reason(reason)
                    record_indexed_stage_outcome(
                        reason=reason,
                        channel=channel or "chat",
                        mode=mode,
                    )
                    if INDEXED_CANDIDATE_FALLBACK:
                        indexed_fallback = True
                        indexed_fallback_reason = reason
                        rank_universe = authorized
                        candidate_pool = set(authorized)
                        record_indexed_fallback(
                            channel=channel or "chat",
                            mode=mode,
                            reason=reason,
                            candidate_count=len(authorized),
                            latency_ms=index_latency_ms,
                        )
                    else:
                        indexed_fallback_reason = reason
                        rank_universe = set()
                        candidate_pool = set()
                else:
                    record_indexed_stage_outcome(
                        reason="",
                        channel=channel or "chat",
                        mode=mode,
                    )
                    index_success = True
                    effective_candidate_retrieval = "indexed"
            rank_t0 = time.perf_counter()
            selected = self.strategy.select(
                rank_universe,
                query,
                limit=effective_limit,
                catalog=catalog,
                history_messages=hist,
                prefer_names=prefer,
                protected_names=protected | forced,
            )
            selected |= forced
            selected &= authorized
            rank_latency_ms = round((time.perf_counter() - rank_t0) * 1000.0, 3)

        if len(selected) > DISCOVERY_HARD_MAX:
            keep = set(forced & selected)
            rest = sorted(selected - keep)
            room = max(0, DISCOVERY_HARD_MAX - len(keep))
            selected = keep | set(rest[:room])

        core = get_tool_index().core_names
        intent_domains = ranking_intent_domains(query, hist) if should_rank else set()
        built = [
            _build_candidate(
                name,
                query=query or "",
                forced=forced,
                prefer=prefer,
                core=core,
                intent_domains=intent_domains,
            )
            for name in selected
        ]
        built.sort(key=lambda item: (-int(item.score), item.name))
        expects_tools = query_expects_tool_use(query, hist)
        top_score = int(built[0].score) if built else 0
        second_score = int(built[1].score) if len(built) > 1 else 0
        gap = top_score - second_score
        low_confidence = (not expects_tools and top_score <= 4) or top_score <= 0
        fallback: Tuple[str, ...] = ()
        # Empty only when the query is not data-domain and nothing scored.
        # False-empty on a valid query is worse than extra candidates.
        if (
            should_rank
            and not forced
            and not expects_tools
            and top_score <= 0
        ):
            fallback = tuple(
                name for name in sorted(core & authorized)
                if name not in {item.name for item in built[:3]}
            )[:8]
            built = []
            low_confidence = True
        candidates = tuple(built)
        from app.services.ai.ai_tool_adaptive_k import (
            recommended_k_for_scores,
            truncate_ranked,
        )
        from app.services.ai.ai_tool_rollout import record_empty_discovery

        conf, rec_k = recommended_k_for_scores(
            top_score=top_score,
            second_score=second_score,
            candidate_count=len(candidates),
            query=query,
            history_messages=hist,
        )
        if (ADAPTIVE_DISCOVERY_K if apply_adaptive is None else bool(apply_adaptive)) and should_rank and candidates:
            candidates = truncate_ranked(
                candidates,
                rec_k,
                forced_names=forced,
            )
            effective_limit = min(effective_limit, max(rec_k, len(forced)))
            adaptive_on = True
        else:
            adaptive_on = bool(
                ADAPTIVE_DISCOVERY_K if apply_adaptive is None else apply_adaptive
            )
        if should_rank and not candidates:
            record_empty_discovery(
                channel=channel or "chat",
                query_expects_tools=expects_tools,
            )
        latency_ms = round((time.perf_counter() - started) * 1000.0, 3)
        offer = DiscoveryOffer(
            candidates=candidates,
            strategy=getattr(self.strategy, "name", DISCOVERY_STRATEGY_KEYWORD),
            channel=channel or "chat",
            execution_mode=mode,
            mutation=mutation.value,
            requested_limit=limit,
            effective_limit=effective_limit,
            authorized_count=len(authorized),
            latency_ms=latency_ms,
            ranked=should_rank,
            capability=cap_filter or None,
            top_score=top_score,
            second_score=second_score,
            score_gap=gap,
            low_confidence=low_confidence,
            fallback_names=fallback,
            confidence_level=conf.level,
            confidence_score=conf.score,
            confidence_reason=conf.reason,
            recommended_k=rec_k,
            adaptive_enabled=adaptive_on,
            indexed_enabled=indexed_on,
            indexed_fallback=indexed_fallback,
            indexed_fallback_reason=indexed_fallback_reason,
            candidate_count=len(candidate_pool),
            candidate_pool=tuple(sorted(candidate_pool)),
            index_success=index_success,
            index_latency_ms=index_latency_ms,
            rank_latency_ms=rank_latency_ms,
            effective_candidate_retrieval=effective_candidate_retrieval,
            expects_tools=bool(expects_tools),
        )
        _observe(offer)
        return offer


_ENGINE = DiscoveryEngine()


def get_discovery_engine() -> DiscoveryEngine:
    return _ENGINE


def discover_tools(
    query: Optional[str] = None,
    *,
    permissioned_names: Iterable[str],
    execution_mode: Optional[str] = None,
    limit: Optional[int] = None,
    history_messages: Optional[List[dict]] = None,
    forced_names: Optional[AbstractSet[str]] = None,
    prefer_names: Optional[AbstractSet[str]] = None,
    protected_names: Optional[AbstractSet[str]] = None,
    channel: str = "chat",
    capability: Optional[str] = None,
    rank: Optional[bool] = None,
    unknown_policy: str = "deny",
    strategy: Optional[DiscoveryStrategy] = None,
    apply_adaptive: Optional[bool] = None,
    apply_indexed: Optional[bool] = None,
) -> DiscoveryOffer:
    """API واحد Discovery. Schema کامل برنمی‌گرداند.

    permissioned_names باید از قبل از Registry آمده باشد.
    Security (side_effect / mutation / mode) همیشه اینجا اعمال می‌شود.
    """
    engine = DiscoveryEngine(strategy) if strategy is not None else get_discovery_engine()
    return engine.discover(
        query,
        permissioned_names=permissioned_names,
        execution_mode=execution_mode,
        limit=limit,
        history_messages=history_messages,
        forced_names=forced_names,
        prefer_names=prefer_names,
        protected_names=protected_names,
        channel=channel,
        capability=capability,
        rank=rank,
        unknown_policy=unknown_policy,
        apply_adaptive=apply_adaptive,
        apply_indexed=apply_indexed,
    )


def _build_candidate(
    name: str,
    *,
    query: str,
    forced: AbstractSet[str],
    prefer: AbstractSet[str],
    core: AbstractSet[str],
    intent_domains: AbstractSet[str] = frozenset(),
) -> ToolCandidate:
    entry = get_manifest_entry(name)
    score = score_tool_for_query(
        name,
        query,
        prefer=name in prefer,
        intent_domains=intent_domains,
    )
    reason = "authorized"
    if name in forced:
        reason = "forced"
    elif score > 0:
        reason = "keyword"
    elif name in prefer:
        reason = "prefer"
    elif name in core:
        reason = "core"
    return ToolCandidate(
        name=name,
        score=score,
        match_reason=reason,
        capability=(entry.capability if entry else ""),
        namespace=(entry.namespace if entry else ""),
        domains=(entry.domains if entry else ()),
        side_effect=(entry.side_effect if entry else ""),
    )


def _observe(offer: DiscoveryOffer) -> None:
    """متریک بدون متن query، بدون PII و بدون دادهٔ مالی."""
    names = sorted(offer.names())
    log_ai_event(
        "tool_discovery",
        extra={
            "channel": offer.channel,
            "mode": offer.execution_mode,
            "mutation": offer.mutation,
            "strategy": offer.strategy,
            "ranked": offer.ranked,
            "selected_count": len(names),
            "selected_tools": names,
            "requested_limit": offer.requested_limit,
            "limit": offer.effective_limit,
            "discovery_latency_ms": offer.latency_ms,
            "capability": offer.capability,
            "top_score": offer.top_score,
            "score_gap": offer.score_gap,
            "low_confidence": offer.low_confidence,
            "confidence_level": offer.confidence_level,
            "recommended_k": offer.recommended_k,
            "effective_k": len(names),
            "adaptive_enabled": offer.adaptive_enabled,
            "indexed_enabled": offer.indexed_enabled,
            "indexed_fallback": offer.indexed_fallback,
            "indexed_fallback_reason": offer.indexed_fallback_reason or None,
            "authorized_count": offer.authorized_count,
            "candidate_count": offer.candidate_count,
            "final_tool_count": len(names),
            "index_success": offer.index_success,
            "index_latency_ms": offer.index_latency_ms,
            "rank_latency_ms": offer.rank_latency_ms,
            "effective_candidate_retrieval": offer.effective_candidate_retrieval,
            "average_k": len(names),
        },
    )
