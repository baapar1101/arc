"""
ساخت پیام‌های سازگار با OpenAI از تاریخچه ذخیره‌شده در دیتابیس.
"""
from __future__ import annotations

import json
from typing import Any, Dict, List, Optional, Tuple

from app.core.json_safe import json_dumps_safe


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
                result = results.get(fname, {})
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

    return llm_messages


def serialize_function_metadata(
    function_calls: Optional[List[Dict[str, Any]]],
    function_results: Optional[Dict[str, Any]],
) -> Tuple[Optional[str], Optional[str]]:
    calls_json = json_dumps_safe(function_calls) if function_calls else None
    results_json = json_dumps_safe(function_results) if function_results else None
    return calls_json, results_json
