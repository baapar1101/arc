"""تست کشف ابزار MCP و سیاست permission داخلی."""
from __future__ import annotations

from types import SimpleNamespace
from unittest.mock import MagicMock, patch

from app.services.ai.ai_mcp_discovery import (
    _score_tool,
    _tokens,
    list_mcp_categories,
    mcp_readonly,
    search_mcp_tools,
)
from app.services.ai.ai_permission_policy import (
    PERMISSION_POLICY_AGENT_INTERNAL,
    catalog_permission_allows,
    permission_policy_for_name,
)
from app.services.ai.ai_tool_manifest import get_manifest_entry


def _catalog():
    return [
        {
            "name": "get_report",
            "description": "گزارش یکپارچه معادل صفحهٔ گزارشات",
            "category": "reports",
            "capability": "reports.overview",
            "read_only": True,
            "required_permissions": ["reports.read"],
            "aliases": ["تراز آزمایشی", "سن بدهی", "اقساط"],
            "keywords": [],
            "input_schema": {"type": "object", "properties": {}},
        },
        {
            "name": "search_invoices",
            "description": "جستجوی فاکتور",
            "category": "financial",
            "capability": "invoices.search",
            "read_only": True,
            "required_permissions": ["invoices.read"],
            "aliases": ["فاکتور"],
            "keywords": [],
            "input_schema": {"type": "object", "properties": {}},
        },
        {
            "name": "create_invoice",
            "description": "ثبت فاکتور",
            "category": "financial",
            "capability": "invoices.write",
            "read_only": False,
            "required_permissions": ["invoices.write"],
            "aliases": [],
            "keywords": [],
            "input_schema": {"type": "object", "properties": {}},
        },
    ]


def test_discovery_tools_are_agent_internal():
    assert permission_policy_for_name("list_mcp_categories") == PERMISSION_POLICY_AGENT_INTERNAL
    assert permission_policy_for_name("search_mcp_tools") == PERMISSION_POLICY_AGENT_INTERNAL
    for name in ("list_mcp_categories", "search_mcp_tools"):
        entry = get_manifest_entry(name)
        assert entry is not None
        assert entry.permission_policy == PERMISSION_POLICY_AGENT_INTERNAL
        assert entry.is_core is True
        fn = SimpleNamespace(name=name, required_permissions=[], permission_policy=entry.permission_policy)
        assert catalog_permission_allows(fn, SimpleNamespace(), 1) is True


def test_tokens_split_persian_and_english():
    assert "تراز" in _tokens("تراز آزمایشی")
    assert "invoice" in _tokens("create invoice")
    assert _tokens("a") == []


def test_score_prefers_name_and_alias():
    catalog = _catalog()
    report = next(item for item in catalog if item["name"] == "get_report")
    invoices = next(item for item in catalog if item["name"] == "search_invoices")
    assert _score_tool(report, _tokens("تراز آزمایشی")) > 0
    assert _score_tool(report, _tokens("get_report")) > _score_tool(invoices, _tokens("get_report"))


def test_list_mcp_categories_groups_visible_tools():
    with patch("app.services.ai.ai_mcp_discovery.visible_tool_catalog", return_value=_catalog()):
        out = list_mcp_categories(MagicMock(), MagicMock(), 1)
    names = {row["category"] for row in out["categories"]}
    assert names == {"financial", "reports"}
    assert out["total_tools"] == 3
    financial = next(row for row in out["categories"] if row["category"] == "financial")
    assert financial["tool_count"] == 2


def test_search_mcp_tools_ranks_and_filters():
    with patch("app.services.ai.ai_mcp_discovery.visible_tool_catalog", return_value=_catalog()):
        empty = search_mcp_tools(MagicMock(), MagicMock(), 1, query=" ")
        ranked = search_mcp_tools(MagicMock(), MagicMock(), 1, query="فاکتور")
        filtered = search_mcp_tools(MagicMock(), MagicMock(), 1, query="فاکتور", category="reports")
        limited = search_mcp_tools(MagicMock(), MagicMock(), 1, query="فاکتور", limit=1)
    assert empty["items"] == []
    assert [item["name"] for item in ranked["items"]][0] in {"search_invoices", "create_invoice"}
    assert filtered["items"] == []
    assert limited["returned"] == 1
    assert all("input_schema" in item for item in ranked["items"])


def test_mcp_readonly_fail_closed():
    registry = SimpleNamespace(get_function=lambda _name: None)
    assert mcp_readonly("missing", registry) is False

    fn = SimpleNamespace(
        requires_approval=False,
        intent_write=False,
        always_confirm=False,
        side_effect="read",
        is_readonly=True,
    )
    registry = SimpleNamespace(get_function=lambda _name: fn)
    with patch("app.services.ai.ai_mcp_discovery.is_readonly_function", return_value=True):
        assert mcp_readonly("search_invoices", registry) is True
    fn.requires_approval = True
    with patch("app.services.ai.ai_mcp_discovery.is_readonly_function", return_value=True):
        assert mcp_readonly("create_invoice", registry) is False


def test_mcp_oauth_still_imports_service_aliases():
    from app.services.ai.ai_mcp_service import _get_tools, _mcp_readonly, _openai_tool_to_mcp

    assert callable(_get_tools)
    assert callable(_mcp_readonly)
    assert callable(_openai_tool_to_mcp)
