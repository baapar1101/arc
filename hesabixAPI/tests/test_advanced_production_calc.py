"""قواعد بها و پیشرفت افزونه تولید، بدون پایگاه‌داده."""
from datetime import date, datetime, timezone
from decimal import Decimal
from pathlib import Path

from app.services.advanced_production_calc import (
	COSTING_METHODS,
	cost_variance,
	cycle_hours,
	is_overdue,
	progress_percent,
	quantity_variance,
	remaining_quantity,
	valued_order_cost,
	weighted_average_unit,
)


def test_remaining_and_progress_do_not_go_negative():
	assert remaining_quantity(10, 12) == Decimal("0.000000")
	assert progress_percent(0, 5) == Decimal("0.00")
	assert progress_percent(8, 2) == Decimal("25.00")


def test_overdue_ignores_closed_orders():
	today = date(2026, 11, 4)
	assert is_overdue(date(2026, 11, 1), today, "in_progress") is True
	assert is_overdue(date(2026, 11, 1), today, "completed") is False
	assert is_overdue(None, today, "released") is False
	assert is_overdue(date(2026, 11, 4), today, "released") is False


def test_cycle_hours_reject_negative_span():
	start = datetime(2026, 11, 4, 8, 0, tzinfo=timezone.utc)
	end = datetime(2026, 11, 4, 10, 30, tzinfo=timezone.utc)
	assert cycle_hours(start, end) == Decimal("2.50")
	assert cycle_hours(end, start) is None
	assert cycle_hours(start, None) is None


def test_variance_positive_means_unfavorable():
	assert quantity_variance(12, 10) > 0
	assert cost_variance(110, 100) == Decimal("10.00")
	assert cost_variance(90, 100) == Decimal("-10.00")


def test_weighted_average_and_methods_do_not_invent_quantity():
	assert weighted_average_unit(300, 0) is None
	unit = weighted_average_unit(300, 2)
	assert unit == Decimal("150.000000")
	assert valued_order_cost("standard", 80, 100, 2, unit) == Decimal("80.00")
	assert valued_order_cost("actual", 80, 100, 2, unit) == Decimal("100.00")
	assert valued_order_cost("weighted_average", 80, 100, 2, unit) == Decimal("300.00")
	assert valued_order_cost("weighted_average", 80, 100, 0, unit) == Decimal("100.00")
	assert set(COSTING_METHODS) == {"actual", "standard", "weighted_average"}


def test_plugin_posting_is_opt_in_and_legacy_path_remains():
	root = Path(__file__).resolve().parents[1]
	invoice = (root / "app" / "services" / "invoice_service.py").read_text(encoding="utf-8")
	assert 'accounts["wip"]' in invoice
	assert "انتقال مواد اولیه به WIP" in invoice
	assert invoice.count("_try_plugin_production_posting(") >= 2
	dependency = (root / "app" / "core" / "advanced_production_plugin_dependency.py").read_text(encoding="utf-8")
	assert 'PLUGIN_CODE = "advanced_production"' in dependency


def test_waste_expense_account_uses_plugin_mapping_only_when_present():
	from app.services.advanced_production_posting import choose_waste_expense_account

	assert choose_waste_expense_account(11, None) == 11
	assert choose_waste_expense_account(11, 22) == 22


def test_wage_variance_needs_actual_hours_and_a_standard_rate():
	from app.services.advanced_production_calc import wage_variances

	assert wage_variances(0, 8, 5, 7) is None
	assert wage_variances(10, 8, 0, 7) is None
	partial = wage_variances(10, None, 5, 7)
	assert partial["rate_variance"] == Decimal("20.00")
	assert partial["efficiency_variance"] is None
	full = wage_variances(10, 8, 5, 7)
	assert full["rate_variance"] == Decimal("20.00")
	assert full["efficiency_variance"] == Decimal("10.00")


def test_required_hours_needs_a_nominal_rate():
	from app.services.advanced_production_calc import required_hours

	assert required_hours(10, 0) is None
	assert required_hours(10, 5) == Decimal("2.000000")
	assert required_hours(-3, 5) == Decimal("0.000000")


def test_units_per_hour_needs_run_time():
	from app.services.advanced_production_calc import units_per_hour

	assert units_per_hour(30, 0) is None
	assert units_per_hour(30, 60) == Decimal("30.000000")


def test_standard_posting_with_mapped_accounts_needs_a_variance_account():
	from app.services.advanced_production_posting import posting_requires_variance_account

	assert posting_requires_variance_account("standard", 5, True, False) is True
	assert posting_requires_variance_account("weighted_average", 5, True, False) is True
	assert posting_requires_variance_account("actual", 5, True, False) is False
	assert posting_requires_variance_account("standard", 5, True, True) is False
	assert posting_requires_variance_account("standard", 0, True, False) is False
	assert posting_requires_variance_account("standard", 5, False, False) is False


def test_order_costing_row_uses_the_order_components():
	from datetime import date
	from types import SimpleNamespace

	from app.services.advanced_production_service import _order_row

	order = SimpleNamespace(
		id=7,
		code="PO-7",
		product_id=3,
		status="completed",
		planned_quantity=10,
		produced_quantity=8,
		planned_start_date=date(2026, 11, 1),
		due_date=date(2026, 11, 5),
		started_at=None,
		completed_at=None,
		standard_materials_cost=100,
		actual_materials_cost=120,
		standard_operations_cost=40,
		actual_operations_cost=30,
	)
	product = SimpleNamespace(code="P", name="سیمان")
	row = _order_row(order, product, date(2026, 11, 5), "actual", None)
	assert row["standard_materials"] == 100
	assert row["actual_materials"] == 120
	assert row["standard_operations"] == 40
	assert row["actual_operations"] == 30
	assert row["standard_total"] == 140
	assert row["actual_total"] == 150
	assert row["valued_total"] == 150
	assert row["unit_cost"] == 18.75
	assert row["cost_variance"] == 10
	blank = _order_row(
		SimpleNamespace(**{**order.__dict__, "produced_quantity": 0}),
		product,
		date(2026, 11, 5),
		"actual",
		None,
	)
	assert blank["unit_cost"] is None


def test_fiscal_year_clips_the_requested_dates():
	from datetime import date

	from app.services.advanced_production_calc import intersect_date_range

	year_start, year_end = date(2026, 3, 21), date(2027, 3, 20)
	start, end, empty = intersect_date_range(None, None, year_start, year_end)
	assert (start, end, empty) == (year_start, year_end, False)
	start, end, empty = intersect_date_range(date(2026, 1, 1), date(2026, 4, 1), year_start, year_end)
	assert (start, end, empty) == (year_start, date(2026, 4, 1), False)
	start, end, empty = intersect_date_range(date(2025, 1, 1), date(2025, 6, 1), year_start, year_end)
	assert empty is True


def test_export_codes_use_translation_keys():
	from app.services.advanced_production_calc import export_code_message

	assert export_code_message("stage", "incoming") == "AP_STAGE_INCOMING"
	assert export_code_message("result", "fail") == "AP_RESULT_FAIL"
	assert export_code_message("status", "completed") == "AP_STATUS_COMPLETED"
	assert export_code_message("kind", "breakdown") == "AP_MAINTENANCE_BREAKDOWN"
	assert export_code_message("costing_method", "weighted_average") == "AP_BASIS_WEIGHTED_AVERAGE"
	assert export_code_message("recyclable", True) == "AP_RECYCLABLE_YES"
	assert export_code_message("recyclable", False) == "AP_RECYCLABLE_NO"
	assert export_code_message("role", "material") == "AP_ROLE_MATERIAL"
	assert export_code_message("product_name", "سیمان") is None
	assert export_code_message("stage", "custom") is None


def test_invalid_minutes_and_amounts_are_known_errors():
	from app.core.responses import ApiError
	from app.services.advanced_production_master import _positive_quantity, _required_minutes, _safe_decimal

	for caller in (
		lambda: _required_minutes("soon"),
		lambda: _safe_decimal("many", "AP_OUTPUT_QUANTITY_REQUIRED"),
		lambda: _positive_quantity("many"),
	):
		try:
			caller()
		except ApiError as exc:
			assert exc.status_code == 400
		else:
			raise AssertionError("invalid number was accepted")


def test_missing_output_line_is_a_known_error():
	from app.core.responses import ApiError
	from app.services.advanced_production_master import _required_int

	try:
		_required_int(None, "AP_LINE_NOT_FOUND")
	except ApiError as exc:
		assert exc.code == "AP_LINE_NOT_FOUND"
		assert exc.status_code == 400
	else:
		raise AssertionError("blank id was accepted")


def test_scrap_recyclable_flag_must_be_explicit():
	from app.core.responses import ApiError
	from app.services.advanced_production_master import _flag

	assert _flag(True) is True
	assert _flag("no") is False
	try:
		_flag("maybe")
	except ApiError as exc:
		assert exc.code == "AP_SCRAP_RECYCLABLE_REQUIRED"
	else:
		raise AssertionError("ambiguous recyclable flag was accepted")


def test_material_rate_split_uses_order_standard_and_skips_missing_rate():
	from app.services.advanced_production_calc import material_rate_split

	assert material_rate_split(10, 12, 0, 78) is None
	assert material_rate_split(10, 0, 5, 0)["price_variance"] is None
	assert material_rate_split(10, 0, 5, 0)["usage_variance"] == Decimal("-50.00")
	split = material_rate_split(10, 12, 5, 78)
	assert split["usage_variance"] == Decimal("10.00")
	assert split["price_variance"] == Decimal("18.00")


def test_conversion_percent_needs_one_positive_input_and_output():
	from app.services.advanced_production_calc import conversion_percent

	assert conversion_percent(0, 10) is None
	assert conversion_percent(8, 0) is None
	assert conversion_percent(8, 10) == Decimal("80.00")
	assert conversion_percent(12, 10) == Decimal("120.00")


def test_calendar_period_follows_requested_calendar():
	from datetime import date
	from app.services.advanced_production_calc import calendar_period

	assert calendar_period(None, "jalali") is None
	assert calendar_period(date(2024, 3, 20), "jalali") == "1403-01"
	assert calendar_period(date(2024, 3, 20), "gregorian") == "2024-03"


def test_yield_unused_and_break_even_do_not_invent_numbers():
	from app.services.advanced_production_calc import break_even_quantity, unused_quantity, yield_percent

	assert yield_percent(0, 0) is None
	assert yield_percent(8, 2) == Decimal("80.00")
	assert unused_quantity(None, 10) is None
	assert unused_quantity(100, 40) == Decimal("60.000000")
	assert unused_quantity(10, 12) == Decimal("0")
	assert break_even_quantity(0, 1000, 10, 50) is None
	assert break_even_quantity(500, 1000, 10, 120) is None
	assert break_even_quantity(500, 1000, 10, 50) == Decimal("10.000000")


def test_capacity_gap_needs_nominal_rate_and_time():
	from app.services.advanced_production_calc import capacity_gap

	assert capacity_gap(0, 60, 10) is None
	assert capacity_gap(120, 0, 10) is None
	gap = capacity_gap(120, 30, 40)
	assert gap["ideal_quantity"] == Decimal("60.000000")
	assert gap["utilization_percent"] == Decimal("66.67")


def test_cost_share_and_acceptance_rate_refuse_empty_bases():
	from app.services.advanced_production_calc import acceptance_rate, cost_share

	assert cost_share(0, 0) is None
	share = cost_share(75, 25)
	assert share["materials_percent"] == Decimal("75.00")
	assert share["operations_percent"] == Decimal("25.00")
	assert acceptance_rate(0, 0) is None
	assert acceptance_rate(8, 2) == Decimal("75.00")
	assert acceptance_rate(5, 6) is None


def test_product_margin_does_not_invent_profit_without_production():
	from app.services.advanced_production_calc import product_margin

	assert product_margin(1000, 10, 0, 0) is None
	assert product_margin(0, 0, 500, 5) is None
	result = product_margin(1000, 10, 400, 8)
	assert result["unit_cost"] == Decimal("50.000000")
	assert result["estimated_cogs"] == Decimal("500.00")
	assert result["margin"] == Decimal("500.00")
	assert result["margin_percent"] == Decimal("50.00")


def test_reliability_needs_two_failures_and_closed_repairs():
	from app.services.advanced_production_calc import mean_gap_days, mean_minutes

	assert mean_gap_days([date(2026, 1, 1)]) is None
	assert mean_gap_days([date(2026, 1, 1), date(2026, 1, 11), date(2026, 1, 31)]) == Decimal("15.00")
	assert mean_minutes([]) is None
	assert mean_minutes([30, 90]) == Decimal("60.00")


def test_oee_caps_factors_and_needs_all_three():
	from app.services.advanced_production_calc import oee_factors

	empty = oee_factors(0, 0, 0, 0, 0)
	assert empty["oee"] is None
	full = oee_factors(50, 50, 100, 80, 20)
	assert full["availability"] == Decimal("0.5000")
	assert full["performance"] == Decimal("1.0000")
	assert full["quality"] == Decimal("0.8000")
	assert full["oee"] == Decimal("0.4000")
	capped = oee_factors(60, 0, 50, 80, 0)
	assert capped["performance"] == Decimal("1.0000")


def test_production_journal_balances_for_actual_standard_and_open_wip():
	from app.services.advanced_production_posting import build_production_journal, value_finished_goods

	actual = build_production_journal(80, 20, 100, 0)
	assert _balanced(actual)
	finished, variance = value_finished_goods("standard", 100, 2, 40, None)
	assert finished == Decimal("80.00")
	assert variance == Decimal("20.00")
	standard = build_production_journal(80, 20, finished, variance)
	assert _balanced(standard)
	favorable = build_production_journal(80, 20, 120, -20)
	assert _balanced(favorable)
	open_wip = build_production_journal(50, 10, 0, 0)
	assert _balanced(open_wip)
	assert any(line["role"] == "wip" and line["debit"] == Decimal("50.00") for line in open_wip)
	assert not any(line["role"] == "finished" for line in open_wip)


def test_advanced_production_report_keys_stay_aligned():
	import re
	root = Path(__file__).resolve().parents[1]
	service = (root / "app/services/advanced_production_service.py").read_text(encoding="utf-8")
	block = service[service.find("REPORT_KEYS = ("):service.find(")", service.find("REPORT_KEYS = ("))]
	keys = set(re.findall(r'"([a-z0-9_]+)"', block))
	api = (root / "adapters/api/v1/advanced_production.py").read_text(encoding="utf-8")
	export = set(re.findall(r'^\t"([a-z0-9_]+)": \(', api, re.M))
	mcp = (root / "app/services/ai/ai_function_extensions_mcp_advanced_production.py").read_text(encoding="utf-8")
	mcp_block = mcp[mcp.find("_REPORTS = ["):mcp.find("]", mcp.find("_REPORTS = ["))]
	reports = set(re.findall(r'"([a-z0-9_]+)"', mcp_block))
	catalog = (root / "app/services/ai/ai_reports_catalog.py").read_text(encoding="utf-8")
	defined = {key.removeprefix("advprod_") for key in re.findall(r'ReportDefinition\("(advprod_[a-z0-9_]+)"', catalog)}
	page = (root.parent / "hesabixUI/hesabix_ui/lib/pages/business/advanced_production/advanced_production_page.dart").read_text(encoding="utf-8")
	listed = page[page.find("final reports = <String>["):page.find("];", page.find("final reports = <String>["))]
	dart = set(re.findall(r"'([a-z0-9_]+)'", listed))
	columns = page[page.find("List<DataTableColumn> _columns"):page.find("String _displayDate")]
	missing_columns = sorted(key for key in keys - {"orders", "progress", "overdue", "schedule", "plan_achievement", "open_orders"} if f"case '{key}':" not in columns)
	assert keys == export == reports == defined == dart
	assert missing_columns == []


def _balanced(lines) -> bool:
	debit = sum(line["debit"] for line in lines)
	credit = sum(line["credit"] for line in lines)
	return debit == credit
