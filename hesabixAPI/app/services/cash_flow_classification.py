"""طبقه‌بندی جریان وجوه نقد بر اساس ماهیت حساب طرف مقابل (IAS 7 / چارت ایرانی)."""
from __future__ import annotations

from typing import Iterable, Optional, Set


_PERSIAN = str.maketrans("۰۱۲۳۴۵۶۷۸۹", "0123456789")


def _norm(code: Optional[str]) -> str:
    if not code:
        return ""
    return str(code).strip().translate(_PERSIAN)


def _startswith_any(code: str, prefixes: tuple[str, ...]) -> bool:
    return any(code.startswith(p) for p in prefixes)


# سرمایه‌گذاری: دارایی ثابت، نامشهود، سپرده بلندمدت، سپرده کوتاه‌مدت سرمایه‌ای
INVESTING_PREFIXES = (
    "107",  # دارایی‌های ثابت
    "108",  # استهلاک انباشته (فروش/اسقاط دارایی)
    "109",  # سپرده بلندمدت
    "110",  # سایر دارایی‌ها / نامشهود
    "103",  # سپرده‌های کوتاه‌مدت (نزدیک سرمایه‌گذاری)
)

# تأمین مالی: وام، بدهی غیرجاری، سرمایه، سود سهام
FINANCING_PREFIXES = (
    "205",  # بدهی غیرجاری / وام / تسهیلات
    "206",  # پرداختنی بلندمدت
    "301",  # سرمایه
    "302",  # اندوخته‌ها (در صورت وجود)
    "303",  # سود انباشته / تقسیم سود (در صورت وجود)
    "709",  # سود و کارمزد وام‌ها (انتخاب تأمین مالی طبق IAS 7)
)


def classify_cfs_section(
    *,
    document_type: Optional[str],
    is_fx_revaluation: bool,
    counterpart_account_codes: Iterable[str],
    counterpart_is_only_cash: bool,
) -> str:
    """
    تعیین بخش صورت جریان وجوه برای یک حرکت نقدی.

    اولویت حسابداری:
    1) تسعیر ارز نقد
    2) انتقال بین حساب‌های نقدی (نه جریان واقعی)
    3) ماهیت حساب طرف مقابل (سرمایه‌گذاری / تأمین مالی)
    4) عملیات (پیش‌فرض برای دریافت/پرداخت/خرید/فروش/هزینه)
    """
    if is_fx_revaluation:
        return "fx_and_other"

    dtype = (document_type or "").strip().lower()
    if dtype == "transfer" or counterpart_is_only_cash:
        return "transfers"

    codes = [_norm(c) for c in counterpart_account_codes if _norm(c)]
    if any(_startswith_any(c, INVESTING_PREFIXES) for c in codes):
        return "investing"
    if any(_startswith_any(c, FINANCING_PREFIXES) for c in codes):
        return "financing"

    if dtype in {
        "receipt",
        "payment",
        "invoice_sales",
        "invoice_sales_return",
        "invoice_purchase",
        "invoice_purchase_return",
        "expense_income",
        "expense",
        "income",
        "invoice_direct_consumption",
        "invoice_waste",
        "invoice_production",
        "opening_balance",
    }:
        return "operating"

    # سند دستی بدون طرف سرمایه‌گذاری/تأمین مالی → سایر/عملیاتی
    if dtype in {"manual_document", "manual", "accounting_document"}:
        return "operating"

    return "fx_and_other"
