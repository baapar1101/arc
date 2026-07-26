"""تست‌های فاز ۹ HScript — مجوز، زمان‌بندی، cron."""

from __future__ import annotations

from datetime import datetime, timezone

from app.core.hscript_permissions import permissions_allow_hscript
from app.services.hscript_schedule_service import (
	compute_next_run_at,
	resolve_cron,
	_normalize_payload,
)
from adapters.db.models.hscript_report import HScriptReportSchedule


def test_permissions_legacy_fallback():
	perms = {"reports": {"view": True, "export": True}}
	assert permissions_allow_hscript(perms, "view") is True
	assert permissions_allow_hscript(perms, "write") is True
	assert permissions_allow_hscript(perms, "export") is True
	assert permissions_allow_hscript({"reports": {"view": True}}, "export") is False


def test_permissions_hscript_section_wins():
	perms = {
		"reports": {"view": True, "export": True},
		"hscript": {"view": True, "write": False, "export": False, "publish": False, "schedule": True},
	}
	assert permissions_allow_hscript(perms, "view") is True
	assert permissions_allow_hscript(perms, "write") is False
	assert permissions_allow_hscript(perms, "export") is False
	assert permissions_allow_hscript(perms, "schedule") is True


def test_normalize_simple_daily_schedule():
	norm = _normalize_payload(
		{
			"title": "صبح",
			"enabled": True,
			"schedule_mode": "simple",
			"simple_repeat": "daily",
			"simple_time": "08:30",
			"output_format": "pdf",
			"channels": ["inapp", "email"],
			"timezone": "Asia/Tehran",
		}
	)
	assert norm["schedule_mode"] == "simple"
	probe = HScriptReportSchedule(
		business_id=1,
		report_id=1,
		schedule_mode=norm["schedule_mode"],
		simple_repeat=norm["simple_repeat"],
		simple_time=norm["simple_time"],
		simple_weekday=norm.get("simple_weekday"),
		simple_interval=norm.get("simple_interval"),
		cron_expression=norm.get("cron_expression"),
		timezone=norm["timezone"],
		enabled=True,
	)
	cron = resolve_cron(probe)
	assert cron == "30 8 * * *"
	nxt = compute_next_run_at(
		enabled=True,
		cron_expr=cron,
		timezone_name="Asia/Tehran",
		from_utc=datetime(2026, 7, 26, 3, 0, tzinfo=timezone.utc),
	)
	assert nxt is not None
	assert nxt > datetime(2026, 7, 26, 3, 0, tzinfo=timezone.utc)


def test_plan_includes_max_schedules():
	from app.services.hscript.plan_limits import _TIER_LIMITS

	assert _TIER_LIMITS["free"]["max_schedules"] == 2
	assert _TIER_LIMITS["monthly"]["max_schedules"] >= 10
