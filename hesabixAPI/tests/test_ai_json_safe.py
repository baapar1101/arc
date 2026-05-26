"""تست سریال‌سازی JSON برای استریم AI."""
from datetime import date, datetime
from decimal import Decimal

from app.core.json_safe import json_dumps_safe, json_safe_value


def test_json_safe_datetime_and_decimal():
    payload = {
        "document_date": datetime(2026, 5, 26, 12, 0, 0),
        "due": date(2026, 6, 1),
        "amount": Decimal("1500.50"),
    }
    safe = json_safe_value(payload)
    assert safe["document_date"] == "2026-05-26T12:00:00"
    assert safe["due"] == "2026-06-01"
    assert safe["amount"] == 1500.5
    json_dumps_safe(payload)  # must not raise
