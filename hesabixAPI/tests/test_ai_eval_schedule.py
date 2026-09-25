"""قفل زمان‌بندی eval روی slot بدون وابستگی به dict درون‌حافظه."""
from __future__ import annotations

from datetime import datetime, timezone

import pytz

from app.services.ai.ai_eval_schedule_service import already_fired_for_slot


def test_already_fired_for_slot_matches_local_minute() -> None:
    tehran = pytz.timezone("Asia/Tehran")
    local = tehran.localize(datetime(2026, 8, 17, 3, 0, 12))
    utc = local.astimezone(timezone.utc).replace(tzinfo=None)
    assert already_fired_for_slot(utc, "Asia/Tehran", "202608170300") is True
    assert already_fired_for_slot(utc, "Asia/Tehran", "202608170301") is False
    assert already_fired_for_slot(None, "Asia/Tehran", "202608170300") is False
