"""حافظهٔ دستیار AI per user + business."""
from __future__ import annotations

from datetime import datetime
from typing import Any, Dict, Optional

from sqlalchemy.orm import Session

from adapters.db.models.ai_business_memory import AIBusinessMemory
from app.core.auth_dependency import AuthContext

MAX_MEMORY_CHARS = 4000


def get_memory(db: Session, business_id: int, user_id: int) -> Optional[AIBusinessMemory]:
    return (
        db.query(AIBusinessMemory)
        .filter(
            AIBusinessMemory.business_id == business_id,
            AIBusinessMemory.user_id == user_id,
        )
        .first()
    )


def get_memory_content(db: Session, business_id: int, user_id: int) -> str:
    row = get_memory(db, business_id, user_id)
    if not row or not row.content:
        return ""
    return row.content.strip()[:MAX_MEMORY_CHARS]


def upsert_memory(
    db: Session,
    business_id: int,
    user_id: int,
    content: str,
) -> AIBusinessMemory:
    text = (content or "").strip()[:MAX_MEMORY_CHARS]
    row = get_memory(db, business_id, user_id)
    if row:
        row.content = text
        row.updated_at = datetime.utcnow()
    else:
        row = AIBusinessMemory(
            business_id=business_id,
            user_id=user_id,
            content=text,
        )
        db.add(row)
    db.commit()
    db.refresh(row)
    return row


def memory_to_dict(row: Optional[AIBusinessMemory]) -> Dict[str, Any]:
    if not row:
        return {"content": "", "updated_at": None}
    return {
        "content": row.content,
        "updated_at": row.updated_at.isoformat() if row.updated_at else None,
    }


def format_memory_for_prompt(db: Session, business_id: int, user_id: int) -> str:
    content = get_memory_content(db, business_id, user_id)
    if not content:
        return ""
    return (
        "\n\n--- حافظهٔ ترجیحات کاربر (رعایت کن مگر خلاف دستور صریح باشد) ---\n"
        f"{content}"
    )
