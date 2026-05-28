"""تست منطق افزونه پخش مویرگی."""

from __future__ import annotations

from datetime import date

from app.core.business_calendar import business_today
from app.services.distribution_geo import check_geofence, haversine_meters
from app.services.distribution_service import _weekday_matches


def test_weekday_matches_none_means_any_day():
	assert _weekday_matches(date(2026, 5, 28), None) is True


def test_weekday_matches_iso_weekday():
	# 2026-05-28 is Thursday -> weekday() == 3
	assert _weekday_matches(date(2026, 5, 28), 3) is True
	assert _weekday_matches(date(2026, 5, 28), 0) is False


def test_business_today_returns_date():
	today = business_today(1)
	assert isinstance(today, date)


def test_haversine_same_point_is_zero():
	assert haversine_meters(35.7, 51.4, 35.7, 51.4) == 0.0


def test_check_geofence_disabled_when_radius_zero():
	ok, dist, msg = check_geofence(35.0, 51.0, 35.1, 51.1, 0, True)
	assert ok is True
	assert dist is None
	assert msg == ""


def test_check_geofence_rejects_far_visit():
	ok, dist, msg = check_geofence(35.7000, 51.4000, 35.7100, 51.4100, 50, True)
	assert ok is False
	assert dist is not None and dist > 50
	assert "متر" in msg
