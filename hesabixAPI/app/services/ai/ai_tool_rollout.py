"""Progressive schema rollout, rediscovery, and miss telemetry.

Cached schema / provider context is never an authorization decision.
Unauthorized tools are never queued into rediscovery.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import AbstractSet, Optional, Set

from app.services.ai.ai_constants import (
    MAX_DISCOVERY_RETRIES,
    PROGRESSIVE_CANARY_PERCENT,
    PROGRESSIVE_ROLLOUT_STAGE,
    PROGRESSIVE_SCHEMA_LOADING,
)
from app.services.ai.ai_ops_metrics import log_ai_event
from app.services.ai.ai_tool_discovery_telemetry import (
    EVENT_AUTHORIZATION_FAILURE,
    EVENT_INDEXED_RETRIEVAL_MISS,
    EVENT_REDISCOVERY_FAILED,
    EVENT_RETRIEVAL_MISS,
    EVENT_SCHEMA_MISS,
    EVENT_UNKNOWN_TOOL,
    classify_unoffered_tool,
    record_counter,
    record_rediscovery_queued,
    record_unoffered_tool,
)

STAGES = ("off", "eval", "canary", "majority", "full")


def progressive_rollout_allows(business_id: Optional[int] = None) -> bool:
    """Master flag still wins. Stage only narrows who sees progressive K."""
    if not PROGRESSIVE_SCHEMA_LOADING:
        return False
    stage = (PROGRESSIVE_ROLLOUT_STAGE or "off").strip().lower()
    if stage in {"off", "eval"}:
        return False
    if stage == "full":
        return True
    if business_id is None:
        return False
    bucket = int(business_id) % 100
    if stage == "canary":
        return bucket < max(0, min(100, int(PROGRESSIVE_CANARY_PERCENT)))
    if stage == "majority":
        return bucket < 50
    return False


@dataclass
class RediscoveryState:
    retries: int = 0
    pending: bool = False
    force_names: Set[str] = field(default_factory=set)
    last_miss: str = ""


def record_discovery_miss(
    tool_name: str,
    *,
    offered: Optional[AbstractSet[str]],
    authorized: Optional[AbstractSet[str]] = None,
    reason: str = "unoffered",
) -> None:
    log_ai_event(
        "tool_discovery_miss",
        extra={
            "tool": tool_name,
            "reason": reason,
            "offered_count": len(offered or ()),
            "authorized_count": len(authorized or ()),
            "was_authorized": bool(authorized and tool_name in authorized),
        },
    )


def plan_unknown_tool_recovery(
    tool_name: str,
    state: RediscoveryState,
    *,
    authorized_names: Optional[AbstractSet[str]],
    offered_names: Optional[AbstractSet[str]],
    ranked_names: Optional[AbstractSet[str]] = None,
    in_registry: Optional[bool] = None,
    channel: str = "",
    arm: str = "",
    indexed_enabled: bool = False,
    candidate_pool: Optional[AbstractSet[str]] = None,
    indexed_fallback: bool = False,
    max_retries: int = MAX_DISCOVERY_RETRIES,
) -> dict:
    """Queue an authorized-but-unoffered tool for the next schema round.

    Never executes the current call. Never treats cache as permission.
    Never rediscovers unauthorized or unknown-registry names.
    """
    name = (tool_name or "").strip()
    authorized = set(authorized_names or ())
    offered = set(offered_names or ())
    ranked = set(ranked_names) if ranked_names is not None else set(offered)
    registered = bool(in_registry) if in_registry is not None else name in authorized
    kind = classify_unoffered_tool(
        name=name,
        in_registry=registered,
        authorized=bool(name) and name in authorized,
        in_ranked_candidates=bool(name) and name in ranked,
        in_offered_schemas=bool(name) and name in offered,
        indexed_enabled=indexed_enabled,
        in_candidate_pool=(
            None if candidate_pool is None else bool(name) and name in candidate_pool
        ),
        indexed_fallback=indexed_fallback,
    )
    if not name or not registered or name not in authorized:
        record_unoffered_tool(
            name or "unknown",
            kind=kind if kind in {EVENT_UNKNOWN_TOOL, EVENT_AUTHORIZATION_FAILURE} else EVENT_AUTHORIZATION_FAILURE,
            channel=channel,
            arm=arm,
        )
        return {
            "rediscovery": False,
            "reason": "unauthorized_or_unknown",
            "force_names": [],
            "kind": kind if name else EVENT_UNKNOWN_TOOL,
        }
    if name in offered:
        record_unoffered_tool(
            name,
            kind=EVENT_UNKNOWN_TOOL,
            channel=channel,
            arm=arm,
        )
        return {
            "rediscovery": False,
            "reason": "already_offered",
            "force_names": [],
            "kind": EVENT_UNKNOWN_TOOL,
        }
    record_unoffered_tool(
        name,
        kind=kind,
        rediscovery=True,
        channel=channel,
        arm=arm,
    )
    if state.retries >= max_retries:
        record_counter(EVENT_REDISCOVERY_FAILED, {"tool": name})
        return {
            "rediscovery": False,
            "reason": "retry_exhausted",
            "force_names": [],
            "kind": kind,
        }
    state.retries += 1
    state.pending = True
    state.force_names.add(name)
    state.last_miss = name
    record_rediscovery_queued(name, retry=state.retries, max_retries=max_retries)
    return {
        "rediscovery": True,
        "reason": "queued_next_round",
        "force_names": sorted(state.force_names),
        "retry": state.retries,
        "kind": kind if kind in {
            EVENT_RETRIEVAL_MISS,
            EVENT_SCHEMA_MISS,
            EVENT_INDEXED_RETRIEVAL_MISS,
        } else EVENT_RETRIEVAL_MISS,
    }


def record_empty_discovery(*, channel: str, query_expects_tools: bool) -> None:
    log_ai_event(
        "empty_discovery",
        extra={"channel": channel, "expects_tools": query_expects_tools},
    )
