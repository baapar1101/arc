"""تست هسته مانده‌گیری و حالت‌های تراز آزمایشی."""
from __future__ import annotations

from decimal import Decimal

from app.services.account_balance_core import (
    AccountBalance,
    apply_column_mode,
    split_debit_credit_balance,
    validate_trial_balance,
)


class TestAccountBalanceCore:
    def test_split_debit_credit_positive(self):
        debit, credit = split_debit_credit_balance(Decimal("1500"))
        assert debit == Decimal("1500")
        assert credit == Decimal("0")

    def test_split_debit_credit_negative(self):
        debit, credit = split_debit_credit_balance(Decimal("-250"))
        assert debit == Decimal("0")
        assert credit == Decimal("250")

    def test_column_mode_2(self):
        item = {
            "opening_debit": 1,
            "opening_credit": 2,
            "period_debit": 3,
            "period_credit": 4,
            "closing_debit": 5,
            "closing_credit": 6,
        }
        row = apply_column_mode(item, 2)
        assert "opening_debit" not in row
        assert "period_debit" not in row
        assert row["closing_debit"] == 5

    def test_column_mode_4(self):
        item = {
            "opening_debit": 1,
            "opening_credit": 2,
            "period_debit": 3,
            "period_credit": 4,
            "closing_debit": 5,
            "closing_credit": 6,
        }
        row = apply_column_mode(item, 4)
        assert "opening_debit" not in row
        assert row["period_debit"] == 3

    def test_validate_balanced(self):
        totals = {
            "opening_debit": Decimal("1000"),
            "opening_credit": Decimal("1000"),
            "period_debit": Decimal("500"),
            "period_credit": Decimal("500"),
            "closing_debit": Decimal("1500"),
            "closing_credit": Decimal("1500"),
        }
        result = validate_trial_balance(totals)
        assert result["balance_valid"] is True

    def test_account_balance_closing(self):
        bal = AccountBalance(Decimal("100"), Decimal("20"), Decimal("50"), Decimal("10"))
        assert bal.closing_net == Decimal("120")
