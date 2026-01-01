#!/usr/bin/env python3
"""
اسکریپت بررسی وضعیت sandbox_mode برای کسب‌وکار مشخص
"""

import sys
import os

# اضافه کردن مسیر پروژه به sys.path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from adapters.db.session import get_db_session
from adapters.db.models.tax_setting import TaxSetting
from app.core.settings import get_settings
from app.integrations.moadian.client import MoadianClient


def check_tax_sandbox_mode(business_id: int):
    """بررسی وضعیت sandbox_mode برای کسب‌وکار مشخص"""
    
    print(f"\n{'='*60}")
    print(f"بررسی وضعیت Sandbox برای کسب‌وکار ID: {business_id}")
    print(f"{'='*60}\n")
    
    with get_db_session() as db:
        # دریافت تنظیمات مالیاتی
        tax_setting = (
            db.query(TaxSetting)
            .filter(TaxSetting.business_id == business_id)
            .first()
        )
        
        if not tax_setting:
            print(f"❌ تنظیمات مالیاتی برای کسب‌وکار {business_id} یافت نشد!")
            return
        
        # نمایش اطلاعات
        print(f"📋 اطلاعات تنظیمات مالیاتی:")
        print(f"   - Business ID: {tax_setting.business_id}")
        print(f"   - Tax Memory ID: {tax_setting.tax_memory_id or 'تعریف نشده'}")
        print(f"   - Economic Code: {tax_setting.economic_code or 'تعریف نشده'}")
        print(f"   - Sandbox Mode: {tax_setting.sandbox_mode}")
        print(f"   - Updated At: {tax_setting.updated_at}")
        print()
        
        # بررسی URL استفاده شده
        settings = get_settings()
        sandbox = bool(tax_setting.sandbox_mode)
        base_url = settings.tax_system_sandbox_base_url if sandbox else settings.tax_system_production_base_url
        
        print(f"🌐 URL استفاده شده:")
        print(f"   - Sandbox Mode: {'✅ فعال' if sandbox else '❌ غیرفعال'}")
        print(f"   - Base URL: {base_url}")
        print()
        
        # نمایش URLهای موجود
        print(f"📌 URLهای موجود در تنظیمات:")
        print(f"   - Sandbox URL: {settings.tax_system_sandbox_base_url}")
        print(f"   - Production URL: {settings.tax_system_production_base_url}")
        print()
        
        # نتیجه‌گیری
        if sandbox:
            print(f"⚠️  هشدار: محیط سندباکس فعال است!")
            print(f"   - فاکتورها به {base_url} ارسال می‌شوند")
            print(f"   - فاکتورها در سایت production (tp.tax.gov.ir) دیده نمی‌شوند")
            print(f"   - باید در سایت sandbox (sandboxrc.tax.gov.ir) جستجو کنید")
        else:
            print(f"✅ محیط Production فعال است")
            print(f"   - فاکتورها به {base_url} ارسال می‌شوند")
            print(f"   - فاکتورها در سایت production قابل مشاهده هستند")
        
        print(f"\n{'='*60}\n")


if __name__ == "__main__":
    business_id = 51
    
    if len(sys.argv) > 1:
        try:
            business_id = int(sys.argv[1])
        except ValueError:
            print(f"❌ خطا: Business ID باید یک عدد باشد!")
            sys.exit(1)
    
    try:
        check_tax_sandbox_mode(business_id)
    except Exception as e:
        print(f"❌ خطا در بررسی: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)





