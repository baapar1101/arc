"""تست قرارداد subagent (AGT-06 فاز ۰–۲)."""
from __future__ import annotations

import asyncio

import pytest

from app.services.ai.ai_subagent import (
    filter_subagent_tools,
    reset_subagent_runs_for_tests,
    should_expose_subagent_tools,
    spawn_subagent_async,
    cancel_subagent_async,
    await_subagent_async,
)
from app.services.ai.ai_write_guard import WRITE_FUNCTIONS


class _Fn:
    def __init__(self, name: str, is_readonly: bool, is_agent_internal: bool = False):
        self.name = name
        self.is_readonly = is_readonly
        self.is_agent_internal = is_agent_internal
        self.requires_approval = not is_readonly


class _Registry:
    def __init__(self, fns: dict[str, _Fn]):
        self._fns = fns

    def get_function(self, name: str):
        return self._fns.get(name)


def _tool(name: str) -> dict:
    return {"type": "function", "function": {"name": name}}


def test_simple_query_does_not_expose_subagent_tools():
    assert should_expose_subagent_tools("موجودی کالای پیچ؟") is False
    assert should_expose_subagent_tools("سلام") is False


def test_multi_domain_query_exposes_subagent_tools():
    query = "گزارش فروش این ماه، موجودی کالاهای کم، و سه بدهکار برتر را یکجا بده."
    assert should_expose_subagent_tools(query) is True
    assert should_expose_subagent_tools(query, is_subagent=True) is False


def test_filter_subagent_tools_strips_writes_and_spawn():
    defs = [
        _tool("get_sales_report"),
        _tool("get_inventory_status"),
        _tool("create_invoice"),
        _tool("spawn_subagent"),
    ]
    registry = _Registry(
        {
            "get_sales_report": _Fn("get_sales_report", True),
            "get_inventory_status": _Fn("get_inventory_status", True),
            "create_invoice": _Fn("create_invoice", False),
            "spawn_subagent": _Fn("spawn_subagent", True, True),
        }
    )
    filtered = filter_subagent_tools(
        defs,
        ["get_sales_report", "get_inventory_status", "create_invoice", "spawn_subagent"],
        registry=registry,
    )
    names = [(d.get("function") or {}).get("name") for d in filtered]
    assert names == ["get_sales_report", "get_inventory_status"]
    assert "create_invoice" not in names
    assert "spawn_subagent" not in names


@pytest.mark.asyncio
async def test_spawn_two_reads_in_child_and_write_fail_closed():
    reset_subagent_runs_for_tests()

    async def fake_completion(**kwargs):
        assert "create_invoice" not in (kwargs.get("allowlist") or [])
        return {
            "content": "فروش و موجودی آماده است.",
            "function_calls": [
                {"name": "get_sales_report"},
                {"name": "get_inventory_status"},
            ],
            "function_results": {
                "get_sales_report": {"total": 1},
                "get_inventory_status": {"low": 2},
            },
            "citations": [{"id": 1, "name": "فروش"}],
        }

    class _Parent:
        _subagent_depth = 0
        business_id = 1
        ctx = None

    result = await spawn_subagent_async(
        _Parent(),
        {
            "goal": "فروش و موجودی این ماه",
            "tool_allowlist": ["get_sales_report", "get_inventory_status"],
            "wait": True,
        },
        session_id=9,
        business_id=1,
        completion_fn=fake_completion,
    )
    assert result["ok"] is True
    assert result["status"] == "completed"
    assert result["subagent_id"]
    names = [c["name"] for c in result["function_calls"]]
    assert names == ["get_sales_report", "get_inventory_status"]
    assert not any(n in WRITE_FUNCTIONS for n in names)


@pytest.mark.asyncio
async def test_spawn_nesting_forbidden():
    reset_subagent_runs_for_tests()

    class _ChildParent:
        _subagent_depth = 1

    result = await spawn_subagent_async(
        _ChildParent(),
        {"goal": "nested"},
        session_id=1,
        completion_fn=lambda **_k: None,
    )
    assert result["ok"] is False
    assert result["error"] == "SUBAGENT_NESTING_FORBIDDEN"


@pytest.mark.asyncio
async def test_cancel_stops_running_subagent():
    reset_subagent_runs_for_tests()
    started = asyncio.Event()

    async def slow_completion(**_kwargs):
        started.set()
        await asyncio.sleep(30)
        return {"content": "should not finish"}

    class _Parent:
        _subagent_depth = 0
        business_id = 1
        ctx = None

    task = asyncio.create_task(
        spawn_subagent_async(
            _Parent(),
            {"goal": "slow", "wait": True},
            session_id=3,
            completion_fn=slow_completion,
        )
    )
    await started.wait()
    from app.services.ai.ai_subagent import _runs

    sid = next(iter(_runs))
    cancelled = await cancel_subagent_async(sid, session_id=3)
    assert cancelled["status"] == "cancelled"
    result = await task
    assert result["status"] == "cancelled"
    assert result["error"] == "SUBAGENT_CANCELLED"


@pytest.mark.asyncio
async def test_await_subagent_returns_completed_envelope():
    reset_subagent_runs_for_tests()

    async def fake_completion(**_kwargs):
        await asyncio.sleep(0.01)
        return {"content": "done", "function_calls": [], "function_results": {}}

    class _Parent:
        _subagent_depth = 0
        business_id = 1
        ctx = None

    spawned = await spawn_subagent_async(
        _Parent(),
        {"goal": "async child", "wait": False},
        session_id=4,
        completion_fn=fake_completion,
    )
    assert spawned["status"] == "running"
    done = await await_subagent_async(spawned["subagent_id"], session_id=4)
    assert done["status"] == "completed"
    assert done["content"] == "done"


@pytest.mark.asyncio
async def test_spawn_default_wait_is_false():
    reset_subagent_runs_for_tests()

    async def fake_completion(**_kwargs):
        await asyncio.sleep(0.05)
        return {"content": "later"}

    class _Parent:
        _subagent_depth = 0
        business_id = 1
        ctx = None

    spawned = await spawn_subagent_async(
        _Parent(),
        {"goal": "nonblocking"},
        session_id=5,
        completion_fn=fake_completion,
    )
    assert spawned["ok"] is True
    assert spawned["status"] == "running"
    assert spawned.get("wait") is False
    from app.services.ai.ai_subagent import cancel_subagent_async

    await cancel_subagent_async(spawned["subagent_id"], session_id=5)


@pytest.mark.asyncio
async def test_spawn_emits_card_and_child_tool_events():
    reset_subagent_runs_for_tests()

    async def fake_completion(**kwargs):
        return {
            "content": "فروش آماده است.",
            "function_calls": [{"name": "get_sales_report"}],
            "function_results": {"get_sales_report": {"total": 1}},
        }

    class _Parent:
        _subagent_depth = 0
        business_id = 1
        ctx = None
        _subagent_sse_queue = asyncio.Queue()

    parent = _Parent()
    result = await spawn_subagent_async(
        parent,
        {
            "goal": "فروش این ماه",
            "tool_allowlist": ["get_sales_report"],
            "wait": True,
        },
        session_id=11,
        business_id=1,
        completion_fn=fake_completion,
    )
    assert result["ok"] is True
    events = []
    while True:
        try:
            events.append(parent._subagent_sse_queue.get_nowait())
        except asyncio.QueueEmpty:
            break
    kinds = [ev.get("kind") for ev in events]
    assert kinds[0] == "subagent"
    assert "tool" in kinds
    assert kinds[-1] == "subagent"
    assert events[0].get("state") == "active"
    assert events[-1].get("state") == "done"
    assert events[0].get("subagent_id") == result["subagent_id"]
    assert events[0].get("title_params", {}).get("goal")


def test_remap_child_trace_prefixes_and_nests():
    from app.services.ai.ai_subagent_sse import remap_child_trace_event
    from app.services.ai.ai_trace import trace_step

    ev = remap_child_trace_event(
        trace_step("tool_1", "tool", "active", tool="get_sales_report"),
        subagent_id="abc123",
        parent_step_id="subagent_abc123",
    )
    assert ev is not None
    assert ev["step_id"] == "sa_abc123_tool_1"
    assert ev["parent_step_id"] == "subagent_abc123"
    assert ev["subagent_id"] == "abc123"
    assert remap_child_trace_event(
        trace_step("ans", "answer", "done"),
        subagent_id="abc123",
        parent_step_id="subagent_abc123",
    ) is None


