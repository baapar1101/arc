"""
خلاصه‌سازی تاریخچه مکالمه برای کاهش context.
"""
from __future__ import annotations

import json
import logging
from typing import Any, Dict, List, Optional

from sqlalchemy.orm import Session

from app.services.ai.ai_language_prompt import (
    build_history_summary_system_prompt,
    detect_message_language,
)
from app.services.ai.prompt_service import get_prompt_by_key

logger = logging.getLogger(__name__)

MAX_SUMMARY_CHARS = 3500


def _message_plain_text(msg: Dict[str, Any]) -> str:
    content = msg.get("content")
    if isinstance(content, str) and content.strip():
        return content.strip()
    if msg.get("tool_calls"):
        return "[فراخوانی ابزار]"
    return ""


def _resolve_summary_language(
    messages: List[Dict[str, Any]],
    *,
    language: Optional[str] = None,
) -> str:
    if language in ("fa", "en"):
        return language
    for msg in reversed(messages):
        if msg.get("role") != "user":
            continue
        detected = detect_message_language(_message_plain_text(msg))
        if detected:
            return detected
    return "fa"


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


def summarize_history_with_llm_detailed(
    provider: Any,
    model: str,
    messages: List[Dict[str, Any]],
    *,
    db: Optional[Session] = None,
    max_output_tokens: int = 500,
    language: Optional[str] = None,
) -> tuple[Optional[str], Optional[Dict[str, Any]]]:
    """خلاصهٔ فشرده با LLM؛ usage را هم برمی‌گرداند تا در صورتحساب لحاظ شود."""
    draft = build_rule_based_history_summary(messages)
    if not draft:
        return None, None

    lang = _resolve_summary_language(messages, language=language)
    system_content = build_history_summary_system_prompt(lang)
    if db is not None:
        try:
            seeded = get_prompt_by_key(db, "aux.history_summary")
            if seeded and lang == "fa":
                system_content = seeded
        except Exception:
            pass

    user_prefix = (
        "Conversation text:\n\n"
        if lang == "en"
        else "متن مکالمه:\n\n"
    )

    prompt_messages = [
        {"role": "system", "content": system_content},
        {
            "role": "user",
            "content": f"{user_prefix}{draft[:12000]}",
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
            return None, None
        usage = result.get("usage") if isinstance(result, dict) else None
        return text[:MAX_SUMMARY_CHARS], usage if isinstance(usage, dict) else None
    except Exception as exc:
        logger.warning("summarize_history_with_llm failed: %s", exc)
        return None, None


def summarize_history_with_llm(
    provider: Any,
    model: str,
    messages: List[Dict[str, Any]],
    *,
    db: Optional[Session] = None,
    max_output_tokens: int = 500,
    language: Optional[str] = None,
) -> Optional[str]:
    """خلاصهٔ فشرده با یک فراخوانی LLM."""
    text, _usage = summarize_history_with_llm_detailed(
        provider,
        model,
        messages,
        db=db,
        max_output_tokens=max_output_tokens,
        language=language,
    )
    return text


def messages_from_db_rows(db_messages: List[Any]) -> List[Dict[str, Any]]:
    """تبدیل پیام‌های DB به dict ساده برای extract_facts."""
    out: List[Dict[str, Any]] = []
    for msg in db_messages:
        role = msg.role if isinstance(msg.role, str) else getattr(msg.role, "value", str(msg.role))
        out.append({"role": role, "content": (msg.content or "").strip()})
    return out
