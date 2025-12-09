"""
اسکریپت مستقیم برای اضافه کردن افزونه تعمیرگاه
"""
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from adapters.db.session import SessionLocal
from adapters.db.models.marketplace import MarketplacePlugin, MarketplacePluginPlan
from adapters.db.models.currency import Currency


def main():
    db = SessionLocal()
    
    try:
        # بررسی وجود قبلی
        existing = db.query(MarketplacePlugin).filter(
            MarketplacePlugin.code == 'repair_shop_management'
        ).first()
        
        if existing:
            print(f"\n✅ افزونه قبلاً ثبت شده است (ID: {existing.id})")
            return
        
        # دریافت ارز تومان
        currency = db.query(Currency).filter(Currency.code == 'IRR').first()
        if not currency:
            print("❌ ارز تومان (IRR) یافت نشد!")
            return
        
        print("\n🔧 در حال ثبت افزونه مدیریت تعمیرگاه...")
        
        # ایجاد افزونه
        plugin = MarketplacePlugin(
            code='repair_shop_management',
            name='مدیریت تعمیرگاه',
            description="""سیستم جامع مدیریت تعمیرگاه با قابلیت‌های زیر:

✅ دریافت و تحویل کالای تعمیری
✅ صدور قبض رسید کالا
✅ کارتابل تعمیرات (Kanban Board)
✅ یکپارچگی با سیستم گارانتی
✅ مدیریت تعمیرکاران و حق‌الزحمه (فیکس، درصدی، موردی)
✅ افزودن قطعات استفاده شده
✅ حواله خروج خودکار قطعات از انبار
✅ بررسی موجودی قبل از مصرف
✅ ارسال پیامک و ایمیل خودکار به مشتری
✅ صدور فاکتور تعمیر (خدمات + قطعات)
✅ ثبت خودکار اسناد حسابداری
✅ تاریخچه کامل تعمیرات براساس کد گارانتی
✅ گزارش‌گیری جامع از عملکرد تعمیرکاران
✅ مدیریت ضمائم و تصاویر (قبل/بعد تعمیر)
✅ کنترل سطح دسترسی کاربران

مناسب برای:
🔧 تعمیرگاه‌های لوازم الکترونیکی
📱 مراکز تعمیر موبایل و تبلت
💻 سرویس‌های تعمیر لپتاپ و کامپیوتر
🏠 تعمیرگاه‌های لوازم خانگی
🚗 مراکز خدمات خودرو""",
            category='operations',
            icon_url='/assets/icons/repair_shop.svg',
            is_active=True,
            trial_days=14,
            trial_allowed=True,
        )
        
        db.add(plugin)
        db.flush()
        
        print(f"✅ افزونه ایجاد شد (ID: {plugin.id})")
        
        # ایجاد پلن ماهانه
        plan_monthly = MarketplacePluginPlan(
            plugin_id=plugin.id,
            period='monthly',
            price=500000,
            currency_id=currency.id,
            is_active=True,
        )
        db.add(plan_monthly)
        print("   ✅ پلن ماهانه: 500,000 تومان")
        
        # ایجاد پلن سالانه
        plan_yearly = MarketplacePluginPlan(
            plugin_id=plugin.id,
            period='yearly',
            price=5000000,
            currency_id=currency.id,
            is_active=True,
        )
        db.add(plan_yearly)
        print("   ✅ پلن سالانه: 5,000,000 تومان")
        
        db.commit()
        
        print("\n" + "="*60)
        print("✅ افزونه مدیریت تعمیرگاه با موفقیت ثبت شد!")
        print("="*60)
        print(f"\n📦 کد افزونه: {plugin.code}")
        print(f"🏷️  نام: {plugin.name}")
        print(f"🎁 دوره آزمایشی: {plugin.trial_days} روز")
        print("\n🔗 API Endpoint:")
        print("   GET /api/v1/marketplace/plugins")
        print("\n🚀 برای شروع trial:")
        print("   POST /api/v1/marketplace/business/{business_id}/plugins/{plugin_id}/start-trial")
        print()
        
    except Exception as e:
        db.rollback()
        print(f"\n❌ خطا: {e}")
        import traceback
        traceback.print_exc()
    
    finally:
        db.close()


if __name__ == "__main__":
    main()




