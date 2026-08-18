"""یادگیری از بازخورد thumbs — به‌صورت آیتم حافظه (بی‌صدا)."""
from __future__ import annotations

import logging
from datetime import datetime
from typing import Dict, Optional, Tuple

from sqlalchemy.orm import Session

from adapters.db.models.ai_chat_message import AIChatMessage
from adapters.db.models.ai_chat_session import AIChatSession
from app.services.ai.ai_constants import MAX_MEMORY_FEEDBACK_UPDATES_PER_DAY
from app.services.ai.ai_ops_metrics import log_ai_event

logger = logging.getLogger(__name__)

_feedback_daily: Dict[Tuple[int, int], Tuple[str, int]] = {}


def _day_key() -> str:
    return datetime.utcnow().strftime("%Y-%m-%d")


def _can_apply_feedback(user_id: int, business_id: int) -> bool:
    key = (int(user_id), int(business_id))
    day = _day_key()
    entry = _feedback_daily.get(key)
    if not entry or entry[0] != day:
        return True
    return entry[1] < MAX_MEMORY_FEEDBACK_UPDATES_PER_DAY


def _record_feedback_apply(user_id: int, business_id: int) -> None:
    key = (int(user_id), int(business_id))
    day = _day_key()
    entry = _feedback_daily.get(key)
    if not entry or entry[0] != day:
        _feedback_daily[key] = (day, 1)
    else:
        _feedback_daily[key] = (day, entry[1] + 1)


def apply_feedback_to_memory(
    db: Session,
    message_id: int,
    user_id: int,
    rating: int,
    comment: Optional[str] = None,
) -> bool:
    msg = db.query(AIChatMessage).filter(AIChatMessage.id == message_id).first()
    if not msg or msg.role != "assistant":
        return False

    session = db.query(AIChatSession).filter(AIChatSession.id == msg.session_id).first()
    if not session or not session.business_id:
        return False

    business_id = int(session.business_id)
    if not _can_apply_feedback(user_id, business_id):
        return False

    # فقط بازخورد منفی با نظر متنی ارزش حافظه دارد
    if rating >= 0 or not (comment or "").strip():
        return False

    from app.services.ai.ai_memory_item_service import upsert_memory_item

    note = f"اجتناب از این الگو: {comment.strip()[:160]}"
    try:
        upsert_memory_item(
            db,
            business_id,
            user_id,
            item_key=None,
            category="constraint",
            content=note,
            source="feedback",
            confidence="medium",
        )
        _record_feedback_apply(user_id, business_id)
        log_ai_event(
            "memory_feedback_applied",
            business_id=business_id,
            user_id=user_id,
            session_id=session.id,
            extra={"rating": rating, "message_id": message_id},
        )
        return True
    except Exception as exc:
        logger.warning("apply_feedback_to_memory failed: %s", exc)
        return False
