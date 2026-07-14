"""
پاک‌سازی خروجی مدل — حذف توکن‌های Harmony و بازیابی tool callهای نشت‌کرده.
"""
from __future__ import annotations

import json
import re
import uuid
from typing import Any, Dict, List, Optional

# فرمت کامل نشت tool call در متن (با یا بدون to=functions.NAME)
_HARMONY_TOOL_LEAK = re.compile(
    r"<\|start\|>assistant<\|channel\|>commentary"
    r"(?:\s+to=functions\.(\w+))?"
    r"(?:\s*<\|constrain\|>\w+)?"
    r"<\|message\|>(\{.*?\})<\|call\|>",
    re.DOTALL,
)

# توکن‌های کنترلی باقی‌مانده
_HARMONY_CONTROL_TOKEN = re.compile(
    r"<\|(?:start|end|channel|message|call|constrain)\|>[^<\n]*"
)

# هر چیزی از <|start|> به بعد (نشت ناقص)
_HARMONY_TAIL = re.compile(r"<\|start\|>.*", re.DOTALL)


def extract_leaked_function_calls(text: str) -> List[Dict[str, Any]]:
    """استخراج tool callهای نشت‌کرده از فرمت Harmony در متن."""
    if not text:
        return []
    calls: List[Dict[str, Any]] = []
    seen: set[str] = set()
    for match in _HARMONY_TOOL_LEAK.finditer(text):
        name = (match.group(1) or "").strip()
        raw_json = (match.group(2) or "").strip()
        if not raw_json:
            continue
        try:
            arguments = json.loads(raw_json)
        except json.JSONDecodeError:
            continue
        if not isinstance(arguments, dict):
            continue
        if not name:
            # برخی مدل‌ها نام ابزار را در JSON می‌گذارند
            inferred = arguments.pop("name", None) or arguments.pop("tool", None)
            if isinstance(inferred, str) and inferred.strip():
                name = inferred.strip()
        if not name:
            continue
        dedupe_key = f"{name}:{json.dumps(arguments, sort_keys=True, ensure_ascii=False)}"
        if dedupe_key in seen:
            continue
        seen.add(dedupe_key)
        calls.append(
            {
                "id": f"leaked_{uuid.uuid4().hex[:12]}",
                "name": name,
                "arguments": arguments,
            }
        )
    return calls


def sanitize_assistant_content(text: str) -> str:
    """حذف توکن‌های Harmony و نشت tool call از متن قابل‌نمایش."""
    if not text:
        return text
    cleaned = _HARMONY_TOOL_LEAK.sub("", text)
    cleaned = _HARMONY_TAIL.sub("", cleaned)
    cleaned = _HARMONY_CONTROL_TOKEN.sub("", cleaned)
    # فاصله‌های اضافی انتهای خطوط و خطوط خالی پیاپی
    cleaned = re.sub(r"[ \t]+\n", "\n", cleaned)
    cleaned = re.sub(r"\n{3,}", "\n\n", cleaned)
    return cleaned.strip()


def prepare_assistant_content_for_persist(
    accumulated_content: str,
    trace_steps: Optional[List[Dict[str, Any]]],
) -> str:
    """ترکیب متن stream/trace و پاک‌سازی قبل از ذخیره."""
    from app.services.ai.ai_trace import merge_accumulated_and_trace_content

    merged = merge_accumulated_and_trace_content(
        accumulated_content or "",
        trace_steps,
    )
    return sanitize_assistant_content(merged)
