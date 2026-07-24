"""تست نگاشت فیلتر نوع حساب."""
from __future__ import annotations

from app.services.account_balance_core import resolve_account_type_filter


class TestAccountTypeFilter:
    def test_bank_aliases(self):
        assert resolve_account_type_filter("bank") == ("bank", "3")

    def test_cash_register_aliases(self):
        assert resolve_account_type_filter("cash_register") == ("cash_register", "1")

    def test_unknown_type_passthrough(self):
        assert resolve_account_type_filter("custom_type") == ("custom_type",)

    def test_none_and_empty(self):
        assert resolve_account_type_filter(None) is None
        assert resolve_account_type_filter("") is None
