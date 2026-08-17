"""لاگ و شمارندهٔ درون‌پردازه‌ای متریک‌های عملیاتی AI (OBS-02)."""
from __future__ import annotations

import logging
from collections import defaultdict
from typing import Any, Dict, Optional

logger = logging.getLogger(__name__)

_counters: Dict[str, int] = defaultdict(int)


def log_ai_event(
    event: str,
    *,
    business_id: Optional[int] = None,
    user_id: Optional[int] = None,
    session_id: Optional[int] = None,
    extra: Optional[Dict[str, Any]] = None,
) -> None:
    _counters[str(event)] += 1
    payload: Dict[str, Any] = {"ai_event": event}
    if business_id is not None:
        payload["business_id"] = business_id
    if user_id is not None:
        payload["user_id"] = user_id
    if session_id is not None:
        payload["session_id"] = session_id
    if extra:
        payload.update(extra)
    logger.info("AI_METRIC %s", payload)


def metric_snapshot() -> Dict[str, int]:
    """نسخهٔ فعلی شمارنده‌های این فرآیند — نه Prometheus."""
    return dict(_counters)


def reset_metrics_for_tests() -> None:
    _counters.clear()
