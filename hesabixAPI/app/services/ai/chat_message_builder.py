"""
ساخت پیام‌های سازگار با OpenAI از تاریخچه ذخیره‌شده در دیتابیس.
"""
from __future__ import annotations

import json
import logging
from typing import Any, Dict, List, Optional, Tuple

from app.core.json_safe import json_dumps_safe

logger = logging.getLogger(__name__)


def parse_json_field(raw: Any) -> Any:
    if raw is None:
        return None
    if isinstance(raw, str):
        try:
            return json.loads(raw)
        except json.JSONDecodeError:
            return None
    return raw


def normalize_function_calls(function_calls: Any) -> List[Dict[str, Any]]:
    if function_calls is None:
        return []
    if isinstance(function_calls, list):
        return function_calls
    if isinstance(function_calls, dict):
        if "calls" in function_calls and isinstance(function_calls["calls"], list):
            return function_calls["calls"]
        if function_calls.get("name"):
            return [function_calls]
    return []


def build_llm_messages_from_history(db_messages: List[Any]) -> List[Dict[str, Any]]:
    """
    تبدیل پیام‌های DB به فرمت OpenAI (شامل assistant+tool برای function calling).
    """
    llm_messages: List[Dict[str, Any]] = []

    for msg in db_messages:
        role = msg.role if isinstance(msg.role, str) else getattr(msg.role, "value", str(msg.role))
        content = (msg.content or "").strip()
        function_calls = parse_json_field(msg.function_calls)
        function_results = parse_json_field(msg.function_results)

        if role == "assistant" and function_calls:
            calls = normalize_function_calls(function_calls)
            if not calls:
                llm_messages.append({"role": role, "content": msg.content or ""})
                continue
            assistant_msg: Dict[str, Any] = {"role": "assistant", "tool_calls": []}
            if content:
                assistant_msg["content"] = content

            tool_call_ids: Dict[str, str] = {}
            for idx, call in enumerate(calls):
                name = call.get("name", "unknown")
                tc_id = call.get("id") or f"hist_{getattr(msg, 'id', 0)}_{idx}_{name}"
                tool_call_ids[name] = tc_id
                args = call.get("arguments", {})
                assistant_msg["tool_calls"].append(
                    {
                        "id": tc_id,
                        "type": "function",
                        "function": {
                            "name": name,
                            "arguments": (
                                json.dumps(args, ensure_ascii=False)
                                if isinstance(args, dict)
                                else str(args)
                            ),
                        },
                    }
                )
            llm_messages.append(assistant_msg)

            results: Dict[str, Any] = function_results if isinstance(function_results, dict) else {}
            for call in calls:
                fname = call.get("name", "unknown")
                tc_id = call.get("id") or tool_call_ids.get(fname, f"hist_{fname}")
                result = results.get(tc_id, results.get(fname, {}))
                if isinstance(result, dict) and "result" in result and "name" in result:
                    result = result.get("result")
                if isinstance(result, (dict, list)):
                    serialized = json_dumps_safe(result)
                else:
                    serialized = str(result) if result is not None else "{}"
                llm_messages.append(
                    {
                        "role": "tool",
                        "tool_call_id": tc_id,
                        "content": serialized,
                    }
                )
        elif role in ("user", "assistant", "system"):
            llm_messages.append({"role": role, "content": msg.content or ""})

    return repair_llm_tool_messages(llm_messages)


def _following_tool_messages(
    messages: List[Dict[str, Any]], start_index: int
) -> List[Dict[str, Any]]:
    tool_msgs: List[Dict[str, Any]] = []
    idx = start_index
    while idx < len(messages) and messages[idx].get("role") == "tool":
        tool_msgs.append(messages[idx])
        idx += 1
    return tool_msgs


def expand_strict_tool_message_pairs(
    messages: List[Dict[str, Any]],
) -> List[Dict[str, Any]]:
    """
    برخی gatewayهای OpenAI-compatible (مثل GPT-OSS روی vLLM) فقط وقتی
    پیام tool را می‌پذیرند که بلافاصله بعد از assistant با همان tool_call باشد.
    """
    if not messages:
        return messages

    out: List[Dict[str, Any]] = []
    idx = 0
    while idx < len(messages):
        msg = messages[idx]
        role = msg.get("role")

        if role == "assistant" and msg.get("tool_calls"):
            tool_calls = msg.get("tool_calls") or []
            tool_msgs = _following_tool_messages(messages, idx + 1)
            next_idx = idx + 1 + len(tool_msgs)

            if len(tool_calls) <= 1:
                out.append(dict(msg))
                out.extend(dict(tm) for tm in tool_msgs)
                idx = next_idx
                continue

            tool_by_id = {
                tm.get("tool_call_id"): tm
                for tm in tool_msgs
                if tm.get("tool_call_id")
            }
            assistant_content = msg.get("content")
            for tc_index, tc in enumerate(tool_calls):
                pair_assistant: Dict[str, Any] = {
                    "role": "assistant",
                    "tool_calls": [tc],
                }
                if assistant_content and tc_index == 0:
                    pair_assistant["content"] = assistant_content
                out.append(pair_assistant)
                tc_id = tc.get("id")
                if tc_id and tc_id in tool_by_id:
                    out.append(dict(tool_by_id[tc_id]))

            matched_ids = {tc.get("id") for tc in tool_calls}
            for tm in tool_msgs:
                if tm.get("tool_call_id") not in matched_ids:
                    out.append(dict(tm))
            idx = next_idx
            continue

        if role == "tool":
            logger.warning(
                "Dropping orphaned tool message without preceding assistant tool_calls"
            )
            idx += 1
            continue

        out.append(dict(msg))
        idx += 1

    return out


def drop_leading_orphan_tool_messages(
    messages: List[Dict[str, Any]],
) -> List[Dict[str, Any]]:
    """حذف toolهای یتیم در ابتدای تاریخچه (مثلاً بعد از trim)."""
    if not messages:
        return messages

    start = 0
    while start < len(messages) and messages[start].get("role") == "tool":
        logger.warning("Dropping leading orphaned tool message at index %s", start)
        start += 1
    if start == 0:
        return messages
    return messages[start:]


def repair_llm_tool_messages(
    messages: List[Dict[str, Any]],
) -> List[Dict[str, Any]]:
    """نرمال‌سازی زنجیره assistant/tool برای providerهای سخت‌گیر."""
    cleaned = drop_leading_orphan_tool_messages(messages)
    return expand_strict_tool_message_pairs(cleaned)


def serialize_function_metadata(
    function_calls: Optional[List[Dict[str, Any]]],
    function_results: Optional[Dict[str, Any]],
) -> Tuple[Optional[str], Optional[str]]:
    calls_json = json_dumps_safe(function_calls) if function_calls else None
    results_json = json_dumps_safe(function_results) if function_results else None
    return calls_json, results_json
