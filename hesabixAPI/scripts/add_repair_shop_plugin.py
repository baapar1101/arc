"""
اسکریپت ثبت افزونه مدیریت تعمیرگاه در بازار افزونه‌ها

استفاده:
    python scripts/add_repair_shop_plugin.py
"""
import sys
import os

# اضافه کردن مسیر پروژه به PYTHONPATH
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from adapters.db.session import get_db_session
from adapters.db.models.marketplace import MarketplacePlugin, MarketplacePluginPlan
from adapters.db.models.currency import Currency


def main():
    """ثبت افزونه مدیریت تعمیرگاه"""
    db = next(get_db_session())
    
    try:
        # بررسی اینکه آیا افزونه قبلاً ثبت شده
        existing_plugin = db.query(MarketplacePlugin).filter(
            MarketplacePlugin.code == 'repair_shop_management'
        ).first()
        
        if existing_plugin:
            print(f"✅ افزونه قبلاً ثبت شده است (ID: {existing_plugin.id})")
            print(f"   نام: {existing_plugin.name}")
            print(f"   وضعیت: {'فعال' if existing_plugin.is_active else 'غیرفعال'}")
            
            # به‌روزرسانی توضیحات
            update = input("\n❓ آیا می‌خواهید توضیحات را به‌روزرسانی کنید؟ (y/n): ")
            if update.lower() == 'y':
                existing_plugin.description = """
سیستم جامع مدیریت تعمیرگاه با قابلیت‌های زیر:

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
🚗 مراکز خدمات خودرو
                """.strip()
                db.commit()
                print("✅ توضیحات به‌روزرسانی شد")
            
            return
        
        # دریافت ارز پیش‌فرض (تومان)
        currency = db.query(Currency).filter(Currency.code == 'IRR').first()
        if not currency:
            print("❌ ارز تومان (IRR) یافت نشد. ابتدا باید ارز را اضافه کنید.")
            return
        
        # ایجاد افزونه جدید
        plugin = MarketplacePlugin(
            code='repair_shop_management',
            name='مدیریت تعمیرگاه',
            description="""
سیستم جامع مدیریت تعمیرگاه با قابلیت‌های زیر:

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
🚗 مراکز خدمات خودرو
            """.strip(),
            category='operations',
            icon_url='/assets/icons/repair_shop.svg',
            is_active=True,
            trial_days=14,
            trial_allowed=True,
        )
        
        db.add(plugin)
        db.flush()
        
        print(f"✅ افزونه ایجاد شد (ID: {plugin.id})")
        
        # ایجاد پلن‌های قیمت‌گذاری
        plans_data = [
            {
                'period': 'monthly',
                'price': 500000,  # 500 هزار تومان
                'description': 'اشتراک ماهانه'
            },
            {
                'period': 'yearly',
                'price': 5000000,  # 5 میلیون تومان (حدود 17% تخفیف)
                'description': 'اشتراک سالانه'
            },
        ]
        
        for plan_data in plans_data:
            plan = MarketplacePluginPlan(
                plugin_id=plugin.id,
                period=plan_data['period'],
                price=plan_data['price'],
                currency_id=currency.id,
                is_active=True,
            )
            db.add(plan)
            print(f"   ✅ پلن {plan_data['description']} ایجاد شد ({plan_data['price']:,} تومان)")
        
        db.commit()
        
        print("\n" + "="*60)
        print("✅ افزونه مدیریت تعمیرگاه با موفقیت ثبت شد!")
        print("="*60)
        print(f"\n📦 کد افزونه: {plugin.code}")
        print(f"🏷️  نام: {plugin.name}")
        print(f"🎁 دوره آزمایشی: {plugin.trial_days} روز")
        print(f"💰 قیمت ماهانه: 500,000 تومان")
        print(f"💰 قیمت سالانه: 5,000,000 تومان")
        print("\n🔗 کاربران می‌توانند از بخش بازار افزونه‌ها این افزونه را خریداری کنند.")
        
    except Exception as e:
        db.rollback()
        print(f"\n❌ خطا: {e}")
        import traceback
        traceback.print_exc()
    
    finally:
        db.close()


if __name__ == "__main__":
    main()

