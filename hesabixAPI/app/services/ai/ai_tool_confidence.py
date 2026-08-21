"""Discovery confidence — ranking signal only, never authorization."""
from __future__ import annotations

from dataclasses import dataclass
from typing import Optional, Sequence

from app.services.ai.ai_tool_intent import query_expects_tool_use

LEVEL_NONE = "none"
LEVEL_HIGH = "high"
LEVEL_NORMAL = "normal"
LEVEL_LOW = "low"
LEVEL_FAIL = "fail"


@dataclass(frozen=True)
class DiscoveryConfidence:
    """Independent of permission / tenant / security."""

    level: str
    score: float
    reason: str
    recommended_k: int
    top_score: int = 0
    second_score: int = 0
    score_gap: int = 0
    candidate_count: int = 0
    expects_tools: bool = False
    semantic_top: float = 0.0

    def to_dict(self) -> dict:
        return {
            "level": self.level,
            "score": round(self.score, 4),
            "reason": self.reason,
            "recommended_k": self.recommended_k,
            "top_score": self.top_score,
            "second_score": self.second_score,
            "score_gap": self.score_gap,
            "candidate_count": self.candidate_count,
            "expects_tools": self.expects_tools,
            "semantic_top": round(self.semantic_top, 4),
        }


def gap_from_scores(ranked_scores: Sequence[int]) -> tuple[int, int, int]:
    top = int(ranked_scores[0]) if ranked_scores else 0
    second = int(ranked_scores[1]) if len(ranked_scores) > 1 else 0
    return top, second, top - second


def assess_discovery_confidence(
    *,
    top_score: int = 0,
    second_score: int = 0,
    candidate_count: int = 0,
    query: Optional[str] = None,
    history_messages: Optional[list] = None,
    expects_tools: Optional[bool] = None,
    recommended_k: int = 15,
    semantic_top: float = 0.0,
    low_confidence_hint: bool = False,
) -> DiscoveryConfidence:
    """Build confidence from ranking signals. Does not look at authorization."""
    top = int(top_score)
    second = int(second_score)
    gap = top - second
    if expects_tools is None:
        expects_tools = query_expects_tool_use(query, history_messages)
        if low_confidence_hint and top <= 4:
            expects_tools = False

    if top <= 0 or (not expects_tools and top <= 4):
        level = LEVEL_NONE
        reason = "empty_or_no_match"
        strength = 0.05 if top > 0 else 0.0
    elif top >= 14 and gap >= 6:
        level = LEVEL_HIGH
        reason = "strong_top_and_gap"
        strength = min(1.0, 0.55 + top / 40.0 + gap / 40.0)
    elif top >= 8 and gap >= 3:
        level = LEVEL_NORMAL
        reason = "clear_top"
        strength = min(0.75, 0.4 + top / 50.0)
    elif top >= 5:
        level = LEVEL_LOW
        reason = "weak_gap"
        strength = min(0.45, 0.2 + top / 60.0)
    else:
        level = LEVEL_FAIL
        reason = "discovery_failure"
        strength = 0.1

    if semantic_top >= 0.72 and level in {LEVEL_LOW, LEVEL_FAIL}:
        reason = f"{reason}+semantic_support"
        strength = min(0.55, strength + 0.15)

    return DiscoveryConfidence(
        level=level,
        score=round(strength, 4),
        reason=reason,
        recommended_k=int(recommended_k),
        top_score=top,
        second_score=second,
        score_gap=gap,
        candidate_count=int(candidate_count),
        expects_tools=bool(expects_tools),
        semantic_top=float(semantic_top or 0.0),
    )
