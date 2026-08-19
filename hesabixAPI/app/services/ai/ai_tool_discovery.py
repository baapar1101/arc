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
    DISCOVERY_HARD_MAX,
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
    merge_tool_allowlists,
    query_expects_tool_use,
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
        if catalog:
            return select_catalog_tool_names(
                authorized,
                query,
                max_tools=limit,
                protected_names=protected_names,
                prefer_names=prefer_names,
                history_messages=history_messages,
            )
        return select_tool_names(
            authorized,
            query,
            max_tools=limit,
            history_messages=history_messages,
            prefer_names=prefer_names,
        )


class SemanticStrategy:
    """رزرو Phase بعد — در Phase 3 فعال نیست."""

    name = "semantic"

    def select(self, *args, **kwargs) -> Set[str]:
        raise NotImplementedError("Semantic tool discovery is not enabled")


class HybridStrategy:
    """رزرو Phase بعد — در Phase 3 فعال نیست."""

    name = "hybrid"

    def select(self, *args, **kwargs) -> Set[str]:
        raise NotImplementedError("Hybrid tool discovery is not enabled")


class DiscoveryEngine:
    def __init__(self, strategy: Optional[DiscoveryStrategy] = None) -> None:
        self.strategy: DiscoveryStrategy = strategy or KeywordIntentStrategy()

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
        if not authorized:
            selected = set()
        elif not should_rank:
            selected = set(sorted(authorized)[:effective_limit])
        else:
            protected = {n for n in (protected_names or ()) if n} & authorized
            if catalog and not protected:
                idx = get_tool_index()
                protected = set(idx.intent_write_names) & authorized
            selected = self.strategy.select(
                authorized,
                query,
                limit=effective_limit,
                catalog=catalog,
                history_messages=hist,
                prefer_names=prefer,
                protected_names=protected | forced,
            )
            selected = merge_tool_allowlists(
                selected,
                skill_names=prefer,
                forced_names=forced,
            )
            selected &= authorized

        if len(selected) > DISCOVERY_HARD_MAX:
            keep = set(forced & selected)
            rest = sorted(selected - keep)
            room = max(0, DISCOVERY_HARD_MAX - len(keep))
            selected = keep | set(rest[:room])

        core = get_tool_index().core_names
        built = [
            _build_candidate(
                name,
                query=query or "",
                forced=forced,
                prefer=prefer,
                core=core,
            )
            for name in selected
        ]
        built.sort(key=lambda item: (-int(item.score), item.name))
        candidates = tuple(built)
        top_score = int(candidates[0].score) if candidates else 0
        second_score = int(candidates[1].score) if len(candidates) > 1 else 0
        gap = top_score - second_score
        expects_tools = query_expects_tool_use(query, hist)
        low_confidence = (not expects_tools and top_score <= 4) or top_score <= 0
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
    )


def _build_candidate(
    name: str,
    *,
    query: str,
    forced: AbstractSet[str],
    prefer: AbstractSet[str],
    core: AbstractSet[str],
) -> ToolCandidate:
    entry = get_manifest_entry(name)
    score = score_tool_for_query(name, query, prefer=name in prefer)
    reason = "authorized"
    if name in forced:
        reason = "forced"
    elif name in prefer:
        reason = "prefer"
    elif name in core:
        reason = "core"
    elif score > 0:
        reason = "keyword"
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
            "candidate_count": offer.authorized_count,
            "selected_count": len(names),
            "selected_tools": names,
            "requested_limit": offer.requested_limit,
            "limit": offer.effective_limit,
            "discovery_latency_ms": offer.latency_ms,
            "capability": offer.capability,
            "top_score": offer.top_score,
            "score_gap": offer.score_gap,
            "low_confidence": offer.low_confidence,
        },
    )
