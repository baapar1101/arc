"""پارس احتمال CRM بدون fallback ساختگی ۵۰."""
from __future__ import annotations

from app.services.ai.ai_crm_parse import parse_probability_percent


def test_parse_plain_number():
    assert parse_probability_percent("75") == 75


def test_parse_persian_digits_and_percent():
    assert parse_probability_percent("احتمال حدود ۷۵٪ است") == 75


def test_parse_unparseable_returns_none_not_fifty():
    assert parse_probability_percent("نمی‌دانم") is None
    assert parse_probability_percent("") is None
    assert parse_probability_percent(None) is None


def test_parse_does_not_invent_fifty_on_prose():
    assert parse_probability_percent("فرصت خوبی است اما عدد دقیقی ندارم") is None


def test_parse_zero_is_valid():
    assert parse_probability_percent("0") == 0
    assert parse_probability_percent("احتمال صفر است 0 درصد") == 0
