"""لاگ متریک‌های عملیاتی AI."""
from __future__ import annotations

import logging
from typing import Any, Dict, Optional

logger = logging.getLogger(__name__)


def log_ai_event(
    event: str,
    *,
    business_id: Optional[int] = None,
    user_id: Optional[int] = None,
    session_id: Optional[int] = None,
    extra: Optional[Dict[str, Any]] = None,
) -> None:
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
