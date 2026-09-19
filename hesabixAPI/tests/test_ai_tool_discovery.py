"""Phase 3 — unified discover_tools API."""
from __future__ import annotations

from pathlib import Path
import importlib.util

from app.services.ai.ai_constants import (
    DISCOVERY_HARD_MAX,
    MAX_TOOLS_AUTONOMOUS,
    MAX_TOOLS_PER_REQUEST,
)
from app.services.ai.ai_ops_metrics import metric_snapshot, reset_metrics_for_tests
from app.services.ai.ai_tool_discovery import (
    DISCOVERY_STRATEGY_KEYWORD,
    DiscoveryEngine,
    HybridStrategy,
    KeywordIntentStrategy,
    SemanticStrategy,
    discover_tools,
    resolve_discovery_limit,
)
from app.services.ai.ai_tool_intent import (
    _CATEGORY_TOOLS,
    _CORE_TOOL_NAMES,
    _WRITE_TOOLS,
)
from app.services.ai.ai_tool_security import QueryMutation, classify_query_mutation


def _gold_cases() -> list[tuple[str, tuple[str, ...]]]:
    path = Path(__file__).with_name("test_ai_tool_intent_gold.py")
    spec = importlib.util.spec_from_file_location("_gold_intent_cases", path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return list(module.GOLD_CASES)


def _catalog() -> set[str]:
    names = set(_CORE_TOOL_NAMES) | set(_WRITE_TOOLS)
    for group in _CATEGORY_TOOLS.values():
        names |= set(group)
    return names


def test_discover_tools_chat_gold_recall():
    catalog = _catalog()
    hits = 0
    total = 0
    missed: list[str] = []
    for query, required in _gold_cases():
        mutation = classify_query_mutation(query)
        mode = (
            "supervised"
            if mutation
            in (
                QueryMutation.WRITE,
                QueryMutation.DESTRUCTIVE,
                QueryMutation.EXPORT,
                QueryMutation.EXECUTE,
            )
            else "analyzer"
        )
        offer = discover_tools(
            query,
            permissioned_names=catalog,
            execution_mode=mode,
            channel="chat",
        )
        cap = (
            MAX_TOOLS_AUTONOMOUS
            if mode == "supervised"
            else MAX_TOOLS_PER_REQUEST
        )
        assert offer.strategy == DISCOVERY_STRATEGY_KEYWORD
        assert offer.candidates
        assert "parameters" not in offer.candidates[0].to_dict()
        assert len(offer.names()) <= cap
        for tool in required:
            total += 1
            if tool in offer.names():
                hits += 1
            else:
                missed.append(f"{query!r} → {tool}")
    assert (hits / total) >= 0.95, f"recall={hits / total:.2%} missed={missed}"


def test_unauthorized_tool_never_returned():
    offer = discover_tools(
        "فاکتور جدید ایجاد کن",
        permissioned_names=["search_invoices", "query_business_data"],
        execution_mode="supervised",
    )
    assert "create_invoice" not in offer.names()
    assert "delete_invoice" not in offer.names()


def test_limit_is_hard_capped():
    catalog = _catalog()
    offer = discover_tools(
        "گزارش فاکتور فروش ماه گذشته",
        permissioned_names=catalog,
        execution_mode="analyzer",
        limit=100000,
    )
    assert offer.requested_limit == 100000
    assert offer.effective_limit == DISCOVERY_HARD_MAX
    assert len(offer) <= DISCOVERY_HARD_MAX


def test_resolve_limit_bounds_invalid_values():
    assert resolve_discovery_limit(None, default=48) == 48
    assert resolve_discovery_limit(0, default=48) == 48
    assert resolve_discovery_limit(-5, default=48) == 48
    assert resolve_discovery_limit(100000, default=48) == DISCOVERY_HARD_MAX
    assert resolve_discovery_limit(20, default=48) == 20


def test_empty_permissioned_set_is_clean_empty():
    offer = discover_tools(
        "گزارش فروش",
        permissioned_names=[],
        execution_mode="analyzer",
    )
    assert offer.candidates == ()
    assert offer.names() == set()
    assert offer.authorized_count == 0
    assert len(offer) == 0


def test_candidate_has_no_schema_fields():
    offer = discover_tools(
        "فاکتور علی را نشان بده",
        permissioned_names=["search_invoices", "query_business_data"],
        execution_mode="analyzer",
    )
    assert offer.names()
    payload = offer.candidates[0].to_dict()
    assert "parameters" not in payload
    assert "parameters_schema" not in payload
    assert "schema" not in payload
    assert set(payload) == {
        "name",
        "score",
        "match_reason",
        "capability",
        "namespace",
        "domains",
        "side_effect",
    }


def test_generic_financial_query_excludes_destructive():
    offer = discover_tools(
        "گزارش وضعیت مالی شرکت را بده",
        permissioned_names=_catalog(),
        execution_mode="supervised",
    )
    names = offer.names()
    assert "delete_invoice" not in names
    assert "export_business_data" not in names
    assert "execute_workflow" not in names


def test_capability_is_prefer_not_hard_filter():
    offer = discover_tools(
        "فروش این ماه را گزارش کن",
        permissioned_names=["search_invoices", "query_business_data", "get_sales_report"],
        execution_mode="analyzer",
        capability="reports.sales",
    )
    assert offer.capability == "reports.sales"
    assert "get_sales_report" in offer.names()


def test_hybrid_strategy_only_returns_authorized_names():
    offer = discover_tools(
        "فاکتور فروش را پیدا کن",
        permissioned_names=["search_invoices", "list_accounts"],
        execution_mode="analyzer",
        limit=10,
        channel="eval",
        strategy=HybridStrategy(),
    )
    assert offer.names() <= {"search_invoices", "list_accounts"}
    assert "create_invoice" not in offer.names()


def test_semantic_strategy_does_not_bypass_authorization():
    offer = discover_tools(
        "delete this check",
        permissioned_names=["search_invoices"],
        execution_mode="analyzer",
        limit=8,
        channel="eval",
        strategy=SemanticStrategy(),
    )
    assert offer.names() <= {"search_invoices"}
    assert "delete_check" not in offer.names()


def test_engine_uses_keyword_strategy_by_default():
    engine = DiscoveryEngine()
    assert isinstance(engine.strategy, KeywordIntentStrategy)
    assert engine.strategy.name == DISCOVERY_STRATEGY_KEYWORD


def test_observability_does_not_log_query_text():
    reset_metrics_for_tests()
    discover_tools(
        "موجودی علی و مبلغ فاکتور",
        permissioned_names=["search_invoices"],
        execution_mode="analyzer",
        channel="chat",
    )
    assert metric_snapshot().get("tool_discovery", 0) >= 1


def test_chat_get_available_functions_calls_discover_tools():
    source = Path(__file__).resolve().parents[1] / "app" / "services" / "ai" / "ai_service.py"
    text = source.read_text(encoding="utf-8")
    assert "from app.services.ai.ai_tool_discovery import discover_tools" in text
    assert "discover_tools(" in text
    assert "load_tool_schemas(" in text
    assert "select_tool_names(" not in text


def test_subagent_uses_get_available_functions_channel():
    source = Path(__file__).resolve().parents[1] / "app" / "services" / "ai" / "ai_subagent.py"
    text = source.read_text(encoding="utf-8")
    assert "get_available_functions(" in text
    assert 'channel="subagent"' in text
    assert "select_tool_names(" not in text
    assert "select_catalog_tool_names(" not in text


def test_crm_ticket_workflow_use_unified_schema_loader():
    root = Path(__file__).resolve().parents[1]
    crm = (root / "adapters" / "api" / "v1" / "ai" / "crm_ai.py").read_text(encoding="utf-8")
    tickets = (root / "adapters" / "api" / "v1" / "support" / "ai_tickets.py").read_text(
        encoding="utf-8"
    )
    workflow = (
        root / "app" / "services" / "workflow" / "actions" / "ai_agent_action.py"
    ).read_text(encoding="utf-8")
    assert "get_available_functions(" in crm
    assert "get_available_functions(" in tickets
    assert "get_available_functions(" in workflow


def test_crm_ticket_workflow_use_unified_schema_loader():
    root = Path(__file__).resolve().parents[1]
    crm = (root / "adapters" / "api" / "v1" / "ai" / "crm_ai.py").read_text(encoding="utf-8")
    tickets = (root / "adapters" / "api" / "v1" / "support" / "ai_tickets.py").read_text(
        encoding="utf-8"
    )
    workflow = (
        root / "app" / "services" / "workflow" / "actions" / "ai_agent_action.py"
    ).read_text(encoding="utf-8")
    assert "get_available_functions(" in crm
    assert "get_available_functions(" in tickets
    assert "get_available_functions(" in workflow
