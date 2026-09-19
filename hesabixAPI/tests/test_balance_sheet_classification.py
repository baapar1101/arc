"""تست طبقه‌بندی حساب‌های ترازنامه."""
from __future__ import annotations

from app.services.balance_sheet_account_classification import (
    balance_sheet_main_section,
    balance_sheet_presentation_amount,
    balance_sheet_subsection,
    is_current_asset_account,
    is_current_liability_account,
    is_non_current_asset_account,
    is_non_current_liability_account,
    is_permanent_account,
)


class TestBalanceSheetClassification:
    def test_permanent_accounts(self):
        assert is_permanent_account("1")
        assert is_permanent_account("101")
        assert is_permanent_account("30106")
        assert not is_permanent_account("50001")
        assert not is_permanent_account("70201")

    def test_asset_sections(self):
        assert balance_sheet_main_section("10203") == "assets"
        assert is_current_asset_account("10203")
        assert not is_non_current_asset_account("10203")
        assert is_non_current_asset_account("10702")
        assert is_non_current_asset_account("10801")

    def test_liability_sections(self):
        assert balance_sheet_main_section("20201") == "liabilities"
        assert is_current_liability_account("20201")
        assert is_non_current_liability_account("20501")
        assert balance_sheet_subsection("20501") == "non_current_liabilities"

    def test_equity_section(self):
        assert balance_sheet_main_section("30106") == "equity"
        assert balance_sheet_subsection("30106") == "equity"

    def test_presentation_amount(self):
        assert balance_sheet_presentation_amount(1000, 0, "10203") == 1000
        assert balance_sheet_presentation_amount(0, 1000, "20201") == 1000
        assert balance_sheet_presentation_amount(200, 500, "30106") == 300
