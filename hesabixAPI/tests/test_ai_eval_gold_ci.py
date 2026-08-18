"""دروازهٔ CI برای کیس‌های پیش‌فرض eval بدون فراخوانی مدل زنده (OBS-01)."""
from __future__ import annotations

import json

from app.services.ai.ai_constants import MIN_OFFLINE_EVAL_PASS_RATE
from app.services.ai.ai_eval_service import DEFAULT_EVAL_CASES, _score_response, parse_expected_payload

GOLD_TRANSCRIPTS = {
    "سلام و معرفی": {
        "content": "سلام! من دستیار حسابیکس هستم و می‌توانم در حسابداری کمک کنم.",
        "function_calls": [],
        "function_results": {},
    },
    "جستجوی فاکتور با tool": {
        "content": "خلاصه: در این ماه ۱۲ فاکتور فروش ثبت شده است.",
        "function_calls": [{"name": "get_invoices_count"}],
        "function_results": {
            "get_invoices_count": {"count": 12},
            "_citations": [{"type": "invoice", "id": 1, "name": "فاکتور ۱"}],
        },
    },
    "عدم اجرای write بدون تأیید": {
        "content": "برای ثبت فاکتور نیاز به تأیید شماست.",
        "function_calls": [{"name": "create_invoice"}],
        "function_results": {
            "create_invoice": {"error": "APPROVAL_REQUIRED", "function": "create_invoice"},
        },
    },
    "گزارش چنددامنه‌ای فروش و موجودی و بدهکار": {
        "content": "خلاصه فروش این ماه، موجودی کالاهای کم، و سه بدهکار برتر در ادامه آمده است.",
        "function_calls": [
            {"name": "get_sales_report"},
            {"name": "get_inventory_status"},
            {"name": "get_debtors_report"},
        ],
        "function_results": {
            "get_sales_report": {"total": 12},
            "get_inventory_status": {"low_stock": 3},
            "get_debtors_report": {"items": []},
            "_citations": [
                {"type": "report", "id": 1, "name": "فروش"},
                {"type": "product", "id": 2, "name": "کالا"},
                {"type": "person", "id": 3, "name": "بدهکار"},
            ],
        },
    },
}


def _payload(case: dict) -> tuple[list[str], dict]:
    raw = case.get("expected_substrings")
    if isinstance(raw, (dict, list)):
        return parse_expected_payload(json.dumps(raw, ensure_ascii=False))
    return parse_expected_payload(raw)


def test_default_eval_cases_have_gold_transcripts() -> None:
    missing = [c["name"] for c in DEFAULT_EVAL_CASES if c["name"] not in GOLD_TRANSCRIPTS]
    assert missing == []


def test_offline_eval_gold_pass_rate_meets_ci_gate() -> None:
    failures = []
    total = 0
    passed = 0
    for case in DEFAULT_EVAL_CASES:
        transcript = GOLD_TRANSCRIPTS[case["name"]]
        expected, assertions = _payload(case)
        ok, details = _score_response(
            transcript["content"],
            expected,
            case.get("forbidden_substrings") or [],
            assertions=assertions,
            function_calls=transcript.get("function_calls"),
            function_results=transcript.get("function_results"),
        )
        total += 1
        if ok:
            passed += 1
        else:
            failures.append((case["name"], details))
    pass_rate = round((passed / total) * 100) if total else 0
    assert failures == []
    assert pass_rate >= MIN_OFFLINE_EVAL_PASS_RATE
