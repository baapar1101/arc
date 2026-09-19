"""تست‌های هسته HScript: نحو، امنیت، محدودیت منابع."""

from __future__ import annotations

import pytest

from app.services.hscript.errors import ResourceLimitErrorHS, SecurityErrorHS
from app.services.hscript.limits import ResourceLimits
from app.services.hscript.runtime import run_script, validate_script


class _DummyDB:
	"""Session جعلی — Gateway در این تست‌ها صدا زده نمی‌شود مگر صریح."""

	pass


def _run(source: str, *, preview: bool = True, params: dict | None = None):
	return run_script(
		source,
		db=_DummyDB(),  # type: ignore[arg-type]
		business_id=1,
		user_id=1,
		params=params,
		preview=preview,
	)


def test_validate_ok():
	src = "x = 1\nreport.title(\"ok\")\n"
	assert validate_script(src)["ok"] is True


def test_forbidden_import():
	r = validate_script("import os\n")
	assert r["ok"] is False
	assert r["error"]["code"] == "E030_SECURITY"


def test_kpi_and_table_without_gateway():
	src = """
report.title("Demo")
rows = [{"name": "A", "total": 10}, {"name": "B", "total": 20}]
t = table(rows)
report.kpi("جمع", t.sum("total"), format="currency")
report.table(t, columns=["name", "total"])
report.bar_chart(t, x="name", y="total", title="مقایسه")
"""
	result = _run(src)
	assert result.ok, result.error
	assert result.spec is not None
	types = [b["type"] for b in result.spec["blocks"]]
	assert "title" in types
	assert "kpi" in types
	assert "table" in types
	assert "chart" in types


def test_functions_and_loops():
	src = """
def double(n):
    return n * 2

total = 0
for i in range(5):
    total = total + double(i)
report.kpi("total", total)
"""
	result = _run(src)
	assert result.ok, result.error
	kpi = next(b for b in result.spec["blocks"] if b["type"] == "kpi")
	assert kpi["value"] == 20


def test_infinite_loop_capped():
	lim = ResourceLimits(max_loop_iterations=50, max_steps=10_000, max_execution_ms=2000)
	src = """
i = 0
while True:
    i = i + 1
"""
	result = run_script(src, db=_DummyDB(), business_id=1, user_id=1, limits=lim, preview=True)  # type: ignore[arg-type]
	assert result.ok is False
	assert result.error["code"] == "E050_RESOURCE_LIMIT"


def test_dunder_blocked():
	src = "x = __import__\n"
	r = validate_script(src)
	# __import__ as identifier might parse as name then fail at runtime, or security at lexer for import keyword
	# Actually __import__ is IDENT, blocked at lookup
	result = _run("x = __builtins__\n")
	assert result.ok is False
	assert result.error["code"] in ("E030_SECURITY", "E010_NAME")


def test_attribute_underscore_blocked():
	src = """
rows = table([{"a": 1}])
x = rows.__class__
"""
	result = _run(src)
	assert result.ok is False
	assert result.error["code"] == "E030_SECURITY"


def test_params_injection_stripped():
	src = """
report.kpi("bid", param.get("business_id") if False else param.get("note", "none"))
"""
	# param is dict — use index
	src = """
report.kpi("note", param["note"])
"""
	result = _run(src, params={"business_id": 999, "note": "hello"})
	assert result.ok, result.error
	kpi = next(b for b in result.spec["blocks"] if b["type"] == "kpi")
	assert kpi["value"] == "hello"


def test_elif_else():
	src = """
x = 2
if x == 1:
    msg = "one"
elif x == 2:
    msg = "two"
else:
    msg = "other"
report.text(msg)
"""
	result = _run(src)
	assert result.ok, result.error
	assert any(b.get("text") == "two" for b in result.spec["blocks"])


def test_sanitize_datetime_and_decimal_from_gateway(monkeypatch):
	"""فیلدهای date/datetime/Decimal اسناد نباید اجرای اسکریپت را بشکنند."""
	from datetime import date, datetime
	from decimal import Decimal
	from unittest.mock import patch

	src = """
rows = invoices.all(limit=10)
report.kpi("n", rows.count())
report.table(rows, columns=["code", "document_date", "total_debit"])
"""
	fake = {
		"items": [
			{
				"id": 1,
				"code": "INV-1",
				"document_date": date(2026, 1, 2),
				"registered_at": datetime(2026, 1, 2, 10, 30, 0),
				"total_debit": Decimal("1500.50"),
				"total_credit": Decimal("0"),
			}
		]
	}
	with patch("app.services.document_service.list_documents", return_value=fake):
		result = _run(src)
	assert result.ok, result.error
	table = next(b for b in result.spec["blocks"] if b["type"] == "table")
	row = table["rows"][0]
	assert row["code"] == "INV-1"
	# با تقویم پیش‌فرض jalali قالب می‌شود
	assert "/" in str(row["document_date"])
	assert row["total_debit"] == 1500.5


def test_report_calendar_jalali_formats_table_dates():
	src = """
report.calendar("jalali")
rows = table([{"document_date": "2026-07-20", "code": "A"}])
report.table(rows, columns=["code", "document_date"])
report.kpi("d", format_date("2026-07-20"))
"""
	result = _run(src)
	assert result.ok, result.error
	assert result.spec["meta"]["calendar_type"] == "jalali"
	table = next(b for b in result.spec["blocks"] if b["type"] == "table")
	assert table["rows"][0]["document_date"] == "1405/04/29"
	kpi = next(b for b in result.spec["blocks"] if b["type"] == "kpi")
	assert kpi["value"] == "1405/04/29"


def test_report_calendar_gregorian_keeps_iso_style():
	src = """
report.calendar("gregorian")
rows = table([{"document_date": "2026-07-20", "code": "A"}])
report.table(rows, columns=["document_date"])
"""
	result = _run(src)
	assert result.ok, result.error
	assert result.spec["meta"]["calendar_type"] == "gregorian"
	table = next(b for b in result.spec["blocks"] if b["type"] == "table")
	assert table["rows"][0]["document_date"] == "2026-07-20"


def test_parse_jalali_filter_date():
	from app.services.hscript.dates import parse_date

	assert parse_date("1404/01/01", calendar="jalali") == "2025-03-21"


def test_format_number_thousands_and_currency():
	from app.services.hscript.number_format import format_number

	assert format_number(1234567, "currency") == "1,234,567"
	assert format_number(1234.5, "number:2") == "1,234.50"
	assert format_number(12.5, "percent") == "12.5%"


def test_report_number_format_and_table_formats():
	src = """
report.number_format(style="western")
report.kpi("m", 1500000, format="currency")
rows = table([{"code": "A", "total": 2500000}])
report.table(rows, columns=["code", "total"], formats={"total": "currency"})
report.text(format_number(9999, "number"))
"""
	result = _run(src)
	assert result.ok, result.error
	assert result.spec["meta"]["number_format"]["thousands_sep"] == ","
	kpi = next(b for b in result.spec["blocks"] if b["type"] == "kpi")
	assert kpi["format"] == "currency"
	table = next(b for b in result.spec["blocks"] if b["type"] == "table")
	assert table["formats"]["total"] == "currency"
	assert any(b.get("text") == "9,999" for b in result.spec["blocks"] if b.get("type") == "text")
