"""تست شمارندهٔ درون‌پردازه‌ای متریک (OBS-02)."""
from __future__ import annotations

from app.services.ai.ai_ops_metrics import log_ai_event, metric_snapshot, reset_metrics_for_tests


def test_log_ai_event_increments_counter() -> None:
    reset_metrics_for_tests()
    log_ai_event("usage_logged", extra={"model": "x"})
    log_ai_event("usage_logged")
    log_ai_event("context_llm_summarized")
    snap = metric_snapshot()
    assert snap["usage_logged"] == 2
    assert snap["context_llm_summarized"] == 1
    reset_metrics_for_tests()
    assert metric_snapshot() == {}
