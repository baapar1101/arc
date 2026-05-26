"""تست امتیازدهی ارزیابی AI."""
from __future__ import annotations

from app.services.ai.ai_eval_service import _score_response


def test_score_response_pass():
    ok, details = _score_response(
        "خلاصه فروش هفتگی: مبلغ خالص ۱۰ میلیون",
        expected=["فروش", "خلاصه"],
        forbidden=["نمی‌دانم"],
    )
    assert ok is True
    assert details["missing_expected"] == []


def test_score_response_fail_missing():
    ok, details = _score_response("سلام", expected=["فاکتور"], forbidden=[])
    assert ok is False
    assert "فاکتور" in details["missing_expected"]
