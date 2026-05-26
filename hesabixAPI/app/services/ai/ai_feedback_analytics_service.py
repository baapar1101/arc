"""
تحلیل بازخورد کاربران روی پاسخ‌های دستیار.
"""
from __future__ import annotations

from datetime import datetime, timedelta
from typing import Any, Dict, List, Optional

from sqlalchemy import case, func
from sqlalchemy.orm import Session

from adapters.db.models.ai_chat_message import AIChatMessage
from adapters.db.models.ai_chat_session import AIChatSession
from adapters.db.models.ai_message_feedback import AIMessageFeedback


def get_feedback_analytics(
    db: Session,
    *,
    business_id: Optional[int] = None,
    days: int = 30,
    limit_recent: int = 20,
) -> Dict[str, Any]:
    since = datetime.utcnow() - timedelta(days=max(1, min(days, 365)))

    q = (
        db.query(AIMessageFeedback)
        .join(AIChatMessage, AIChatMessage.id == AIMessageFeedback.message_id)
        .join(AIChatSession, AIChatSession.id == AIChatMessage.session_id)
        .filter(AIMessageFeedback.created_at >= since)
    )
    if business_id is not None:
        q = q.filter(AIChatSession.business_id == business_id)

    rows = q.all()
    positive = sum(1 for r in rows if r.rating > 0)
    negative = sum(1 for r in rows if r.rating < 0)
    total = len(rows)
    pass_rate = round((positive / total) * 100, 1) if total else None

    daily_q = (
        db.query(
            func.date(AIMessageFeedback.created_at).label("day"),
            func.sum(case((AIMessageFeedback.rating > 0, 1), else_=0)).label("up"),
            func.sum(case((AIMessageFeedback.rating < 0, 1), else_=0)).label("down"),
        )
        .join(AIChatMessage, AIChatMessage.id == AIMessageFeedback.message_id)
        .join(AIChatSession, AIChatSession.id == AIChatMessage.session_id)
        .filter(AIMessageFeedback.created_at >= since)
    )
    if business_id is not None:
        daily_q = daily_q.filter(AIChatSession.business_id == business_id)
    daily_rows = daily_q.group_by(func.date(AIMessageFeedback.created_at)).order_by("day").all()

    daily_series = [
        {
            "date": str(d.day),
            "positive": int(d.up or 0),
            "negative": int(d.down or 0),
        }
        for d in daily_rows
    ]

    recent_negative: List[Dict[str, Any]] = []
    neg_rows = sorted(
        [r for r in rows if r.rating < 0],
        key=lambda x: x.created_at or datetime.min,
        reverse=True,
    )[:limit_recent]
    for fb in neg_rows:
        msg = db.query(AIChatMessage).filter(AIChatMessage.id == fb.message_id).first()
        if not msg:
            continue
        recent_negative.append(
            {
                "message_id": fb.message_id,
                "rating": fb.rating,
                "comment": fb.comment,
                "created_at": fb.created_at.isoformat() if fb.created_at else None,
                "content_preview": (msg.content or "")[:400],
                "session_id": msg.session_id,
            }
        )

    return {
        "period_days": days,
        "business_id": business_id,
        "summary": {
            "total": total,
            "positive": positive,
            "negative": negative,
            "satisfaction_rate_percent": pass_rate,
        },
        "daily": daily_series,
        "recent_negative": recent_negative,
    }
