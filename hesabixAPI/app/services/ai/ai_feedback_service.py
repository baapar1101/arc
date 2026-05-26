"""بازخورد کاربر روی پیام‌های دستیار."""
from __future__ import annotations

from datetime import datetime
from typing import Any, Dict, Optional

from sqlalchemy.orm import Session

from adapters.db.models.ai_chat_message import AIChatMessage
from adapters.db.models.ai_chat_session import AIChatSession
from adapters.db.models.ai_message_feedback import AIMessageFeedback
from app.core.responses import ApiError


def upsert_feedback(
    db: Session,
    message_id: int,
    user_id: int,
    rating: int,
    comment: Optional[str] = None,
) -> AIMessageFeedback:
    if rating not in (-1, 1):
        raise ApiError("INVALID_RATING", "امتیاز باید ۱ یا ‎-۱ باشد", http_status=400)

    msg = db.query(AIChatMessage).filter(AIChatMessage.id == message_id).first()
    if not msg:
        raise ApiError("MESSAGE_NOT_FOUND", "پیام یافت نشد", http_status=404)

    session = db.query(AIChatSession).filter(AIChatSession.id == msg.session_id).first()
    if not session or session.user_id != user_id:
        raise ApiError("FORBIDDEN", "دسترسی به این پیام مجاز نیست", http_status=403)

    row = (
        db.query(AIMessageFeedback)
        .filter(
            AIMessageFeedback.message_id == message_id,
            AIMessageFeedback.user_id == user_id,
        )
        .first()
    )
    if row:
        row.rating = rating
        row.comment = (comment or "").strip() or None
    else:
        row = AIMessageFeedback(
            message_id=message_id,
            user_id=user_id,
            rating=rating,
            comment=(comment or "").strip() or None,
        )
        db.add(row)
    db.commit()
    db.refresh(row)
    return row


def feedback_to_dict(row: AIMessageFeedback) -> Dict[str, Any]:
    return {
        "id": row.id,
        "message_id": row.message_id,
        "rating": row.rating,
        "comment": row.comment,
        "created_at": row.created_at.isoformat() if row.created_at else None,
    }


def get_feedback_summary_for_messages(
    db: Session,
    message_ids: list[int],
    user_id: int,
) -> Dict[int, int]:
    if not message_ids:
        return {}
    rows = (
        db.query(AIMessageFeedback)
        .filter(
            AIMessageFeedback.message_id.in_(message_ids),
            AIMessageFeedback.user_id == user_id,
        )
        .all()
    )
    return {r.message_id: r.rating for r in rows}
