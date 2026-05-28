"""حافظهٔ دستیار AI per user + business."""
from __future__ import annotations

import logging
import re
from datetime import datetime
from typing import Any, Dict, List, Optional

from sqlalchemy.orm import Session

from adapters.db.models.ai_business_memory import AIBusinessMemory
from app.services.ai.ai_memory_structured import (
    extract_structured_from_text,
    merge_structured_patch,
    parse_structured,
    serialize_structured,
    structured_to_digest_sections,
    structured_to_prompt_block,
)
from app.services.ai.ai_ops_metrics import log_ai_event

logger = logging.getLogger(__name__)
MAX_MEMORY_CHARS = 4000
AUTO_SUMMARIZE_MIN_MESSAGES = 4
AUTO_SUMMARIZE_MAX_MESSAGES = 20
AUTO_SECTION_MARKER = "# به‌روزرسانی اخیر:"


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


def get_memory_structured(db: Session, business_id: int, user_id: int) -> Dict[str, Any]:
    row = get_memory(db, business_id, user_id)
    return parse_structured(row.structured if row else None)


def upsert_memory(
    db: Session,
    business_id: int,
    user_id: int,
    content: str,
    structured: Optional[Dict[str, Any]] = None,
) -> AIBusinessMemory:
    text = (content or "").strip()[:MAX_MEMORY_CHARS]
    row = get_memory(db, business_id, user_id)
    parsed_structured = merge_structured_patch(
        parse_structured(row.structured if row else None),
        structured,
    )
    if not structured and text:
        parsed_structured = merge_structured_patch(
            parsed_structured,
            extract_structured_from_text(text),
        )

    if row:
        row.content = text
        row.structured = serialize_structured(parsed_structured)
        row.updated_at = datetime.utcnow()
    else:
        row = AIBusinessMemory(
            business_id=business_id,
            user_id=user_id,
            content=text,
            structured=serialize_structured(parsed_structured),
        )
        db.add(row)
    db.commit()
    db.refresh(row)
    return row


def upsert_structured_only(
    db: Session,
    business_id: int,
    user_id: int,
    structured_patch: Dict[str, Any],
) -> AIBusinessMemory:
    row = get_memory(db, business_id, user_id)
    merged = merge_structured_patch(
        parse_structured(row.structured if row else None),
        structured_patch,
    )
    if row:
        row.structured = serialize_structured(merged)
        row.updated_at = datetime.utcnow()
    else:
        row = AIBusinessMemory(
            business_id=business_id,
            user_id=user_id,
            content="",
            structured=serialize_structured(merged),
        )
        db.add(row)
    db.commit()
    db.refresh(row)
    return row


def clear_memory(db: Session, business_id: int, user_id: int) -> None:
    row = get_memory(db, business_id, user_id)
    if row:
        db.delete(row)
        db.commit()
    log_ai_event("memory_cleared", business_id=business_id, user_id=user_id)


def memory_to_dict(row: Optional[AIBusinessMemory]) -> Dict[str, Any]:
    if not row:
        return {
            "content": "",
            "structured": parse_structured(None),
            "updated_at": None,
            "char_count": 0,
            "max_chars": MAX_MEMORY_CHARS,
            "has_auto_sections": False,
        }
    content = row.content or ""
    return {
        "content": content,
        "structured": parse_structured(row.structured),
        "updated_at": row.updated_at.isoformat() if row.updated_at else None,
        "char_count": len(content),
        "max_chars": MAX_MEMORY_CHARS,
        "has_auto_sections": AUTO_SECTION_MARKER in content
        or "# ترجیحات کاربر (خودکار):" in content,
    }


def get_memory_digest(
    db: Session,
    business_id: int,
    user_id: int,
) -> Dict[str, Any]:
    row = get_memory(db, business_id, user_id)
    content = row.content if row else ""
    structured = parse_structured(row.structured if row else None)
    digest = structured_to_digest_sections(structured, content)
    digest["updated_at"] = row.updated_at.isoformat() if row and row.updated_at else None
    return digest


def format_memory_goal_hint_for_insights(
    db: Session,
    business_id: int,
    user_id: int,
    insights: Dict[str, Any],
) -> str:
    """یک خط راهنما برای مقایسه هدف حافظه با KPI واقعی."""
    structured = get_memory_structured(db, business_id, user_id)
    goal = structured.get("sales_goal_monthly")
    if not goal or goal <= 0:
        return ""

    kpis = insights.get("kpis") or {}
    sales_week = kpis.get("sales_last_7_days") or {}
    estimate_month = float(sales_week.get("total_net") or 0) * 4.33
    if estimate_month <= 0:
        return ""

    pct = round((estimate_month / float(goal)) * 100, 1)
    return (
        f"\nهدف فروش ماهانه (از حافظه): {float(goal):,.0f} — "
        f"برآورد فعلی از فروش ۷ روز: ~{estimate_month:,.0f} ({pct}٪ از هدف)."
    )


def format_memory_for_prompt(db: Session, business_id: int, user_id: int) -> str:
    row = get_memory(db, business_id, user_id)
    if not row:
        return ""

    parts: List[str] = []
    structured_block = structured_to_prompt_block(parse_structured(row.structured))
    if structured_block:
        parts.append(structured_block)

    content = (row.content or "").strip()[:MAX_MEMORY_CHARS]
    if content:
        parts.append(content)

    if not parts:
        return ""

    body = "\n".join(parts)
    return (
        "\n\n--- حافظهٔ ترجیحات کاربر (رعایت کن مگر خلاف دستور صریح باشد) ---\n"
        "حقایق پایدار از این بخش؛ اسناد طولانی در knowledge؛ دادهٔ لحظه‌ای با ابزار.\n"
        f"{body}"
    )


def extract_facts_from_messages(messages: List[Dict[str, Any]]) -> List[str]:
    """استخراج واقعیت‌های کلیدی از مکالمه برای ذخیره در حافظه."""
    facts: List[str] = []
    seen: set[str] = set()

    preference_patterns = [
        r"ترجیح\s*می‌?دم|prefer|دوست\s*دارم|همیشه|معمولاً|اکثراً",
        r"نشان\s*بده|نمایش\s*بده|بگو|بنویس|خلاصه\s*کن",
        r"زبان\s*(فارسی|انگلیسی)|به\s*صورت\s*(جدولی|لیستی|خلاصه)",
        r"هدف\s*فروش|هدف\s*ماه|میلیون|میلیارد|تومان|ریال",
        r"به\s*خاطر\s*بسپار|یادت\s*باشه|فراموش\s*نکن|remember",
        r"اصطلاح|معنی\s*می‌?دهد|منظورم",
    ]

    for msg in messages:
        if msg.get("role") != "user":
            continue
        content = (msg.get("content") or "").strip()
        if len(content) < 10:
            continue

        matched = False
        for pattern in preference_patterns:
            if re.search(pattern, content, re.IGNORECASE):
                matched = True
                break
        if not matched:
            continue

        snippet = content.replace("\n", " ").strip()[:220]
        key = snippet[:60].lower()
        if key in seen:
            continue
        seen.add(key)
        facts.append(snippet)
        if len(facts) >= 5:
            break

    return facts


def merge_memory_content(current_memory: str, facts: List[str]) -> str:
    new_facts = facts
    if current_memory:
        new_facts = [f for f in facts if f[:50] not in current_memory]
        if not new_facts:
            return current_memory
        new_facts_text = "\n".join(f"- {f}" for f in new_facts)
        updated = f"{current_memory}\n\n{AUTO_SECTION_MARKER}\n{new_facts_text}"
    else:
        new_facts_text = "\n".join(f"- {f}" for f in facts)
        updated = f"# ترجیحات کاربر (خودکار):\n{new_facts_text}"

    if len(updated) > MAX_MEMORY_CHARS:
        updated = updated[-MAX_MEMORY_CHARS:]
    return updated


async def auto_summarize_session(
    db: Session,
    business_id: int,
    user_id: int,
    session_messages: List[Dict[str, Any]],
    ai_service=None,
) -> bool:
    """
    خلاصه‌سازی خودکار مکالمه و ادغام با حافظه کاربر.
    ai_service نادیده گرفته می‌شود (سازگاری با امضای قبلی).
    """
    if len(session_messages) < AUTO_SUMMARIZE_MIN_MESSAGES:
        return False

    user_msgs = [m for m in session_messages if m.get("role") == "user"]
    facts = extract_facts_from_messages(user_msgs[-AUTO_SUMMARIZE_MAX_MESSAGES:])
    if not facts:
        return False

    row = get_memory(db, business_id, user_id)
    current_memory = row.content if row else ""
    updated = merge_memory_content(current_memory or "", facts)
    if updated == current_memory:
        return False

    try:
        upsert_memory(
            db,
            business_id,
            user_id,
            updated,
            structured=extract_structured_from_text("\n".join(facts)),
        )
        log_ai_event(
            "memory_auto_summarized",
            business_id=business_id,
            user_id=user_id,
            extra={"facts": len(facts)},
        )
        return True
    except Exception as exc:
        logger.warning("AI memory auto-summarize failed: %s", exc)
        return False


async def maybe_auto_summarize_session(
    db: Session,
    business_id: int,
    user_id: int,
    session_messages: List[Dict[str, Any]],
) -> bool:
    return await auto_summarize_session(db, business_id, user_id, session_messages)


def append_to_memory(
    db: Session,
    business_id: int,
    user_id: int,
    note: str,
    *,
    section_title: str = "یادداشت دستیار",
) -> AIBusinessMemory:
    """افزودن متن به حافظه (برای ابزار update_user_memory)."""
    note = (note or "").strip()
    if not note:
        raise ValueError("متن حافظه خالی است")
    row = get_memory(db, business_id, user_id)
    current = row.content if row else ""
    block = f"\n\n# {section_title}:\n- {note[:500]}"
    merged = (current + block).strip()[:MAX_MEMORY_CHARS]
    return upsert_memory(db, business_id, user_id, merged)
