"""
کمک‌کننده‌های استریم SSE برای چت AI (heartbeat و نگاشت chunk).
"""
from __future__ import annotations

import asyncio
import time
from typing import Any, AsyncGenerator, Callable, Dict, List, Optional

HEARTBEAT_INTERVAL_SEC = 3.0


def chunk_to_sse_data(chunk: Dict[str, Any]) -> List[Dict[str, Any]]:
    """تبدیل chunk داخلی AIService به یک یا چند payload SSE."""
    event_type = chunk.get("event")
    if event_type == "status":
        data: Dict[str, Any] = {
            "type": "status",
            "phase": chunk.get("phase"),
            "done": False,
        }
        if chunk.get("step"):
            data["step"] = chunk["step"]
        if chunk.get("tool_key"):
            data["tool_key"] = chunk["tool_key"]
        if chunk.get("iteration") is not None:
            data["iteration"] = chunk["iteration"]
        if chunk.get("max_iterations") is not None:
            data["max_iterations"] = chunk["max_iterations"]
        if chunk.get("exploration"):
            data["exploration"] = chunk.get("exploration")
        return [data]

    if event_type == "context_usage":
        return [
            {
                "type": "context_usage",
                "estimated_tokens": chunk.get("estimated_tokens"),
                "budget_tokens": chunk.get("budget_tokens"),
                "usage_ratio": chunk.get("usage_ratio"),
                "usage_percent": chunk.get("usage_percent"),
                "history_summarized": chunk.get("history_summarized", False),
                "context_retried": chunk.get("context_retried", False),
                "done": False,
            }
        ]

    if event_type == "trace_step":
        data = {
            "type": "trace_step",
            "trace_id": chunk.get("trace_id"),
            "step_id": chunk.get("step_id"),
            "kind": chunk.get("kind"),
            "state": chunk.get("state", "done"),
            "layer": chunk.get("layer"),
            "visibility": chunk.get("visibility"),
            "done": False,
        }
        for key in (
            "title_key",
            "title_params",
            "body_markdown",
            "tool",
            "tool_key",
            "iteration",
            "elapsed_ms",
            "result_count",
            "citations",
            "bundle_id",
            "explore_target",
            "entity_refs",
            "findings_count",
            "hypothesis",
            "confidence",
            "retry_attempt",
        ):
            if chunk.get(key) is not None:
                data[key] = chunk.get(key)
        return [data]

    if event_type == "stream_error":
        return [
            {
                "type": "error",
                "error": chunk.get("error"),
                "recoverable": chunk.get("recoverable", False),
                "suggested_action": chunk.get("suggested_action"),
                "done": False,
            }
        ]

    if event_type in ("tool_start", "tool_end"):
        data = {
            "type": event_type,
            "tool": chunk.get("tool"),
            "tool_key": chunk.get("tool_key"),
            "label": chunk.get("label"),
            "done": False,
        }
        if event_type == "tool_end":
            data["success"] = chunk.get("success")
            data["approval_required"] = chunk.get("approval_required", False)
        return [data]

    delta = chunk.get("delta", {})
    content_chunk = delta.get("content", "")
    payloads: List[Dict[str, Any]] = []

    if content_chunk:
        payloads.append({"content": content_chunk, "done": False})

    if chunk.get("done", False):
        done_payload: Dict[str, Any] = {
            "content": "",
            "done": True,
            "usage": chunk.get("usage"),
            "function_calls": chunk.get("function_calls"),
            "function_results": chunk.get("function_results"),
        }
        if chunk.get("agent_trace"):
            done_payload["agent_trace"] = chunk.get("agent_trace")
        payloads.append(done_payload)
    elif not content_chunk and not event_type:
        pass

    return payloads


async def iter_with_heartbeat(
    stream_factory: Callable[[], AsyncGenerator[Dict[str, Any], None]],
    *,
    initial_status: Optional[Dict[str, Any]] = None,
) -> AsyncGenerator[Dict[str, Any], None]:
    """
    رویدادهای stream_factory را با heartbeat دوره‌ای در سکوت طولانی ترکیب می‌کند.
    """
    queue: asyncio.Queue = asyncio.Queue()
    producer_done = False

    async def producer() -> None:
        nonlocal producer_done
        try:
            async for chunk in stream_factory():
                await queue.put(("chunk", chunk))
        finally:
            producer_done = True
            await queue.put(("eof", None))

    if initial_status:
        yield initial_status

    task = asyncio.create_task(producer())
    started = time.monotonic()
    try:
        while True:
            if producer_done and queue.empty():
                break
            try:
                kind, item = await asyncio.wait_for(
                    queue.get(), timeout=HEARTBEAT_INTERVAL_SEC
                )
            except asyncio.TimeoutError:
                elapsed_ms = int((time.monotonic() - started) * 1000)
                yield {
                    "event": "heartbeat",
                    "elapsed_ms": elapsed_ms,
                    "done": False,
                }
                continue

            if kind == "eof":
                break
            if kind == "chunk" and item is not None:
                yield item
    finally:
        if not task.done():
            task.cancel()
            try:
                await task
            except asyncio.CancelledError:
                pass
