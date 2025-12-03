"""افزودن افزونه گارانتی کالا به بازار افزونه‌ها

revision: 20250118_000001_add_product_warranty_plugin
down_revision: 20250117_000001
branch_labels: None
depends_on: None

این میگریشن:
1. افزونه "گارانتی کالا" را به جدول marketplace_plugins اضافه می‌کند
2. پلن‌های ماهانه و سالانه برای این افزونه ایجاد می‌کند
"""
from __future__ import annotations

from datetime import datetime
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '20250118_000001'
down_revision = '20250117_000001'
branch_labels = None
depends_on = None


def upgrade():
    """افزودن افزونه گارانتی کالا"""
    conn = op.get_bind()
    
    # پیدا کردن اولین ارز (معمولاً IRR)
    currency_result = conn.execute(sa.text("SELECT id FROM currencies ORDER BY id ASC LIMIT 1")).fetchone()
    if not currency_result:
        raise Exception("هیچ ارزی در سیستم یافت نشد. لطفاً ابتدا ارزها را اضافه کنید.")
    currency_id = currency_result[0]
    
    # بررسی اینکه آیا افزونه از قبل وجود دارد
    existing_plugin = conn.execute(
        sa.text("SELECT id FROM marketplace_plugins WHERE code = 'product_warranty' LIMIT 1")
    ).fetchone()
    
    if existing_plugin:
        # اگر از قبل وجود دارد، فقط اطمینان حاصل می‌کنیم که فعال است
        conn.execute(sa.text("""
            UPDATE marketplace_plugins
            SET is_active = 1,
                updated_at = NOW()
            WHERE code = 'product_warranty'
        """))
    else:
        # ایجاد افزونه گارانتی کالا
        now = datetime.utcnow()
        insert_plugin = sa.text("""
            INSERT INTO marketplace_plugins (
                code, name, description, category, icon_url, is_active, created_at, updated_at
            )
            VALUES (
                'product_warranty',
                'گارانتی کالا',
                'افزونه مدیریت گارانتی کالا - امکان ثبت و پیگیری گارانتی محصولات فروخته شده',
                'product_management',
                NULL,
                1,
                :created_at,
                :updated_at
            )
        """)
        conn.execute(insert_plugin, {"created_at": now, "updated_at": now})
    
    # دریافت ID افزونه
    plugin_result = conn.execute(
        sa.text("SELECT id FROM marketplace_plugins WHERE code = 'product_warranty' LIMIT 1")
    ).fetchone()
    plugin_id = plugin_result[0]
    
    # بررسی و ایجاد پلن ماهانه
    existing_monthly = conn.execute(
        sa.text("""
            SELECT id FROM marketplace_plugin_plans
            WHERE plugin_id = :plugin_id AND period = 'monthly'
            LIMIT 1
        """).bindparams(plugin_id=plugin_id)
    ).fetchone()
    
    if not existing_monthly:
        now = datetime.utcnow()
        insert_monthly = sa.text("""
            INSERT INTO marketplace_plugin_plans (
                plugin_id, period, price, currency_id, is_active, created_at, updated_at
            )
            VALUES (
                :plugin_id,
                'monthly',
                100000,
                :currency_id,
                1,
                :created_at,
                :updated_at
            )
        """)
        conn.execute(insert_monthly, {
            "plugin_id": plugin_id,
            "currency_id": currency_id,
            "created_at": now,
            "updated_at": now
        })
    
    # بررسی و ایجاد پلن سالانه
    existing_yearly = conn.execute(
        sa.text("""
            SELECT id FROM marketplace_plugin_plans
            WHERE plugin_id = :plugin_id AND period = 'yearly'
            LIMIT 1
        """).bindparams(plugin_id=plugin_id)
    ).fetchone()
    
    if not existing_yearly:
        now = datetime.utcnow()
        insert_yearly = sa.text("""
            INSERT INTO marketplace_plugin_plans (
                plugin_id, period, price, currency_id, is_active, created_at, updated_at
            )
            VALUES (
                :plugin_id,
                'yearly',
                1000000,
                :currency_id,
                1,
                :created_at,
                :updated_at
            )
        """)
        conn.execute(insert_yearly, {
            "plugin_id": plugin_id,
            "currency_id": currency_id,
            "created_at": now,
            "updated_at": now
        })


def downgrade():
    """حذف افزونه گارانتی کالا"""
    conn = op.get_bind()
    
    # حذف پلن‌ها
    conn.execute(sa.text("""
        DELETE FROM marketplace_plugin_plans
        WHERE plugin_id IN (
            SELECT id FROM marketplace_plugins WHERE code = 'product_warranty'
        )
    """))
    
    # حذف افزونه
    conn.execute(sa.text("""
        DELETE FROM marketplace_plugins
        WHERE code = 'product_warranty'
    """))

