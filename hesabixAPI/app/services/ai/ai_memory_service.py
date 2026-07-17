"""حافظهٔ دو لایهٔ دستیار AI: دستورات کاربر + یادگیری بی‌صدا."""
from __future__ import annotations

import logging
import re
from datetime import datetime
from typing import Any, Dict, List, Optional

from sqlalchemy.orm import Session

from adapters.db.models.ai_business_memory import AIBusinessMemory
from app.services.ai.ai_ops_metrics import log_ai_event

logger = logging.getLogger(__name__)

MAX_MEMORY_CHARS = 4000
AUTO_SUMMARIZE_MIN_MESSAGES = 4
AUTO_SUMMARIZE_MAX_MESSAGES = 20
AUTO_SECTION_MARKER = "# به‌روزرسانی اخیر:"
LEGACY_AUTO_MARKER = "# ترجیحات کاربر (خودکار):"
_AUTO_MARKERS = (AUTO_SECTION_MARKER, LEGACY_AUTO_MARKER)


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
    """دستورات همیشگی کاربر (بدون بخش‌های یادگیری خودکار قدیمی)."""
    row = get_memory(db, business_id, user_id)
    if not row or not row.content:
        return ""
    return strip_auto_sections(row.content).strip()[:MAX_MEMORY_CHARS]


def strip_auto_sections(content: str) -> str:
    """حذف بلوک‌های یادگیری خودکار قدیمی از متن دستورات."""
    text = content or ""
    for marker in _AUTO_MARKERS:
        idx = text.find(marker)
        if idx >= 0:
            text = text[:idx]
    # بخش‌های با عنوان قدیمی دستیار که از فیدبک آمده‌اند هم در دستورات نمانند
    text = re.sub(
        r"\n\n# (ترجیحات تأییدشده|بازخورد منفی|یادداشت دستیار):.*",
        "",
        text,
        flags=re.DOTALL,
    )
    return text.strip()


def upsert_memory(
    db: Session,
    business_id: int,
    user_id: int,
    content: str,
    structured: Optional[Dict[str, Any]] = None,  # noqa: ARG001 — سازگاری عقب‌رو
) -> AIBusinessMemory:
    """ذخیرهٔ فقط دستورات همیشگی کاربر. structured نادیده گرفته می‌شود."""
    text = strip_auto_sections(content or "").strip()[:MAX_MEMORY_CHARS]
    row = get_memory(db, business_id, user_id)
    if row:
        row.content = text
        row.structured = None
        row.updated_at = datetime.utcnow()
    else:
        row = AIBusinessMemory(
            business_id=business_id,
            user_id=user_id,
            content=text,
            structured=None,
        )
        db.add(row)
    db.commit()
    db.refresh(row)
    return row


def clear_memory(db: Session, business_id: int, user_id: int) -> None:
    """پاک کردن دستورات + همهٔ آیتم‌های یادگرفته‌شده."""
    row = get_memory(db, business_id, user_id)
    if row:
        db.delete(row)
        db.commit()
    try:
        from app.services.ai.ai_memory_item_service import clear_all_memory_items

        clear_all_memory_items(db, business_id, user_id)
    except Exception as exc:
        logger.warning("clear memory items failed: %s", exc)
    log_ai_event("memory_cleared", business_id=business_id, user_id=user_id)


def memory_to_dict(
    row: Optional[AIBusinessMemory],
    *,
    items: Optional[List[Dict[str, Any]]] = None,
) -> Dict[str, Any]:
    instructions = strip_auto_sections(row.content) if row else ""
    return {
        "instructions": instructions,
        "content": instructions,  # سازگاری با کلاینت‌های قدیمی
        "items": items or [],
        "structured": {},  # فیلد ساخت‌یافته حذف شد
        "updated_at": row.updated_at.isoformat() if row and row.updated_at else None,
        "char_count": len(instructions),
        "max_chars": MAX_MEMORY_CHARS,
        "has_auto_sections": False,
        "learned_count": len(items or []),
    }


def get_memory_payload(db: Session, business_id: int, user_id: int) -> Dict[str, Any]:
    from app.services.ai.ai_memory_item_service import list_memory_items, memory_item_to_dict

    row = get_memory(db, business_id, user_id)
    items = [
        memory_item_to_dict(r)
        for r in list_memory_items(db, business_id, user_id, limit=100)
    ]
    return memory_to_dict(row, items=items)


def get_memory_digest(db: Session, business_id: int, user_id: int) -> Dict[str, Any]:
    """خلاصهٔ خواندنی — سازگاری با API قدیمی."""
    payload = get_memory_payload(db, business_id, user_id)
    sections: List[Dict[str, str]] = []
    if payload["instructions"]:
        preview = payload["instructions"]
        if len(preview) > 800:
            preview = preview[:800] + "…"
        sections.append({"title": "دستورات همیشگی", "body": preview})
    if payload["items"]:
        lines = [f"• {it.get('content', '')}" for it in payload["items"][:12]]
        sections.append({"title": "آنچه یاد گرفته‌ام", "body": "\n".join(lines)})
    return {
        "sections": sections,
        "is_empty": not sections,
        "updated_at": payload.get("updated_at"),
        "items": payload["items"],
        "instructions": payload["instructions"],
    }


def format_memory_for_prompt(db: Session, business_id: int, user_id: int) -> str:
    parts: List[str] = []

    instructions = get_memory_content(db, business_id, user_id)
    if instructions:
        parts.append("### دستورات همیشگی کاربر (الزامی مگر خلاف صریح بگوید)\n" + instructions)

    try:
        from app.services.ai.ai_memory_item_service import format_memory_items_for_prompt

        items_block = format_memory_items_for_prompt(db, business_id, user_id)
        if items_block:
            parts.append(items_block)
    except Exception:
        pass

    if not parts:
        return ""

    body = "\n\n".join(parts)
    return (
        "\n\n--- حافظهٔ بلندمدت کاربر ---\n"
        "دستورات همیشگی را رعایت کن. حقایق یادگرفته‌شده زمینهٔ پایدارند؛ "
        "اسناد بلند در knowledge و دادهٔ لحظه‌ای با ابزار.\n"
        "برای افزودن/ویرایش حقایق یادگرفته‌شده از upsert_memory_item / "
        "list_memory_items / delete_memory_item استفاده کن "
        "(بدون پرسیدن از کاربر — یادگیری بی‌صدا).\n"
        f"{body}"
    )


def format_memory_goal_hint_for_insights(
    db: Session,
    business_id: int,
    user_id: int,
    insights: Dict[str, Any],
) -> str:
    """سازگاری عقب‌رو — هدف ساخت‌یافته حذف شد."""
    return ""


# ---- استخراج و یادگیری بی‌صدا -------------------------------------------------

_PREFERENCE_RE = re.compile(
    r"ترجیح\s*می‌?دم|prefer|دوست\s*دارم|همیشه|معمولاً|اکثراً|"
    r"به\s*خاطر\s*بسپار|یادت\s*باشه|فراموش\s*نکن|remember|"
    r"اسم\s*(?:کسب\s*و\s*کار|شرکت|فروشگاه|پروژه)|"
    r"روی\s*پروژه|کار\s*می‌?کنم\s*روی|"
    r"هدف\s*فروش|هدف\s*ماه|اصطلاح|معنی\s*می‌?دهد",
    re.IGNORECASE,
)

_EXPLICIT_REMEMBER = re.compile(
    r"(?:به\s*خاطر\s*بسپار|یادت\s*باشه|فراموش\s*نکن|remember(?:\s+that)?)\s*[:：]?\s*(.+)",
    re.IGNORECASE | re.DOTALL,
)

_NAMED_ENTITY = re.compile(
    r"(?:اسم\s*(?:کسب\s*و\s*کار|شرکت|فروشگاه|برند)|نام\s*پروژه|پروژه(?:‌ام|م)?)\s*"
    r"[:：]?\s*[«\"']?([^«\"'\n،.]{2,80})[»\"']?",
    re.IGNORECASE,
)

_GOAL_RE = re.compile(
    r"هدف\s*(?:فروش)?\s*(?:ماه(?:انه)?)?\s*[:：]?\s*([\d،,\.]+)\s*(میلیون|میلیارد|هزار)?",
    re.IGNORECASE,
)

_TERM_RE = re.compile(
    r"(?:اصطلاح|منظور(?:م)?\s*از)\s*[«\"']?([^«\"'\n]{2,40})[»\"']?\s*"
    r"(?:یعنی|معنی(?:‌اش|ش)?|:=?\s*)\s*[«\"']?([^«\"'\n]{2,120})",
    re.IGNORECASE,
)


def _normalize_fact_text(text: str) -> str:
    return re.sub(r"\s+", " ", (text or "").strip())[:220]


def _fact_key(category: str, content: str) -> str:
    from app.services.ai.ai_memory_item_service import slugify_key

    base = content[:48] if content else category
    return slugify_key(f"{category}_{base}")


def extract_learned_candidates(messages: List[Dict[str, Any]]) -> List[Dict[str, str]]:
    """استخراج کاندیدهای حافظهٔ یادگرفته‌شده از پیام‌های کاربر."""
    candidates: List[Dict[str, str]] = []
    seen: set[str] = set()

    def _add(category: str, content: str, confidence: str = "medium") -> None:
        text = _normalize_fact_text(content)
        if len(text) < 8:
            return
        key = _fact_key(category, text)
        dedupe = text[:60].lower()
        if dedupe in seen:
            return
        seen.add(dedupe)
        candidates.append(
            {
                "item_key": key,
                "category": category,
                "content": text,
                "confidence": confidence,
            }
        )

    for msg in messages:
        if msg.get("role") != "user":
            continue
        content = (msg.get("content") or "").strip()
        if len(content) < 10:
            continue

        m = _EXPLICIT_REMEMBER.search(content)
        if m:
            _add("fact", m.group(1).strip(), "high")
            continue

        for em in _NAMED_ENTITY.finditer(content):
            name = em.group(1).strip()
            label = "نام کسب‌وکار/پروژه"
            _add("fact", f"{label}: {name}", "high")

        gm = _GOAL_RE.search(content)
        if gm:
            num_raw = gm.group(1).replace("،", "").replace(",", "")
            try:
                val = float(num_raw)
                mult = gm.group(2) or ""
                if "میلیارد" in mult:
                    val *= 1_000_000_000
                elif "میلیون" in mult:
                    val *= 1_000_000
                elif "هزار" in mult:
                    val *= 1_000
                _add("goal", f"هدف فروش ماهانه حدود {val:,.0f}", "medium")
            except ValueError:
                pass

        tm = _TERM_RE.search(content)
        if tm:
            term = tm.group(1).strip()
            meaning = tm.group(2).strip()
            _add("term", f"اصطلاح «{term}»: {meaning}", "high")

        if _PREFERENCE_RE.search(content) and not any(
            c["content"][:40] in content for c in candidates[-3:]
        ):
            snippet = _normalize_fact_text(content)
            if len(snippet) <= 180:
                cat = "preference" if re.search(
                    r"ترجیح|prefer|دوست\s*دارم|همیشه|معمولاً", content, re.I
                ) else "fact"
                _add(cat, snippet, "low")

        if len(candidates) >= 8:
            break

    return candidates[:8]


def extract_facts_from_messages(messages: List[Dict[str, Any]]) -> List[str]:
    """سازگاری با تست‌های قدیمی — متن حقایق استخراج‌شده."""
    return [c["content"] for c in extract_learned_candidates(messages)]


def merge_memory_content(current_memory: str, facts: List[str]) -> str:
    """سازگاری عقب‌رو — دیگر برای یادگیری استفاده نمی‌شود."""
    new_facts = facts
    if current_memory:
        new_facts = [f for f in facts if f[:50] not in current_memory]
        if not new_facts:
            return current_memory
        new_facts_text = "\n".join(f"- {f}" for f in new_facts)
        updated = f"{current_memory}\n\n{AUTO_SECTION_MARKER}\n{new_facts_text}"
    else:
        new_facts_text = "\n".join(f"- {f}" for f in facts)
        updated = f"{LEGACY_AUTO_MARKER}\n{new_facts_text}"

    if len(updated) > MAX_MEMORY_CHARS:
        updated = updated[-MAX_MEMORY_CHARS:]
    return updated


def _content_similar(a: str, b: str) -> bool:
    aa = _normalize_fact_text(a).lower()
    bb = _normalize_fact_text(b).lower()
    if not aa or not bb:
        return False
    if aa == bb or aa in bb or bb in aa:
        return True
    return aa[:40] == bb[:40]


def silent_learn_from_messages(
    db: Session,
    business_id: int,
    user_id: int,
    session_messages: List[Dict[str, Any]],
) -> int:
    """
    یادگیری بی‌صدا: حقایق پایدار را به‌صورت آیتم در ai_memory_items ذخیره می‌کند.
    دستورات همیشگی کاربر را تغییر نمی‌دهد.
    """
    from app.services.ai.ai_memory_item_service import (
        list_memory_items,
        upsert_memory_item,
    )

    candidates = extract_learned_candidates(
        session_messages[-AUTO_SUMMARIZE_MAX_MESSAGES:]
    )
    if not candidates:
        return 0

    existing = list_memory_items(db, business_id, user_id, limit=100)
    existing_contents = [e.content for e in existing]
    created = 0

    for cand in candidates:
        if any(_content_similar(cand["content"], ec) for ec in existing_contents):
            continue
        try:
            row = upsert_memory_item(
                db,
                business_id,
                user_id,
                item_key=cand["item_key"],
                category=cand["category"],
                content=cand["content"],
                source="auto",
                confidence=cand.get("confidence") or "medium",
            )
            existing_contents.append(row.content)
            created += 1
        except Exception as exc:
            logger.debug("silent learn upsert skipped: %s", exc)

    # پاک‌سازی بخش‌های خودکار قدیمی از فیلد دستورات
    row = get_memory(db, business_id, user_id)
    if row and row.content and any(m in row.content for m in _AUTO_MARKERS):
        cleaned = strip_auto_sections(row.content)
        if cleaned != (row.content or "").strip():
            row.content = cleaned
            row.structured = None
            row.updated_at = datetime.utcnow()
            db.commit()

    if created:
        log_ai_event(
            "memory_silent_learned",
            business_id=business_id,
            user_id=user_id,
            extra={"items": created},
        )
    return created


async def auto_summarize_session(
    db: Session,
    business_id: int,
    user_id: int,
    session_messages: List[Dict[str, Any]],
    ai_service=None,  # noqa: ARG001
) -> bool:
    if len(session_messages) < AUTO_SUMMARIZE_MIN_MESSAGES:
        return False
    created = silent_learn_from_messages(db, business_id, user_id, session_messages)
    return created > 0


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
    """
    سازگاری با ابزار قدیمی: به‌جای آلوده کردن دستورات،
    یک آیتم یادگرفته‌شده می‌سازد و دستورات را دست‌نخورده برمی‌گرداند.
    """
    note = (note or "").strip()
    if not note:
        raise ValueError("متن حافظه خالی است")
    from app.services.ai.ai_memory_item_service import upsert_memory_item

    upsert_memory_item(
        db,
        business_id,
        user_id,
        item_key=None,
        category="fact",
        content=f"{section_title}: {note[:500]}",
        source="assistant",
        confidence="medium",
    )
    row = get_memory(db, business_id, user_id)
    if row:
        return row
    return upsert_memory(db, business_id, user_id, "")
