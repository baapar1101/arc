"""تجمیع chat_completion_stream به شکل پاسخ غیر استریم.

STR-02: یک حلقهٔ ایجنت؛ مسیر sync/تلگرام/CRM/تیکت فقط همین generator را مصرف می‌کند.
"""
from __future__ import annotations

from typing import Any, AsyncIterator, Dict, Optional


async def aggregate_chat_completion_stream(
    stream: AsyncIterator[Dict[str, Any]],
) -> Dict[str, Any]:
    """مصرف کامل استریم و بازگرداندن دیکت سازگار با chat_completion قدیمی.

    شکل خروجی:
      message.content / message.role
      usage
      _function_calls / _function_results
      فیلدهای اختیاری done (awaiting_approval, agent_run, …)
    """
    content_parts: list[str] = []
    final_content: Optional[str] = None
    function_calls: Any = None
    function_results: Any = None
    usage: Any = None
    done_chunk: Dict[str, Any] = {}

    async for chunk in stream:
        delta = chunk.get("delta") or {}
        piece = delta.get("content") or ""
        if piece:
            content_parts.append(piece)
        if chunk.get("function_calls"):
            function_calls = chunk["function_calls"]
        if chunk.get("function_results") is not None:
            function_results = chunk["function_results"]
        if chunk.get("usage"):
            usage = chunk["usage"]
        if chunk.get("done"):
            done_chunk = chunk
            explicit = chunk.get("final_content")
            if explicit is None:
                explicit = delta.get("content") if isinstance(delta, dict) else None
            if isinstance(explicit, str) and explicit.strip():
                final_content = explicit

    content = final_content if final_content is not None else "".join(content_parts)
    message: Dict[str, Any] = {"role": "assistant", "content": content}
    if function_calls:
        message["function_calls"] = function_calls

    response: Dict[str, Any] = {
        "message": message,
        "usage": usage or {},
    }
    if function_calls:
        response["_function_calls"] = function_calls
    if function_results is not None:
        response["_function_results"] = function_results

    for key in (
        "awaiting_approval",
        "agent_run",
        "agent_budget",
        "can_continue",
        "run_id",
        "citations_context",
        "citations",
        "activated_skills",
        "requested_model",
        "resolved_model",
        "execution_mode",
        "agent_trace",
    ):
        if key in done_chunk and done_chunk.get(key) is not None:
            response[key] = done_chunk[key]
    return response
