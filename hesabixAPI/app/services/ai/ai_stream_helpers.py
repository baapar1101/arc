"""
کمک‌کننده‌های استریم SSE برای چت AI (heartbeat و نگاشت chunk).
"""
from __future__ import annotations

import asyncio
import time
from typing import Any, AsyncGenerator, Callable, Dict, List, Optional

from app.core.json_safe import json_dumps_safe
from app.services.ai.ai_sse_event_buffer import append_sse_event

HEARTBEAT_INTERVAL_SEC = 3.0
SSE_NGINX_PAD = ":" + (" " * 2048) + "\n"


def format_sse_payload(
    data: Dict[str, Any],
    *,
    event_id: Optional[int] = None,
) -> str:
    """قالب SSE با pad پروکسی و شناسهٔ رویداد اختیاری."""
    parts = [SSE_NGINX_PAD]
    if event_id is not None:
        parts.append(f"id: {event_id}\n")
    parts.append(f"data: {json_dumps_safe(data)}\n\n")
    return "".join(parts)


class SseEventSequencer:
    """شمارندهٔ id رویداد + بافر per-run برای Last-Event-ID."""

    def __init__(self, run_id: Optional[str] = None, start_id: int = 0) -> None:
        self.run_id = run_id
        self.last_id = int(start_id)

    def bind_run(self, run_id: Optional[str]) -> None:
        if run_id:
            self.run_id = str(run_id)

    def format(self, data: Dict[str, Any]) -> str:
        self.last_id += 1
        payload = dict(data)
        payload["sse_id"] = self.last_id
        if self.run_id and "run_id" not in payload:
            payload["run_id"] = self.run_id
        if self.run_id:
            append_sse_event(self.run_id, self.last_id, payload)
        return format_sse_payload(payload, event_id=self.last_id)


# فیلدهایی که باید از chunk پایانی سرویس به رویداد done کلاینت برسند.
STREAM_DONE_OPTIONAL_KEYS = (
    "agent_trace",
    "agent_budget",
    "agent_run",
    "awaiting_approval",
    "citations_context",
    "citations",
    "activated_skills",
    "requested_model",
    "resolved_model",
    "execution_mode",
    "can_continue",
    "run_id",
    "final_content",
    "stop_reason",
    "stop_message_fa",
)


def attach_stream_done_metadata(
    payload: Dict[str, Any],
    source: Optional[Dict[str, Any]],
) -> Dict[str, Any]:
    """کپی فیلدهای متادیتای پایان استریم بدون حذف مقدار False/0."""
    if not source:
        return payload
    for key in STREAM_DONE_OPTIONAL_KEYS:
        if key not in source:
            continue
        value = source.get(key)
        if key in ("awaiting_approval", "can_continue"):
            payload[key] = bool(value)
            continue
        if value is not None:
            payload[key] = value
    return payload


def build_chat_done_sse_data(
    *,
    message_id: Optional[int],
    usage: Optional[Dict[str, Any]],
    function_calls: Any = None,
    function_results: Any = None,
    extra: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    """رویداد یکتای done پس از persist — شامل متادیتای کامل حلقهٔ agent."""
    data: Dict[str, Any] = {
        "content": "",
        "done": True,
        "usage": usage,
        "message_id": message_id,
        "function_calls": function_calls,
        "function_results": function_results,
    }
    attach_stream_done_metadata(data, extra)
    if not usage:
        data["warning"] = "Usage information not available"
    return data


def chunk_to_sse_data(chunk: Dict[str, Any]) -> List[Dict[str, Any]]:
    """تبدیل chunk داخلی AIService به یک یا چند payload SSE."""
    event_type = chunk.get("event")
    if event_type == "agent_run":
        data = {
            "type": "agent_run",
            "run_id": chunk.get("run_id"),
            "phase": chunk.get("phase"),
            "iteration": chunk.get("iteration"),
            "needs_tools": bool(chunk.get("needs_tools")),
            "status": chunk.get("status"),
            "can_continue": bool(chunk.get("can_continue")),
            "done": False,
        }
        if chunk.get("stop_reason") is not None:
            data["stop_reason"] = chunk.get("stop_reason")
        return [data]

    if event_type == "run_resumed":
        return [
            {
                "type": "run_resumed",
                "run_id": chunk.get("run_id"),
                "phase": chunk.get("phase"),
                "iteration": chunk.get("iteration"),
                "done": False,
            }
        ]

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

    if event_type == "agent_budget":
        data = {
            "type": "agent_budget",
            "done": False,
        }
        for key in (
            "iteration",
            "max_iterations",
            "base_max_iterations",
            "tokens_used",
            "max_total_tokens",
            "elapsed_sec",
            "wall_clock_sec",
            "unproductive_rounds",
            "max_unproductive_rounds",
            "extensions_granted",
            "max_extensions",
            "reasoning_effort",
            "stop_reason",
            "stop_message_fa",
        ):
            if chunk.get(key) is not None:
                data[key] = chunk.get(key)
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

    if event_type == "session_todo_snapshot":
        data = {
            "type": "session_todo_snapshot",
            "items": chunk.get("items") or [],
            "summary": chunk.get("summary") or {},
            "done": False,
        }
        if chunk.get("plan_title"):
            data["plan_title"] = chunk.get("plan_title")
        return [data]

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
            if chunk.get("approval_detail"):
                data["approval_detail"] = chunk.get("approval_detail")
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
        attach_stream_done_metadata(done_payload, chunk)
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
        else:
            # اگر producer با خطا تمام شده، آن را به مصرف‌کننده propagate کن
            # (در غیر این صورت chat.py پیام خالی ذخیره می‌کند و کلاینت بدون خطا تمام می‌شود).
            exc = task.exception()
            if exc is not None:
                raise exc
