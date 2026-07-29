"""
مدیریت حجم context ارسالی به مدل (تک API).
"""
from __future__ import annotations

import json
from typing import Any, Dict, List, Optional

from app.services.ai.ai_constants import (
    MAX_HISTORY_MESSAGES,
    MAX_SINGLE_MESSAGE_CHARS,
    MAX_SYSTEM_PROMPT_CHARS,
    MAX_TOOL_RESULT_JSON_CHARS,
)

_TRUNC_SUFFIX = "\n\n… [متن کوتاه شد]"


def _truncate_text(text: str, max_chars: int) -> str:
    if len(text) <= max_chars:
        return text
    return text[: max_chars - len(_TRUNC_SUFFIX)] + _TRUNC_SUFFIX


def trim_system_prompt(prompt: str) -> str:
    if len(prompt) <= MAX_SYSTEM_PROMPT_CHARS:
        return prompt
    return _truncate_text(prompt, MAX_SYSTEM_PROMPT_CHARS)


def trim_system_prompt_sections(
    core: str,
    runtime_sections: Optional[List[str]] = None,
    *,
    max_chars: int = MAX_SYSTEM_PROMPT_CHARS,
) -> str:
    """
    کوتاه‌سازی با اولویت: هستهٔ پرامپت (بلوک‌های ثابت) حفظ می‌شود؛
    بخش‌های runtime (insights، memory، knowledge، …) بر اساس اولویت اضافه می‌شوند.
    """
    runtime_sections = [s for s in (runtime_sections or []) if s and s.strip()]
    core = core or ""
    if not runtime_sections:
        return trim_system_prompt(core)

    budget = max_chars
    if len(core) >= budget:
        return _truncate_text(core, budget)

    remaining = budget - len(core)
    kept: List[str] = []
    for section in runtime_sections:
        section = section.strip()
        if not section:
            continue
        if len(section) <= remaining:
            kept.append(section)
            remaining -= len(section)
            continue
        if remaining > 120:
            kept.append(_truncate_text(section, remaining))
        break

    combined = core + "".join(kept)
    if len(combined) <= max_chars:
        return combined
    return _truncate_text(combined, max_chars)


def trim_messages_for_llm(messages: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """نگه‌داشتن آخرین پیام‌ها و کوتاه‌کردن محتوای بلند."""
    if not messages:
        return messages

    system_msgs = [m for m in messages if m.get("role") == "system"]
    rest = [m for m in messages if m.get("role") != "system"]

    if len(rest) > MAX_HISTORY_MESSAGES:
        rest = rest[-MAX_HISTORY_MESSAGES:]

    trimmed: List[Dict[str, Any]] = []
    for msg in system_msgs + rest:
        out = dict(msg)
        content = out.get("content")
        if isinstance(content, str) and len(content) > MAX_SINGLE_MESSAGE_CHARS:
            out["content"] = _truncate_text(content, MAX_SINGLE_MESSAGE_CHARS)
        trimmed.append(out)
    return trimmed


def serialize_tool_result_for_llm(result: Any) -> str:
    """JSON فشرده برای role=tool با سقف طول."""
    if isinstance(result, (dict, list)):
        text = json.dumps(result, ensure_ascii=False)
    else:
        text = str(result)
    if len(text) <= MAX_TOOL_RESULT_JSON_CHARS:
        return text
    return text[: MAX_TOOL_RESULT_JSON_CHARS - 24] + "\n… [نتیجه کوتاه شد]"
