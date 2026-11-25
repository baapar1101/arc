"""فعال‌سازی سراسری افزونه و مخفی‌سازی از بازار."""

from __future__ import annotations

from datetime import datetime, timedelta
from types import SimpleNamespace
from unittest.mock import MagicMock

import pytest

from app.core.payroll_plugin_dependency import check_payroll_plugin_active
from app.core.plugin_license import (
	SOURCE_SYSTEM_DEFAULT,
	assert_plugin_purchasable,
	ensure_plugin_config_row,
	is_plugin_active,
	license_row_is_valid,
	merge_global_plugin_rows,
	plugin_is_listed,
	plugin_is_purchasable,
	synthetic_global_license,
)
from app.core.responses import ApiError
from app.services.hscript.plan_limits import resolve_hscript_entitlement
from app.services.marketplace_service import (
	get_business_plugin_status,
	list_all_plugins,
	list_business_plugins,
	list_plugins,
	start_trial_plugin,
)


class _Query:
	def __init__(self, rows):
		if rows is None:
			self._rows = []
		elif isinstance(rows, list):
			self._rows = rows
		else:
			self._rows = [rows]

	def filter(self, *args, **kwargs):
		return self

	def order_by(self, *args, **kwargs):
		return self

	def with_for_update(self):
		return self

	def first(self):
		return self._rows[0] if self._rows else None

	def all(self):
		return list(self._rows)


class _DB:
	def __init__(self, **models):
		self.models = models
		self.committed = False
		self.rolled_back = False

	def query(self, model):
		name = getattr(model, "__name__", str(model))
		return _Query(self.models.get(name, []))

	def commit(self):
		self.committed = True

	def rollback(self):
		self.rolled_back = True

	def add(self, obj):
		self.models.setdefault(type(obj).__name__, []).append(obj)

	def flush(self):
		return None

	def refresh(self, obj):
		return None


def _plugin(**kwargs):
	data = dict(
		id=10,
		code="payroll",
		name="حقوق و دستمزد",
		description="desc",
		category="hr_payroll",
		icon_url=None,
		is_active=True,
		listed_in_marketplace=True,
		enabled_for_all_businesses=False,
		trial_days=14,
		trial_allowed=True,
		created_at=datetime.utcnow(),
		updated_at=datetime.utcnow(),
	)
	data.update(kwargs)
	return SimpleNamespace(**data)


def _license(**kwargs):
	data = dict(
		id=3,
		business_id=1,
		plugin_id=10,
		plan_id=7,
		status="active",
		starts_at=datetime.utcnow() - timedelta(days=2),
		ends_at=datetime.utcnow() + timedelta(days=20),
		auto_renew=False,
		is_trial=False,
		trial_started_at=None,
		created_at=datetime.utcnow(),
		updated_at=datetime.utcnow(),
	)
	data.update(kwargs)
	return SimpleNamespace(**data)


def test_global_enable_is_active_without_business_license():
	plugin = _plugin(enabled_for_all_businesses=True, listed_in_marketplace=False)
	db = _DB(MarketplacePlugin=[plugin], BusinessPlugin=[])
	assert is_plugin_active(db, 99, "payroll") is True
	assert check_payroll_plugin_active(db, 99) is True


def test_global_enable_requires_plugin_operationally_active():
	plugin = _plugin(is_active=False, enabled_for_all_businesses=True)
	db = _DB(MarketplacePlugin=[plugin], BusinessPlugin=[])
	assert is_plugin_active(db, 1, "payroll") is False


def test_global_off_falls_back_to_purchased_license():
	plugin = _plugin(enabled_for_all_businesses=False)
	db = _DB(MarketplacePlugin=[plugin], BusinessPlugin=[_license()])
	assert is_plugin_active(db, 1, "payroll") is True


def test_global_off_without_license_is_inactive():
	plugin = _plugin(enabled_for_all_businesses=False)
	db = _DB(MarketplacePlugin=[plugin], BusinessPlugin=[])
	assert is_plugin_active(db, 1, "payroll") is False


def test_expired_license_is_inactive_when_not_global():
	plugin = _plugin()
	db = _DB(
		MarketplacePlugin=[plugin],
		BusinessPlugin=[_license(ends_at=datetime.utcnow() - timedelta(days=1))],
	)
	assert is_plugin_active(db, 1, "payroll") is False


def test_expired_license_is_active_when_global():
	plugin = _plugin(enabled_for_all_businesses=True)
	db = _DB(
		MarketplacePlugin=[plugin],
		BusinessPlugin=[_license(status="expired", ends_at=datetime.utcnow() - timedelta(days=1))],
	)
	assert is_plugin_active(db, 1, "payroll") is True


def test_admin_list_includes_unlisted_and_global_flags():
	hidden = _plugin(listed_in_marketplace=False, enabled_for_all_businesses=True)
	db = _DB(MarketplacePlugin=[hidden], MarketplacePluginPlan=[])
	items = list_all_plugins(db)
	assert len(items) == 1
	assert items[0]["listed_in_marketplace"] is False
	assert items[0]["enabled_for_all_businesses"] is True


def test_catalog_hides_unlisted_plugins():
	visible = _plugin(id=1, code="payroll", listed_in_marketplace=True)
	hidden = _plugin(
		id=2,
		code="office_automation",
		listed_in_marketplace=False,
		enabled_for_all_businesses=True,
	)
	db = _DB(MarketplacePlugin=[visible, hidden], MarketplacePluginPlan=[])
	items = list_plugins(db)
	codes = [i["code"] for i in items]
	assert "payroll" in codes
	assert "office_automation" not in codes
	assert items[0]["purchasable"] is True


def test_unlisted_or_global_plugin_is_not_purchasable():
	assert plugin_is_listed(_plugin(listed_in_marketplace=False)) is False
	assert plugin_is_purchasable(_plugin(enabled_for_all_businesses=True)) is False
	with pytest.raises(ApiError) as unlisted:
		assert_plugin_purchasable(_plugin(listed_in_marketplace=False))
	assert unlisted.value.detail["error"]["code"] == "PLUGIN_NOT_FOR_SALE"
	with pytest.raises(ApiError) as global_err:
		assert_plugin_purchasable(_plugin(enabled_for_all_businesses=True))
	assert global_err.value.detail["error"]["code"] == "PLUGIN_NOT_FOR_SALE"


def test_start_trial_blocked_for_global_plugin():
	plugin = _plugin(enabled_for_all_businesses=True, listed_in_marketplace=False)
	db = _DB(MarketplacePlugin=[plugin])
	with pytest.raises(ApiError) as ei:
		start_trial_plugin(db, business_id=1, plugin_id=10, user_id=1)
	assert ei.value.detail["error"]["code"] == "PLUGIN_NOT_FOR_SALE"


def test_list_business_plugins_injects_synthetic_global_row():
	plugin = _plugin(enabled_for_all_businesses=True, listed_in_marketplace=False)
	db = _DB(MarketplacePlugin=[plugin], BusinessPlugin=[])
	rows = list_business_plugins(db, 1)
	assert len(rows) == 1
	assert rows[0]["source"] == SOURCE_SYSTEM_DEFAULT
	assert rows[0]["is_active"] is True
	assert rows[0]["plugin_code"] == "payroll"
	assert rows[0]["purchasable"] is False


def test_list_business_plugins_overlays_expired_purchase_when_global():
	plugin = _plugin(enabled_for_all_businesses=True)
	expired = _license(status="expired", ends_at=datetime.utcnow() - timedelta(days=3))
	existing = [
		{
			"license_id": expired.id,
			"plugin_id": plugin.id,
			"plugin_code": plugin.code,
			"status": "expired",
			"is_active": False,
			"is_expired": True,
			"source": "purchase",
		}
	]
	merged = merge_global_plugin_rows(existing, [plugin])
	assert len(merged) == 1
	assert merged[0]["is_active"] is True
	assert merged[0]["status"] == "active"
	assert merged[0]["source"] == "purchase"
	assert merged[0]["globally_enabled"] is True
	assert merged[0]["is_trial"] is False
	assert merged[0]["is_expired"] is False
	assert merged[0]["ends_at"] is None
	assert merged[0]["trial_remaining_days"] is None


def test_overlay_hides_expired_trial_when_global():
	from app.core.plugin_license import overlay_global_access

	row = overlay_global_access(
		{
			"plugin_id": 10,
			"is_trial": True,
			"trial_remaining_days": 0,
			"is_active": False,
			"is_expired": True,
			"status": "expired",
			"ends_at": datetime.utcnow() - timedelta(days=1),
			"trial_started_at": datetime.utcnow() - timedelta(days=8),
		}
	)
	assert row["is_active"] is True
	assert row["is_trial"] is False
	assert row["is_expired"] is False
	assert row["ends_at"] is None
	assert row["trial_started_at"] is None
	assert row["globally_enabled"] is True


def test_repair_shop_status_does_not_treat_purchase_as_global():
	from app.core.repair_shop_plugin_dependency import get_business_plugin_status as repair_status

	plugin = _plugin(
		code="repair_shop_management",
		enabled_for_all_businesses=False,
	)
	license_row = _license(is_trial=True, ends_at=datetime.utcnow() + timedelta(days=5))
	db = _DB(MarketplacePlugin=[plugin], BusinessPlugin=[license_row])
	status = repair_status(db, 1)
	assert status["is_active"] is True
	assert status["globally_enabled"] is False
	assert status["is_trial"] is True
	assert status["ends_at"] is not None


def test_repair_shop_status_overlays_only_when_globally_enabled():
	from app.core.repair_shop_plugin_dependency import get_business_plugin_status as repair_status

	plugin = _plugin(
		code="repair_shop_management",
		enabled_for_all_businesses=True,
	)
	license_row = _license(
		is_trial=True,
		status="expired",
		ends_at=datetime.utcnow() - timedelta(days=1),
	)
	db = _DB(MarketplacePlugin=[plugin], BusinessPlugin=[license_row])
	status = repair_status(db, 1)
	assert status["is_active"] is True
	assert status["globally_enabled"] is True
	assert status["is_trial"] is False
	assert status["ends_at"] is None


def test_status_endpoint_returns_synthetic_when_global_and_no_row():
	plugin = _plugin(enabled_for_all_businesses=True, listed_in_marketplace=False)
	db = _DB(MarketplacePlugin=[plugin], BusinessPlugin=[])
	status = get_business_plugin_status(db, 1, 10)
	assert status is not None
	assert status["source"] == SOURCE_SYSTEM_DEFAULT
	assert status["is_active"] is True


def test_hscript_global_enable_uses_lifetime_tier():
	plugin = _plugin(
		code="hscript_custom_reports",
		enabled_for_all_businesses=True,
		listed_in_marketplace=False,
	)
	db = _DB(MarketplacePlugin=[plugin], BusinessPlugin=[])
	ent = resolve_hscript_entitlement(db, 1)  # type: ignore[arg-type]
	assert ent.plugin_active is True
	assert ent.tier == "lifetime"
	assert ent.plan_period == "lifetime"


def test_seed_does_not_overwrite_admin_visibility_flags():
	from adapters.db.models.currency import Currency
	from adapters.db.models.marketplace import MarketplacePlugin, MarketplacePluginPlan
	from adapters.db.seed_data.marketplace_plugins_seed import ensure_default_marketplace_plugins

	plugin = _plugin(
		listed_in_marketplace=False,
		enabled_for_all_businesses=True,
		code="payroll",
	)
	plan = SimpleNamespace(id=1, plugin_id=10, period="monthly", is_active=True, updated_at=None)
	currency = SimpleNamespace(id=1, code="IRR")

	class _SeedQuery(_Query):
		def __init__(self, model, plugin_obj, plan_obj, currency_obj):
			self._model = model
			self._plugin = plugin_obj
			self._plan = plan_obj
			self._currency = currency_obj
			super().__init__([])

		def first(self):
			name = getattr(self._model, "__name__", "")
			if name == "Currency":
				return self._currency
			if name == "MarketplacePlugin":
				return self._plugin
			if name == "MarketplacePluginPlan":
				return self._plan
			return None

		def all(self):
			return []

	class _SeedDB:
		def query(self, model):
			return _SeedQuery(model, plugin, plan, currency)

		def add(self, obj):
			return None

		def flush(self):
			return None

	ensure_default_marketplace_plugins(_SeedDB())  # type: ignore[arg-type]
	assert plugin.listed_in_marketplace is False
	assert plugin.enabled_for_all_businesses is True
	assert Currency is not None and MarketplacePlugin is not None and MarketplacePluginPlan is not None


def test_config_row_created_only_when_global():
	plugin = _plugin(enabled_for_all_businesses=True)
	plan = SimpleNamespace(id=7, plugin_id=10, period="lifetime", is_active=True, price=0)
	db = _DB(MarketplacePlugin=[plugin], BusinessPlugin=[], MarketplacePluginPlan=[plan])
	row = ensure_plugin_config_row(db, 1, plugin)
	assert row is not None
	assert row.status == SOURCE_SYSTEM_DEFAULT
	assert row.plan_id == 7
	assert license_row_is_valid(row) is False
	assert is_plugin_active(db, 1, "payroll") is True


def test_config_row_not_created_when_not_global():
	plugin = _plugin(enabled_for_all_businesses=False)
	plan = SimpleNamespace(id=7, plugin_id=10, period="lifetime", is_active=True, price=0)
	db = _DB(MarketplacePlugin=[plugin], BusinessPlugin=[], MarketplacePluginPlan=[plan])
	assert ensure_plugin_config_row(db, 1, plugin) is None


def test_list_skips_system_default_stub_and_injects_synthetic():
	plugin = _plugin(enabled_for_all_businesses=True)
	stub = _license(status=SOURCE_SYSTEM_DEFAULT, is_trial=False, ends_at=None)
	db = _DB(MarketplacePlugin=[plugin], BusinessPlugin=[stub], MarketplacePluginPlan=[])
	rows = list_business_plugins(db, 1)
	assert len(rows) == 1
	assert rows[0]["source"] == SOURCE_SYSTEM_DEFAULT
	assert rows[0]["license_id"] is None
	assert rows[0]["is_active"] is True


def test_status_hides_stub_when_global_off():
	plugin = _plugin(enabled_for_all_businesses=False)
	stub = _license(status=SOURCE_SYSTEM_DEFAULT, is_trial=False, ends_at=None)
	db = _DB(MarketplacePlugin=[plugin], BusinessPlugin=[stub], MarketplacePluginPlan=[])
	assert get_business_plugin_status(db, 1, 10) is None


def test_start_trial_reuses_system_default_stub():
	plugin = _plugin(enabled_for_all_businesses=False, listed_in_marketplace=True)
	stub = _license(
		status=SOURCE_SYSTEM_DEFAULT,
		is_trial=False,
		trial_started_at=None,
		ends_at=None,
	)
	business = SimpleNamespace(id=1)
	plan = SimpleNamespace(id=7, plugin_id=10, is_active=True, price=1)
	db = _DB(
		MarketplacePlugin=[plugin],
		BusinessPlugin=[stub],
		Business=[business],
		MarketplacePluginPlan=[plan],
	)
	out = start_trial_plugin(db, 1, 10, 1)
	assert stub.is_trial is True
	assert stub.status == "active"
	assert out["is_trial"] is True
	assert out["plan_id"] == 7


def test_synthetic_license_shape():
	row = synthetic_global_license(_plugin())
	assert row["source"] == SOURCE_SYSTEM_DEFAULT
	assert row["license_id"] is None
	assert row["ends_at"] is None
	assert row["is_trial"] is False


def test_magicmock_plugin_does_not_count_as_globally_enabled():
	"""تست‌های قدیمی MagicMock نباید ناگهان سراسری محسوب شوند."""
	db = MagicMock()
	plugin = MagicMock()
	plugin.id = 99
	plugin.is_active = True
	license_row = MagicMock()
	license_row.status = "active"
	license_row.ends_at = datetime.utcnow() + timedelta(days=10)

	def query_side_effect(model):
		q = MagicMock()
		if model.__name__ == "MarketplacePlugin":
			q.filter.return_value.first.return_value = plugin
		elif model.__name__ == "BusinessPlugin":
			q.filter.return_value.first.return_value = license_row
		return q

	db.query.side_effect = query_side_effect
	assert is_plugin_active(db, 1, "payroll") is True
	plugin_no_license = MagicMock()
	plugin_no_license.id = 99
	plugin_no_license.is_active = True

	def query_no_license(model):
		q = MagicMock()
		if model.__name__ == "MarketplacePlugin":
			q.filter.return_value.first.return_value = plugin_no_license
		else:
			q.filter.return_value.first.return_value = None
		return q

	db.query.side_effect = query_no_license
	assert is_plugin_active(db, 1, "payroll") is False
