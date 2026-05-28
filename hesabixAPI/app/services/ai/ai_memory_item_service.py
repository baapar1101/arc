"""سرویس آیتم‌های حافظه AI (v2)."""
from __future__ import annotations

import json
import re
from datetime import datetime
from typing import Any, Dict, List, Optional

from sqlalchemy.orm import Session

from adapters.db.models.ai_memory_item import AIMemoryItem
from app.services.ai.ai_constants import (
    MAX_MEMORY_ITEM_CONTENT_CHARS,
    MAX_MEMORY_ITEMS_PER_USER,
)

_SLUG_RE = re.compile(r"[^a-z0-9_\u0600-\u06ff]+", re.IGNORECASE)
ALLOWED_CATEGORIES = frozenset({"fact", "term", "preference", "goal", "hint"})


def slugify_key(raw: str) -> str:
    text = (raw or "").strip().lower()[:80]
    text = _SLUG_RE.sub("_", text).strip("_")
    return text or f"item_{int(datetime.utcnow().timestamp())}"


def list_memory_items(
    db: Session,
    business_id: int,
    user_id: int,
    *,
    category: Optional[str] = None,
    include_deleted: bool = False,
    limit: int = 50,
) -> List[AIMemoryItem]:
    q = db.query(AIMemoryItem).filter(
        AIMemoryItem.business_id == business_id,
        AIMemoryItem.user_id == user_id,
    )
    if not include_deleted:
        q = q.filter(AIMemoryItem.deleted_at.is_(None))
    if category:
        q = q.filter(AIMemoryItem.category == category.strip().lower())
    return q.order_by(AIMemoryItem.updated_at.desc()).limit(min(limit, 100)).all()


def count_active_items(db: Session, business_id: int, user_id: int) -> int:
    return (
        db.query(AIMemoryItem)
        .filter(
            AIMemoryItem.business_id == business_id,
            AIMemoryItem.user_id == user_id,
            AIMemoryItem.deleted_at.is_(None),
        )
        .count()
    )


def get_memory_item_by_key(
    db: Session,
    business_id: int,
    user_id: int,
    item_key: str,
) -> Optional[AIMemoryItem]:
    return (
        db.query(AIMemoryItem)
        .filter(
            AIMemoryItem.business_id == business_id,
            AIMemoryItem.user_id == user_id,
            AIMemoryItem.item_key == item_key,
            AIMemoryItem.deleted_at.is_(None),
        )
        .first()
    )


def upsert_memory_item(
    db: Session,
    business_id: int,
    user_id: int,
    *,
    item_key: Optional[str] = None,
    category: str = "fact",
    content: str,
    structured: Optional[Dict[str, Any]] = None,
    source: str = "assistant",
    confidence: Optional[str] = None,
) -> AIMemoryItem:
    cat = (category or "fact").strip().lower()
    if cat not in ALLOWED_CATEGORIES:
        cat = "fact"
    key = slugify_key(item_key or content[:40])
    text = (content or "").strip()[:MAX_MEMORY_ITEM_CONTENT_CHARS]
    struct_text = json.dumps(structured, ensure_ascii=False) if structured else None

    row = get_memory_item_by_key(db, business_id, user_id, key)
    if row:
        row.content = text
        row.category = cat
        row.structured = struct_text
        row.source = source
        row.confidence = confidence
        row.updated_at = datetime.utcnow()
    else:
        active = count_active_items(db, business_id, user_id)
        if active >= MAX_MEMORY_ITEMS_PER_USER:
            raise ValueError(
                f"حداکثر {MAX_MEMORY_ITEMS_PER_USER} آیتم حافظه مجاز است. "
                "ابتدا آیتم‌های قدیمی را حذف کنید."
            )
        row = AIMemoryItem(
            business_id=business_id,
            user_id=user_id,
            item_key=key,
            category=cat,
            content=text,
            structured=struct_text,
            source=source,
            confidence=confidence,
        )
        db.add(row)
    db.commit()
    db.refresh(row)
    return row


def soft_delete_memory_item(
    db: Session,
    business_id: int,
    user_id: int,
    *,
    item_id: Optional[int] = None,
    item_key: Optional[str] = None,
) -> bool:
    q = db.query(AIMemoryItem).filter(
        AIMemoryItem.business_id == business_id,
        AIMemoryItem.user_id == user_id,
        AIMemoryItem.deleted_at.is_(None),
    )
    if item_id is not None:
        q = q.filter(AIMemoryItem.id == item_id)
    elif item_key:
        q = q.filter(AIMemoryItem.item_key == slugify_key(item_key))
    else:
        return False
    row = q.first()
    if not row:
        return False
    row.deleted_at = datetime.utcnow()
    db.commit()
    return True


def memory_item_to_dict(row: AIMemoryItem) -> Dict[str, Any]:
    structured = None
    if row.structured:
        try:
            structured = json.loads(row.structured)
        except json.JSONDecodeError:
            structured = None
    return {
        "id": row.id,
        "item_key": row.item_key,
        "category": row.category,
        "content": row.content,
        "structured": structured,
        "source": row.source,
        "confidence": row.confidence,
        "created_at": row.created_at.isoformat() if row.created_at else None,
        "updated_at": row.updated_at.isoformat() if row.updated_at else None,
    }


def format_memory_items_for_prompt(
    db: Session,
    business_id: int,
    user_id: int,
    *,
    limit: int = 24,
) -> str:
    """خلاصهٔ آیتم‌های فعال برای system prompt."""
    items = list_memory_items(db, business_id, user_id, limit=limit)
    if not items:
        return ""
    lines = ["### حافظهٔ ترجیحات و حقایق (آیتم‌ها)"]
    for item in items:
        lines.append(f"- [{item.category}] **{item.item_key}**: {item.content[:300]}")
    return "\n".join(lines)
