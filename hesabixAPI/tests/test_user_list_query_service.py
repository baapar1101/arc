from __future__ import annotations

from adapters.api.v1.schemas import FilterItem
from app.services.user_list_query_service import (
	_build_full_name_filter,
	_build_id_filter,
	_build_role_filter,
	_build_status_filter,
	normalize_user_search_fields,
)


class TestNormalizeUserSearchFields:
	def test_full_name_expands_to_first_and_last(self):
		result = normalize_user_search_fields(["full_name", "email"])
		assert result == ["first_name", "last_name", "email"]

	def test_deduplicates_fields(self):
		result = normalize_user_search_fields(
			["first_name", "full_name", "last_name"]
		)
		assert result == ["first_name", "last_name"]

	def test_none_passthrough(self):
		assert normalize_user_search_fields(None) is None


class TestVirtualFilters:
	def test_status_active_filter(self):
		cond = _build_status_filter(
			FilterItem(property="status", operator="=", value="active")
		)
		assert cond is not None

	def test_status_pending_filter(self):
		cond = _build_status_filter(
			FilterItem(property="status", operator="in", value=["pending"])
		)
		assert cond is not None

	def test_role_admin_filter(self):
		cond = _build_role_filter(
			FilterItem(property="role", operator="in", value=["admin"])
		)
		assert cond is not None

	def test_full_name_contains_filter(self):
		cond = _build_full_name_filter("*", "احمد")
		assert cond is not None

	def test_id_contains_filter(self):
		cond = _build_id_filter("*", "12")
		assert cond is not None

	def test_id_exact_filter(self):
		cond = _build_id_filter("=", "42")
		assert cond is not None
