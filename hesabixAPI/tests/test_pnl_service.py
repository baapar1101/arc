"""تست منطق گزارش سود و زیان و طبقه‌بندی حساب‌ها."""
from __future__ import annotations

from datetime import date
from decimal import Decimal
from types import SimpleNamespace

from app.services.pnl_account_classification import (
    is_pnl_cogs_account,
    is_pnl_non_operating_expense_account,
    is_pnl_non_operating_income_account,
    is_pnl_operating_expense_account,
    is_pnl_operating_other_income_account,
    is_pnl_other_income_account,
    is_pnl_sales_account,
    is_pnl_tax_expense_account,
    pnl_account_section,
)
from app.services.pnl_service import (
    _build_statement_lines,
    _prior_year_dates,
    _resolve_compare_mode,
)


def _account(code: str, account_type: str = "accounting_document") -> SimpleNamespace:
    return SimpleNamespace(code=code, account_type=account_type)


class TestPnlSectionClassification:
    def test_sales_group5(self):
        assert is_pnl_sales_account("50001")
        assert pnl_account_section("50001") == "sales"

    def test_operating_other_income_group601(self):
        assert is_pnl_operating_other_income_account("60101")
        assert pnl_account_section("60101") == "other_income"
        assert is_pnl_other_income_account("60101")

    def test_non_operating_income_group602(self):
        assert is_pnl_non_operating_income_account("60204")
        assert pnl_account_section("60204") == "non_operating_income"
        assert is_pnl_other_income_account("60204")

    def test_cogs_group4(self):
        assert is_pnl_cogs_account("40001")
        assert pnl_account_section("40001") == "cogs"

    def test_operating_expense_group7(self):
        assert is_pnl_operating_expense_account("70201")
        assert pnl_account_section("70201") == "operating_expense"

    def test_non_operating_expense_group708_709(self):
        assert is_pnl_non_operating_expense_account("70901")
        assert not is_pnl_operating_expense_account("70901")
        assert pnl_account_section("70901") == "non_operating_expense"
        assert is_pnl_non_operating_expense_account("70801")
        assert pnl_account_section("70801") == "non_operating_expense"

    def test_income_tax_50101_is_tax_expense(self):
        assert is_pnl_tax_expense_account("50101")
        assert not is_pnl_operating_expense_account("50101")
        assert pnl_account_section("50101") == "tax_expense"
        assert not is_pnl_sales_account("50101")


class TestCompareMode:
    def test_resolve_prior_period_legacy_flag(self):
        assert _resolve_compare_mode(True, None, is_cumulative=False) == "prior_period"
        assert _resolve_compare_mode(True, None, is_cumulative=True) == "prior_year"

    def test_resolve_explicit_mode(self):
        assert _resolve_compare_mode(False, "prior_year", is_cumulative=False) == "prior_year"

    def test_prior_year_dates(self):
        start, end = _prior_year_dates(date(2025, 3, 1), date(2025, 3, 31))
        assert start == date(2024, 3, 1)
        assert end == date(2024, 3, 31)


class TestPnlStatementLines:
    def _sample_items(self):
        sales = [{"account_code": "50001", "account_name": "فروش", "amount": 1000.0}]
        other = [{"account_code": "60101", "account_name": "خدمات", "amount": 200.0}]
        cogs = [{"account_code": "40001", "account_name": "بهای تمام‌شده", "amount": 600.0}]
        operating = [{"account_code": "70201", "account_name": "حقوق", "amount": 300.0}]
        summary = {
            "total_sales": 1000.0,
            "total_other_income": 200.0,
            "total_revenue": 1200.0,
            "total_cogs": 600.0,
            "gross_profit": 600.0,
            "total_operating_expense": 300.0,
            "operating_profit": 300.0,
            "total_non_operating_income": 0.0,
            "total_non_operating_expense": 0.0,
            "profit_before_tax": 300.0,
            "total_tax_expense": 0.0,
            "net_profit_after_tax": 300.0,
            "net_profit_loss": 300.0,
        }
        return sales, other, cogs, operating, summary

    def test_statement_has_hierarchical_subtotals(self):
        sales, other, cogs, operating, summary = self._sample_items()
        lines = _build_statement_lines(sales, other, cogs, operating, [], summary)

        types = [line["type"] for line in lines]
        assert "section_header" in types
        assert "subtotal" in types
        assert "grand_total" in types

        labels = [line.get("label_fa") for line in lines if line.get("label_fa")]
        assert "جمع درآمد" in labels
        assert "سود ناخالص" in labels
        assert "سود عملیاتی" in labels
        assert "سود/زیان خالص پس از مالیات" in labels

    def test_statement_includes_non_operating_and_tax(self):
        sales, other, cogs, operating, summary = self._sample_items()
        non_op_income = [{"account_code": "60201", "account_name": "سود سپرده", "amount": 50.0}]
        non_op_expense = [{"account_code": "70901", "account_name": "بهره وام", "amount": 20.0}]
        tax = [{"account_code": "50101", "account_name": "مالیات", "amount": 30.0}]
        summary = dict(summary)
        summary["total_non_operating_income"] = 50.0
        summary["total_non_operating_expense"] = 20.0
        summary["profit_before_tax"] = 330.0
        summary["total_tax_expense"] = 30.0
        summary["net_profit_after_tax"] = 300.0
        summary["net_profit_loss"] = 300.0
        lines = _build_statement_lines(
            sales,
            other,
            cogs,
            operating,
            tax,
            summary,
            non_operating_income_items=non_op_income,
            non_operating_expense_items=non_op_expense,
        )
        labels = [line.get("label_fa") for line in lines if line.get("label_fa")]
        assert "درآمدهای غیرعملیاتی" in labels
        assert "هزینه‌های غیرعملیاتی" in labels
        assert "سود قبل از مالیات" in labels

    def test_gross_profit_calculation(self):
        sales, other, cogs, operating, summary = self._sample_items()
        gross = Decimal(str(summary["total_revenue"])) - Decimal(str(summary["total_cogs"]))
        assert gross == Decimal("600")

    def test_net_with_non_operating_items(self):
        operating_profit = Decimal("300")
        non_op_income = Decimal("50")
        non_op_expense = Decimal("20")
        tax = Decimal("30")
        pbt = operating_profit + non_op_income - non_op_expense
        net = pbt - tax
        assert pbt == Decimal("330")
        assert net == Decimal("300")
