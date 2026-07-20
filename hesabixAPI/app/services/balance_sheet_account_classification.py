"""طبقه‌بندی حساب‌های ترازنامه (گروه‌های ۱، ۲، ۳) بر اساس چارت حساب استاندارد ایرانی."""
from __future__ import annotations

from typing import Optional

_PERSIAN_DIGITS = str.maketrans("۰۱۲۳۴۵۶۷۸۹", "0123456789")

# حساب‌هایی که مانده بستانکار دارند ولی در بخش دارایی‌ها قرار می‌گیرند (کاهنده دارایی)
CONTRA_ASSET_CODE_PREFIXES = (
    "108",  # استهلاک انباشته
    "10402",  # ذخیره مطالبات مشکوک‌الوصول
)

# پیشوند بخش‌های جاری/غیرجاری — دارایی
CURRENT_ASSET_PREFIXES = ("101", "102", "103", "104", "105")
NON_CURRENT_ASSET_PREFIXES = ("106", "107", "108", "109", "110")

# پیشوند بخش‌های جاری/غیرجاری — بدهی
CURRENT_LIABILITY_PREFIXES = ("201", "202", "203", "204")
NON_CURRENT_LIABILITY_PREFIXES = ("205", "206")

# کد حساب سود انباشته سنواتی
RETAINED_EARNINGS_CODE = "30106"

# کد حساب سهم سود و زیان (ممکن است در بستن سال استفاده شود)
CURRENT_YEAR_PROFIT_SHARE_CODE = "30105"


def normalize_account_code(code: str | None) -> str:
    if not code:
        return ""
    return str(code).strip().translate(_PERSIAN_DIGITS)


def _starts_with_any(code_clean: str, prefixes: tuple[str, ...]) -> bool:
    return any(code_clean.startswith(p) for p in prefixes)


def is_permanent_account(code: str | None) -> bool:
    """حساب دائم: گروه ۱ (دارایی)، ۲ (بدهی)، ۳ (حقوق صاحبان سهام)."""
    code_clean = normalize_account_code(code)
    if not code_clean:
        return False
    return code_clean[0] in ("1", "2", "3")


def is_asset_account(code: str | None) -> bool:
    code_clean = normalize_account_code(code)
    return bool(code_clean) and code_clean[0] == "1"


def is_liability_account(code: str | None) -> bool:
    code_clean = normalize_account_code(code)
    return bool(code_clean) and code_clean[0] == "2"


def is_equity_account(code: str | None) -> bool:
    code_clean = normalize_account_code(code)
    return bool(code_clean) and code_clean[0] == "3"


def is_contra_asset_account(code: str | None) -> bool:
    code_clean = normalize_account_code(code)
    if not code_clean:
        return False
    return _starts_with_any(code_clean, CONTRA_ASSET_CODE_PREFIXES)


def is_current_asset_account(code: str | None) -> bool:
    code_clean = normalize_account_code(code)
    if not code_clean or not is_asset_account(code_clean):
        return False
    if is_contra_asset_account(code_clean):
        return False
    return _starts_with_any(code_clean, CURRENT_ASSET_PREFIXES)


def is_non_current_asset_account(code: str | None) -> bool:
    code_clean = normalize_account_code(code)
    if not code_clean or not is_asset_account(code_clean):
        return False
    if is_contra_asset_account(code_clean):
        return True
    return _starts_with_any(code_clean, NON_CURRENT_ASSET_PREFIXES)


def is_current_liability_account(code: str | None) -> bool:
    code_clean = normalize_account_code(code)
    if not code_clean or not is_liability_account(code_clean):
        return False
    return _starts_with_any(code_clean, CURRENT_LIABILITY_PREFIXES)


def is_non_current_liability_account(code: str | None) -> bool:
    code_clean = normalize_account_code(code)
    if not code_clean or not is_liability_account(code_clean):
        return False
    return _starts_with_any(code_clean, NON_CURRENT_LIABILITY_PREFIXES)


def is_retained_earnings_account(code: str | None) -> bool:
    code_clean = normalize_account_code(code)
    return code_clean == RETAINED_EARNINGS_CODE or code_clean.startswith(RETAINED_EARNINGS_CODE)


def balance_sheet_main_section(code: str | None) -> Optional[str]:
    """بخش اصلی ترازنامه: assets | liabilities | equity."""
    if is_asset_account(code):
        return "assets"
    if is_liability_account(code):
        return "liabilities"
    if is_equity_account(code):
        return "equity"
    return None


def balance_sheet_subsection(code: str | None) -> Optional[str]:
    """زیربخش ترازنامه."""
    if is_current_asset_account(code):
        return "current_assets"
    if is_non_current_asset_account(code):
        return "non_current_assets"
    if is_current_liability_account(code):
        return "current_liabilities"
    if is_non_current_liability_account(code):
        return "non_current_liabilities"
    if is_equity_account(code):
        return "equity"
    return None


def balance_sheet_normal_side(code: str | None) -> str:
    """طرف طبیعی مانده: debit برای دارایی، credit برای بدهی و حقوق صاحبان سهام."""
    if is_liability_account(code) or is_equity_account(code):
        return "credit"
    return "debit"


def balance_sheet_presentation_amount(
    debit: float,
    credit: float,
    code: str | None,
) -> float:
    """مبلغ نمایشی ترازنامه با رعایت طرف طبیعی حساب."""
    net_debit = debit - credit
    side = balance_sheet_normal_side(code)
    if side == "credit":
        return float(-net_debit)
    return float(net_debit)


BS_SECTION_LABELS_FA = {
    "current_assets": "دارایی‌های جاری",
    "non_current_assets": "دارایی‌های غیرجاری",
    "current_liabilities": "بدهی‌های جاری",
    "non_current_liabilities": "بدهی‌های غیرجاری",
    "equity": "حقوق صاحبان سهام",
    "current_period_profit": "سود (زیان) دوره جاری",
}

BS_SECTION_LABELS_EN = {
    "current_assets": "Current Assets",
    "non_current_assets": "Non-Current Assets",
    "current_liabilities": "Current Liabilities",
    "non_current_liabilities": "Non-Current Liabilities",
    "equity": "Shareholders' Equity",
    "current_period_profit": "Current Period Profit (Loss)",
}

BS_MAIN_SECTION_LABELS_FA = {
    "assets": "دارایی‌ها",
    "liabilities": "بدهی‌ها",
    "equity": "حقوق صاحبان سهام",
}

BS_MAIN_SECTION_LABELS_EN = {
    "assets": "Assets",
    "liabilities": "Liabilities",
    "equity": "Shareholders' Equity",
}
