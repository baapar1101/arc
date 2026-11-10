"""قواعد خالص دستیار CRM: پاسخ مجاز، امتیاز پیش‌بین و جمله وظیفه.

این ماژول سند حسابداری نمی‌سازد.
"""
from __future__ import annotations

import re
from datetime import datetime, timedelta
from typing import Any

PREDICTIVE_CLOSED_DEAL_GATE = 200
_STAGE_SAMPLE = 20
_DIGITS = str.maketrans("۰۱۲۳۴۵۶۷۸۹٠١٢٣٤٥٦٧٨٩", "01234567890123456789")
_DAY_PHRASE = re.compile(r"[0-9]+\s*روز")

FINANCIAL_KEYS = (
    "balance",
    "status",
    "sales_total",
    "returns_total",
    "net_sales",
    "open_document_count",
    "open_remaining",
    "margin_amount",
    "margin_complete",
    "mixed_currency",
    "documents_truncated",
    "receipt_count",
)
REPEAT_KEYS = ("product_name", "invoice_count", "last_document_date")
ACTION_KEYS = ("code", "title", "reason")
PREDICTIVE_KEYS = ("available", "score", "reason", "closed_deals", "required", "sample_size", "basis")


def whitelist_financial_answer(payload: dict[str, Any] | None) -> dict[str, Any]:
    source = payload or {}
    answer = {key: source.get(key) for key in FINANCIAL_KEYS if key in source}
    repeats = []
    for row in source.get("repeat_products") or []:
        if isinstance(row, dict):
            repeats.append({key: row.get(key) for key in REPEAT_KEYS})
    answer["repeat_products"] = repeats[:5]
    action = source.get("next_action")
    answer["next_action"] = {key: action.get(key) for key in ACTION_KEYS} if isinstance(action, dict) else None
    predictive = source.get("predictive")
    answer["predictive"] = {key: predictive.get(key) for key in PREDICTIVE_KEYS} if isinstance(predictive, dict) else None
    answer["posted_document"] = False
    return answer


def predictive_from_counts(
    *,
    closed_deals: int,
    business_won: int,
    stage_closed: int = 0,
    stage_won: int = 0,
) -> dict[str, Any]:
    closed = max(int(closed_deals or 0), 0)
    base = {
        "available": False,
        "score": None,
        "closed_deals": closed,
        "required": PREDICTIVE_CLOSED_DEAL_GATE,
        "sample_size": None,
        "basis": None,
    }
    if closed < PREDICTIVE_CLOSED_DEAL_GATE:
        base["reason"] = "closed_deal_volume"
        return base
    if int(stage_closed or 0) >= _STAGE_SAMPLE:
        sample = int(stage_closed)
        won = int(stage_won or 0)
        basis = "stage"
    else:
        sample = closed
        won = int(business_won or 0)
        basis = "business"
    rate = 0 if sample <= 0 else max(0, min(won, sample)) / sample
    base.update(
        {
            "available": True,
            "score": int(round(rate * 100)),
            "reason": "historical_win_rate",
            "sample_size": sample,
            "basis": basis,
        }
    )
    return base


def parse_task_sentence(text: str, now: datetime) -> dict[str, Any]:
    raw = " ".join((text or "").split()).strip()
    if not raw:
        raise ValueError("متن وظیفه خالی است")
    folded = raw.translate(_DIGITS)
    due_in_days = None
    if "پس‌فردا" in raw or "پس فردا" in raw:
        due_in_days = 2
    elif "فردا" in raw:
        due_in_days = 1
    elif "امروز" in raw:
        due_in_days = 0
    else:
        match = _DAY_PHRASE.search(folded)
        if match:
            due_in_days = min(int(match.group(0).split()[0]), 365)
    subject = raw
    for token in ("پس‌فردا", "پس فردا", "فردا", "امروز"):
        subject = subject.replace(token, " ")
    subject = _DAY_PHRASE.sub(" ", subject.translate(_DIGITS))
    subject = " ".join(subject.split()).strip(" ،-") or "پیگیری"
    due = None if due_in_days is None else (now + timedelta(days=due_in_days)).replace(microsecond=0)
    return {
        "subject": subject[:255],
        "due_at": due.isoformat() if due else None,
        "due_in_days": due_in_days,
        "is_task": True,
    }
