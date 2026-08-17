"""سیاست ابزار per-channel (CHN-02 / WFA-02)."""
from app.services.ai.ai_channel_policy import (
    CHANNEL_CRM,
    CHANNEL_CRM_READ_TOOLS,
    CHANNEL_ITERATION_CAP,
    CHANNEL_TICKET,
    apply_iteration_cap,
    filter_tools_by_allowlist,
    resolve_round_tool_offer,
)


def _tool(name: str) -> dict:
    return {"type": "function", "function": {"name": name}}


def test_filter_keeps_allowlisted_reads():
    tools = [
        _tool("search_leads"),
        _tool("get_lead_details"),
        _tool("create_invoice"),
        _tool("search_invoices"),
    ]
    names = {
        (t.get("function") or {}).get("name")
        for t in filter_tools_by_allowlist(tools, CHANNEL_CRM_READ_TOOLS)
    }
    assert names == {"search_leads", "get_lead_details"}


def test_filter_strips_writes_even_if_allowlisted():
    from app.services.ai.ai_write_guard import WRITE_FUNCTIONS

    write_name = next(iter(WRITE_FUNCTIONS))
    allow = frozenset({write_name, "search_leads"})
    names = {
        (t.get("function") or {}).get("name")
        for t in filter_tools_by_allowlist(
            [_tool(write_name), _tool("search_leads")],
            allow,
        )
    }
    assert "search_leads" in names
    assert write_name not in names


def test_resolve_round_keeps_caller_tools_even_when_routing_is_simple():
    provided = [_tool("search_leads")]
    offer, kept = resolve_round_tool_offer(
        provided_tools=provided,
        provider_allows_tools=True,
        routing_needs_tools=False,
    )
    assert offer == "keep"
    assert kept == provided


def test_resolve_round_empty_caller_list_does_not_load_catalog():
    offer, kept = resolve_round_tool_offer(
        provided_tools=[],
        provider_allows_tools=True,
        routing_needs_tools=True,
    )
    assert offer == "keep"
    assert kept == []


def test_resolve_round_none_when_provider_disallows():
    offer, kept = resolve_round_tool_offer(
        provided_tools=[_tool("search_leads")],
        provider_allows_tools=False,
        routing_needs_tools=True,
    )
    assert offer == "none"
    assert kept is None


def test_resolve_round_load_when_caller_omits_tools():
    offer, kept = resolve_round_tool_offer(
        provided_tools=None,
        provider_allows_tools=True,
        routing_needs_tools=True,
    )
    assert offer == "load"
    assert kept is None


def test_iteration_cap_clamps_adaptive():
    assert apply_iteration_cap(12, CHANNEL_ITERATION_CAP[CHANNEL_CRM]) == 4
    assert apply_iteration_cap(2, CHANNEL_ITERATION_CAP[CHANNEL_TICKET]) == 2
    assert apply_iteration_cap(3, None) == 3
    assert apply_iteration_cap(0, 4) == 1
