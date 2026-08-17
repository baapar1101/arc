"""بافر SSE و شناسهٔ رویداد برای reconnect."""
from __future__ import annotations

from app.services.ai.ai_sse_event_buffer import (
    append_sse_event,
    drop_sse_events,
    events_after,
)
from app.services.ai.ai_stream_helpers import (
    SseEventSequencer,
    chunk_to_sse_data,
    format_sse_payload,
)


def test_format_sse_payload_includes_id_and_data():
    raw = format_sse_payload({"type": "heartbeat", "done": False}, event_id=7)
    assert "id: 7\n" in raw
    assert "data: " in raw
    assert '"type": "heartbeat"' in raw or '"type":"heartbeat"' in raw


def test_sequencer_increments_and_buffers():
    drop_sse_events("deadbeefcafebabe")
    seq = SseEventSequencer(run_id="deadbeefcafebabe", start_id=0)
    first = seq.format({"type": "status", "phase": "thinking", "done": False})
    second = seq.format({"type": "heartbeat", "elapsed_ms": 3, "done": False})
    assert "id: 1\n" in first
    assert "id: 2\n" in second
    replayed = events_after("deadbeefcafebabe", 1)
    assert len(replayed) == 1
    assert replayed[0][0] == 2
    assert replayed[0][1]["type"] == "heartbeat"
    drop_sse_events("deadbeefcafebabe")


def test_events_after_empty_unknown_run():
    assert events_after("missingrun000000", 0) == []


def test_chunk_to_sse_agent_run_and_resumed():
    run_events = chunk_to_sse_data(
        {
            "event": "agent_run",
            "run_id": "abc123def4567890",
            "phase": "agent_loop",
            "iteration": 2,
            "needs_tools": True,
            "status": "running",
            "can_continue": False,
        }
    )
    assert run_events[0]["type"] == "agent_run"
    assert run_events[0]["run_id"] == "abc123def4567890"
    resumed = chunk_to_sse_data(
        {"event": "run_resumed", "run_id": "abc123def4567890", "iteration": 2}
    )
    assert resumed[0]["type"] == "run_resumed"


def test_append_and_replay_skips_older():
    drop_sse_events("runreplay0000001")
    append_sse_event("runreplay0000001", 1, {"type": "a"})
    append_sse_event("runreplay0000001", 2, {"type": "b"})
    append_sse_event("runreplay0000001", 3, {"type": "c"})
    after = events_after("runreplay0000001", 2)
    assert [eid for eid, _ in after] == [3]
    drop_sse_events("runreplay0000001")
