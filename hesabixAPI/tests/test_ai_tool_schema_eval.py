"""Phase 7 — schema loading eval smoke + production K unchanged."""
from __future__ import annotations

from app.services.ai.ai_constants import (
    MAX_TOOLS_AUTONOMOUS,
    MAX_TOOLS_PER_REQUEST,
    PROGRESSIVE_SCHEMA_LOADING,
)
from app.services.ai.ai_tool_discovery_gold import load_gold_queries
from app.services.ai.ai_tool_schema_eval import simulate_mode


def test_production_discovery_k_unchanged():
    assert MAX_TOOLS_PER_REQUEST == 48
    assert MAX_TOOLS_AUTONOMOUS == 128
    assert PROGRESSIVE_SCHEMA_LOADING is False


def test_progressive_simulation_uses_fewer_wire_tokens_than_k48():
    gold = load_gold_queries()[:40]
    current = simulate_mode(k=48, progressive=False, rows=gold)
    progressive = simulate_mode(k=10, progressive=True, rows=gold)
    assert progressive["avg_wire_schema_tokens_per_request"] < current[
        "avg_wire_schema_tokens_per_request"
    ]
    assert progressive["recall"] <= current["recall"] + 1e-9
