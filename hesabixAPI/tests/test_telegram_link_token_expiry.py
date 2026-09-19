from __future__ import annotations

from datetime import date, datetime, timedelta

from adapters.api.v1.integrations.telegram import _is_link_token_expired, _to_utc_datetime


def test_to_utc_datetime_from_date():
	result = _to_utc_datetime(date(2026, 7, 24))
	assert result.year == 2026
	assert result.month == 7
	assert result.day == 24
	assert result.tzinfo is not None


def test_is_link_token_expired_with_date_column():
	today = date.today()
	assert _is_link_token_expired(today) is False
	assert _is_link_token_expired(today - timedelta(days=1)) is True


def test_is_link_token_expired_with_datetime_column():
	future = datetime.utcnow() + timedelta(minutes=10)
	past = datetime.utcnow() - timedelta(minutes=10)
	assert _is_link_token_expired(future) is False
	assert _is_link_token_expired(past) is True
