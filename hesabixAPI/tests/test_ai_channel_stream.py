"""استریم SSE کانال‌های جانبی (CRM / تیکت)."""
from __future__ import annotations

import json

import pytest

from app.services.ai.ai_channel_stream import iter_channel_assist_sse, tool_names_from_calls
from app.services.ai.ai_constants import SSE_SCHEMA_VERSION
from app.services.ai.ai_stream_helpers import format_sse_payload
from app.services.ai.ai_run_hub import replay_buffered_events
from app.services.ai.ai_sse_event_buffer import append_sse_event, drop_sse_events


class _FakeConfig:
    provider = "openai"
    model_name = "test-model"


class _FakeAI:
    business_id = 1
    config = _FakeConfig()
    charged = False

    def __init__(self, chunks):
        self._chunks = chunks

    async def chat_completion_stream(self, *args, **kwargs):
        for chunk in self._chunks:
            yield chunk

    def check_quota_and_charge(self, input_tokens, output_tokens):
        self.charged = True
        return {"cost": 0, "payment_method": "free"}

    def log_usage(self, **kwargs):
        return None


def _data_lines(raw: str) -> list[dict]:
    out = []
    for line in raw.splitlines():
        if line.startswith("data:"):
            payload = line[5:].strip()
            out.append(json.loads(payload))
    return out


@pytest.mark.asyncio
async def test_channel_assist_streams_deltas_then_done_with_result_field():
    ai = _FakeAI(
        [
            {"event": "status", "phase": "thinking", "done": False},
            {"delta": {"content": "سلام "}, "done": False},
            {"delta": {"content": "دنیا"}, "done": False},
            {
                "done": True,
                "final_content": "سلام دنیا",
                "usage": {"input_tokens": 2, "output_tokens": 3},
                "citations": [{"title": "فاکتور"}],
                "function_calls": [{"name": "get_crm_summary"}],
            },
        ]
    )
    payloads = []
    async for raw in iter_channel_assist_sse(
        ai,
        [{"role": "user", "content": "x"}],
        tools=[{"name": "get_crm_summary"}],
        user_query="x",
        result_field="summary",
        feature="crm_summarize_lead",
        extra={"lead_id": 9},
    ):
        payloads.extend(_data_lines(raw))

    types = [p.get("type") for p in payloads]
    assert types[0] == "status"
    assert payloads[0]["phase"] == "connecting"
    assert any(p.get("content") == "سلام " for p in payloads)
    done = [p for p in payloads if p.get("done") is True]
    assert done
    last = done[-1]
    assert last["summary"] == "سلام دنیا"
    assert last["final_content"] == "سلام دنیا"
    assert last["tools_used"] == ["get_crm_summary"]
    assert last["citations"] == [{"title": "فاکتور"}]
    assert last["usage"]["input_tokens"] == 2
    assert last["schema_version"] == SSE_SCHEMA_VERSION
    assert ai.charged is True


@pytest.mark.asyncio
async def test_channel_assist_empty_stream_is_typed_error():
    ai = _FakeAI([])
    payloads = []
    async for raw in iter_channel_assist_sse(
        ai,
        [{"role": "user", "content": "x"}],
        result_field="suggested_reply",
        feature="ticket_suggest_reply",
    ):
        payloads.extend(_data_lines(raw))
    errors = [p for p in payloads if p.get("type") == "error"]
    assert errors
    assert errors[-1]["error_code"] == "EMPTY_STREAM"
    assert errors[-1]["done"] is True


def test_format_sse_payload_includes_schema_version():
    raw = format_sse_payload({"type": "heartbeat", "done": False}, event_id=1)
    assert '"schema_version": 1' in raw or '"schema_version":1' in raw


def test_replay_buffered_events_stops_at_done():
    drop_sse_events("replaychn00000001")
    append_sse_event("replaychn00000001", 1, {"type": "status", "phase": "thinking"})
    append_sse_event("replaychn00000001", 2, {"content": "hi", "done": True})
    append_sse_event("replaychn00000001", 3, {"type": "status", "phase": "late"})
    events, cursor, terminal = replay_buffered_events("replaychn00000001", 0)
    assert terminal is True
    assert cursor == 2
    assert [eid for eid, _ in events] == [1, 2]
    drop_sse_events("replaychn00000001")


def test_tool_names_from_calls_skips_invalid():
    assert tool_names_from_calls(None) == []
    assert tool_names_from_calls([{"name": "a"}, "x", {}]) == ["a"]
