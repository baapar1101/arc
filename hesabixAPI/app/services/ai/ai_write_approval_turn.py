"""نوبت تأیید نوشتن بدون پیام جعلی کاربر (CHAT-06)."""
from __future__ import annotations

from typing import Any, Sequence

LEGACY_WRITE_APPROVAL_USER_TEXT = (
    "کاربر عملیات پیشنهادی را تأیید کرد. لطفاً همان عملیات را اجرا کن."
)

SILENT_WRITE_APPROVAL_LLM_TURN = (
    "[user_approved_writes]\n"
    "کاربر عملیات نوشتن پیشنهادی را تأیید کرد. "
    "فقط همان فراخوانی‌های تأییدشده را اجرا کن؛ عملیات جدید اختراع نکن."
)


def is_legacy_approval_user_text(content: str | None) -> bool:
    text = (content or "").strip()
    return text == LEGACY_WRITE_APPROVAL_USER_TEXT or text.startswith(
        "[user_approved_writes]"
    )


def is_silent_write_approval(
    *,
    approve_writes: bool,
    silent: bool = False,
    content: str | None = None,
) -> bool:
    if not approve_writes:
        return False
    if silent:
        return True
    text = (content or "").strip()
    return (not text) or is_legacy_approval_user_text(text)


def last_real_user_query(messages: Sequence[Any] | None) -> str:
    """آخرین پیام واقعی کاربر — نه متن جعلی تأیید."""
    for msg in reversed(list(messages or [])):
        if isinstance(msg, dict):
            role = msg.get("role")
            content = msg.get("content") or ""
        else:
            role = getattr(msg, "role", None)
            if not isinstance(role, str):
                role = getattr(role, "value", str(role or ""))
            content = getattr(msg, "content", None) or ""
        if str(role).lower() != "user":
            continue
        text = str(content).strip()
        if not text or is_legacy_approval_user_text(text):
            continue
        return text
    return ""
