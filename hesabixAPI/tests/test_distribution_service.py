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


def test_user_and_person_label_helpers_exist():
	from app.services.distribution_documents import person_label, user_label

	assert callable(user_label)
	assert callable(person_label)


def test_extend_settings_defaults():
	from app.services.distribution_phase3_service import extend_settings_dict

	d = extend_settings_dict(None)
	assert d["enable_van_sales"] is False
	assert d["geofence_radius_meters"] == 0
	assert d["visit_checklist_template"] == []


def test_period_bounds_month():
	from datetime import date
	from app.services.distribution_phase4_service import _period_bounds, _normalize_period_start, _compute_variance

	start, end = _period_bounds("month", date(2026, 9, 15))
	assert start == date(2026, 9, 1)
	assert end == date(2026, 9, 30)
	assert _normalize_period_start("month", date(2026, 9, 15)) == date(2026, 9, 1)
	assert _compute_variance(1000, 800, 100, 50, 50, 0) == 0.0
	assert _compute_variance(1000, 900, 0, 0, 0, 50) == -150.0


def test_allocation_person_lines():
	from types import SimpleNamespace
	from app.services.distribution_phase4_service import _build_allocation_person_lines

	row = SimpleNamespace(
		visit_snapshot=[
			{"status": "completed", "outcome": "order", "person_id": 1, "document_id": 10, "amount": 600, "person_name": "A"},
			{"status": "completed", "outcome": "order", "person_id": 2, "document_id": 11, "amount": 400, "person_name": "B"},
		]
	)
	lines = _build_allocation_person_lines(row, 1000, None)
	assert len(lines) == 2
	assert abs(sum(l["amount"] for l in lines) - 1000) < 0.02
	assert lines[0]["extra_info"]["invoice_id"] == 10


def test_build_invoice_lines_tax_helpers_exist():
	from app.services.distribution_documents import build_invoice_lines, create_distribution_invoice

	assert callable(build_invoice_lines)
	assert callable(create_distribution_invoice)


def test_finalize_proforma_helper_exists():
	from app.services.distribution_documents import finalize_distribution_proforma_invoice

	assert callable(finalize_distribution_proforma_invoice)


def test_commercial_ops_helpers_exist():
	from app.services.distribution_commercial_service import (
		apply_promotions_to_lines,
		confirm_visit_order,
		complete_delivery_stop,
		list_shelf_audits,
		start_delivery_trip,
	)

	assert callable(apply_promotions_to_lines)
	assert callable(confirm_visit_order)
	assert callable(complete_delivery_stop)
	assert callable(list_shelf_audits)
	assert callable(start_delivery_trip)


def test_offline_sync_supports_presell_composite():
	import inspect
	from app.services.distribution_phase3_service import process_offline_sync

	src = inspect.getsource(process_offline_sync)
	assert "complete_visit_with_presell" in src
	assert "create_presell_order" in src
