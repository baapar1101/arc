"""
سرویس Explainability / Citation — پیوست منابع به پاسخ AI.

منابع از envelope ابزار استخراج می‌شوند، در function_results persist
می‌شوند، و به مدل و UI می‌رسند (RAG-02).
"""
from __future__ import annotations

import logging
import re
from typing import Any, Dict, List, Optional, Sequence, Tuple

from app.services.ai.ai_tool_result import (
    extract_record_citations,
    extract_record_list,
    iter_tool_payloads,
    unwrap_registry_result,
)

logger = logging.getLogger(__name__)

CITATIONS_STORAGE_KEY = "_citations"

_ENTITY_FROM_TOOL: Tuple[Tuple[str, str], ...] = (
    ("invoice", "invoice"),
    ("person", "person"),
    ("customer", "person"),
    ("product", "product"),
    ("inventory", "product"),
    ("kardex", "product"),
    ("lead", "lead"),
    ("deal", "deal"),
    ("workflow", "workflow"),
    ("warehouse", "warehouse_doc"),
    ("receipt", "receipt_payment"),
    ("payment", "receipt_payment"),
    ("knowledge", "knowledge"),
    ("account", "account"),
)

_MONEYISH_RE = re.compile(
    r"(ریال|تومان|میلیون|میلیارد|درصد|٪)|"
    r"[\d۰-۹]{1,3}(?:[٬,][\d۰-۹]{3}){2,}",
)


def infer_citation_entity(source_tool: str, ref: Dict[str, Any]) -> Optional[str]:
    """نوع موجودیت برای لینک UI؛ اول type رکورد، بعد نام ابزار."""
    declared = str(ref.get("type") or ref.get("entity") or "").strip().lower()
    if declared:
        for needle, entity in _ENTITY_FROM_TOOL:
            if needle in declared:
                return entity
        if declared in {
            "invoice",
            "person",
            "product",
            "lead",
            "deal",
            "workflow",
            "warehouse_doc",
            "receipt_payment",
            "knowledge",
            "account",
        }:
            return declared
    tool = (source_tool or "").lower()
    for needle, entity in _ENTITY_FROM_TOOL:
        if needle in tool:
            return entity
    return None


def _normalize_ref(ref: Dict[str, Any], source_tool: str) -> Dict[str, Any]:
    out: Dict[str, Any] = {}
    if ref.get("id") is not None:
        out["id"] = ref["id"]
    elif ref.get("code") is not None:
        out["id"] = ref["code"]
    elif ref.get("number") is not None:
        out["id"] = ref["number"]
    name = ref.get("name") or ref.get("title") or ref.get("alias_name")
    if name:
        out["name"] = name
    entity = infer_citation_entity(source_tool, ref)
    if entity:
        out["entity"] = entity
    declared_type = ref.get("type") or ref.get("document_type")
    if declared_type:
        out["type"] = declared_type
    amount = ref.get("amount") if "amount" in ref else ref.get("total") or ref.get("balance")
    if amount is not None:
        out["amount"] = amount
    if source_tool:
        out["source"] = source_tool
    return out


def extract_citation_sources(
    function_results: Optional[Dict[str, Any]],
    *,
    max_sources: int = 8,
) -> List[Dict[str, Any]]:
    """لیست پایدار منابع از نتایج ابزار (نه متن prompt)."""
    if not function_results:
        return []
    all_refs: List[Dict[str, Any]] = []
    for fn_name, raw in iter_tool_payloads(function_results):
        result = unwrap_registry_result(raw)
        refs: List[Dict[str, Any]] = []
        if isinstance(result, dict) and isinstance(result.get("citations"), list):
            refs = [dict(x) for x in result["citations"] if isinstance(x, dict)]
        if not refs:
            records, _ = extract_record_list(result)
            refs = extract_record_citations(records)
        for ref in refs:
            normalized = _normalize_ref(ref, fn_name)
            if normalized.get("id") is None and not normalized.get("name"):
                continue
            all_refs.append(normalized)

    unique_refs: List[Dict[str, Any]] = []
    seen: set = set()
    for ref in all_refs:
        key = f"{ref.get('entity','')}-{ref.get('id','')}-{ref.get('name','')}"
        if key in seen:
            continue
        seen.add(key)
        unique_refs.append(ref)
        if len(unique_refs) >= max_sources:
            break
    return unique_refs


def merge_citations_into_function_results(
    function_results: Optional[Dict[str, Any]],
    sources: Sequence[Dict[str, Any]],
) -> Dict[str, Any]:
    merged = dict(function_results or {})
    if sources:
        merged[CITATIONS_STORAGE_KEY] = [dict(x) for x in sources]
    return merged


def citations_from_function_results(
    function_results: Optional[Dict[str, Any]],
) -> List[Dict[str, Any]]:
    if not isinstance(function_results, dict):
        return []
    stored = function_results.get(CITATIONS_STORAGE_KEY)
    if isinstance(stored, list) and stored:
        return [dict(x) for x in stored if isinstance(x, dict)]
    return extract_citation_sources(function_results)


def format_citation_lines(sources: Sequence[Dict[str, Any]]) -> List[str]:
    lines: List[str] = []
    for ref in sources:
        parts: List[str] = []
        if ref.get("type"):
            parts.append(str(ref["type"]))
        elif ref.get("entity"):
            parts.append(str(ref["entity"]))
        if ref.get("id") is not None:
            parts.append(f"#{ref['id']}")
        if ref.get("name"):
            parts.append(str(ref["name"]))
        if ref.get("amount") is not None:
            try:
                parts.append(f"مبلغ: {float(ref['amount']):,.0f}")
            except (TypeError, ValueError):
                pass
        if parts:
            lines.append("- " + " | ".join(parts))
    return lines


def build_citation_context(
    function_results: Dict[str, Any],
    max_sources: int = 8,
) -> str:
    """بخش citation در system prompt از نتایج tool calls."""
    sources = extract_citation_sources(function_results, max_sources=max_sources)
    if not sources:
        return ""
    lines = ["\n\n--- منابع داده (برای ارجاع در پاسخ) ---"]
    lines.extend(format_citation_lines(sources))
    lines.append(
        "\nهر عدد یا ادعای وضعیت باید به یکی از منابع بالا ارجاع بدهد. "
        "اگر منبع نداری عدد قطعی نگو و بگو داده در نتایج ابزار نیست."
    )
    return "\n".join(lines)


def format_citations_for_response(
    function_results: Optional[Dict[str, Any]],
) -> Optional[str]:
    """متن citation برای prompt / متادیتای done. اگر منبعی نباشد None."""
    if not function_results:
        return None
    citation_text = build_citation_context(function_results)
    if not citation_text.strip():
        return None
    return citation_text


def content_has_moneyish_claim(content: str) -> bool:
    text = (content or "").strip()
    if not text:
        return False
    return bool(_MONEYISH_RE.search(text))


def ungrounded_numeric_warning(
    content: str,
    sources: Sequence[Dict[str, Any]],
) -> Optional[str]:
    """اگر پاسخ عدد مالی دارد ولی منبعی persist نشده، هشدار UI/eval."""
    if sources:
        return None
    if not content_has_moneyish_claim(content):
        return None
    return "اعداد این پاسخ به رکورد منبع در نتایج ابزار وصل نشد."
