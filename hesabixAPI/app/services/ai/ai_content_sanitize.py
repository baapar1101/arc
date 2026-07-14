"""
پاک‌سازی خروجی مدل — حذف توکن‌های Harmony و بازیابی tool callهای نشت‌کرده.
"""
from __future__ import annotations

import json
import re
import uuid
from typing import Any, Dict, Iterable, List, Optional, Set

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

# مدل گاهی فقط «برنامه» می‌دهد بدون فراخوانی واقعی API
_INTENT_EN = re.compile(
    r"(?i)\b(?:will|need to|going to|let'?s|should|must|have to)\s+"
    r"(?:call|use|invoke)\b"
)
_INTENT_FA = re.compile(
    r"فراخوانی\s+ابزار|ابتدا\s+باید|"
    r"در\s+حال\s+(?:تبدیل|تعیین|آماده|استخراج)|"
    r"سپس\s+.*(?:محاسبه|دریافت|استخراج|محاسبه)"
)
_BACKTICK_TOOL = re.compile(r"`([a-zA-Z_][\w]*)`")
_PLAIN_TOOL_CALL = re.compile(
    r"(?i)\b(?:call|use|invoke)\s+[`']?([a-zA-Z_][\w]*)[`']?"
)


def text_announces_pending_tool_use(text: str) -> bool:
    """آیا متن فقط اعلام intent ابزار است، نه پاسخ نهایی با داده؟"""
    stripped = (text or "").strip()
    if not stripped:
        return False
    if _INTENT_EN.search(stripped) or _INTENT_FA.search(stripped):
        return True
    if "**اقدام:**" in stripped or "**اقدام**" in stripped:
        return True
    if _PLAIN_TOOL_CALL.search(stripped):
        return True
    # backtick tool name بدون عدد/جدول نتیجه
    if _BACKTICK_TOOL.search(stripped) and not re.search(
        r"\*\*\d|`\d|یافت شد|مورد|\|\s*[-—]",
        stripped,
    ):
        if re.search(
            r"(?i)(?:call|use|invoke|فراخوانی|ابزار|ابتدا|سپس|need to|will)",
            stripped,
        ):
            return True
    return False


def _collect_tool_names_from_text(
    text: str,
    known_tools: Set[str],
) -> List[str]:
    names: List[str] = []
    seen: set[str] = set()

    def _add(name: str) -> None:
        if name in known_tools and name not in seen:
            seen.add(name)
            names.append(name)

    for match in _BACKTICK_TOOL.finditer(text):
        _add(match.group(1))
    for match in _PLAIN_TOOL_CALL.finditer(text):
        _add(match.group(1))
    for name in sorted(known_tools, key=len, reverse=True):
        if re.search(rf"\b{re.escape(name)}\b", text):
            _add(name)
    return names


def infer_announced_function_calls(
    text: str,
    known_tools: Optional[Iterable[str]] = None,
) -> List[Dict[str, Any]]:
    """استنتاج tool call از متن برنامه‌ای مدل وقتی API tool_calls خالی است."""
    if not text or not text_announces_pending_tool_use(text):
        return []
    tool_set = {t for t in (known_tools or []) if isinstance(t, str) and t.strip()}
    if not tool_set:
        return []
    names = _collect_tool_names_from_text(text, tool_set)
    if not names:
        return []
    return [
        {
            "id": f"announced_{uuid.uuid4().hex[:12]}",
            "name": name,
            "arguments": {},
        }
        for name in names[:3]
    ]


def resolve_round_function_calls(
    *,
    api_function_calls: Optional[List[Dict[str, Any]]],
    round_text: str,
    round_reasoning: str,
    known_tools: Optional[Iterable[str]] = None,
) -> Optional[List[Dict[str, Any]]]:
    """ترکیب tool_calls API، Harmony leak و intent متنی."""
    if api_function_calls:
        return api_function_calls
    combined = f"{round_text or ''}\n{round_reasoning or ''}".strip()
    if not combined:
        return None
    for source in (round_text, round_reasoning, combined):
        leaked = extract_leaked_function_calls(source or "")
        if leaked:
            return leaked
    announced = infer_announced_function_calls(combined, known_tools)
    return announced or None

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
