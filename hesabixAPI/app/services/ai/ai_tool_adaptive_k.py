"""Adaptive Top-K policy — independent of providers and MCP.

Confidence is not permission. This module only truncates an already
authorized, already ranked candidate list.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import AbstractSet, Optional, Sequence, Tuple

from app.services.ai.ai_constants import DISCOVERY_HARD_MAX
from app.services.ai.ai_tool_confidence import (
    LEVEL_FAIL,
    LEVEL_HIGH,
    LEVEL_LOW,
    LEVEL_NONE,
    DiscoveryConfidence,
    assess_discovery_confidence,
)


@dataclass(frozen=True)
class AdaptiveKPolicy:
    """Thresholds are eval-calibrated starting points, not vendor magic."""

    name: str = "gap_v1"
    high_k: int = 10
    normal_k: int = 15
    low_k: int = 20
    expand_k: int = 30
    none_k: int = 5
    min_k: int = 5
    max_k: int = 30

    def recommend(self, confidence: DiscoveryConfidence) -> int:
        level = confidence.level
        if level == LEVEL_NONE:
            raw = self.none_k
        elif level == LEVEL_HIGH:
            raw = self.high_k
        elif level == LEVEL_LOW:
            raw = self.low_k
        elif level == LEVEL_FAIL:
            raw = self.expand_k
        else:
            raw = self.normal_k
        return max(self.min_k, min(int(self.max_k), int(raw)))


# Calibrated on Gold 2026-08-19.v1: lowest avg K with Recall >= 95%.
DEFAULT_ADAPTIVE_POLICY = AdaptiveKPolicy(
    name="tight",
    high_k=10,
    normal_k=10,
    low_k=15,
    expand_k=20,
    none_k=5,
    max_k=20,
)

EXPAND_POLICY = AdaptiveKPolicy(
    name="expand",
    high_k=15,
    normal_k=20,
    low_k=24,
    expand_k=30,
    none_k=5,
    max_k=30,
)


def recommended_k_for_scores(
    *,
    top_score: int,
    second_score: int,
    candidate_count: int,
    query: Optional[str],
    history_messages: Optional[list] = None,
    policy: Optional[AdaptiveKPolicy] = None,
    expand: bool = False,
    semantic_top: float = 0.0,
) -> Tuple[DiscoveryConfidence, int]:
    chosen = EXPAND_POLICY if expand else (policy or DEFAULT_ADAPTIVE_POLICY)
    prelim = assess_discovery_confidence(
        top_score=top_score,
        second_score=second_score,
        candidate_count=candidate_count,
        query=query,
        history_messages=history_messages,
        recommended_k=chosen.normal_k,
        semantic_top=semantic_top,
    )
    k = chosen.recommend(prelim)
    conf = assess_discovery_confidence(
        top_score=top_score,
        second_score=second_score,
        candidate_count=candidate_count,
        query=query,
        history_messages=history_messages,
        expects_tools=prelim.expects_tools,
        recommended_k=k,
        semantic_top=semantic_top,
    )
    return conf, k


def truncate_ranked(
    ranked: Sequence,
    k: int,
    *,
    forced_names: Optional[AbstractSet[str]] = None,
    hard_max: int = DISCOVERY_HARD_MAX,
) -> tuple:
    """Keep Top-K plus forced names. Never reintroduces unauthorized tools."""
    cap = max(1, min(int(k), int(hard_max)))
    forced = {n for n in (forced_names or ()) if n}
    kept = []
    seen: set[str] = set()
    for item in ranked:
        name = getattr(item, "name", None)
        if not name or name in seen:
            continue
        if len(kept) >= cap and name not in forced:
            continue
        kept.append(item)
        seen.add(name)
    for item in ranked:
        name = getattr(item, "name", None)
        if name in forced and name not in seen:
            kept.append(item)
            seen.add(name)
    return tuple(kept)
