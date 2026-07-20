"""تست‌های فاز ۷: پلن، cross-tenant، entitlement."""

from __future__ import annotations

import pytest

from app.core.responses import ApiError
from app.services.hscript.plan_limits import resolve_hscript_entitlement
from app.services import hscript_report_service as svc


class _DummyQuery:
	def __init__(self, result=None, count_value=0):
		self._result = result
		self._count = count_value

	def filter(self, *args, **kwargs):
		return self

	def order_by(self, *args, **kwargs):
		return self

	def offset(self, *args, **kwargs):
		return self

	def limit(self, *args, **kwargs):
		return self

	def first(self):
		return self._result

	def count(self):
		return self._count

	def all(self):
		return []


class _DummyDB:
	"""Session حداقلی برای تست‌های بدون DB واقعی."""

	def __init__(self, *, report=None, report_count=0, plugin=None, license_row=None, plan=None):
		self._report = report
		self._report_count = report_count
		self._plugin = plugin
		self._license = license_row
		self._plan = plan
		self._query_calls = []

	def query(self, model):
		name = getattr(model, "__name__", str(model))
		# Mapped columns: model may be InstrumentedAttribute — use class name from entity
		entity = getattr(model, "class_", None) or getattr(getattr(model, "parent", None), "class_", None)
		ename = getattr(entity, "__name__", None) or name

		from adapters.db.models.hscript_report import HScriptReport, HScriptReportRun
		from adapters.db.models.marketplace import BusinessPlugin, MarketplacePlugin, MarketplacePluginPlan

		if model is HScriptReport or ename == "HScriptReport" or model is HScriptReport.id:
			if model is HScriptReport.id:
				return _DummyQuery(result=(1,) if self._report_count else None, count_value=self._report_count)
			return _DummyQuery(result=self._report, count_value=self._report_count)
		if model is HScriptReportRun or ename == "HScriptReportRun" or model is HScriptReportRun.id:
			return _DummyQuery(count_value=0)
		if model is MarketplacePlugin or ename == "MarketplacePlugin":
			return _DummyQuery(result=self._plugin)
		if model is BusinessPlugin or ename == "BusinessPlugin":
			return _DummyQuery(result=self._license)
		if model is MarketplacePluginPlan or ename == "MarketplacePluginPlan":
			return _DummyQuery(result=self._plan)
		return _DummyQuery()


def test_free_tier_entitlement_without_plugin():
	db = _DummyDB(plugin=None)
	ent = resolve_hscript_entitlement(db, business_id=1)  # type: ignore[arg-type]
	assert ent.tier == "free"
	assert ent.plugin_active is False
	assert ent.max_saved_reports == 25
	assert ent.runs_per_minute == 8


def test_cross_tenant_get_report_not_found():
	"""گزارش متعلق به business دیگر نباید دیده شود."""

	class _Report:
		id = 10
		business_id = 1

	db = _DummyDB(report=None)  # فیلتر business_id نتیجه خالی
	with pytest.raises(ApiError) as exc:
		svc.get_report(db, business_id=2, report_id=10)  # type: ignore[arg-type]
	assert exc.value.detail["error"]["code"] == "HSCRIPT_REPORT_NOT_FOUND"


def test_create_report_hits_saved_limit(monkeypatch):
	db = _DummyDB(report_count=25)

	def _fake_validate(code):
		return {"ok": True}

	monkeypatch.setattr(svc, "validate_script", _fake_validate)
	monkeypatch.setattr(svc, "count_saved_reports", lambda *_a, **_k: 25)

	with pytest.raises(ApiError) as exc:
		svc.create_report(
			db,  # type: ignore[arg-type]
			business_id=1,
			user_id=1,
			title="x",
			source_code='report.title("t")',
		)
	assert exc.value.detail["error"]["code"] == "HSCRIPT_REPORT_LIMIT"


def test_seed_includes_hscript_plugin():
	from adapters.db.seed_data.marketplace_plugins_seed import _DEFAULT_PLUGINS

	codes = [p.code for p in _DEFAULT_PLUGINS]
	assert "hscript_custom_reports" in codes
