"""Phase 8 — confidence, adaptive K, hybrid, provider context, rollout."""
from __future__ import annotations

from app.services.ai.ai_constants import (
    ADAPTIVE_DISCOVERY_K,
    ADAPTIVE_K_ROLLOUT_PERCENT,
    HYBRID_TOOL_DISCOVERY,
    MAX_TOOLS_AUTONOMOUS,
    MAX_TOOLS_PER_REQUEST,
    PROGRESSIVE_SCHEMA_LOADING,
)
from app.services.ai.ai_provider_context import (
    attach_fingerprint_to_cache_key,
    resolve_provider_context_policy,
    tool_context_fingerprint,
)
from app.services.ai.ai_tool_adaptive_k import (
    DEFAULT_ADAPTIVE_POLICY,
    recommended_k_for_scores,
    truncate_ranked,
)
from app.services.ai.ai_tool_confidence import (
    LEVEL_HIGH,
    LEVEL_NONE,
    assess_discovery_confidence,
)
from app.services.ai.ai_tool_embedding import (
    hashed_ngram_vector,
    metadata_content_hash,
    reset_tool_embedding_index_for_tests,
)
from app.services.ai.ai_tool_hybrid import HybridRanker, protect_semantic_score
from app.services.ai.ai_tool_rollout import (
    RediscoveryState,
    plan_unknown_tool_recovery,
    progressive_rollout_allows,
)
from app.services.ai.ai_tool_error import unknown_tool_result


class _Cand:
    def __init__(self, name: str, score: int) -> None:
        self.name = name
        self.score = score


def test_production_flags_stay_off():
    assert MAX_TOOLS_PER_REQUEST == 48
    assert MAX_TOOLS_AUTONOMOUS == 128
    assert PROGRESSIVE_SCHEMA_LOADING is False
    assert ADAPTIVE_DISCOVERY_K is False
    assert ADAPTIVE_K_ROLLOUT_PERCENT == 0
    assert HYBRID_TOOL_DISCOVERY is False
    assert progressive_rollout_allows(1) is False


def test_confidence_is_not_authorization():
    conf = assess_discovery_confidence(top_score=40, second_score=2, candidate_count=12)
    assert conf.level == LEVEL_HIGH
    assert conf.score > 0
    # High confidence still says nothing about permission.


def test_no_match_confidence_is_none():
    conf = assess_discovery_confidence(
        top_score=2,
        second_score=0,
        candidate_count=3,
        query="هوا امروز چطوره؟",
    )
    assert conf.level == LEVEL_NONE


def test_adaptive_high_confidence_recommends_k10():
    conf, k = recommended_k_for_scores(
        top_score=20,
        second_score=8,
        candidate_count=40,
        query="فاکتور فروش ۱۲ را نشان بده",
        policy=DEFAULT_ADAPTIVE_POLICY,
    )
    assert conf.level == LEVEL_HIGH
    assert k == 10


def test_truncate_keeps_forced_and_top_k():
    ranked = [_Cand("a", 9), _Cand("b", 8), _Cand("c", 7), _Cand("d", 6)]
    out = truncate_ranked(ranked, 2, forced_names={"d"})
    names = [item.name for item in out]
    assert names[:2] == ["a", "b"]
    assert "d" in names


def test_embedding_changes_when_text_changes():
    a = hashed_ngram_vector("search invoices sales")
    b = hashed_ngram_vector("delete warehouse document")
    assert a != b
    assert metadata_content_hash("x") != metadata_content_hash("y")
    reset_tool_embedding_index_for_tests()


def test_similar_tool_semantic_is_dampened_across_family():
    protected = protect_semantic_score(
        "delete_account",
        query="delete this check",
        mutation="destructive",
        semantic=0.9,
    )
    same = protect_semantic_score(
        "delete_check",
        query="delete this check",
        mutation="destructive",
        semantic=0.9,
    )
    assert protected < same


def test_hybrid_ranker_does_not_invent_unauthorized_names():
    ranker = HybridRanker()
    scored = ranker.score_authorized(
        ["search_invoices"],
        "فاکتور فروش",
    )
    assert set(scored) <= {"search_invoices"}


def test_fingerprint_is_stable_and_not_auth():
    a = tool_context_fingerprint([("search_invoices", "1.aaa"), ("list_accounts", "1.bbb")])
    b = tool_context_fingerprint([("list_accounts", "1.bbb"), ("search_invoices", "1.aaa")])
    c = tool_context_fingerprint([("search_invoices", "2.ccc"), ("list_accounts", "1.bbb")])
    assert a == b
    assert a != c
    key = attach_fingerprint_to_cache_key("hx:v1:user", a)
    assert a[:16] in key


def test_local_provider_resends_schemas():
    policy = resolve_provider_context_policy("local", fingerprint="abc")
    assert policy.send_tools_every_request is True
    assert policy.supports_tool_prefix_cache is False


def test_cached_context_does_not_authorize_unknown_tool():
    state = RediscoveryState()
    plan = plan_unknown_tool_recovery(
        "delete_invoice",
        state,
        authorized_names={"search_invoices"},
        offered_names={"search_invoices"},
    )
    assert plan["rediscovery"] is False
    assert plan["reason"] == "unauthorized_or_unknown"
    payload = unknown_tool_result("delete_invoice")
    assert payload["error"] == "UNKNOWN_TOOL"
    assert payload["rediscovery"] is False


def test_rediscovery_queues_authorized_unoffered_once():
    state = RediscoveryState()
    first = plan_unknown_tool_recovery(
        "search_invoices",
        state,
        authorized_names={"search_invoices", "list_accounts"},
        offered_names={"list_accounts"},
    )
    second = plan_unknown_tool_recovery(
        "search_invoices",
        state,
        authorized_names={"search_invoices", "list_accounts"},
        offered_names={"list_accounts"},
    )
    assert first["rediscovery"] is True
    assert second["rediscovery"] is False
    assert "search_invoices" in first["force_names"]
