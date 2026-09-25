"""طبقه‌بندی حساب‌های موقت سود و زیان (گروه‌های ۴، ۵، ۶، ۷).

مبنا: چارت حساب استاندارد ایرانی + استثناهای شناخته‌شده (مثل 50101).
"""
from __future__ import annotations

from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from adapters.db.models.account import Account

_PERSIAN_DIGITS = str.maketrans("۰۱۲۳۴۵۶۷۸۹", "0123456789")

# حساب‌هایی که با پیشوند درآمد (گروه ۵) اشتباه گرفته می‌شوند ولی هزینه‌اند
PNL_EXPENSE_OVERRIDE_CODES = frozenset({"50101"})

# هزینه مالیات بر درآمد و زیرحساب‌های مرتبط
PNL_TAX_EXPENSE_CODES = frozenset({"50101"})

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


def _starts_with_any(code_clean: str, prefixes: tuple[str, ...]) -> bool:
    return any(code_clean.startswith(p) for p in prefixes)


def is_pnl_tax_expense_account(code: str | None) -> bool:
    """هزینه مالیات بر درآمد (۵۰۱۰۱ و زیرحساب‌ها)."""
    code_clean = normalize_account_code(code)
    if not code_clean:
        return False
    if code_clean in PNL_TAX_EXPENSE_CODES:
        return True
    return code_clean.startswith("50101")


def is_pnl_sales_account(code: str | None) -> bool:
    """گروه ۵ — فروش و درآمد عملیاتی."""
    code_clean = normalize_account_code(code)
    if not code_clean or code_clean in PNL_EXPENSE_OVERRIDE_CODES:
        return False
    return code_clean.startswith("5") or code_clean.startswith("۵")


def is_pnl_other_income_account(code: str | None) -> bool:
    """گروه ۶ — درآمد (عملیاتی و غیرعملیاتی)."""
    code_clean = normalize_account_code(code)
    if not code_clean:
        return False
    return code_clean.startswith("6") or code_clean.startswith("۶")


def is_pnl_operating_other_income_account(code: str | None) -> bool:
    """گروه ۶۰۱ — درآمدهای عملیاتی (خدمات و مشابه)."""
    code_clean = normalize_account_code(code)
    if not code_clean:
        return False
    return _starts_with_any(code_clean, ("601", "۶۰۱"))


def is_pnl_non_operating_income_account(code: str | None) -> bool:
    """گروه ۶۰۲ — درآمدهای غیرعملیاتی."""
    code_clean = normalize_account_code(code)
    if not code_clean:
        return False
    return _starts_with_any(code_clean, ("602", "۶۰۲"))


def is_pnl_cogs_account(code: str | None) -> bool:
    """گروه ۴ — بهای تمام‌شده کالای فروش‌رفته."""
    code_clean = normalize_account_code(code)
    if not code_clean or code_clean in PNL_EXPENSE_OVERRIDE_CODES:
        return False
    return code_clean.startswith("4") or code_clean.startswith("۴")


def is_pnl_non_operating_expense_account(code: str | None) -> bool:
    """گروه ۷۰۸/۷۰۹ — هزینه‌های غیرعملیاتی (تسعیر، بانکی و ...)."""
    code_clean = normalize_account_code(code)
    if not code_clean or is_pnl_tax_expense_account(code_clean):
        return False
    if not (code_clean.startswith("7") or code_clean.startswith("۷")):
        return False
    return _starts_with_any(code_clean, ("708", "709", "۷۰۸", "۷۰۹"))


def is_pnl_operating_expense_account(code: str | None) -> bool:
    """گروه ۷ — هزینه‌های عملیاتی (بدون مالیات و غیرعملیاتی)."""
    code_clean = normalize_account_code(code)
    if not code_clean or is_pnl_tax_expense_account(code_clean):
        return False
    if is_pnl_non_operating_expense_account(code_clean):
        return False
    return code_clean.startswith("7") or code_clean.startswith("۷")


def is_pnl_revenue_account(code: str | None) -> bool:
    """گروه ۵ (فروش) و ۶ (درآمد) — بدون 50101."""
    return is_pnl_sales_account(code) or is_pnl_other_income_account(code)


def is_pnl_expense_account(code: str | None) -> bool:
    """گروه ۴، ۷ و هزینه مالیات."""
    return (
        is_pnl_cogs_account(code)
        or is_pnl_operating_expense_account(code)
        or is_pnl_non_operating_expense_account(code)
        or is_pnl_tax_expense_account(code)
    )


def pnl_account_section(code: str | None) -> str | None:
    """بخش صورت سود و زیان."""
    if is_pnl_sales_account(code):
        return "sales"
    if is_pnl_operating_other_income_account(code):
        return "other_income"
    if is_pnl_non_operating_income_account(code):
        return "non_operating_income"
    if is_pnl_cogs_account(code):
        return "cogs"
    if is_pnl_tax_expense_account(code):
        return "tax_expense"
    if is_pnl_non_operating_expense_account(code):
        return "non_operating_expense"
    if is_pnl_operating_expense_account(code):
        return "operating_expense"
    return None


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
