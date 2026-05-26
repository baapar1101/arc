"""حافظهٔ دستیار AI per user + business.

ویژگی‌های جدید:
  - auto_summarize_session: خلاصه‌سازی خودکار مکالمه و ادغام با حافظه
  - extract_facts_from_messages: استخراج واقعیت‌های مهم از مکالمه
"""
from __future__ import annotations

import logging
from datetime import datetime
from typing import Any, Dict, List, Optional

from sqlalchemy.orm import Session

from adapters.db.models.ai_business_memory import AIBusinessMemory
from app.core.auth_dependency import AuthContext

logger = logging.getLogger(__name__)
MAX_MEMORY_CHARS = 4000
AUTO_SUMMARIZE_MIN_MESSAGES = 4   # حداقل پیام برای شروع خلاصه‌سازی
AUTO_SUMMARIZE_MAX_MESSAGES = 20  # حداکثر پیامی که پردازش می‌شود


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


def extract_facts_from_messages(messages: List[Dict[str, Any]]) -> List[str]:
    """استخراج واقعیت‌های کلیدی از مکالمه برای ذخیره در حافظه."""
    import re

    facts: List[str] = []
    for msg in messages:
        if msg.get("role") != "user":
            continue
        content = (msg.get("content") or "").strip()
        if len(content) < 10:
            continue

        # الگوهای بیانگر ترجیح یا اطلاعات شخصی
        preference_patterns = [
            r"ترجیح\s*می‌?دم|prefer|دوست\s*دارم|همیشه|معمولاً|اکثراً",
            r"نشان\s*بده|نمایش\s*بده|بگو|بنویس|خلاصه\s*کن",
            r"زبان\s*(فارسی|انگلیسی)|به\s*صورت\s*(جدولی|لیستی|خلاصه)",
        ]
        for pattern in preference_patterns:
            if re.search(pattern, content, re.IGNORECASE):
                if len(content) < 200:
                    facts.append(content[:200])
                    break

    return facts[:5]


async def auto_summarize_session(
    db: Session,
    business_id: int,
    user_id: int,
    session_messages: List[Dict[str, Any]],
    ai_service=None,
) -> bool:
    """
    خلاصه‌سازی خودکار مکالمه و ادغام با حافظه کاربر.
    بهترین زمان فراخوانی: پایان session یا هر N پیام.

    Returns True اگر حافظه به‌روز شد.
    """
    if len(session_messages) < AUTO_SUMMARIZE_MIN_MESSAGES:
        return False

    # استخراج واقعیت‌ها از پیام‌های کاربر
    user_msgs = [m for m in session_messages if m.get("role") == "user"]
    facts = extract_facts_from_messages(user_msgs[-AUTO_SUMMARIZE_MAX_MESSAGES:])

    if not facts:
        return False

    current_memory = get_memory_content(db, business_id, user_id)

    # ترکیب حافظه فعلی + واقعیت‌های جدید
    new_facts_text = "\n".join(f"- {f}" for f in facts)
    if current_memory:
        # جلوگیری از تکرار
        new_facts = [f for f in facts if f[:50] not in current_memory]
        if not new_facts:
            return False
        new_facts_text = "\n".join(f"- {f}" for f in new_facts)
        updated = f"{current_memory}\n\n# به‌روزرسانی اخیر:\n{new_facts_text}"
    else:
        updated = f"# ترجیحات کاربر (خودکار):\n{new_facts_text}"

    if len(updated) > MAX_MEMORY_CHARS:
        updated = updated[-MAX_MEMORY_CHARS:]

    try:
        upsert_memory(db, business_id, user_id, updated)
        logger.info(
            "AI memory auto-summarized: business=%s user=%s facts=%d",
            business_id,
            user_id,
            len(facts),
        )
        return True
    except Exception as exc:
        logger.warning("AI memory auto-summarize failed: %s", exc)
        return False
