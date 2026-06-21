"""تست‌های تبدیل تاریخ برای AI و date_input."""
from __future__ import annotations

from datetime import date

import pytest

from app.core.date_input import (
    DateParseError,
    format_user_date,
    jalali_month_range,
    normalize_date_range,
    parse_user_date,
)
from app.services.ai.ai_date_resolver import (
    normalize_query_dates,
    resolve_relative_date_range,
)


def test_parse_jalali_slash_format():
    d = parse_user_date("1403/01/01", calendar_type="jalali")
    assert d == date(2024, 3, 20)


def test_parse_gregorian_iso():
    d = parse_user_date("2024-03-20", calendar_type="gregorian")
    assert d == date(2024, 3, 20)


def test_parse_invalid_raises():
    with pytest.raises(DateParseError):
        parse_user_date("not-a-date", calendar_type="jalali")


def test_normalize_date_range_order():
    with pytest.raises(ValueError):
        normalize_date_range("1403/02/01", "1403/01/01", calendar_type="jalali")


def test_jalali_month_range_farvardin_1403():
    start, end = jalali_month_range(1403, 1)
    assert start == date(2024, 3, 20)
    assert end == date(2024, 4, 19)


def test_resolve_relative_last_month_jalali():
    resolved = resolve_relative_date_range("last_month", calendar_type="jalali", business_id=1)
    assert resolved.from_date <= resolved.to_date
    payload = resolved.to_dict()
    assert payload["from_date_display"]
    assert payload["to_date_display"]


def test_normalize_query_dates_flat_and_alias():
    q = normalize_query_dates(
        {"date_from": "1403/01/01", "date_to": "1403/01/31"},
        calendar_type="jalali",
        entity="invoice",
    )
    assert q["from_date"] == "2024-03-20"
    assert q["to_date"] == "2024-04-19"
    assert "date_from" not in q


def test_normalize_query_dates_advanced_filter():
    q = normalize_query_dates(
        {
            "filters": [
                {"property": "document_date", "operator": ">=", "value": "1403/01/01"},
            ]
        },
        calendar_type="jalali",
        entity="invoice",
    )
    assert q["filters"][0]["value"] == "2024-03-20"


def test_format_user_date_jalali():
    text = format_user_date(date(2024, 3, 20), calendar_type="jalali")
    assert text == "1403/01/01"
