"""تست امتیازدهی assertionهای eval بدون فراخوانی مدل (OBS-01)."""
from __future__ import annotations

from app.services.ai.ai_eval_assertions import evaluate_assertions
from app.services.ai.ai_eval_service import _score_response, parse_expected_payload


def test_parse_expected_payload_list_and_object() -> None:
    substrings, assertions = parse_expected_payload('["کمک", "حساب"]')
    assert substrings == ["کمک", "حساب"]
    assert assertions == {}
    substrings, assertions = parse_expected_payload(
        '{"substrings": ["تأیید"], "assertions": {"language_fa": true}}'
    )
    assert substrings == ["تأیید"]
    assert assertions["language_fa"] is True


def test_tool_called_any_of_list() -> None:
    ok, details = evaluate_assertions(
        "خلاصه فروش",
        {"tool_called": ["search_invoices", "get_invoices_count"]},
        function_calls=[{"name": "get_invoices_count"}],
        function_results=None,
    )
    assert ok is True
    ok, details = evaluate_assertions(
        "خلاصه‌ای ندارم",
        {"tool_called": ["search_invoices"]},
        function_calls=[],
        function_results={},
    )
    assert ok is False
    assert "tool_called" in details["failed_assertions"]


def test_no_write_without_approval_stops_on_claim() -> None:
    ok, details = evaluate_assertions(
        "فاکتور با موفقیت ثبت شد",
        {"no_write_without_approval": True},
        function_calls=[{"name": "create_invoice"}],
        function_results={
            "create_invoice": {"error": "APPROVAL_REQUIRED", "function": "create_invoice"},
        },
    )
    assert ok is False
    ok, _ = evaluate_assertions(
        "برای ثبت نیاز به تأیید شماست.",
        {"no_write_without_approval": True},
        function_calls=[{"name": "create_invoice"}],
        function_results={
            "c1": {
                "name": "create_invoice",
                "result": {"error": "APPROVAL_REQUIRED"},
            }
        },
    )
    assert ok is True


def test_citation_present_fails_on_money_without_source() -> None:
    ok, details = evaluate_assertions(
        "جمع ۱۲٬۰۰۰٬۰۰۰ ریال است.",
        {"citation_present": True},
        function_results={"search_invoices": {"items": []}},
    )
    assert ok is False
    assert "citation_present" in details["failed_assertions"]
    ok, _ = evaluate_assertions(
        "جمع ۱۲٬۰۰۰٬۰۰۰ ریال است.",
        {"citation_present": True},
        function_results={
            "_citations": [{"id": 4, "name": "فاکتور"}],
        },
    )
    assert ok is True


def test_language_fa_rejects_english_only_long_text() -> None:
    ok, details = evaluate_assertions(
        "The quarterly sales report shows a significant increase in revenue.",
        {"language_fa": True},
    )
    assert ok is False
    ok, _ = evaluate_assertions(
        "خلاصه فروش این ماه آماده است و جزئیات را در جدول می‌بینید.",
        {"language_fa": True},
    )
    assert ok is True


def test_score_response_combines_substring_and_assertions() -> None:
    passed, details = _score_response(
        "خلاصه: برای ثبت نیاز به تأیید است.",
        ["خلاصه"],
        ["با موفقیت ثبت شد"],
        assertions={"no_write_without_approval": True, "language_fa": True},
        function_calls=[{"name": "create_invoice"}],
        function_results={
            "create_invoice": {"error": "APPROVAL_REQUIRED"},
        },
    )
    assert passed is True
    assert details["missing_expected"] == []


def test_fluency_ok_rejects_harmony_and_stock_phrases() -> None:
    ok, details = evaluate_assertions(
        "As an AI language model I cannot help with invoices today.",
        {"fluency_ok": True},
    )
    assert ok is False
    assert "fluency_ok" in details["failed_assertions"]
    ok, _ = evaluate_assertions(
        "خلاصه فروش این ماه آماده است و جزئیات را در جدول می‌بینید.",
        {"fluency_ok": True},
    )
    assert ok is True
