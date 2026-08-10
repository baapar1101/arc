"""تست‌های فاز ۳ چندارزی: ترازنامه دوستونه، CFS غیرمستقیم، کیفیت داده."""
import inspect

from app.services.balance_sheet_service import get_balance_sheet_report
from app.services.cash_flow_report_service import get_cash_flow_report
from app.services.financial_package_service import get_financial_package_report
from app.services.fx_data_quality_service import get_missing_base_amount_warnings


def test_balance_sheet_supports_include_base_equivalent():
    sig = inspect.signature(get_balance_sheet_report)
    assert "include_base_equivalent" in sig.parameters


def test_financial_package_supports_include_base_equivalent():
    sig = inspect.signature(get_financial_package_report)
    assert "include_base_equivalent" in sig.parameters


def test_cash_flow_supports_include_indirect():
    sig = inspect.signature(get_cash_flow_report)
    assert "include_indirect" in sig.parameters


def test_fx_data_quality_service_export():
    sig = inspect.signature(get_missing_base_amount_warnings)
    assert "business_id" in sig.parameters
    assert "sample_limit" in sig.parameters


def test_bs_statement_lines_carry_amount_base_when_in_summary():
    """وقتی summary دارای *_base باشد، subtotal در statement_lines هم amount_base دارد."""
    from app.services.balance_sheet_service import _build_statement_lines

    grouped = {
        "current_assets": [],
        "non_current_assets": [],
        "current_liabilities": [],
        "non_current_liabilities": [],
        "equity": [],
    }
    summary = {
        "total_current_assets": 10.0,
        "total_non_current_assets": 0.0,
        "total_assets": 10.0,
        "total_current_liabilities": 0.0,
        "total_non_current_liabilities": 0.0,
        "total_liabilities": 0.0,
        "total_equity_accounts": 0.0,
        "current_period_profit": 0.0,
        "total_equity": 10.0,
        "total_liabilities_and_equity": 10.0,
        "balance_difference": 0.0,
        "total_assets_base": 100.0,
        "total_equity_base": 100.0,
        "total_liabilities_and_equity_base": 100.0,
    }
    lines = _build_statement_lines(grouped, summary)
    assets = next(l for l in lines if l.get("type") == "subtotal" and l.get("section") == "assets")
    assert assets.get("amount_base") == 100.0
