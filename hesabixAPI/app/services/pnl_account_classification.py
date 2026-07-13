"""طبقه‌بندی حساب‌های موقت سود و زیان (گروه‌های ۴، ۵، ۶، ۷).

مبنا: چارت حساب استاندارد ایرانی + استثناهای شناخته‌شده (مثل 50101).
"""
from __future__ import annotations

from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from adapters.db.models.account import Account

_PERSIAN_DIGITS = str.maketrans("۰۱۲۳۴۵۶۷۸۹", "0123456789")

# حساب‌هایی که با پیشوند درآمد اشتباه گرفته می‌شوند ولی هزینه‌اند
PNL_EXPENSE_OVERRIDE_CODES = frozenset({"50101"})

# حساب‌هایی که هرگز در بستن سود و زیان شرکت نمی‌کنند (زیردفتر)
PNL_NON_GL_ACCOUNT_TYPES = frozenset({
    "person",
    "bank",
    "product",
    "cash_register",
    "petty_cash",
    "check",
})


def normalize_account_code(code: str | None) -> str:
    if not code:
        return ""
    return str(code).strip().translate(_PERSIAN_DIGITS)


def is_pnl_revenue_account(code: str | None) -> bool:
    """گروه ۵ (فروش) و ۶ (درآمد) — بدون 50101."""
    code_clean = normalize_account_code(code)
    if not code_clean or code_clean in PNL_EXPENSE_OVERRIDE_CODES:
        return False
    return (
        code_clean.startswith("5")
        or code_clean.startswith("6")
        or code_clean.startswith("۵")
        or code_clean.startswith("۶")
    )


def is_pnl_expense_account(code: str | None) -> bool:
    """گروه ۴ (بهای تمام‌شده) و ۷ (هزینه) + استثناهای هزینه."""
    code_clean = normalize_account_code(code)
    if not code_clean:
        return False
    if code_clean in PNL_EXPENSE_OVERRIDE_CODES:
        return True
    return (
        code_clean.startswith("4")
        or code_clean.startswith("7")
        or code_clean.startswith("۴")
        or code_clean.startswith("۷")
    )


def is_pnl_temporary_gl_account(account: Account) -> bool:
    """آیا حساب در بستن/گزارش سود و زیان لحاظ شود؟"""
    account_type = (account.account_type or "").strip().lower()
    if account_type in PNL_NON_GL_ACCOUNT_TYPES:
        return False
    code = account.code
    return is_pnl_revenue_account(code) or is_pnl_expense_account(code)


def is_pnl_revenue_gl_account(account: Account) -> bool:
    return is_pnl_temporary_gl_account(account) and is_pnl_revenue_account(account.code)


def is_pnl_expense_gl_account(account: Account) -> bool:
    return is_pnl_temporary_gl_account(account) and is_pnl_expense_account(account.code)
