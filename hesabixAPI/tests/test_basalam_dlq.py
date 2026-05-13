"""تست‌های سبک برای صف مردهٔ سینک باسلام (بدون DB)."""

from __future__ import annotations

from app.services import basalam_integration_service as bas


def test_normalize_sync_dead_letter_filters_invalid_entries() -> None:
    prev = bas._default_settings()
    out = bas._normalize_settings({"sync_dead_letter": [{"ok": True}, "bad", 99]}, prev)
    assert out["sync_dead_letter"] == [{"ok": True}]


def test_payment_dlq_status_constants_include_manual_review() -> None:
    assert "manual_review_required" in bas._PAYMENT_DLQ_STATUSES
    assert "payment_exceeds_invoice_remaining" in bas._PAYMENT_DLQ_STATUSES
    assert "payment_invoice_already_settled" in bas._PAYMENT_DLQ_STATUSES
