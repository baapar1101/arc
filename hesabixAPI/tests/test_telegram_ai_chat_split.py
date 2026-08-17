"""تست صفحه‌بندی و دکمه‌های تأیید تلگرام (CHN-01)."""
from app.services.telegram_ai_chat_text import (
    TELEGRAM_CALLBACK_DATA_LIMIT,
    TELEGRAM_MESSAGE_LIMIT,
    split_telegram_text,
    telegram_approval_inline_rows,
)


def test_split_short_text_stays_one_chunk():
    assert split_telegram_text("سلام") == ["سلام"]


def test_split_long_text_breaks_on_newline():
    block = "\n".join(f"خط {i}" for i in range(40))
    chunks = split_telegram_text(block, limit=80)
    assert len(chunks) > 1
    assert all(len(c) <= 80 for c in chunks)
    assert "خط 0" in chunks[0]


def test_split_respects_default_limit():
    text = "x" * (TELEGRAM_MESSAGE_LIMIT + 50)
    chunks = split_telegram_text(text)
    assert len(chunks) == 2
    assert len(chunks[0]) <= TELEGRAM_MESSAGE_LIMIT


def test_approval_inline_rows_fit_telegram_callback_limit():
    rows = telegram_approval_inline_rows(
        [
            {
                "approval_id": "abc123def4567890",
                "function": "create_person",
                "label": "ایجاد شخص",
                "arguments": {"name": "علی"},
            }
        ]
    )
    assert len(rows) == 1
    assert rows[0][0]["callback_data"] == "ai:approve:abc123def4567890"
    assert rows[0][1]["callback_data"] == "ai:reject:abc123def4567890"
    for btn in rows[0]:
        assert len(btn["callback_data"].encode("utf-8")) <= TELEGRAM_CALLBACK_DATA_LIMIT


def test_approval_inline_rows_skip_missing_id():
    assert telegram_approval_inline_rows([{"function": "create_person"}]) == []
