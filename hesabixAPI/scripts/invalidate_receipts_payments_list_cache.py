#!/usr/bin/env python3
"""
پاک کردن کش لیست دریافت/پرداخت تا داده‌های به‌روز (مثل طرف حساب) از API برگردند.
بعد از backfill یا تغییر در document_to_dict اجرا کنید.
"""
from __future__ import annotations

import sys
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.core.cache import get_cache


def main() -> None:
    cache = get_cache()
    if not cache.enabled:
        print("کش غیرفعال است. نیازی به پاک‌سازی نیست.")
        return
    n = cache.delete_pattern("receipts_payments_list:*")
    print(f"تعداد کلیدهای کش لیست دریافت/پرداخت پاک‌شده: {n}")
    print("کش لیست دریافت/پرداخت پاک شد. در درخواست بعدی لیست، داده از دیتابیس خوانده می‌شود.")


if __name__ == "__main__":
    main()
