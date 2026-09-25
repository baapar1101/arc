"""Phase 2 — security-first candidate filtering."""
from __future__ import annotations

from app.services.ai.ai_execution_policy import EXECUTION_MODE_ANALYZER
from app.services.ai.ai_mcp_service import mcp_explicit_write_approval, prepare_mcp_tool_arguments
from app.services.ai.ai_tool_intent import (
    _CATEGORY_TOOLS,
    _CORE_TOOL_NAMES,
    filter_function_definitions,
    select_tool_names,
)
from app.services.ai.ai_tool_rank import score_tool_for_query
from app.services.ai.ai_tool_security import (
    QueryMutation,
    ToolSecurityClass,
    classify_query_mutation,
    classify_tool_security,
    filter_security_candidates,
)
from app.services.ai.ai_write_guard import is_write_function


_FINANCIAL_QUERY = "گزارش وضعیت مالی شرکت را بده"
_READ_QUERY = "فاکتور علی را نشان بده"
_WRITE_QUERY = "فاکتور جدید ایجاد کن"
_DESTRUCTIVE_QUERY = "این فاکتور را حذف کن"


def _permissioned_catalog() -> set[str]:
    names = set(_CORE_TOOL_NAMES)
    for group in _CATEGORY_TOOLS.values():
        names |= set(group)
    names |= {
        "delete_invoice",
        "delete_account",
        "export_business_data",
        "execute_workflow",
        "create_invoice",
        "search_invoices",
    }
    return names


def test_query_mutation_read_write_destructive():
    assert classify_query_mutation(_READ_QUERY) == QueryMutation.READ
    assert classify_query_mutation(_WRITE_QUERY) == QueryMutation.WRITE
    assert classify_query_mutation(_DESTRUCTIVE_QUERY) == QueryMutation.DESTRUCTIVE
    assert classify_query_mutation(_FINANCIAL_QUERY) == QueryMutation.READ
    assert classify_query_mutation("") == QueryMutation.UNKNOWN


def test_tool_class_from_manifest_not_name_prefix_alone():
    assert classify_tool_security("search_invoices") == ToolSecurityClass.READ_ONLY
    assert classify_tool_security("create_invoice") == ToolSecurityClass.WRITE
    assert classify_tool_security("delete_invoice") == ToolSecurityClass.DESTRUCTIVE
    assert classify_tool_security("export_business_data") == ToolSecurityClass.HIGH_RISK
    assert classify_tool_security("execute_workflow") == ToolSecurityClass.HIGH_RISK
    assert classify_tool_security("not_a_real_tool") == ToolSecurityClass.UNKNOWN


def test_unauthorized_tool_not_candidate():
    """Permission/tenant قبلاً نام را حذف کرده‌اند — فیلتر آن را برنمی‌گرداند."""
    out = filter_security_candidates(
        ["search_invoices", "query_business_data"],
        _WRITE_QUERY,
    )
    assert "create_invoice" not in out
    assert "delete_invoice" not in out


def test_authorized_read_is_candidate():
    out = filter_security_candidates(["search_invoices"], _READ_QUERY)
    assert "search_invoices" in out


def test_unauthorized_write_not_candidate_on_read_query():
    out = filter_security_candidates(
        ["create_invoice", "search_invoices"],
        _READ_QUERY,
    )
    assert "create_invoice" not in out
    assert "search_invoices" in out


def test_analyzer_drops_writes_even_on_write_query():
    out = filter_security_candidates(
        ["create_invoice", "search_invoices"],
        _WRITE_QUERY,
        execution_mode=EXECUTION_MODE_ANALYZER,
    )
    assert "create_invoice" not in out
    assert "search_invoices" in out


def test_generic_financial_query_excludes_destructive_and_export():
    selected = select_tool_names(_permissioned_catalog(), _FINANCIAL_QUERY)
    assert "delete_invoice" not in selected
    assert "delete_account" not in selected
    assert "export_business_data" not in selected
    assert "execute_workflow" not in selected
    assert "create_invoice" not in selected
    assert "search_invoices" in selected or "query_business_data" in selected


def test_ranking_score_cannot_override_security():
    q = _FINANCIAL_QUERY
    selected = select_tool_names(
        _permissioned_catalog(),
        q,
        prefer_names={"delete_invoice", "export_business_data", "execute_workflow"},
    )
    assert "delete_invoice" not in selected
    assert "export_business_data" not in selected
    assert "execute_workflow" not in selected
    assert score_tool_for_query("delete_invoice", q) >= 0


def test_explicit_destructive_intent_may_include_delete():
    selected = select_tool_names(_permissioned_catalog(), _DESTRUCTIVE_QUERY)
    assert "delete_invoice" in selected
    assert "search_invoices" in selected or "query_business_data" in selected
    assert "create_invoice" not in selected
    assert "export_business_data" not in selected
    assert is_write_function("delete_invoice") is True


def test_unknown_security_is_fail_closed():
    out = filter_security_candidates(
        ["totally_unknown_tool", "search_invoices"],
        _READ_QUERY,
        unknown_policy="deny",
    )
    assert "totally_unknown_tool" not in out
    assert "search_invoices" in out


def test_unknown_policy_allow_keeps_ranking_fillers():
    out = filter_security_candidates(
        ["zzz_filler_001", "search_invoices"],
        _READ_QUERY,
        unknown_policy="allow",
    )
    assert "zzz_filler_001" in out


def test_filter_never_invents_names():
    out = filter_security_candidates(
        ["search_invoices"],
        _DESTRUCTIVE_QUERY,
    )
    assert out <= {"search_invoices"}
    assert "delete_invoice" not in out


def test_tenant_isolation_is_input_contract():
    """Toolها هویت per-tenant ندارند؛ نبودن در ورودی = کسب‌وکار/نشست دیگر."""
    tenant_a = {"search_invoices", "create_invoice"}
    out = filter_security_candidates(tenant_a, _WRITE_QUERY)
    assert "delete_invoice" not in out
    assert out <= tenant_a


def test_forced_approval_tool_stays_candidate():
    out = filter_security_candidates(
        ["create_invoice"],
        "تأیید",
        forced_names={"create_invoice"},
    )
    assert "create_invoice" in out


def test_empty_allowlist_is_fail_closed():
    defs = [
        {"function": {"name": "delete_invoice"}},
        {"function": {"name": "search_invoices"}},
    ]
    assert filter_function_definitions(defs, set()) == []


def test_mcp_execution_guard_still_active_for_writes():
    for name in (
        "create_invoice",
        "delete_invoice",
        "export_business_data",
        "execute_workflow",
    ):
        assert is_write_function(name) is True
    assert mcp_explicit_write_approval({"approve_writes": True}) is True
    assert mcp_explicit_write_approval({}) is False
    cleaned = prepare_mcp_tool_arguments({"_approve_writes": True, "id": 1})
    assert "_approve_writes" not in cleaned
