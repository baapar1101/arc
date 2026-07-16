"""ساخت پاسخ قطعی از شواهد ابزار — بدون LLM.

وقتی wall-clock تمام شده یا سنتز LLM شکست خورده، باید از داده‌های
جمع‌آوری‌شده همان‌قدر که داریم به کاربر پاسخ بدهیم؛ نه پیام خالیِ بودجه.
"""
from __future__ import annotations

from typing import Any, Dict, List, Optional

from app.services.ai.ai_content_sanitize import sanitize_assistant_content
from app.services.ai.ai_premature_answer import looks_like_status_narrative
from app.services.ai.ai_tool_keys import tool_label_fa


def build_deterministic_answer_from_trace(
    trace_steps: Optional[List[Dict[str, Any]]],
    *,
    user_query: Optional[str] = None,
    budget_note: bool = False,
) -> str:
    """پاسخ خوانا از explored/observation/thought — بدون فراخوانی مدل.

    اولویت:
      1) آخرین narrative غیر-وضعیت (خلاصهٔ نوشته‌شده توسط مدل)
      2) ترکیب explored (+ thought در صورت نبود explored)
      3) خالی اگر هیچ شاهد مفیدی نیست
    """
    if not trace_steps:
        return ""

    # ۱) narrative ترکیبی آماده
    for step in reversed(trace_steps):
        if step.get("kind") != "narrative":
            continue
        body = sanitize_assistant_content(
            (step.get("body_markdown") or "").strip()
        )
        if len(body) < 40 or looks_like_status_narrative(body):
            continue
        return _wrap_answer(body, budget_note=budget_note)

    # ۲) explored را ترجیح بده (معمولاً همان observation را خلاصه کرده)
    explored_parts: List[str] = []
    thought_parts: List[str] = []
    observation_parts: List[str] = []
    for step in trace_steps:
        kind = step.get("kind")
        body = sanitize_assistant_content(
            (step.get("body_markdown") or "").strip()
        )
        if not body or len(body) < 12:
            continue
        if kind == "explored":
            explored_parts.append(body)
        elif kind == "thought":
            thought_parts.append(body)
        elif kind == "observation":
            tool = step.get("tool") or ""
            label = tool_label_fa(tool) if tool else "نتیجه ابزار"
            observation_parts.append(f"### {label}\n{body}")

    sections: List[str] = []
    if explored_parts:
        sections.extend(explored_parts)
        # thought کوتاه فقط اگر ارزش افزوده‌ای دارد و خیلی تکراری نیست
        for thought in thought_parts:
            if len(thought) < 500 and thought not in sections:
                sections.append(thought)
    elif observation_parts:
        sections.extend(observation_parts)
        sections.extend(thought_parts)
    elif thought_parts:
        sections.extend(thought_parts)

    if not sections:
        return ""

    header_bits: List[str] = ["**خلاصه بر اساس داده‌های جمع‌آوری‌شده**"]
    q = (user_query or "").strip()
    if q:
        header_bits.append(f"*سوال:* {q[:160]}")
    body = "\n\n".join(sections)
    if len(body) > 6000:
        body = body[:6000].rstrip() + "\n\n…"
    text = "\n\n".join(header_bits + ["", body])
    return _wrap_answer(text, budget_note=budget_note)


def _wrap_answer(text: str, *, budget_note: bool) -> str:
    text = (text or "").strip()
    if not text:
        return ""
    if budget_note:
        note = (
            "\n\n---\n"
            "_زمان تحلیل به پایان رسید؛ پاسخ بالا بر اساس داده‌هایی است "
            "که تا این لحظه جمع‌آوری شده بود._"
        )
        if note.strip() not in text:
            text = text + note
    return text


def redact_final_answer_from_reasoning_trace(
    trace_steps: List[Dict[str, Any]],
    final_answer: str,
) -> None:
    """پاسخ نهایی را از narrativeهای reasoning پاک می‌کند (درجا).

    تا در پنل تحلیل دوباره همان متن پاسخ دیده نشود.
    """
    final = sanitize_assistant_content((final_answer or "").strip())
    if not final or len(final) < 40:
        return
    final_norm = " ".join(final.split())
    for step in trace_steps:
        if step.get("kind") != "narrative":
            continue
        body = sanitize_assistant_content(
            (step.get("body_markdown") or "").strip()
        )
        if not body:
            continue
        body_norm = " ".join(body.split())
        # اگر narrative همان پاسخ نهایی (یا بخش عمدهٔ آن) است، بدنه را بردار
        if body_norm == final_norm or (
            len(body_norm) >= 40 and body_norm in final_norm
        ):
            step["body_markdown"] = None
            step["visibility"] = "internal"
            step["title_key"] = step.get("title_key") or "aiTraceComposingAnswer"
