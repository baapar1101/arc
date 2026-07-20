"""بسته یکپارچه گزارش‌های مالی: تراز آزمایشی، ترازنامه و سود و زیان."""
from __future__ import annotations

from typing import Any, Dict, Optional

from sqlalchemy.orm import Session

from app.services.balance_sheet_service import get_balance_sheet_report
from app.services.pnl_service import get_pnl_period_report
from app.services.trial_balance_service import get_trial_balance_report


def get_financial_package_report(
    db: Session,
    business_id: int,
    *,
    fiscal_year_id: Optional[int] = None,
    currency_id: Optional[int] = None,
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
    project_id: Optional[int] = None,
    include_zero_balance: bool = False,
    account_level: int = 4,
    column_mode: int = 8,
    compare_prior_period: bool = False,
    compare_mode: Optional[str] = None,
) -> Dict[str, Any]:
    """
    جمع‌آوری سه گزارش مالی با پارامترهای یکسان.

    ترتیب استاندارد ارائه:
    ۱. تراز آزمایشی (کنترل تراز دفترداری)
    ۲. صورت سود و زیان (عملکرد دوره)
    ۳. ترازنامه (وضعیت مالی در پایان دوره)
    """
    trial_balance = get_trial_balance_report(
        db=db,
        business_id=business_id,
        fiscal_year_id=fiscal_year_id,
        currency_id=currency_id,
        date_from=date_from,
        date_to=date_to,
        project_id=project_id,
        include_zero_balance=include_zero_balance,
        column_mode=column_mode,
        display_mode="flat",
        account_level=account_level,
        skip=0,
        take=10000,
    )

    pnl_period = get_pnl_period_report(
        db=db,
        business_id=business_id,
        fiscal_year_id=fiscal_year_id,
        currency_id=currency_id,
        date_from=date_from,
        date_to=date_to,
        project_id=project_id,
        include_zero_balance=include_zero_balance,
        compare_prior_period=compare_prior_period,
        compare_mode=compare_mode,
        skip=0,
        take=10000,
    )

    balance_sheet = get_balance_sheet_report(
        db=db,
        business_id=business_id,
        fiscal_year_id=fiscal_year_id,
        currency_id=currency_id,
        date_from=date_from,
        date_to=date_to,
        project_id=project_id,
        include_zero_balance=include_zero_balance,
        account_level=account_level,
        compare_prior_period=compare_prior_period,
        compare_mode=compare_mode,
    )

    tb_summary = trial_balance.get("summary") or {}
    bs_summary = balance_sheet.get("summary") or {}
    pnl_summary = pnl_period.get("summary") or {}

    package_summary = {
        "trial_balance_valid": bool(tb_summary.get("balance_valid")),
        "trial_balance_opening_diff": float(tb_summary.get("opening_balance_diff", 0) or 0),
        "trial_balance_closing_diff": float(tb_summary.get("closing_balance_diff", 0) or 0),
        "total_assets": float(bs_summary.get("total_assets", 0) or 0),
        "total_liabilities": float(bs_summary.get("total_liabilities", 0) or 0),
        "total_equity": float(bs_summary.get("total_equity", 0) or 0),
        "balance_sheet_equation_balanced": bool(bs_summary.get("equation_balanced")),
        "balance_sheet_difference": float(bs_summary.get("balance_difference", 0) or 0),
        "net_profit_after_tax": float(
            pnl_summary.get("net_profit_after_tax", pnl_summary.get("net_profit_loss", 0)) or 0
        ),
        "total_revenue": float(pnl_summary.get("total_revenue", 0) or 0),
        "gross_profit": float(pnl_summary.get("gross_profit", 0) or 0),
        "operating_profit": float(pnl_summary.get("operating_profit", 0) or 0),
    }

    return {
        "trial_balance": trial_balance,
        "balance_sheet": balance_sheet,
        "pnl_period": pnl_period,
        "package_summary": package_summary,
        "meta": {
            "fiscal_year_id": fiscal_year_id,
            "currency_id": currency_id,
            "date_from": date_from,
            "date_to": date_to,
            "project_id": project_id,
            "account_level": account_level,
            "column_mode": column_mode,
            "compare_mode": compare_mode if compare_prior_period or compare_mode else None,
        },
    }
