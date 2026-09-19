"""تست‌های منطقهٔ زمانی و فرمت تاریخ/زمان."""

from __future__ import annotations

from datetime import datetime, timezone
from types import SimpleNamespace

import pytest

from app.core.datetime_utils import (
	business_wall_clock_now,
	export_filename_timestamp,
	format_generated_at_for_pdf,
	localize_assumed_utc_naive_for_display,
	resolve_calendar_type_for_request,
	utc_naive_to_iso_z,
	utc_now_aware,
)
from app.core.responses import format_datetime_fields


class _FakeRequest:
	def __init__(self, calendar_type: str = "jalali", business_id: int | None = None):
		self.state = SimpleNamespace(calendar_type=calendar_type, business_id=business_id)
		self.headers: dict[str, str] = {}


def test_utc_naive_to_iso_z_appends_z_suffix() -> None:
	dt = datetime(2025, 7, 9, 14, 0, 0)
	assert utc_naive_to_iso_z(dt) == "2025-07-09T14:00:00Z"


def test_utc_naive_to_iso_z_handles_aware_utc() -> None:
	dt = datetime(2025, 7, 9, 14, 0, 0, tzinfo=timezone.utc)
	assert utc_naive_to_iso_z(dt) == "2025-07-09T14:00:00Z"


def test_localize_assumed_utc_to_tehran_adds_offset() -> None:
	utc = datetime(2025, 7, 9, 14, 0, 0)
	local = localize_assumed_utc_naive_for_display(utc, "Asia/Tehran")
	assert local.hour == 17
	assert local.minute == 30


def test_format_datetime_fields_raw_is_utc_z_and_display_is_jalali() -> None:
	req = _FakeRequest(calendar_type="jalali", business_id=None)
	payload = {"registered_at": datetime(2025, 7, 9, 14, 0, 0), "business_id": 1}
	out = format_datetime_fields(payload, req, business_id=1)
	assert out["registered_at_raw"] == "2025-07-09T14:00:00Z"
	assert str(out["registered_at"]).startswith("1404/")
	assert "17:30" in str(out["registered_at"])


def test_format_datetime_fields_parses_iso_string_registered_at() -> None:
	req = _FakeRequest(calendar_type="gregorian")
	payload = {"registered_at": "2025-07-09T14:00:00Z"}
	out = format_datetime_fields(payload, req)
	assert out["registered_at_raw"] == "2025-07-09T14:00:00Z"
	assert "2025-07-09" in str(out["registered_at"])


def test_resolve_calendar_type_from_request_header() -> None:
	req = _FakeRequest()
	req.state.calendar_type = None
	req.headers["X-Calendar-Type"] = "gregorian"
	assert resolve_calendar_type_for_request(req, is_fa=True) == "gregorian"


def test_format_generated_at_for_pdf_uses_business_timezone(monkeypatch: pytest.MonkeyPatch) -> None:
	monkeypatch.setattr(
		"app.core.business_calendar.business_now",
		lambda business_id=None: datetime(2025, 7, 9, 17, 30, 0),
	)
	display = format_generated_at_for_pdf(1, "gregorian")
	assert "2025-07-09" in display
	assert "17:30" in display


def test_export_filename_timestamp_format(monkeypatch: pytest.MonkeyPatch) -> None:
	monkeypatch.setattr(
		"app.core.business_calendar.business_now",
		lambda business_id=None: datetime(2025, 7, 9, 17, 30, 45),
	)
	assert export_filename_timestamp(1) == "20250709_173045"


def test_utc_now_aware_is_timezone_aware() -> None:
	now = utc_now_aware()
	assert now.tzinfo is not None
	assert now.tzinfo == timezone.utc


def test_business_wall_clock_now_is_naive(monkeypatch: pytest.MonkeyPatch) -> None:
	monkeypatch.setattr(
		"app.core.business_calendar.business_now",
		lambda business_id=None: datetime(2025, 7, 9, 17, 30, 0, tzinfo=timezone.utc),
	)
	wall = business_wall_clock_now(1)
	assert wall.tzinfo is None
	assert wall.hour == 17
