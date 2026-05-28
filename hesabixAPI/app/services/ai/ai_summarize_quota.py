"""سقف روزانهٔ خلاصه‌سازی LLM."""
from __future__ import annotations

import logging
import time
from typing import Dict, Tuple

from app.services.ai.ai_constants import MAX_LLM_SUMMARIZE_PER_USER_DAY

logger = logging.getLogger(__name__)

_quota_store: Dict[Tuple[int, int], Tuple[str, int]] = {}


def _day_key() -> str:
    return time.strftime("%Y-%m-%d", time.gmtime())


def can_use_llm_summarize(user_id: int, business_id: int) -> bool:
    key = (int(user_id), int(business_id))
    day = _day_key()
    entry = _quota_store.get(key)
    if not entry or entry[0] != day:
        return True
    return entry[1] < MAX_LLM_SUMMARIZE_PER_USER_DAY


def record_llm_summarize(user_id: int, business_id: int) -> None:
    key = (int(user_id), int(business_id))
    day = _day_key()
    entry = _quota_store.get(key)
    if not entry or entry[0] != day:
        _quota_store[key] = (day, 1)
    else:
        _quota_store[key] = (day, entry[1] + 1)
    logger.info(
        "ai_llm_summarize_used user=%s business=%s count=%s",
        user_id,
        business_id,
        _quota_store[key][1],
    )
