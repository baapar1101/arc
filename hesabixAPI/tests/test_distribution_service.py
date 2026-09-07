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
	assert d["map_tile_source"] == "osm"
	assert d["memaps_api_key"] is None
	assert d["share_live_location"] is True


def test_business_day_utc_bounds_covers_local_noon():
	from datetime import datetime, time
	from zoneinfo import ZoneInfo

	from app.core.business_calendar import business_day_utc_bounds, business_timezone_name

	day = date(2026, 9, 7)
	start, end = business_day_utc_bounds(None, day)
	tz = ZoneInfo(business_timezone_name(None))
	local_noon = datetime.combine(day, time(12, 0), tzinfo=tz).astimezone(ZoneInfo("UTC")).replace(tzinfo=None)
	assert start <= local_noon <= end
	assert (end - start).total_seconds() >= 23 * 3600


def test_presence_from_age_buckets():
	from datetime import datetime, timedelta

	from app.services.distribution_phase3_service import _presence_from_age

	now = datetime.utcnow()
	assert _presence_from_age(None) == "none"
	assert _presence_from_age(now) == "online"
	assert _presence_from_age(now - timedelta(minutes=5)) == "recent"
	assert _presence_from_age(now - timedelta(hours=2)) == "stale"
	assert _presence_from_age(now - timedelta(days=2)) == "offline"


def test_normalize_map_tile_source():
	from app.services.distribution_phase3_service import normalize_map_tile_source

	assert normalize_map_tile_source("osm") == "osm"
	assert normalize_map_tile_source("MEMAPS") == "memaps"
	assert normalize_map_tile_source("google") == "osm"
	assert normalize_map_tile_source(None) == "osm"


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


def test_stop_due_on_frequencies():
	from datetime import date
	from app.services.distribution_field_ops_service import stop_due_on, week_of_month, iso_week_parity

	thursday = date(2026, 9, 10)  # weekday 3
	assert stop_due_on(thursday, weekday=3, frequency="weekly") is True
	assert stop_due_on(thursday, weekday=2, frequency="weekly") is False
	assert iso_week_parity(thursday) in (0, 1)
	off = iso_week_parity(thursday)
	assert stop_due_on(thursday, weekday=3, frequency="biweekly", cycle_offset=off) is True
	assert stop_due_on(thursday, weekday=3, frequency="biweekly", cycle_offset=1 - off) is False
	assert week_of_month(date(2026, 9, 1)) == 0
	assert week_of_month(date(2026, 9, 10)) == 1
	assert stop_due_on(date(2026, 9, 10), weekday=3, frequency="monthly", cycle_offset=1) is True


def test_perfect_store_score_weights():
	from app.services.distribution_field_ops_service import perfect_store_score

	assert perfect_store_score(None) is None
	score = perfect_store_score({
		"osa": True,
		"shelf_facing": True,
		"price_tag": True,
		"planogram": False,
		"share_of_shelf": 50,
	})
	assert score is not None
	assert 70 <= score <= 85


def test_reason_catalog_codes():
	from app.services.distribution_field_ops_service import reason_catalog

	c = reason_catalog()
	assert any(r["code"] == "closed" for r in c["no_order"])
	assert any(r["code"] == "expired" for r in c["return"])
	assert "weekly" in c["frequencies"]


def test_extend_settings_has_field_ops_flags():
	from app.services.distribution_phase3_service import extend_settings_dict

	d = extend_settings_dict(None)
	assert d["carry_over_missed_visits"] is True
	assert d["nav_provider"] == "neshan"
	assert d["auto_apply_promotions"] is True
	assert d["require_pod_signature"] is False


def test_previous_due_dates_weekly_lookback():
	from datetime import date
	from app.services.distribution_field_ops_service import previous_due_dates

	thursday = date(2026, 9, 10)
	prev = previous_due_dates(thursday, weekday=3, frequency="weekly", cycle_offset=0, lookback_days=14)
	assert date(2026, 9, 3) in prev
	assert date(2026, 8, 27) in prev
	assert date(2026, 9, 4) not in prev


def test_foc_appends_zero_price_free_line():
	import inspect
	from app.services.distribution_commercial_service import apply_promotions_to_lines

	src = inspect.getsource(apply_promotions_to_lines)
	assert "foc_lines.append" in src
	assert "is_foc" in src
	assert "unit_price" in src
	assert "out.extend(foc_lines)" in src


def test_commission_uses_collection_and_coverage():
	import inspect
	from app.services.distribution_commercial_service import compute_commission_run

	src = inspect.getsource(compute_commission_run)
	assert "on_collection" in src
	assert "coverage_factor" in src
	assert "collected_amount" in src


def test_confirm_load_plan_accepts_actual_lines():
	import inspect
	from app.services.distribution_commercial_service import confirm_load_plan

	src = inspect.getsource(confirm_load_plan)
	assert "actual_lines" in src
	assert "variance_qty" in src
	assert "loaded_qty" in src


def test_consume_van_lots_fefo_empty_when_no_lots():
	from types import SimpleNamespace
	from app.services.distribution_field_ops_service import consume_van_lots_fefo

	class _Q:
		def filter(self, *a, **k):
			return self

		def order_by(self, *a, **k):
			return self

		def all(self):
			return []

	db = SimpleNamespace(query=lambda *a, **k: _Q())
	assert consume_van_lots_fefo(db, 1, 2, 5) == []

