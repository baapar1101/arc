"""
قرارداد نتیجهٔ ابزار برای مدل و citation (TOOL-04).

ابزارهای موجود شکل خود را نگه می‌دارند؛ وقتی نتیجه بزرگ است به‌جای
برش وسط JSON یک envelope معتبر با records/summary/truncated ساخته می‌شود.
"""
from __future__ import annotations

from typing import Any, Dict, Iterable, List, Optional, Sequence, Tuple

from app.core.json_safe import json_dumps_safe
from app.services.ai.ai_constants import (
    MAX_TOOL_RESULT_JSON_CHARS,
    MAX_TOOL_RESULT_RECORDS,
)

TOOL_RESULT_ENVELOPE_VERSION = 1
TOOL_LIST_KEYS: Tuple[str, ...] = (
    "records",
    "items",
    "data",
    "results",
    "invoices",
    "products",
    "persons",
    "leads",
    "deals",
    "documents",
    "rows",
)
_SCALAR_KEEP_KEYS: Tuple[str, ...] = (
    "message",
    "summary",
    "description",
    "total",
    "pagination",
    "count",
    "ok",
    "success",
    "page",
    "limit",
    "offset",
)
_TRUNCATION_NOTE_FA = (
    "نتیجه کوتاه شده است. برای جمع‌بندی فقط از summary.total استفاده کن؛ "
    "روی ردیف‌های حذف‌شده عدد نساز."
)


def unwrap_registry_result(result: Any) -> Any:
    """خروجی registry گاهی {name, result} است."""
    if (
        isinstance(result, dict)
        and "result" in result
        and "name" in result
        and len(result) <= 4
    ):
        return result.get("result")
    return result


def extract_record_list(payload: Any) -> Tuple[List[Any], Optional[str]]:
    if isinstance(payload, list):
        return list(payload), "items"
    if not isinstance(payload, dict):
        return [], None
    for key in TOOL_LIST_KEYS:
        items = payload.get(key)
        if isinstance(items, list) and items:
            return list(items), key
    return [], None


def extract_record_citations(
    records: Sequence[Any], *, limit: int = 10
) -> List[Dict[str, Any]]:
    refs: List[Dict[str, Any]] = []
    for item in records:
        if not isinstance(item, dict):
            continue
        ref_id = item.get("id") or item.get("code") or item.get("number")
        name = item.get("name") or item.get("title") or item.get("alias_name")
        doc_type = item.get("document_type") or item.get("type") or ""
        amount = item.get("total") or item.get("amount") or item.get("balance")
        if ref_id is None and name is None:
            continue
        ref: Dict[str, Any] = {}
        if ref_id is not None:
            ref["id"] = ref_id
        if name:
            ref["name"] = name
        if doc_type:
            ref["type"] = doc_type
        if amount is not None:
            ref["amount"] = amount
        refs.append(ref)
        if len(refs) >= limit:
            break
    return refs


def _keep_scalars(payload: Dict[str, Any]) -> Dict[str, Any]:
    out: Dict[str, Any] = {}
    for key in _SCALAR_KEEP_KEYS:
        if key in payload:
            out[key] = payload[key]
    return out


def _total_count(payload: Any, records: List[Any], list_key: Optional[str]) -> int:
    if isinstance(payload, dict):
        pagination = payload.get("pagination")
        if isinstance(pagination, dict):
            for k in ("total", "count", "total_count"):
                val = pagination.get(k)
                if isinstance(val, int) and val >= len(records):
                    return val
        for k in ("total", "total_count", "count"):
            val = payload.get(k)
            if isinstance(val, int) and val >= len(records):
                return val
        if list_key:
            alias = payload.get(f"{list_key}_total")
            if isinstance(alias, int) and alias >= len(records):
                return alias
    return len(records)


def build_tool_result_envelope(
    tool_name: str,
    result: Any,
    *,
    max_records: int = MAX_TOOL_RESULT_RECORDS,
) -> Dict[str, Any]:
    """شکل پایدار برای مدل؛ list_key اصلی حفظ می‌شود تا سازگار با ابزارهای فعلی بماند."""
    payload = unwrap_registry_result(result)
    records, list_key = extract_record_list(payload)
    key = list_key or "records"
    total = _total_count(payload, records, list_key)
    kept_n = min(max(0, max_records), len(records))
    kept = records[:kept_n]
    omitted = max(0, total - kept_n)
    truncated = omitted > 0 or kept_n < len(records)
    summary: Dict[str, Any] = {"count": len(kept), "total": total}
    extra: Dict[str, Any] = {}
    if isinstance(payload, dict):
        extra = _keep_scalars(payload)
        if isinstance(extra.get("summary"), dict):
            merged = dict(extra.pop("summary"))
            merged.update(summary)
            summary = merged
    envelope: Dict[str, Any] = {
        "_envelope": TOOL_RESULT_ENVELOPE_VERSION,
        "ok": True,
        "tool": tool_name,
        key: kept,
        "summary": summary,
        "citations": extract_record_citations(kept),
        "truncated": truncated,
        "omitted_count": omitted,
        **extra,
    }
    if truncated:
        envelope["note"] = _TRUNCATION_NOTE_FA
    if isinstance(payload, dict):
        for meta_key, meta_val in payload.items():
            if str(meta_key).startswith("_") and meta_key not in envelope:
                envelope[meta_key] = meta_val
    return envelope


def _dumps(payload: Any) -> str:
    return json_dumps_safe(payload)


def compact_tool_result_for_llm(
    function_name: str,
    result: Any,
    *,
    max_chars: int = MAX_TOOL_RESULT_JSON_CHARS,
    max_records: int = MAX_TOOL_RESULT_RECORDS,
) -> str:
    """JSON معتبر برای role=tool — هرگز وسط سند را قطع نمی‌کند."""
    if result is None:
        return "نتیجه‌ای برنگشت."
    payload = unwrap_registry_result(result)

    if isinstance(payload, dict):
        if payload.get("error") == "APPROVAL_REQUIRED":
            return _dumps(payload)
        if "error" in payload:
            return _dumps(
                {
                    "ok": False,
                    "error": payload.get("error"),
                    "message": payload.get("message") or payload.get("message_fa"),
                    "message_fa": payload.get("message_fa"),
                    "hint_fa": payload.get("hint_fa"),
                    "retryable": payload.get("retryable"),
                    "expected_args": payload.get("expected_args"),
                    "tool": payload.get("tool") or function_name,
                }
            )

    records, _list_key = extract_record_list(payload)
    needs_envelope = False
    if records and len(records) > max_records:
        needs_envelope = True
    raw_text = _dumps(payload) if isinstance(payload, (dict, list)) else str(payload)
    if len(raw_text) > max_chars:
        needs_envelope = True

    if not needs_envelope and isinstance(payload, dict) and records:
        compact = _keep_scalars(payload)
        key = _list_key or "items"
        compact[key] = records
        text = _dumps(compact) if compact else raw_text
        return text if len(text) <= max_chars else _fit_envelope(
            function_name, payload, max_chars=max_chars, max_records=max_records
        )

    if not needs_envelope:
        if isinstance(payload, (dict, list)):
            return raw_text
        text = str(payload)
        if len(text) <= max_chars:
            return text
        return _dumps(
            {
                "_envelope": TOOL_RESULT_ENVELOPE_VERSION,
                "ok": True,
                "tool": function_name,
                "truncated": True,
                "summary": {"preview": text[:400]},
                "note": _TRUNCATION_NOTE_FA,
            }
        )

    return _fit_envelope(
        function_name, payload, max_chars=max_chars, max_records=max_records
    )


def _fit_envelope(
    function_name: str,
    payload: Any,
    *,
    max_chars: int,
    max_records: int,
) -> str:
    n = max_records
    while n >= 0:
        envelope = build_tool_result_envelope(
            function_name, payload, max_records=n
        )
        envelope["truncated"] = True
        envelope["note"] = _TRUNCATION_NOTE_FA
        text = _dumps(envelope)
        if len(text) <= max_chars:
            return text
        if n == 0:
            break
        n = max(0, n // 2) if n > 1 else 0

    records, list_key = extract_record_list(payload)
    omitted = _total_count(payload, records, list_key)
    fallback = {
        "_envelope": TOOL_RESULT_ENVELOPE_VERSION,
        "ok": True,
        "tool": function_name,
        "records": [],
        "summary": _keep_scalars(payload) if isinstance(payload, dict) else {},
        "citations": [],
        "truncated": True,
        "omitted_count": omitted,
        "note": _TRUNCATION_NOTE_FA,
    }
    if isinstance(fallback["summary"], dict):
        fallback["summary"]["total"] = omitted
    text = _dumps(fallback)
    if len(text) <= max_chars:
        return text
    return _dumps(
        {
            "_envelope": TOOL_RESULT_ENVELOPE_VERSION,
            "ok": True,
            "tool": function_name,
            "truncated": True,
            "note": _TRUNCATION_NOTE_FA,
        }
    )


def iter_tool_payloads(
    function_results: Optional[Dict[str, Any]],
) -> Iterable[Tuple[str, Any]]:
    if not function_results:
        return
    for key, entry in function_results.items():
        if str(key).startswith("_"):
            continue
        if isinstance(entry, dict) and "result" in entry:
            yield str(entry.get("name") or key), entry.get("result")
        else:
            yield str(key), entry
