"""تست تحلیل بازخورد."""
from __future__ import annotations

from unittest.mock import MagicMock

from app.services.ai.ai_feedback_analytics_service import get_feedback_analytics


def test_empty_feedback_analytics():
    db = MagicMock()
    db.query.return_value.join.return_value.join.return_value.filter.return_value.all.return_value = []
    db.query.return_value.join.return_value.join.return_value.filter.return_value.group_by.return_value.order_by.return_value.all.return_value = []

    data = get_feedback_analytics(db, business_id=1, days=30)
    assert data["summary"]["total"] == 0
    assert data["summary"]["satisfaction_rate_percent"] is None
