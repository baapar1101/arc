"""remove phone and email from repair orders

Revision ID: 20251206_000001_remove_phone_email_from_repair_orders
Revises: 20251205_000001_add_projects_table
Create Date: 2025-12-06 00:00:01.000000

"""
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = '20251206_000001_remove_phone_email_from_repair_orders'
down_revision = '20250205_000002_seed_repair_shop_plugin'
branch_labels = None
depends_on = None


def upgrade():
    """
    حذف فیلدهای customer_phone و customer_email از جدول repair_orders
    این اطلاعات از جدول persons دریافت می‌شوند
    """
    from sqlalchemy import inspect
    
    bind = op.get_bind()
    inspector = inspect(bind)
    
    # بررسی وجود جدول
    tables = inspector.get_table_names()
    if 'repair_orders' not in tables:
        print("⚠️  جدول repair_orders وجود ندارد، migration skip می‌شود")
        return
    
    # دریافت لیست ستون‌های موجود
    columns = [col['name'] for col in inspector.get_columns('repair_orders')]
    
    # قبل از حذف، داده‌های موجود را به persons منتقل می‌کنیم (اختیاری)
    # این کار فقط در صورتی انجام می‌شود که داده‌ای در repair_orders باشد
    try:
        result = bind.execute(sa.text("SELECT COUNT(*) FROM repair_orders")).scalar()
        if result > 0:
            print(f"📊 {result} سفارش تعمیر موجود است")
            
            # به‌روزرسانی persons با داده‌های repair_orders (اگر خالی باشند)
            if 'customer_phone' in columns:
                bind.execute(sa.text("""
                    UPDATE persons p
                    INNER JOIN repair_orders ro ON p.id = ro.customer_person_id
                    SET p.mobile = COALESCE(p.mobile, ro.customer_phone)
                    WHERE ro.customer_phone IS NOT NULL 
                      AND ro.customer_phone != ''
                      AND (p.mobile IS NULL OR p.mobile = '')
                """))
                print("✅ داده‌های customer_phone به persons.mobile منتقل شد")
            
            if 'customer_email' in columns:
                bind.execute(sa.text("""
                    UPDATE persons p
                    INNER JOIN repair_orders ro ON p.id = ro.customer_person_id
                    SET p.email = COALESCE(p.email, ro.customer_email)
                    WHERE ro.customer_email IS NOT NULL 
                      AND ro.customer_email != ''
                      AND (p.email IS NULL OR p.email = '')
                """))
                print("✅ داده‌های customer_email به persons.email منتقل شد")
    except Exception as e:
        print(f"⚠️  خطا در انتقال داده‌ها (ادامه می‌دهیم): {e}")
    
    # حذف ستون‌ها
    if 'customer_phone' in columns:
        op.drop_column('repair_orders', 'customer_phone')
        print("✅ ستون customer_phone حذف شد")
    
    if 'customer_email' in columns:
        op.drop_column('repair_orders', 'customer_email')
        print("✅ ستون customer_email حذف شد")


def downgrade():
    """بازگردانی ستون‌ها"""
    from sqlalchemy import inspect
    
    bind = op.get_bind()
    inspector = inspect(bind)
    
    tables = inspector.get_table_names()
    if 'repair_orders' not in tables:
        return
    
    columns = [col['name'] for col in inspector.get_columns('repair_orders')]
    
    if 'customer_phone' not in columns:
        op.add_column('repair_orders',
            sa.Column('customer_phone', sa.String(length=20), nullable=True,
                     comment='شماره تماس مشتری'))
        print("✅ ستون customer_phone بازگردانده شد")
    
    if 'customer_email' not in columns:
        op.add_column('repair_orders',
            sa.Column('customer_email', sa.String(length=255), nullable=True,
                     comment='ایمیل مشتری'))
        print("✅ ستون customer_email بازگردانده شد")

