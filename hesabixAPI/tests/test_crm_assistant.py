"""فهرست سفید، دروازه امتیاز و جمله وظیفه، بدون پایگاه داده."""
from datetime import datetime

from app.services.crm_assistant import (
    PREDICTIVE_CLOSED_DEAL_GATE,
    parse_task_sentence,
    predictive_from_counts,
    whitelist_financial_answer,
)


def test_financial_answer_keeps_only_whitelisted_fields():
    answer = whitelist_financial_answer(
        {
            "balance": 10,
            "status": "بدهکار",
            "sales_total": 20,
            "bank_account": "secret",
            "extra_info": {"token": "x"},
            "repeat_products": [{"product_name": "کالا", "invoice_count": 2, "unit_cost": 9, "last_document_date": "2026-01-01"}],
            "next_action": {"code": "open_invoice", "title": "وصول", "reason": "مانده دارد", "internal_id": 4},
            "predictive": {"available": False, "score": None, "reason": "closed_deal_volume", "closed_deals": 3, "required": 200},
        }
    )
    assert "bank_account" not in answer
    assert "extra_info" not in answer
    assert answer["repeat_products"] == [{"product_name": "کالا", "invoice_count": 2, "last_document_date": "2026-01-01"}]
    assert answer["next_action"] == {"code": "open_invoice", "title": "وصول", "reason": "مانده دارد"}
    assert answer["posted_document"] is False


def test_predictive_score_stays_closed_until_volume_gate():
    blocked = predictive_from_counts(closed_deals=PREDICTIVE_CLOSED_DEAL_GATE - 1, business_won=10, stage_closed=50, stage_won=25)
    assert blocked["available"] is False
    assert blocked["score"] is None
    assert blocked["reason"] == "closed_deal_volume"
    opened = predictive_from_counts(closed_deals=200, business_won=50, stage_closed=20, stage_won=5)
    assert opened["available"] is True
    assert opened["score"] == 25
    assert opened["basis"] == "stage"


def test_task_sentence_extracts_due_day_and_does_not_create_anything():
    draft = parse_task_sentence("فردا با علی تماس بگیر", datetime(2026, 11, 10, 9, 0, 0))
    assert draft["subject"] == "با علی تماس بگیر"
    assert draft["due_at"].startswith("2026-11-11")
    assert draft["is_task"] is True
    assert "posted" not in draft
