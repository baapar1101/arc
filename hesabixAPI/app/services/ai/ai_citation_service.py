"""
سرویس Explainability / Citation — پیوست منابع به پاسخ AI.

این سرویس از نتایج tool calls، citations را استخراج کرده
و در پیام system تزریق می‌کند تا LLM بتواند آن‌ها را cite کند.
"""
from __future__ import annotations

import json
import logging
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)


def _extract_doc_refs(items: List[Any]) -> List[Dict[str, Any]]:
    """استخراج رفرنس‌های سند/رکورد از یک لیست آیتم."""
    refs: List[Dict[str, Any]] = []
    for item in items:
        if not isinstance(item, dict):
            continue
        ref_id = item.get("id") or item.get("code") or item.get("number")
        name = item.get("name") or item.get("title") or item.get("alias_name")
        doc_type = item.get("document_type") or item.get("type") or ""
        amount = item.get("total") or item.get("amount") or item.get("balance")

        if ref_id is None and name is None:
            continue
        ref: Dict[str, Any] = {}
        if ref_id:
            ref["id"] = ref_id
        if name:
            ref["name"] = name
        if doc_type:
            ref["type"] = doc_type
        if amount is not None:
            ref["amount"] = amount
        refs.append(ref)
    return refs[:10]


def build_citation_context(
    function_results: Dict[str, Any],
    max_sources: int = 8,
) -> str:
    """
    ساخت بخش citation در system prompt از نتایج tool calls.
    LLM را تشویق می‌کند که به رکوردهای مشخص ارجاع دهد.
    """
    all_refs: List[Dict[str, Any]] = []

    for tc_id, entry in function_results.items():
        if tc_id.startswith("_"):
            continue
        if isinstance(entry, dict) and "result" in entry:
            result = entry["result"]
        else:
            result = entry

        if not isinstance(result, dict):
            continue

        for list_key in ("items", "data", "results", "invoices", "products", "persons",
                         "leads", "deals", "documents"):
            items = result.get(list_key)
            if isinstance(items, list) and items:
                refs = _extract_doc_refs(items)
                fn_name = entry.get("name", "") if isinstance(entry, dict) else ""
                for ref in refs:
                    ref["_source"] = fn_name
                all_refs.extend(refs)
                break

    if not all_refs:
        return ""

    unique_refs = []
    seen_ids: set = set()
    for ref in all_refs:
        key = f"{ref.get('type','')}-{ref.get('id','')}-{ref.get('name','')}"
        if key not in seen_ids:
            seen_ids.add(key)
            unique_refs.append(ref)

    unique_refs = unique_refs[:max_sources]

    lines = ["\n\n--- منابع داده (برای ارجاع در پاسخ) ---"]
    for ref in unique_refs:
        parts = []
        if ref.get("type"):
            parts.append(ref["type"])
        if ref.get("id"):
            parts.append(f"#{ref['id']}")
        if ref.get("name"):
            parts.append(ref["name"])
        if ref.get("amount"):
            try:
                parts.append(f"مبلغ: {float(ref['amount']):,.0f}")
            except (TypeError, ValueError):
                pass
        lines.append("- " + " | ".join(parts))

    lines.append(
        "\nدر پاسخ خود می‌توانی با ذکر شماره/نام رکوردهای بالا ارجاع بدهی."
    )
    return "\n".join(lines)


def format_citations_for_response(
    function_results: Optional[Dict[str, Any]],
) -> Optional[str]:
    """
    تولید بخش citation برای اضافه کردن به انتهای پاسخ.
    اگر هیچ source معناداری نباشد None برمی‌گرداند.
    """
    if not function_results:
        return None
    citation_text = build_citation_context(function_results)
    if not citation_text.strip():
        return None
    return citation_text
