"""
حافظهٔ ساخت‌یافته (JSON) — مکمل فیلد متنی آزاد.
"""
from __future__ import annotations

import json
import re
from typing import Any, Dict, List, Optional

STRUCTURED_SCHEMA_VERSION = 1

DEFAULT_STRUCTURED: Dict[str, Any] = {
    "schema_version": STRUCTURED_SCHEMA_VERSION,
    "sales_goal_monthly": None,
    "sales_goal_unit": "toman",
    "currency_display": "toman",
    "report_style": "summary",
    "preferred_language": "fa",
    "business_role": None,
    "internal_terms": [],
    "knowledge_hints": [],
}

ALLOWED_CURRENCY = {"toman", "rial", "usd", "eur"}
ALLOWED_REPORT_STYLE = {"summary", "table", "detailed"}
ALLOWED_LANGUAGE = {"fa", "en"}


def _empty_structured() -> Dict[str, Any]:
    return json.loads(json.dumps(DEFAULT_STRUCTURED))


def parse_structured(raw: Any) -> Dict[str, Any]:
    if raw is None or raw == "":
        return _empty_structured()
    if isinstance(raw, dict):
        data = dict(raw)
    elif isinstance(raw, str):
        try:
            data = json.loads(raw)
        except json.JSONDecodeError:
            return _empty_structured()
        if not isinstance(data, dict):
            return _empty_structured()
    else:
        return _empty_structured()

    out = _empty_structured()
    for key in DEFAULT_STRUCTURED:
        if key in data and data[key] is not None:
            out[key] = data[key]

    if out.get("currency_display") not in ALLOWED_CURRENCY:
        out["currency_display"] = "toman"
    if out.get("report_style") not in ALLOWED_REPORT_STYLE:
        out["report_style"] = "summary"
    if out.get("preferred_language") not in ALLOWED_LANGUAGE:
        out["preferred_language"] = "fa"

    terms = out.get("internal_terms")
    if isinstance(terms, list):
        cleaned: List[Dict[str, str]] = []
        for t in terms[:30]:
            if isinstance(t, dict):
                term = str(t.get("term") or "").strip()[:80]
                meaning = str(t.get("meaning") or "").strip()[:200]
                if term:
                    cleaned.append({"term": term, "meaning": meaning})
            elif isinstance(t, str) and t.strip():
                cleaned.append({"term": t.strip()[:80], "meaning": ""})
        out["internal_terms"] = cleaned
    else:
        out["internal_terms"] = []

    hints = out.get("knowledge_hints")
    if isinstance(hints, list):
        out["knowledge_hints"] = [str(h).strip()[:120] for h in hints[:10] if str(h).strip()]
    else:
        out["knowledge_hints"] = []

    goal = out.get("sales_goal_monthly")
    if goal is not None:
        try:
            out["sales_goal_monthly"] = float(goal)
        except (TypeError, ValueError):
            out["sales_goal_monthly"] = None

    return out


def serialize_structured(data: Dict[str, Any]) -> str:
    return json.dumps(parse_structured(data), ensure_ascii=False)


def merge_structured_patch(
    current: Dict[str, Any],
    patch: Optional[Dict[str, Any]],
) -> Dict[str, Any]:
    if not patch:
        return parse_structured(current)
    base = parse_structured(current)
    for key, value in patch.items():
        if key not in DEFAULT_STRUCTURED or value is None:
            continue
        if key == "internal_terms" and isinstance(value, list):
            existing = {
                t["term"]: t
                for t in base.get("internal_terms") or []
                if isinstance(t, dict) and t.get("term")
            }
            for t in value:
                if isinstance(t, dict) and t.get("term"):
                    existing[str(t["term"]).strip()] = {
                        "term": str(t["term"]).strip()[:80],
                        "meaning": str(t.get("meaning") or "").strip()[:200],
                    }
            base["internal_terms"] = list(existing.values())[:30]
        else:
            base[key] = value
    return parse_structured(base)


def structured_to_prompt_block(structured: Dict[str, Any]) -> str:
    s = parse_structured(structured)
    lines: List[str] = []

    goal = s.get("sales_goal_monthly")
    if goal is not None and goal > 0:
        unit = s.get("sales_goal_unit") or "toman"
        lines.append(f"هدف فروش ماهانه: {goal:,.0f} ({unit})")

    role = s.get("business_role")
    if role:
        lines.append(f"نقش کاربر در کسب‌وکار: {role}")

    currency = s.get("currency_display")
    if currency:
        lines.append(f"نمایش مبالغ: {currency}")

    style = s.get("report_style")
    if style:
        lines.append(f"سبک گزارش ترجیحی: {style}")

    lang = s.get("preferred_language")
    if lang == "en":
        lines.append("زبان پاسخ ترجیحی: انگلیسی")
    elif lang == "fa":
        lines.append("زبان پاسخ ترجیحی: فارسی")

    for t in s.get("internal_terms") or []:
        if isinstance(t, dict) and t.get("term"):
            meaning = t.get("meaning") or ""
            if meaning:
                lines.append(f"اصطلاح «{t['term']}»: {meaning}")
            else:
                lines.append(f"اصطلاح داخلی: {t['term']}")

    for hint in s.get("knowledge_hints") or []:
        lines.append(f"یادآوری دانشنامه: {hint}")

    if not lines:
        return ""
    return "\n".join(lines)


def structured_to_digest_sections(structured: Dict[str, Any], content: str) -> Dict[str, Any]:
    s = parse_structured(structured)
    sections: List[Dict[str, str]] = []

    block = structured_to_prompt_block(s)
    if block:
        sections.append({"title": "تنظیمات ساخت‌یافته", "body": block})

    if content and content.strip():
        preview = content.strip()
        if len(preview) > 800:
            preview = preview[:800] + "…"
        sections.append({"title": "یادداشت آزاد", "body": preview})

    return {
        "sections": sections,
        "is_empty": not block and not (content or "").strip(),
        "structured": s,
    }


def extract_structured_from_text(content: str) -> Dict[str, Any]:
    patch: Dict[str, Any] = {}
    text = (content or "").lower()

    if re.search(r"تومان|toman", text):
        patch["currency_display"] = "toman"
    elif re.search(r"ریال|rial", text):
        patch["currency_display"] = "rial"

    if re.search(r"جدول|table", text):
        patch["report_style"] = "table"
    elif re.search(r"خلاصه|summary", text):
        patch["report_style"] = "summary"

    m = re.search(
        r"هدف\s*(?:فروش)?\s*(?:ماه(?:انه)?)?\s*[:：]?\s*([\d،,\.]+)\s*(میلیون|میلیارد|هزار)?",
        content or "",
        re.IGNORECASE,
    )
    if m:
        num_raw = m.group(1).replace("،", "").replace(",", "")
        try:
            val = float(num_raw)
            mult = m.group(2) or ""
            if "میلیارد" in mult:
                val *= 1_000_000_000
            elif "میلیون" in mult:
                val *= 1_000_000
            elif "هزار" in mult:
                val *= 1_000
            patch["sales_goal_monthly"] = val
            patch["sales_goal_unit"] = patch.get("currency_display") or "toman"
        except ValueError:
            pass

    return patch
