"""
خلاصه‌سازی تاریخچه مکالمه برای کاهش context.
"""
from __future__ import annotations

import json
import logging
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)

MAX_SUMMARY_CHARS = 3500


def _message_plain_text(msg: Dict[str, Any]) -> str:
    content = msg.get("content")
    if isinstance(content, str) and content.strip():
        return content.strip()
    if msg.get("tool_calls"):
        return "[فراخوانی ابزار]"
    return ""


def build_rule_based_history_summary(messages: List[Dict[str, Any]]) -> str:
    """خلاصهٔ سریع بدون LLM — برای fallback."""
    lines: List[str] = []
    for msg in messages:
        role = msg.get("role")
        if role not in ("user", "assistant"):
            continue
        text = _message_plain_text(msg)
        if not text or text.startswith("{"):
            continue
        label = "کاربر" if role == "user" else "دستیار"
        snippet = text.replace("\n", " ").strip()[:280]
        lines.append(f"- {label}: {snippet}")
    if not lines:
        return ""
    body = "\n".join(lines[-40:])
    if len(body) > MAX_SUMMARY_CHARS:
        body = body[-MAX_SUMMARY_CHARS:]
    return body


def summarize_history_with_llm(
    provider: Any,
    model: str,
    messages: List[Dict[str, Any]],
    *,
    max_output_tokens: int = 500,
) -> Optional[str]:
    """خلاصهٔ فشرده با یک فراخوانی LLM."""
    draft = build_rule_based_history_summary(messages)
    if not draft:
        return None

    prompt_messages = [
        {
            "role": "system",
            "content": (
                "توضیحات مکالمهٔ قبلی بین کاربر و دستیار حسابداری را به فارسی خلاصه کن. "
                "فقط حقایق، اعداد، ترجیحات و تصمیم‌های مهم را نگه دار. "
                "حداکثر ۱۵ بولت کوتاه. از حدس زدن خودداری کن."
            ),
        },
        {
            "role": "user",
            "content": f"متن مکالمه:\n\n{draft[:12000]}",
        },
    ]

    try:
        result = provider.chat_completion(
            messages=prompt_messages,
            model=model,
            max_tokens=max_output_tokens,
            temperature=0.2,
            tools=None,
        )
        content = (result.get("message") or {}).get("content") or ""
        text = str(content).strip()
        if not text:
            return None
        return text[:MAX_SUMMARY_CHARS]
    except Exception as exc:
        logger.warning("summarize_history_with_llm failed: %s", exc)
        return None


def messages_from_db_rows(db_messages: List[Any]) -> List[Dict[str, Any]]:
    """تبدیل پیام‌های DB به dict ساده برای extract_facts."""
    out: List[Dict[str, Any]] = []
    for msg in db_messages:
        role = msg.role if isinstance(msg.role, str) else getattr(msg.role, "value", str(msg.role))
        out.append({"role": role, "content": (msg.content or "").strip()})
    return out
