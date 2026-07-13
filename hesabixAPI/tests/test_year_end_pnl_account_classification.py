"""تست طبقه‌بندی حساب‌های سود و زیان و منطق بستن سال مالی."""
from __future__ import annotations

from decimal import Decimal
from types import SimpleNamespace

from app.services.pnl_account_classification import (
    is_pnl_expense_account,
    is_pnl_expense_gl_account,
    is_pnl_revenue_account,
    is_pnl_revenue_gl_account,
)


def _account(code: str, account_type: str = "accounting_document") -> SimpleNamespace:
    return SimpleNamespace(code=code, account_type=account_type)


class TestPnlAccountClassification:
    def test_sales_accounts_are_revenue(self):
        assert is_pnl_revenue_account("50001")
        assert is_pnl_revenue_account("50003")
        assert is_pnl_revenue_gl_account(_account("50001"))

    def test_income_group6_accounts_are_revenue(self):
        assert is_pnl_revenue_account("60101")
        assert is_pnl_revenue_account("60204")
        assert is_pnl_revenue_gl_account(_account("60101"))

    def test_income_tax_expense_is_not_revenue(self):
        assert not is_pnl_revenue_account("50101")
        assert is_pnl_expense_account("50101")
        assert is_pnl_expense_gl_account(_account("50101"))
        assert not is_pnl_revenue_gl_account(_account("50101"))

    def test_cogs_and_expense_accounts(self):
        assert is_pnl_expense_account("40001")
        assert is_pnl_expense_account("70801")
        assert is_pnl_expense_gl_account(_account("70201"))

    def test_subledger_accounts_excluded_from_pnl_close(self):
        person_as_revenue_code = _account("603", "person")
        bank_as_expense_code = _account("70410", "bank")
        assert not is_pnl_revenue_gl_account(person_as_revenue_code)
        assert not is_pnl_expense_gl_account(bank_as_expense_code)

    def test_persian_digit_prefix_supported(self):
        assert is_pnl_revenue_account("۶۰۱۰۱")
        assert is_pnl_expense_account("۷۰۸۰۱")


def _simulate_summary_totals(
    revenue_items: list[dict],
    expense_items: list[dict],
) -> tuple[Decimal, Decimal]:
    """شبیه‌سازی منطق جمع درآمد/هزینه پس از پردازش همه حساب‌ها."""
    total_revenue = Decimal(0)
    total_expense = Decimal(0)

    for item in revenue_items:
        balance = Decimal(str(item["closing_balance"]))
        if balance > 0:
            total_revenue += balance
        elif balance < 0:
            total_expense += abs(balance)

    for item in expense_items:
        balance = Decimal(str(item["closing_balance"]))
        if balance > 0:
            total_expense += balance
        elif balance < 0:
            total_revenue += abs(balance)

    return total_revenue, total_expense


class TestYearEndSummaryTotals:
    def test_negative_expense_included_in_revenue_summary(self):
        revenue_items = [{"closing_balance": 100}]
        expense_items = [{"closing_balance": -20}]
        total_revenue, total_expense = _simulate_summary_totals(revenue_items, expense_items)
        assert total_revenue == Decimal("120")
        assert total_expense == Decimal("0")
        assert total_revenue - total_expense == Decimal("120")

    def test_negative_revenue_included_in_expense_summary(self):
        revenue_items = [{"closing_balance": -15}]
        expense_items = [{"closing_balance": 40}]
        total_revenue, total_expense = _simulate_summary_totals(revenue_items, expense_items)
        assert total_revenue == Decimal("0")
        assert total_expense == Decimal("55")
        assert total_revenue - total_expense == Decimal("-55")

    def test_mixed_real_world_case(self):
        revenue_items = [
            {"closing_balance": 4504000000},
            {"closing_balance": 73800000},
        ]
        expense_items = [{"closing_balance": -5465436}]
        total_revenue, total_expense = _simulate_summary_totals(revenue_items, expense_items)
        assert total_revenue == Decimal("4583265436")
        assert total_expense == Decimal("0")
