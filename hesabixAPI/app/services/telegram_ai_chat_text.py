"""کمک‌کننده‌های متن تلگرام بدون وابستگی به AIService."""
from __future__ import annotations

from typing import Any, Dict, List

TELEGRAM_MESSAGE_LIMIT = 3500
TELEGRAM_CALLBACK_DATA_LIMIT = 64
TELEGRAM_APPROVAL_HINT_FA = (
    "\n\nبرای تأیید یا رد این عملیات، دکمه‌های زیر را بزنید."
)
TELEGRAM_APPROVE_PREFIX = "ai:approve:"
TELEGRAM_REJECT_PREFIX = "ai:reject:"


def split_telegram_text(text: str, limit: int = TELEGRAM_MESSAGE_LIMIT) -> List[str]:
    """صفحه‌بندی پاسخ بلند تلگرام بدون برش وسط کلمه در حد امکان."""
    body = (text or "").strip()
    if not body:
        return [""]
    if len(body) <= limit:
        return [body]
    chunks: List[str] = []
    rest = body
    while rest:
        if len(rest) <= limit:
            chunks.append(rest)
            break
        cut = rest.rfind("\n", 0, limit)
        if cut < limit // 2:
            cut = rest.rfind(" ", 0, limit)
        if cut < limit // 3:
            cut = limit
        chunks.append(rest[:cut].rstrip())
        rest = rest[cut:].lstrip()
    return chunks or [body[:limit]]


def telegram_approval_inline_rows(
    ops: List[Dict[str, Any]],
    *,
    max_ops: int = 3,
) -> List[List[Dict[str, str]]]:
    """دکمه‌های تأیید/رد با callback_data زیر سقف ۶۴ بایت تلگرام."""
    rows: List[List[Dict[str, str]]] = []
    for op in ops[: max(0, max_ops)]:
        aid = str(op.get("approval_id") or "").strip()
        if not aid:
            continue
        approve_data = f"{TELEGRAM_APPROVE_PREFIX}{aid}"
        reject_data = f"{TELEGRAM_REJECT_PREFIX}{aid}"
        if (
            len(approve_data.encode("utf-8")) > TELEGRAM_CALLBACK_DATA_LIMIT
            or len(reject_data.encode("utf-8")) > TELEGRAM_CALLBACK_DATA_LIMIT
        ):
            continue
        label = str(op.get("label") or op.get("function") or "عملیات").strip()
        if len(label) > 18:
            label = label[:17] + "…"
        rows.append(
            [
                {"text": f"✅ تأیید {label}", "callback_data": approve_data},
                {"text": "❌ رد", "callback_data": reject_data},
            ]
        )
    return rows
