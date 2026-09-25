"""Phase 11 — metadata coverage, index canary, flags stay off."""
from __future__ import annotations

from app.services.ai.ai_constants import (
    ADAPTIVE_DISCOVERY_K,
    ADAPTIVE_K_CANARY_SALT,
    ADAPTIVE_K_ROLLOUT_PERCENT,
    HYBRID_TOOL_DISCOVERY,
    INDEXED_CANDIDATE_CANARY_SALT,
    INDEXED_CANDIDATE_FALLBACK,
    INDEXED_CANDIDATE_RETRIEVAL,
    INDEXED_CANDIDATE_ROLLOUT_PERCENT,
    MAX_TOOLS_AUTONOMOUS,
    MAX_TOOLS_PER_REQUEST,
    PROGRESSIVE_SCHEMA_LOADING,
    VECTOR_CANDIDATE_RETRIEVAL,
)
from app.services.ai.ai_tool_canary import (
    resolve_adaptive_assignment,
    resolve_indexed_assignment,
    stable_canary_bucket,
)
from app.services.ai.ai_tool_candidates import retrieve_candidates
from app.services.ai.ai_tool_discovery import discover_tools
from app.services.ai.ai_tool_discovery_gold import load_gold_queries
from app.services.ai.ai_tool_discovery_telemetry import (
    EVENT_INDEXED_RETRIEVAL_MISS,
    EVENT_RETRIEVAL_MISS,
    classify_unoffered_tool,
)
from app.services.ai.ai_tool_intent import (
    _CATEGORY_TOOLS,
    _CORE_TOOL_NAMES,
    _WRITE_TOOLS,
    query_expects_tool_use,
    ranking_intent_domains,
)
from app.services.ai.ai_tool_manifest import get_manifest_entry
from app.services.ai.ai_tool_rank import score_tool_for_query
from app.services.ai.ai_tool_retrieval_index import ToolRetrievalIndex
from app.services.ai.ai_tool_rollout import RediscoveryState, plan_unknown_tool_recovery
from app.services.ai.ai_tool_spec import ToolManifestEntry
from app.services.ai.ai_tool_text import normalize_search_text, tokenize_search_text

PHASE11_MISS_IDS = ("ppl-05", "acc-21", "hard-gen-01", "plat-01", "exp-158")


def _catalog() -> set[str]:
    names = set(_CORE_TOOL_NAMES) | set(_WRITE_TOOLS)
    for group in _CATEGORY_TOOLS.values():
        names |= set(group)
    return names


def _fresh_index() -> ToolRetrievalIndex:
    index = ToolRetrievalIndex()
    index.rebuild_from_manifest()
    return index


def _posting_map(index: ToolRetrievalIndex) -> dict[str, set[str]]:
    out: dict[str, set[str]] = {}
    for name in index.names():
        rec = index.get(name)
        if rec is None or not rec.is_searchable():
            continue
        for token in rec.tokens:
            out.setdefault(token, set()).add(name)
    return out


def test_production_phase11_flags_stay_off():
    assert INDEXED_CANDIDATE_RETRIEVAL is False
    assert INDEXED_CANDIDATE_FALLBACK is True
    assert VECTOR_CANDIDATE_RETRIEVAL is False
    assert HYBRID_TOOL_DISCOVERY is False
    assert ADAPTIVE_DISCOVERY_K is False
    assert ADAPTIVE_K_ROLLOUT_PERCENT == 0
    assert PROGRESSIVE_SCHEMA_LOADING is False
    assert MAX_TOOLS_PER_REQUEST == 48
    assert MAX_TOOLS_AUTONOMOUS == 128


def test_five_gold_misses_are_now_in_candidate_set():
    gold = {row.id: row for row in load_gold_queries()}
    index = _fresh_index()
    catalog = list(index.names())
    for qid in PHASE11_MISS_IDS:
        row = gold[qid]
        offer = retrieve_candidates(
            row.query,
            catalog,
            n=100,
            intent_domains=ranking_intent_domains(row.query),
            expects_tools=query_expects_tool_use(row.query),
            fallback_on_empty=False,
            include_vector=False,
            index=index,
        )
        expected = set(row.primary_expected_tools)
        assert expected & offer.as_set(), (
            f"{qid} {row.query!r} expected {expected} not in candidates"
        )


def test_metadata_covers_real_query_language_not_stuffed_aliases():
    dashboard = get_manifest_entry("get_business_dashboard")
    assert dashboard is not None
    assert "reports_meta" in dashboard.domains
    text = dashboard.search_text("get_business_dashboard")
    for term in ("داشبورد", "گزارش کلی", "اوضاع"):
        assert term in text
    assert text.count("گزارش") < 8

    info = get_manifest_entry("get_business_info")
    assert info is not None
    assert "اطلاعات کسب‌وکار" in info.aliases

    person = get_manifest_entry("get_person_balance")
    assert person is not None
    assert "مانده حساب" in person.aliases

    currencies = get_manifest_entry("list_currencies")
    assert currencies is not None
    assert "ارزها" in currencies.aliases
    assert "لیست ارزها" in currencies.aliases


def test_indexed_canary_percent_zero_never_enables():
    for biz, user in ((1, 1), (99, 12), (1000, 4)):
        assigned = resolve_indexed_assignment(business_id=biz, user_id=user, percent=0)
        assert assigned.enabled is False
        assert assigned.arm == "control"


def test_indexed_assignment_is_stable_hides_ids_and_uses_own_salt():
    first = resolve_indexed_assignment(business_id=18, user_id=3, percent=25)
    second = resolve_indexed_assignment(business_id=18, user_id=3, percent=25)
    assert first.arm == second.arm
    assert first.bucket == second.bucket
    payload = first.to_log_dict()
    blob = str(payload)
    assert "18" not in blob
    assert "user_id" not in blob
    assert "business_id" not in blob
    adaptive_bucket = stable_canary_bucket(
        business_id=18, user_id=3, salt=ADAPTIVE_K_CANARY_SALT
    )
    indexed_bucket = stable_canary_bucket(
        business_id=18, user_id=3, salt=INDEXED_CANDIDATE_CANARY_SALT
    )
    assert indexed_bucket == first.bucket
    # Independent salts; buckets may coincide but must be computed separately.
    assert adaptive_bucket == stable_canary_bucket(
        business_id=18, user_id=3, salt=ADAPTIVE_K_CANARY_SALT
    )


def test_apply_indexed_still_uses_phase6_ranker_for_final_topk():
    catalog = _catalog()
    offer = discover_tools(
        "فاکتور فروش این ماه را پیدا کن",
        permissioned_names=catalog,
        execution_mode="analyzer",
        limit=10,
        apply_indexed=True,
        apply_adaptive=False,
    )
    assert INDEXED_CANDIDATE_RETRIEVAL is False
    assert offer.indexed_enabled is True
    assert offer.adaptive_enabled is False
    assert len(offer.candidates) <= 10
    scores = [item.score for item in offer.candidates]
    assert scores == sorted(scores, reverse=True)
    assert "search_invoices" in offer.names()
    offered = {item.name: item.score for item in offer.candidates}
    ranked_score = score_tool_for_query(
        "search_invoices",
        "فاکتور فروش این ماه را پیدا کن",
        intent_domains=ranking_intent_domains("فاکتور فروش این ماه را پیدا کن"),
    )
    assert offered["search_invoices"] == ranked_score


def test_indexed_fallback_stays_inside_authorized_set():
    offer = discover_tools(
        "هوا امروز چطوره؟",
        permissioned_names=["list_accounts", "search_invoices"],
        execution_mode="analyzer",
        apply_indexed=True,
    )
    assert offer.names() <= {"list_accounts", "search_invoices"}
    assert "get_business_info" not in offer.names()
    assert "get_person_balance" not in offer.candidate_pool


def test_unauthorized_never_enters_indexed_candidate_pool():
    index = _fresh_index()
    offer = retrieve_candidates(
        "مانده حساب علی چقدر است",
        ["list_accounts"],
        n=100,
        fallback_on_empty=False,
        include_vector=False,
        index=index,
        expects_tools=True,
    )
    assert "get_person_balance" not in offer.as_set()
    assert offer.as_set() <= {"list_accounts"}


def test_disable_deprecate_and_reenable_restore_postings():
    index = ToolRetrievalIndex()
    entry = ToolManifestEntry(
        domains=("financial",),
        capability="financial.invoice",
        namespace="financial",
        aliases=("فاکتور آزمایشی فاز یازده",),
        enabled=True,
        version="1",
        schema_version="1",
    )
    index.upsert("phase11_demo_tool", entry=entry)
    assert "phase11_demo_tool" in index.lookup_token("آزمایشی")
    index.disable("phase11_demo_tool")
    assert "phase11_demo_tool" not in index.lookup_token("آزمایشی")
    index.enable("phase11_demo_tool")
    assert "phase11_demo_tool" in index.lookup_token("آزمایشی")
    index.deprecate("phase11_demo_tool")
    assert "phase11_demo_tool" not in index.lookup_token("آزمایشی")
    rec = index.get("phase11_demo_tool")
    assert rec is not None and rec.deprecated is True
    index.enable("phase11_demo_tool")
    assert "phase11_demo_tool" in index.lookup_token("آزمایشی")


def test_full_rebuild_matches_incremental_upsert_and_disable_reenable():
    names = (
        "search_invoices",
        "list_accounts",
        "get_person_balance",
        "list_currencies",
        "get_business_dashboard",
        "get_business_info",
    )
    full = ToolRetrievalIndex()
    full.load_many((name, "") for name in names)

    incremental = ToolRetrievalIndex()
    for name in names:
        incremental.upsert(name)

    bounced = ToolRetrievalIndex()
    for name in names:
        bounced.upsert(name)
        bounced.disable(name)
        bounced.enable(name)

    assert _posting_map(full) == _posting_map(incremental)
    assert _posting_map(full) == _posting_map(bounced)
    for token in ("فاکتور", "مانده", "ارزها", "داشبورد", "اطلاعات"):
        assert full.lookup_token(token) == incremental.lookup_token(token)
        assert full.lookup_token(token) == bounced.lookup_token(token)


def test_index_properties_unicode_duplicates_empty_collision_version():
    assert normalize_search_text("طرف‌حساب") == normalize_search_text("طرف حساب")
    assert "ی" in normalize_search_text("پيگيري")
    assert "ک" in normalize_search_text("شركت")
    tokens = tokenize_search_text("اطلاعات این کسب‌وکار")
    assert "اطلاعات" in tokens
    assert "کسب" in tokens

    index = ToolRetrievalIndex()
    dup = ToolManifestEntry(
        domains=("financial",),
        aliases=("فاکتور", "فاکتور", "invoice", "invoice"),
        keywords=("فاکتور", "فاکتور"),
    )
    index.upsert("dup_alias_tool", entry=dup)
    assert index.lookup_token("فاکتور") == frozenset({"dup_alias_tool"})

    empty = ToolManifestEntry()
    index.upsert("empty_meta_tool", entry=empty)
    rec = index.get("empty_meta_tool")
    assert rec is not None
    assert "empty" in rec.tokens

    first = ToolManifestEntry(aliases=("اولی",), version="1")
    second = ToolManifestEntry(aliases=("دومی",), version="2")
    index.upsert("collision_tool", entry=first)
    index.upsert("collision_tool", entry=second)
    assert "collision_tool" not in index.lookup_token("اولی")
    assert "collision_tool" in index.lookup_token("دومی")
    assert index.get("collision_tool").version == "2"
    assert index.is_stale(
        "collision_tool",
        search_text=second.search_text("collision_tool"),
        version="1",
        schema_version="1",
    )
    assert not index.is_stale(
        "collision_tool",
        search_text=second.search_text("collision_tool"),
        version="2",
        schema_version="1",
    )


def test_indexed_retrieval_miss_is_not_adaptive_or_ranker_miss():
    assert classify_unoffered_tool(
        name="get_person_balance",
        in_registry=True,
        authorized=True,
        in_ranked_candidates=False,
        in_offered_schemas=False,
        indexed_enabled=True,
        in_candidate_pool=False,
        indexed_fallback=False,
    ) == EVENT_INDEXED_RETRIEVAL_MISS
    assert classify_unoffered_tool(
        name="get_person_balance",
        in_registry=True,
        authorized=True,
        in_ranked_candidates=False,
        in_offered_schemas=False,
        indexed_enabled=True,
        in_candidate_pool=True,
        indexed_fallback=False,
    ) == EVENT_RETRIEVAL_MISS
    plan = plan_unknown_tool_recovery(
        "get_person_balance",
        RediscoveryState(),
        authorized_names={"get_person_balance", "list_accounts"},
        offered_names={"list_accounts"},
        ranked_names={"list_accounts"},
        in_registry=True,
        indexed_enabled=True,
        candidate_pool={"list_accounts"},
        indexed_fallback=False,
    )
    assert plan["kind"] == EVENT_INDEXED_RETRIEVAL_MISS
    assert plan["rediscovery"] is True


def test_chat_wires_indexed_assignment_independently():
    from pathlib import Path

    root = Path(__file__).resolve().parents[1]
    service = (root / "app" / "services" / "ai" / "ai_service.py").read_text(
        encoding="utf-8"
    )
    assert "apply_adaptive=assignment.enabled" in service
    assert "apply_indexed=indexed.enabled" in service
    assert "resolve_indexed_assignment" in service
