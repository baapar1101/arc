"""
فهرست authoritative ابزارهای AI — جلوگیری از hallucination نام ابزار.

وقتی کاربر می‌پرسد «چه ابزارهایی داری؟»، کاتالوگ واقعی از registry
به context تزریق می‌شود (مشابه tool list در system prompt آنتروپیک).
"""
from __future__ import annotations

import re
from typing import Any, Dict, List, Optional

from app.services.ai.ai_tool_intent import _CATEGORY_TOOLS
from app.services.ai.ai_tool_keys import tool_label_fa

_TOOL_DISCOVERY_PATTERNS = re.compile(
    r"(?:"
    r"چه\s*ابزار|ابزارهای?\s*(?:داری|دارید|موجود|در\s*دسترس)|"
    r"قابلیت(?:ها)?\s*(?:داری|دارید)|امکانات\s*(?:داری|دارید)|"
    r"what\s+tools|which\s+tools|tools?\s+(?:do\s+you\s+have|are\s+available|can\s+you\s+use)|"
    r"your\s+capabilities|list\s+(?:your\s+)?tools|available\s+functions?"
    r")",
    re.IGNORECASE,
)

_CATEGORY_LABELS_FA: dict[str, str] = {
    "financial": "مالی و فاکتور",
    "warehouse": "انبار و موجودی",
    "crm": "CRM",
    "customer_club": "باشگاه مشتریان",
    "tax": "مالیات و مودیان",
    "projects": "پروژه",
    "integration": "یکپارچه‌سازی",
    "workflow": "گردش کار",
    "misc": "سایر",
    "agent": "برنامهٔ کاری agent",
    "people": "اشخاص",
    "products_write": "کالا و دسته‌بندی",
    "query": "پرس‌وجوی داده",
    "reports_meta": "گزارش‌ها",
    "report_templates": "قالب گزارش",
    "marketplace": "بازار افزونه",
}

_TOOL_NAME_TO_CATEGORY: dict[str, str] = {}
for _cat, _names in _CATEGORY_TOOLS.items():
    for _name in _names:
        _TOOL_NAME_TO_CATEGORY.setdefault(_name, _cat)


def is_tool_discovery_query(user_query: Optional[str]) -> bool:
    q = (user_query or "").strip()
    if not q:
        return False
    return bool(_TOOL_DISCOVERY_PATTERNS.search(q))


def _tool_description(defn: Dict[str, Any]) -> str:
    fn = defn.get("function") if isinstance(defn, dict) else None
    if not isinstance(fn, dict):
        return ""
    desc = (fn.get("description") or "").strip()
    if len(desc) > 120:
        return desc[:117] + "…"
    return desc


def _tool_name(defn: Dict[str, Any]) -> str:
    fn = defn.get("function") if isinstance(defn, dict) else None
    if isinstance(fn, dict):
        return str(fn.get("name") or "")
    return ""


def build_tool_catalog_markdown(
    definitions: List[Dict[str, Any]],
    *,
    readonly_only: bool = False,
) -> str:
    """جدول markdown از ابزارهای واقعی registry."""
    by_category: dict[str, List[tuple[str, str, str]]] = {}
    for defn in definitions:
        name = _tool_name(defn)
        if not name:
            continue
        cat = _TOOL_NAME_TO_CATEGORY.get(name, "misc")
        label = tool_label_fa(name)
        desc = _tool_description(defn)
        by_category.setdefault(cat, []).append((name, label, desc))

    if not by_category:
        return "*(هیچ ابزاری برای این کاربر در دسترس نیست)*"

    lines = [
        "### فهرست رسمی ابزارها (فقط از این نام‌ها استفاده کن)",
        "",
        "نام‌های زیر از سیستم حسابیکس خوانده شده‌اند. **هرگز ابزار جعلی نساز.** "
        "برای دادهٔ زنده حتماً `function call` بزن؛ برای معرفی قابلیت‌ها همین فهرست کافی است.",
        "",
    ]
    for cat in sorted(by_category.keys(), key=lambda c: _CATEGORY_LABELS_FA.get(c, c)):
        rows = sorted(by_category[cat], key=lambda r: r[1])
        lines.append(f"#### {_CATEGORY_LABELS_FA.get(cat, cat)}")
        lines.append("")
        lines.append("| ابزار | توضیح |")
        lines.append("|--------|--------|")
        for name, label, desc in rows:
            lines.append(f"| `{name}` | {label}" + (f" — {desc}" if desc else "") + " |")
        lines.append("")

    if readonly_only:
        lines.append(
            "> حالت فعلی: **فقط‌خواندنی** — ابزارهای نوشتنی در این جلسه فعال نیستند."
        )
    return "\n".join(lines).strip()


def build_tool_catalog_system_section(
    definitions: List[Dict[str, Any]],
    *,
    readonly_only: bool = False,
) -> str:
    catalog = build_tool_catalog_markdown(definitions, readonly_only=readonly_only)
    return f"[tool_catalog]\n\n{catalog}"
