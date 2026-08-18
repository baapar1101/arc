"""سرویس آیتم‌های حافظه AI (v2) — کلید پایدار + kind یکپارچه."""
from __future__ import annotations

import json
from datetime import datetime
from typing import Any, Dict, List, Optional

from sqlalchemy.orm import Session

from adapters.db.models.ai_memory_item import AIMemoryItem
from app.services.ai.ai_constants import (
    MAX_MEMORY_ITEM_CONTENT_CHARS,
    MAX_MEMORY_ITEMS_PER_USER,
    MEMORY_KINDS,
)
from app.services.ai.ai_memory_keys import (
    canonical_kind,
    normalize_memory_key,
    slugify_legacy_key,
)

ALLOWED_CATEGORIES = MEMORY_KINDS | frozenset({"fact", "term", "hint"})


def slugify_key(raw: str) -> str:
    """سازگاری با کد قدیمی — ترجیح با normalize_memory_key."""
    return slugify_legacy_key(raw)


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
        wanted = canonical_kind(category)
        aliases = [wanted]
        if wanted == "context":
            aliases.extend(["fact", "term"])
        elif wanted == "constraint":
            aliases.append("hint")
        q = q.filter(AIMemoryItem.category.in_(aliases))
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
    *,
    include_deleted: bool = False,
) -> Optional[AIMemoryItem]:
    q = db.query(AIMemoryItem).filter(
        AIMemoryItem.business_id == business_id,
        AIMemoryItem.user_id == user_id,
        AIMemoryItem.item_key == item_key,
    )
    if not include_deleted:
        q = q.filter(AIMemoryItem.deleted_at.is_(None))
    return q.first()


def upsert_memory_item(
    db: Session,
    business_id: int,
    user_id: int,
    *,
    item_key: Optional[str] = None,
    category: str = "context",
    content: str,
    structured: Optional[Dict[str, Any]] = None,
    source: str = "assistant",
    confidence: Optional[str] = None,
) -> AIMemoryItem:
    cat = canonical_kind(category)
    key = normalize_memory_key(item_key, kind=cat, content=content or "")
    text = (content or "").strip()[:MAX_MEMORY_ITEM_CONTENT_CHARS]
    struct_text = json.dumps(structured, ensure_ascii=False) if structured else None

    row = get_memory_item_by_key(
        db, business_id, user_id, key, include_deleted=True
    )
    if row:
        row.content = text
        row.category = cat
        row.structured = struct_text
        row.source = source
        row.confidence = confidence
        row.deleted_at = None
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


def clear_all_memory_items(db: Session, business_id: int, user_id: int) -> int:
    """حذف نرم همهٔ آیتم‌های فعال."""
    rows = list_memory_items(db, business_id, user_id, limit=MAX_MEMORY_ITEMS_PER_USER)
    now = datetime.utcnow()
    for row in rows:
        row.deleted_at = now
    if rows:
        db.commit()
    return len(rows)


def update_memory_item_content(
    db: Session,
    business_id: int,
    user_id: int,
    item_id: int,
    content: str,
) -> Optional[AIMemoryItem]:
    text = (content or "").strip()[:MAX_MEMORY_ITEM_CONTENT_CHARS]
    if not text:
        raise ValueError("متن حافظه خالی است")
    row = (
        db.query(AIMemoryItem)
        .filter(
            AIMemoryItem.id == item_id,
            AIMemoryItem.business_id == business_id,
            AIMemoryItem.user_id == user_id,
            AIMemoryItem.deleted_at.is_(None),
        )
        .first()
    )
    if not row:
        return None
    row.content = text
    row.source = "user"
    row.updated_at = datetime.utcnow()
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
        key = normalize_memory_key(item_key, content=item_key)
        q = q.filter(AIMemoryItem.item_key == key)
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
    kind = canonical_kind(row.category)
    return {
        "id": row.id,
        "item_key": row.item_key,
        "category": kind,
        "kind": kind,
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
    """سازگاری عقب‌رو — مسیر اصلی compile_memory_prompt است."""
    from app.services.ai.ai_memory_compiler import compile_memory_prompt

    items = [
        memory_item_to_dict(r)
        for r in list_memory_items(db, business_id, user_id, limit=limit)
    ]
    return compile_memory_prompt(items=items)
