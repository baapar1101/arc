"""تست سیاست ابزار نود AI Agent در ورک‌فلو (WFA-01)."""
from __future__ import annotations

from app.services.ai.ai_workflow_agent_policy import (
    WORKFLOW_AGENT_DEFAULT_DENYLIST,
    filter_workflow_agent_tools,
    merge_workflow_agent_denylist,
)


class _Fn:
    def __init__(self, requires_approval: bool):
        self.requires_approval = requires_approval


class _Reg:
    def __init__(self, mapping):
        self._m = mapping

    def get_function(self, name):
        return self._m.get(name)


def _tool(name: str) -> dict:
    return {"type": "function", "function": {"name": name}}


def test_filter_strips_writes_and_workflow_loop_tools():
    reg = _Reg(
        {
            "search_invoices": _Fn(False),
            "create_invoice": _Fn(True),
            "create_workflow": _Fn(True),
            "get_business_info": _Fn(False),
        }
    )
    tools = [
        _tool("search_invoices"),
        _tool("create_invoice"),
        _tool("create_workflow"),
        _tool("get_business_info"),
    ]
    filtered = filter_workflow_agent_tools(
        tools,
        denylist=merge_workflow_agent_denylist(),
        allow_writes=False,
        registry=reg,
    )
    names = {(t.get("function") or {}).get("name") for t in filtered}
    assert "search_invoices" in names
    assert "get_business_info" in names
    assert "create_invoice" not in names
    assert "create_workflow" not in names


def test_allow_writes_still_blocks_workflow_mutation_tools():
    reg = _Reg({"create_invoice": _Fn(True), "create_workflow": _Fn(True)})
    filtered = filter_workflow_agent_tools(
        [_tool("create_invoice"), _tool("create_workflow")],
        denylist=merge_workflow_agent_denylist(),
        allow_writes=True,
        registry=reg,
    )
    names = {(t.get("function") or {}).get("name") for t in filtered}
    assert "create_invoice" in names
    assert "create_workflow" not in names
    assert "create_workflow" in WORKFLOW_AGENT_DEFAULT_DENYLIST
