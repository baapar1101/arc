"""کامپایل بلوک واحد حافظه برای system prompt (Recall)."""
from __future__ import annotations

import re
from typing import Any, Iterable, List, Optional, Sequence

from app.services.ai.ai_constants import (
    MEMORY_ALWAYS_KIND_CHAR_BUDGET,
    MEMORY_ALWAYS_KINDS,
    MEMORY_RECALL_KIND_CHAR_BUDGET,
    MEMORY_RECALL_KINDS,
    MEMORY_RECALL_MAX_ITEMS,
)
from app.services.ai.ai_memory_keys import KEY_PROMPT_LABELS, KIND_PROMPT_TITLES, canonical_kind

IDENTITY_TOOL_POLICY = (
    "نام و هویت خود کاربر را از get_business_info یا search_persons نگیر. "
    "اگر نام خطاب در حافظه پایدار هست همان را جواب بده و برای این سؤال ابزار نزن."
)

_TOKEN_RE = re.compile(r"[\w\u0600-\u06FF]+", re.UNICODE)

KIND_ORDER = (
    "instruction",
    "identity",
    "preference",
    "constraint",
    "context",
    "goal",
)


def _tokens(text: str) -> set[str]:
    return {m.group(0).lower() for m in _TOKEN_RE.finditer(text or "") if len(m.group(0)) >= 2}


def _score_recall(item: dict[str, Any], query: str) -> int:
    q = _tokens(query)
    if not q:
        return 0
    blob = f"{item.get('item_key') or ''} {item.get('content') or ''}"
    return len(q & _tokens(blob))


def _item_line(item: dict[str, Any]) -> str:
    content = (item.get("content") or "").strip()
    if not content:
        return ""
    key = (item.get("item_key") or "").strip()
    label = KEY_PROMPT_LABELS.get(key)
    if label and label not in content:
        return f"{label}: {content}"[:300]
    return content[:300]


def extract_preferred_name(items: Iterable[dict[str, Any]]) -> str:
    for it in items or []:
        if (it.get("item_key") or "").strip() != "identity.preferred_name":
            continue
        content = (it.get("content") or "").strip()
        if content:
            return content
    return ""


def build_identity_anchor(items: Optional[Iterable[dict[str, Any]]] = None) -> str:
    """لنگر هویت کنار شناسه کسب‌وکار — منبع حقیقت نام کاربر، نه خروجی ابزار."""
    catalog = list(items or [])
    name = extract_preferred_name(catalog)
    lines = [
        "هویت گوینده با کارت کسب‌وکار یکی نیست.",
        "برای نام یا هویت خود کاربر get_business_info یا search_persons صدا نزن.",
        "اگر نام خطاب در حافظه پایدار هست همان را جواب بده و برای این سؤال ابزار نزن.",
    ]
    if name:
        label = KEY_PROMPT_LABELS["identity.preferred_name"]
        if label not in name:
            lines.insert(0, f"{label} (حافظه پایدار — منبع حقیقت): {name}")
        else:
            lines.insert(0, f"حافظه پایدار — منبع حقیقت: {name}")
    return "\n" + "\n".join(lines)


def _trim_block(title: str, lines: Sequence[str], budget: int) -> str:
    body_lines = [f"- {line}" for line in lines if line and str(line).strip()]
    if not body_lines:
        return ""
    text = f"### {title}\n" + "\n".join(body_lines)
    if len(text) <= budget:
        return text
    kept: List[str] = []
    header = f"### {title}\n"
    used = len(header)
    for line in body_lines:
        extra = len(line) + 1
        if used + extra > budget:
            break
        kept.append(line)
        used += extra
    if not kept:
        return ""
    return header + "\n".join(kept)


def compile_memory_prompt(
    *,
    instructions: str = "",
    items: Optional[Iterable[dict[str, Any]]] = None,
    user_query: Optional[str] = None,
) -> str:
    """
    یک بلوک حافظه برای پرامپت بساز.
    instruction + identity + preference + constraint همیشه؛
    context/goal بر اساس تازگی و همپوشانی با سوال جاری.
    """
    grouped: dict[str, List[str]] = {k: [] for k in KIND_ORDER}
    instr = (instructions or "").strip()
    if instr:
        grouped["instruction"].append(instr)

    catalog = list(items or [])
    always_items = [
        it for it in catalog if canonical_kind(it.get("kind") or it.get("category")) in MEMORY_ALWAYS_KINDS
    ]
    recall_items = [
        it for it in catalog if canonical_kind(it.get("kind") or it.get("category")) in MEMORY_RECALL_KINDS
    ]

    for it in always_items:
        kind = canonical_kind(it.get("kind") or it.get("category"))
        line = _item_line(it)
        if not line:
            continue
        grouped[kind].append(line)

    query = (user_query or "").strip()
    if recall_items:
        scored = sorted(
            recall_items,
            key=lambda it: (
                -_score_recall(it, query),
                str(it.get("updated_at") or ""),
            ),
        )
        for it in scored[:MEMORY_RECALL_MAX_ITEMS]:
            kind = canonical_kind(it.get("kind") or it.get("category"))
            content = (it.get("content") or "").strip()
            if not content:
                continue
            grouped[kind].append(_item_line(it))

    always_parts: List[str] = []
    recall_parts: List[str] = []
    always_budget_left = MEMORY_ALWAYS_KIND_CHAR_BUDGET
    recall_budget_left = MEMORY_RECALL_KIND_CHAR_BUDGET

    for kind in KIND_ORDER:
        lines = grouped.get(kind) or []
        if not lines:
            continue
        title = KIND_PROMPT_TITLES.get(kind, kind)
        if kind in MEMORY_ALWAYS_KINDS:
            block = _trim_block(title, lines, max(120, always_budget_left))
            if block:
                always_parts.append(block)
                always_budget_left -= len(block)
        else:
            block = _trim_block(title, lines, max(120, recall_budget_left))
            if block:
                recall_parts.append(block)
                recall_budget_left -= len(block)

    parts = always_parts + recall_parts
    if not parts:
        return ""

    body = "\n\n".join(parts)
    return (
        "\n\n--- حافظهٔ پایدار کاربر ---\n"
        "این بلوک زمینهٔ بین جلسات است و برای هویت/ترجیح/سیاست کاربر منبع حقیقت است. "
        "سیاست‌های الزام‌آور را رعایت کن مگر کاربر صریحاً خلاف بگوید. "
        "اعداد، مانده، فاکتور، موجودی و مشخصات شرکت را از ابزار بخوان؛ آن‌ها را از حافظه حدس نزن. "
        "نام و هویت خود کاربر را از get_business_info یا search_persons نگیر — "
        "اگر در این بلوک هست همان را جواب بده و برای این سؤال ابزار نزن. "
        "در این نوبت حافظه را با ابزار ننویس — کیوریتور پس از پاسخ آن را به‌روز می‌کند. "
        "ابزار حافظه فقط وقتی لازم است که کاربر بخواهد فهرست/ویرایش/حذف حافظه را مدیریت کند.\n"
        f"{body}"
    )
