"""seed repair shop plugin in marketplace

Revision ID: 20250205_000002_seed_repair_shop_plugin
Revises: 20250205_000001_create_repair_shop_tables
Create Date: 2025-02-05 00:00:02.000000

"""
from alembic import op
import sqlalchemy as sa
from datetime import datetime

# revision identifiers, used by Alembic.
revision = '20250205_000002_seed_repair_shop_plugin'
down_revision = '20250205_000001_create_repair_shop_tables'
branch_labels = None
depends_on = None


def upgrade():
    """اضافه کردن افزونه مدیریت تعمیرگاه به marketplace"""
    
    conn = op.get_bind()
    
    # بررسی اینکه آیا افزونه قبلاً وجود دارد
    result = conn.execute(sa.text(
        "SELECT id FROM marketplace_plugins WHERE code = 'repair_shop_management'"
    ))
    existing_plugin = result.fetchone()
    
    if existing_plugin:
        print(f"✅ افزونه قبلاً وجود دارد (ID: {existing_plugin[0]})")
        return
    
    # دریافت ارز تومان
    result = conn.execute(sa.text("SELECT id FROM currencies WHERE code = 'IRR' LIMIT 1"))
    currency_row = result.fetchone()
    
    if not currency_row:
        print("⚠️ ارز تومان (IRR) یافت نشد. لطفاً ابتدا ارز را اضافه کنید.")
        return
    
    currency_id = currency_row[0]
    
    # اضافه کردن افزونه
    result = conn.execute(
        sa.text("""
            INSERT INTO marketplace_plugins 
            (code, name, description, category, icon_url, is_active, trial_days, trial_allowed, created_at, updated_at)
            VALUES 
            (:code, :name, :description, :category, :icon_url, :is_active, :trial_days, :trial_allowed, NOW(), NOW())
        """),
        {
            'code': 'repair_shop_management',
            'name': 'مدیریت تعمیرگاه',
            'description': """سیستم جامع مدیریت تعمیرگاه با قابلیت‌های زیر:

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
            'category': 'operations',
            'icon_url': '/assets/icons/repair_shop.svg',
            'is_active': True,
            'trial_days': 14,
            'trial_allowed': True,
        }
    )
    
    # دریافت ID افزونه ایجاد شده
    result = conn.execute(sa.text(
        "SELECT id FROM marketplace_plugins WHERE code = 'repair_shop_management'"
    ))
    plugin_row = result.fetchone()
    plugin_id = plugin_row[0]
    
    print(f"✅ افزونه ایجاد شد (ID: {plugin_id})")
    
    # اضافه کردن پلن ماهانه
    conn.execute(
        sa.text("""
            INSERT INTO marketplace_plugin_plans 
            (plugin_id, period, price, currency_id, is_active, created_at, updated_at)
            VALUES 
            (:plugin_id, :period, :price, :currency_id, :is_active, NOW(), NOW())
        """),
        {
            'plugin_id': plugin_id,
            'period': 'monthly',
            'price': 500000,
            'currency_id': currency_id,
            'is_active': True,
        }
    )
    print("   ✅ پلن ماهانه ایجاد شد (500,000 تومان)")
    
    # اضافه کردن پلن سالانه
    conn.execute(
        sa.text("""
            INSERT INTO marketplace_plugin_plans 
            (plugin_id, period, price, currency_id, is_active, created_at, updated_at)
            VALUES 
            (:plugin_id, :period, :price, :currency_id, :is_active, NOW(), NOW())
        """),
        {
            'plugin_id': plugin_id,
            'period': 'yearly',
            'price': 5000000,
            'currency_id': currency_id,
            'is_active': True,
        }
    )
    print("   ✅ پلن سالانه ایجاد شد (5,000,000 تومان)")
    
    print("\n" + "="*60)
    print("✅ افزونه مدیریت تعمیرگاه با موفقیت در marketplace ثبت شد!")
    print("="*60)


def downgrade():
    """حذف افزونه مدیریت تعمیرگاه از marketplace"""
    
    conn = op.get_bind()
    
    # دریافت ID افزونه
    result = conn.execute(sa.text(
        "SELECT id FROM marketplace_plugins WHERE code = 'repair_shop_management'"
    ))
    plugin_row = result.fetchone()
    
    if not plugin_row:
        print("⚠️ افزونه یافت نشد")
        return
    
    plugin_id = plugin_row[0]
    
    # حذف پلن‌ها
    conn.execute(
        sa.text("DELETE FROM marketplace_plugin_plans WHERE plugin_id = :plugin_id"),
        {'plugin_id': plugin_id}
    )
    
    # حذف افزونه
    conn.execute(
        sa.text("DELETE FROM marketplace_plugins WHERE id = :plugin_id"),
        {'plugin_id': plugin_id}
    )
    
    print("✅ افزونه مدیریت تعمیرگاه حذف شد")




