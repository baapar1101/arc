"""تست‌های ارتقای HScript 1.1 — HTable، param schema، catalog."""

from __future__ import annotations

from app.services.hscript.catalog import build_catalog, list_recipes
from app.services.hscript.param_schema import infer_param_schema
from app.services.hscript.runtime import run_script
from app.services.hscript.values import HTable


class _DummyDB:
	pass


def _run(source: str, *, params: dict | None = None):
	return run_script(
		source,
		db=_DummyDB(),  # type: ignore[arg-type]
		business_id=1,
		user_id=1,
		params=params,
		preview=True,
	)


def test_htable_where_and_join_pivot():
	left = HTable.from_rows(
		[
			{"id": 1, "person_id": 10, "amount": 100},
			{"id": 2, "person_id": 20, "amount": 250},
			{"id": 3, "person_id": 10, "amount": 50},
		]
	)
	right = HTable.from_rows(
		[
			{"id": 10, "name": "A"},
			{"id": 20, "name": "B"},
		]
	)
	filtered = left.where("amount", "gt", 60)
	assert filtered.count() == 2
	filtered2 = left.where(amount__gte=100, person_id=10)
	assert filtered2.count() == 1
	joined = left.join(right, left_on="person_id", right_on="id", how="left")
	assert joined.count() == 3
	assert joined.rows[0]["name"] == "A"
	pivoted = HTable.from_rows(
		[
			{"month": "01", "product": "x", "amount": 10},
			{"month": "01", "product": "y", "amount": 5},
			{"month": "02", "product": "x", "amount": 7},
		]
	).pivot(index="month", columns="product", values="amount", agg="sum")
	assert pivoted.count() == 2
	row01 = next(r for r in pivoted.rows if r["month"] == "01")
	assert row01["x"] == 10.0
	assert row01["y"] == 5.0


def test_htable_in_script():
	src = """
t = table([{"name": "A", "cat": "x", "total": 10}, {"name": "B", "cat": "x", "total": 30}, {"name": "A", "cat": "y", "total": 5}])
big = t.where("total", "gte", 10)
report.kpi("big", big.count())
piv = t.pivot(index="name", columns="cat", values="total", agg="sum")
report.table(piv)
"""
	result = _run(src)
	assert result.ok, result.error
	kpi = next(b for b in result.spec["blocks"] if b["type"] == "kpi")
	assert kpi["value"] == 2


def test_param_schema_annotations():
	code = '''
# @param from_date date "از تاریخ" required
# @param limit integer "سقف" default=20
# @param kind select "نوع" options=["receipt","payment"] default="receipt"
x = params.get("limit", 20)
y = params.get("search", "")
'''
	schema = infer_param_schema(source_code=code, default_params={"extra": True})
	names = [f["name"] for f in schema["fields"]]
	assert "from_date" in names
	assert "limit" in names
	assert "kind" in names
	assert "search" in names
	assert "extra" in names
	limit = next(f for f in schema["fields"] if f["name"] == "limit")
	assert limit["default"] == 20
	assert limit["type"] == "integer"
	kind = next(f for f in schema["fields"] if f["name"] == "kind")
	assert kind["type"] == "select"
	assert "receipt" in kind["options"]


def test_catalog_and_recipes():
	cat = build_catalog()
	assert cat["language_version"] == "1.1.0"
	mod_names = {m["name"] for m in cat["modules"]}
	assert {"invoices", "debtors", "banks", "warehouses", "persons", "creditors"} <= mod_names
	recipes = list_recipes()
	assert len(recipes) >= 3
	assert any(r.get("source_code") for r in recipes)


def test_dates_helpers_in_script():
	src = """
b = dates.month_bounds()
report.kpi("ok", 1)
report.text(dates.days_ago(1))
"""
	result = _run(src)
	assert result.ok, result.error
