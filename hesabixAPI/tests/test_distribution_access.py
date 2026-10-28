"""تست ایزوله بودن منابع پخش بین ویزیتورها."""

from __future__ import annotations

import pytest

from app.core.responses import ApiError
from app.services.distribution_service import (
	_assert_owner_or_access,
	_can_manage_distribution,
	_can_see_full_distribution_catalog,
	_can_see_team_distribution,
	_redact_settings_secrets,
	_scope_visit_user_id,
	date_ranges_overlap,
	merge_date_ranges,
	workspace_for_ctx,
)


class FakeCtx:
	def __init__(self, uid, *, superadmin=False, owner=False, perms=()):
		self._uid = uid
		self._super = superadmin
		self._owner = owner
		self._perms = set(perms)
		self.db = object() if owner else None

	def get_user_id(self):
		return self._uid

	def is_superadmin(self):
		return self._super

	def is_business_owner(self, business_id):
		return self._owner

	def has_business_permission(self, section, action):
		return (section, action) in self._perms


def _visitor(uid=10):
	return FakeCtx(uid, perms={("distribution", "view"), ("distribution", "operate")})


def _reports_team(uid=11):
	return FakeCtx(uid, perms={("distribution", "view"), ("distribution", "reports_team")})


def _manager(uid=12):
	return FakeCtx(uid, perms={("distribution", "view"), ("distribution", "manage")})


def test_visitor_scope_is_self():
	ctx = _visitor(10)
	assert _scope_visit_user_id(ctx, 1) == 10
	assert _can_see_full_distribution_catalog(ctx, 1) is False
	assert _can_manage_distribution(ctx, 1) is False


def test_reports_team_sees_catalog_but_cannot_manage():
	ctx = _reports_team()
	assert _scope_visit_user_id(ctx, 1) == 11
	assert _can_see_full_distribution_catalog(ctx, 1) is False
	assert _can_see_team_distribution(ctx, 1) is True
	assert _can_manage_distribution(ctx, 1) is False
	assert workspace_for_ctx(ctx, 1) == "supervisor"


def test_manager_and_owner_have_full_write():
	assert _can_manage_distribution(_manager(), 1) is True
	assert _can_manage_distribution(FakeCtx(1, owner=True), 1) is True
	assert _can_manage_distribution(FakeCtx(1, superadmin=True), 1) is True


def test_visitor_can_access_own_resource_read_and_write():
	ctx = _visitor(10)
	_assert_owner_or_access(ctx, 1, 10, write=False)
	_assert_owner_or_access(ctx, 1, 10, write=True)


def test_visitor_cannot_read_peer_resource():
	ctx = _visitor(10)
	with pytest.raises(ApiError) as ei:
		_assert_owner_or_access(ctx, 1, 99, write=False, message="no")
	assert ei.value.status_code == 403


def test_visitor_cannot_write_peer_resource():
	ctx = _visitor(10)
	with pytest.raises(ApiError) as ei:
		_assert_owner_or_access(ctx, 1, 99, write=True, message="no")
	assert ei.value.status_code == 403


def test_reports_team_cannot_read_peer_without_territory_scope():
	ctx = _reports_team(11)
	with pytest.raises(ApiError) as ei:
		_assert_owner_or_access(ctx, 1, 99, write=False, message="no")
	assert ei.value.status_code == 403
	with pytest.raises(ApiError) as ei:
		_assert_owner_or_access(ctx, 1, 99, write=True, message="no")
	assert ei.value.status_code == 403


def test_reports_team_can_read_self():
	_assert_owner_or_access(_reports_team(11), 1, 11, write=False)


def test_manager_can_write_peer_resource():
	_assert_owner_or_access(_manager(12), 1, 99, write=True)


def test_settings_redact_memaps_key_for_non_managers():
	raw = {"memaps_api_key": "secret-live-key", "share_live_location": False}
	redacted = _redact_settings_secrets(raw, include_secrets=False)
	assert redacted["memaps_api_key"] is None
	assert redacted["has_memaps_api_key"] is True
	kept = _redact_settings_secrets(raw, include_secrets=True)
	assert kept["memaps_api_key"] == "secret-live-key"
	assert kept["has_memaps_api_key"] is True


def test_new_settings_default_hides_live_location():
	from app.services.distribution_phase3_service import extend_settings_dict

	d = extend_settings_dict(None)
	assert d["share_live_location"] is False
	assert d["exclusive_assignments"] is True
	assert d["exclusive_customer_ownership"] is True
	assert d["require_location_consent"] is True
	assert d["exclusive_territories"] is False
	assert d["lock_published_plans"] is False
	assert d["require_published_plan"] is False


def test_date_ranges_overlap_open_ended():
	from datetime import date

	assert date_ranges_overlap(date(2026, 1, 1), None, date(2026, 2, 1), date(2026, 2, 10)) is True
	assert date_ranges_overlap(date(2026, 1, 1), date(2026, 1, 10), date(2026, 2, 1), date(2026, 2, 10)) is False
	assert date_ranges_overlap(date(2026, 1, 1), date(2026, 1, 31), date(2026, 1, 31), None) is True


def test_merge_date_ranges_extends_open_ended():
	from datetime import date

	assert merge_date_ranges(date(2026, 1, 1), date(2026, 1, 10), date(2026, 1, 5), None) == (
		date(2026, 1, 1),
		None,
	)
	assert merge_date_ranges(date(2026, 1, 5), date(2026, 1, 20), date(2026, 1, 1), date(2026, 1, 10)) == (
		date(2026, 1, 1),
		date(2026, 1, 20),
	)


def test_visitor_workspace_is_field():
	assert workspace_for_ctx(_visitor(10), 1) == "field"
	assert workspace_for_ctx(_manager(12), 1) == "office"


def test_manager_full_catalog_and_team_scope():
	ctx = _manager()
	assert _can_see_full_distribution_catalog(ctx, 1) is True
	assert _can_see_team_distribution(ctx, 1) is True
	assert _scope_visit_user_id(ctx, 1) is None


def test_offline_sync_lookup_includes_user_id():
	import inspect
	from app.services.distribution_phase3_service import process_offline_sync

	src = inspect.getsource(process_offline_sync)
	assert "DistributionOfflineSyncBatch.user_id == user_id" in src
	assert "complete_visit_with_presell" in src


def test_heartbeat_does_not_overwrite_visit_start_coords():
	import inspect
	from app.services.distribution_service import heartbeat_visit

	src = inspect.getsource(heartbeat_visit)
	assert "start_latitude" not in src
	assert "live_tracking_allowed" in src


def test_report_live_location_does_not_overwrite_visit_start_coords():
	import inspect
	from app.services.distribution_commercial_service import report_live_location

	src = inspect.getsource(report_live_location)
	assert "start_latitude" not in src
	assert "live_tracking_allowed" in src


def test_start_visit_claims_owner_only_when_assigned_to_route():
	import inspect
	from app.services.distribution_service import start_visit

	src = inspect.getsource(start_visit)
	assert "_assigned_route_ids_for_user" in src
	assert "int(v.route_id) in assigned_today" in src
	assert "_claim_customer_owner" in src


def test_assignment_exclusive_skips_same_user():
	import inspect
	from app.services.distribution_service import assert_assignment_exclusive

	src = inspect.getsource(assert_assignment_exclusive)
	assert "int(other.user_id) == int(user_id)" in src
	assert "exclusive_customer_ownership" not in src


def test_team_map_live_pin_requires_consent():
	import inspect
	from app.services.distribution_phase3_service import get_team_map

	src = inspect.getsource(get_team_map)
	assert "require_location_consent" in src
	assert "consent_by_user" in src
	assert "start_latitude" not in src
