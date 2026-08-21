"""استریم SSE مشترک برای کانال‌های جانبی (CRM / تیکت) — CHN-02.

همان حلقهٔ chat_completion_stream با heartbeat و خطای ساخت‌یافته؛
مسیر JSON قبلی از aggregate استفاده می‌کند.
"""
from __future__ import annotations

import logging
from typing import Any, AsyncIterator, Dict, List, Optional

from app.services.ai.ai_stream_errors import STREAM_ERROR_EMPTY, stream_error_payload
from app.services.ai.ai_stream_helpers import (
    SseEventSequencer,
    chunk_to_sse_data,
    iter_with_heartbeat,
)

logger = logging.getLogger(__name__)


def tool_names_from_calls(function_calls: Any) -> List[str]:
    names: List[str] = []
    if not isinstance(function_calls, list):
        return names
    for item in function_calls:
        if isinstance(item, dict) and item.get("name"):
            names.append(str(item["name"]))
    return names


def _charge_stream_usage(ai_service: Any, usage: Optional[Dict[str, Any]], extra: Dict[str, Any]) -> Dict[str, Any]:
    usage = usage or {}
    input_tokens = int(usage.get("input_tokens", 0) or 0)
    output_tokens = int(usage.get("output_tokens", 0) or 0)
    charge_result: Dict[str, Any] = {}
    if input_tokens or output_tokens:
        try:
            charge_result = ai_service.check_quota_and_charge(input_tokens, output_tokens)
            ai_service.log_usage(
                provider=ai_service.config.provider if ai_service.config else "openai",
                model=ai_service.config.model_name if ai_service.config else "gpt-4",
                input_tokens=input_tokens,
                output_tokens=output_tokens,
                cost=charge_result.get("cost", 0),
                payment_method=charge_result.get("payment_method", "free"),
                wallet_transaction_id=charge_result.get("wallet_transaction_id"),
                document_id=charge_result.get("document_id"),
                context=extra,
            )
        except Exception:
            logger.warning("channel assist usage charge failed", exc_info=True)
    return {
        "input_tokens": input_tokens,
        "output_tokens": output_tokens,
        "total_tokens": input_tokens + output_tokens,
        "cost": charge_result.get("cost", 0),
        "payment_method": charge_result.get("payment_method", "free"),
    }


async def iter_channel_assist_sse(
    ai_service: Any,
    messages: List[Dict[str, Any]],
    *,
    tools: Optional[List[Any]] = None,
    user_query: str = "",
    iteration_cap: int = 4,
    result_field: str = "summary",
    feature: str = "channel_assist",
    extra: Optional[Dict[str, Any]] = None,
    execution_mode: str = "analyzer",
) -> AsyncIterator[str]:
    """رویدادهای status/content/tool/heartbeat/done برای ویجت کانال."""
    sequencer = SseEventSequencer()
    extra_ctx = {"feature": feature, **(extra or {})}
    yield sequencer.format({"type": "status", "phase": "connecting", "done": False})

    accumulated: List[str] = []
    usage: Optional[Dict[str, Any]] = None
    function_calls: Any = None
    citations: Any = None
    final_text = ""
    emitted_done = False

    async def _factory():
        async for chunk in ai_service.chat_completion_stream(
            messages,
            tools=tools,
            use_function_calling=bool(tools),
            execution_mode=execution_mode,
            approve_writes=False,
            user_query=user_query,
            session_business_id=getattr(ai_service, "business_id", None),
            iteration_cap=iteration_cap,
        ):
            yield chunk

    try:
        async for chunk in iter_with_heartbeat(_factory):
            for payload in chunk_to_sse_data(chunk):
                if payload.get("done"):
                    continue
                yield sequencer.format(payload)
            delta = chunk.get("delta") or {}
            piece = delta.get("content") or ""
            if piece:
                accumulated.append(str(piece))
            if chunk.get("function_calls"):
                function_calls = chunk["function_calls"]
            if chunk.get("usage"):
                usage = chunk["usage"]
            if chunk.get("citations") is not None:
                citations = chunk.get("citations")
            if chunk.get("done"):
                explicit = chunk.get("final_content")
                if isinstance(explicit, str) and explicit.strip():
                    final_text = explicit
                else:
                    final_text = "".join(accumulated)
                charge = _charge_stream_usage(ai_service, usage, extra_ctx)
                cites = citations if isinstance(citations, list) else []
                yield sequencer.format(
                    {
                        "type": "done",
                        "done": True,
                        "content": "",
                        "final_content": final_text,
                        result_field: final_text,
                        "tools_used": tool_names_from_calls(function_calls),
                        "citations": cites,
                        "usage": charge,
                    }
                )
                emitted_done = True
                return
    except Exception as exc:
        logger.exception("channel assist stream failed feature=%s", feature)
        yield sequencer.format(stream_error_payload(exc))
        return

    if not emitted_done:
        yield sequencer.format(
            stream_error_payload(code=STREAM_ERROR_EMPTY)
        )
