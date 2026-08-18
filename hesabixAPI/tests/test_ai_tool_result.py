"""تست قرارداد envelope نتیجهٔ ابزار (TOOL-04)."""
from __future__ import annotations

import json

from app.services.ai.ai_citation_service import build_citation_context
from app.services.ai.ai_tool_result import (
    compact_tool_result_for_llm,
    extract_record_list,
)


def test_small_list_keeps_original_key_and_valid_json() -> None:
    payload = {
        "items": [
            {"id": 1, "name": "الف", "amount": 10},
            {"id": 2, "name": "ب", "amount": 20},
        ],
        "total": 2,
    }
    text = compact_tool_result_for_llm("search_invoices", payload)
    data = json.loads(text)
    assert data["items"][0]["name"] == "الف"
    assert data.get("truncated") is not True


def test_large_list_uses_envelope_not_mid_json_cut() -> None:
    items = [
        {"id": i, "name": f"مشتری-{i}", "amount": i * 1000}
        for i in range(1, 80)
    ]
    payload = {"items": items, "pagination": {"total": 79}}
    text = compact_tool_result_for_llm("search_persons", payload, max_chars=2500)
    data = json.loads(text)
    assert data["_envelope"] == 1
    assert data["truncated"] is True
    assert data["omitted_count"] > 0
    assert data["summary"]["total"] == 79
    assert "نتیجه کوتاه شده" in data["note"]
    kept = data.get("items") or data.get("records")
    assert isinstance(kept, list)
    assert len(kept) < 79
    assert len(text) <= 2500


def test_huge_dict_without_list_stays_valid_json() -> None:
    payload = {"blob": "x" * 9000, "message": "گزارش آماده است"}
    text = compact_tool_result_for_llm("get_report", payload, max_chars=800)
    data = json.loads(text)
    assert data.get("truncated") is True
    assert "…" not in text[-5:] or data.get("_envelope") == 1


def test_error_compact_keeps_hint_and_expected_args() -> None:
    payload = {
        "ok": False,
        "error": "INVALID_ARGUMENTS",
        "message": "پارامتر ناقص است",
        "message_fa": "پارامتر ناقص است",
        "hint_fa": "items را بفرست",
        "retryable": True,
        "expected_args": ["items"],
        "tool": "create_session_plan",
    }
    text = compact_tool_result_for_llm("create_session_plan", payload)
    data = json.loads(text)
    assert data["hint_fa"] == "items را بفرست"
    assert data["expected_args"] == ["items"]
    assert data["retryable"] is True


def test_approval_required_passthrough() -> None:
    payload = {
        "error": "APPROVAL_REQUIRED",
        "function": "create_invoice",
        "message": "نیاز به تأیید",
    }
    text = compact_tool_result_for_llm("create_invoice", payload)
    data = json.loads(text)
    assert data["error"] == "APPROVAL_REQUIRED"


def test_citation_prefers_envelope_citations() -> None:
    results = {
        "tc1": {
            "name": "search_invoices",
            "result": {
                "_envelope": 1,
                "citations": [{"id": 44, "name": "فاکتور بهار", "amount": 120000}],
                "items": [{"id": 44, "name": "فاکتور بهار"}],
            },
        }
    }
    text = build_citation_context(results)
    assert "فاکتور بهار" in text
    assert "#44" in text


def test_extract_record_list_from_bare_array() -> None:
    records, key = extract_record_list([{"id": 1, "name": "a"}])
    assert key == "items"
    assert records[0]["id"] == 1
