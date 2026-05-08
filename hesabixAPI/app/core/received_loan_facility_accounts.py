"""کدهای ثابت حساب‌های عمومی مرتبط با تسهیلات دریافتی کسب‌وکار.

میگریشن `20260613_000001_seed_received_loan_facility_chart_accounts` حساب‌های
بدهی 20505–20507 را زیر گروه «وام پرداختنی» (20501) اضافه می‌کند.

هزینه بهره و جریمه از حساب‌های ازپیش‌دادهٔ نمودار استفاده می‌کنند.
"""

from __future__ import annotations

# بدهی: اصل تسهیلات (معین کنترلی)
RECEIVED_LOAN_PRINCIPAL_PAYABLE_CODE = "20505"
# بدهی: ذخیره / بهره پرداختنی تا زمان پرداخت
RECEIVED_LOAN_ACCRUED_INTEREST_PAYABLE_CODE = "20506"
# بدهی: وجه التزام / جریمه پرداختنی
RECEIVED_LOAN_ACCRUED_PENALTY_PAYABLE_CODE = "20507"

# هزینه بهره تسهیلات (درخت موجود)
LOAN_BANKING_INTEREST_EXPENSE_CODE = "70901"
# جرائم دیرکرد بانکی (درخت موجود)
LOAN_BANKING_LATE_FEE_EXPENSE_CODE = "70903"
