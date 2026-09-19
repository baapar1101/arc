"""تست نوبت تأیید نوشتن بدون پیام جعلی کاربر."""
from __future__ import annotations

from app.services.ai.ai_write_approval_turn import (
    LEGACY_WRITE_APPROVAL_USER_TEXT,
    SILENT_WRITE_APPROVAL_LLM_TURN,
    is_silent_write_approval,
    last_real_user_query,
)


def test_silent_when_flag_or_empty_or_legacy_text():
    assert is_silent_write_approval(
        approve_writes=True, silent=True, content="هر چیزی"
    )
    assert is_silent_write_approval(approve_writes=True, content="")
    assert is_silent_write_approval(
        approve_writes=True, content=LEGACY_WRITE_APPROVAL_USER_TEXT
    )
    assert not is_silent_write_approval(
        approve_writes=False, silent=True, content=""
    )
    assert not is_silent_write_approval(
        approve_writes=True, content="یک فاکتور بساز"
    )


def test_last_real_user_query_skips_legacy_confirm():
    messages = [
        {"role": "user", "content": "یک شخص جدید بساز"},
        {"role": "assistant", "content": "نیاز به تأیید"},
        {"role": "user", "content": LEGACY_WRITE_APPROVAL_USER_TEXT},
    ]
    assert last_real_user_query(messages) == "یک شخص جدید بساز"
    assert "[user_approved_writes]" in SILENT_WRITE_APPROVAL_LLM_TURN
