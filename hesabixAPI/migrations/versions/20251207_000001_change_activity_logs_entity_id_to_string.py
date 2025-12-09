"""change entity_id column type from integer to string

Revision ID: 20251207_000001_change_activity_logs_entity_id_to_string
Revises: 20251206_000001_remove_phone_email_from_repair_orders
Create Date: 2025-12-07 10:13:30.000000

"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy import inspect

# revision identifiers, used by Alembic.
revision = '20251207_000001_change_activity_logs_entity_id_to_string'
down_revision = '4d60f85a6561'  # merge point
branch_labels = None
depends_on = None


def upgrade():
    """
    تغییر نوع ستون entity_id از Integer به String(36) برای پشتیبانی از UUID
    این تغییر برای پشتیبانی از موجودیت‌هایی مثل FileStorage که از UUID استفاده می‌کنند
    """
    bind = op.get_bind()
    inspector = inspect(bind)
    
    # بررسی وجود جدول
    tables = inspector.get_table_names()
    if 'activity_logs' not in tables:
        print("⚠️  جدول activity_logs وجود ندارد، migration skip می‌شود")
        return
    
    # دریافت اطلاعات ستون فعلی
    columns = {col['name']: col for col in inspector.get_columns('activity_logs')}
    
    if 'entity_id' not in columns:
        print("⚠️  ستون entity_id وجود ندارد، migration skip می‌شود")
        return
    
    current_type = str(columns['entity_id']['type'])
    
    # اگر قبلاً String است، نیازی به تغییر نیست
    if 'VARCHAR' in current_type.upper() or 'STRING' in current_type.upper():
        print("✅ ستون entity_id قبلاً String است، نیازی به تغییر نیست")
        return
    
    print("🔄 در حال تبدیل entity_id از Integer به String...")
    
    # در MySQL/MariaDB باید ابتدا داده‌های موجود را تبدیل کنیم
    # تبدیل تمام مقادیر integer به string
    try:
        bind.execute(sa.text("""
            UPDATE activity_logs 
            SET entity_id = CAST(entity_id AS CHAR) 
            WHERE entity_id IS NOT NULL
        """))
        print("✅ داده‌های موجود به string تبدیل شدند")
    except Exception as e:
        print(f"⚠️  خطا در تبدیل داده‌ها (ادامه می‌دهیم): {e}")
    
    # تغییر نوع ستون
    # در MySQL/MariaDB از MODIFY COLUMN استفاده می‌کنیم
    try:
        op.alter_column('activity_logs', 'entity_id',
                       existing_type=sa.Integer(),
                       type_=sa.String(36),
                       existing_nullable=True,
                       existing_server_default=None)
        print("✅ نوع ستون entity_id به String(36) تغییر یافت")
    except Exception as e:
        # اگر خطا داد، ممکن است نیاز به روش دیگری باشد
        print(f"⚠️  خطا در تغییر نوع ستون: {e}")
        print("🔄 تلاش با روش جایگزین...")
        
        # روش جایگزین: حذف و ایجاد مجدد ستون
        try:
            # حذف index اگر وجود دارد
            indexes = [idx['name'] for idx in inspector.get_indexes('activity_logs')]
            if 'ix_activity_logs_entity_id' in indexes:
                op.drop_index('ix_activity_logs_entity_id', table_name='activity_logs')
                print("✅ ایندکس entity_id حذف شد")
            
            # تغییر نوع ستون با MODIFY
            bind.execute(sa.text("""
                ALTER TABLE activity_logs 
                MODIFY COLUMN entity_id VARCHAR(36) NULL
            """))
            print("✅ نوع ستون entity_id به String(36) تغییر یافت (روش جایگزین)")
            
            # ایجاد مجدد index
            op.create_index('ix_activity_logs_entity_id', 'activity_logs', ['entity_id'], unique=False)
            print("✅ ایندکس entity_id ایجاد شد")
        except Exception as e2:
            print(f"❌ خطا در روش جایگزین: {e2}")
            raise


def downgrade():
    """بازگردانی نوع ستون entity_id به Integer"""
    bind = op.get_bind()
    inspector = inspect(bind)
    
    tables = inspector.get_table_names()
    if 'activity_logs' not in tables:
        return
    
    columns = {col['name']: col for col in inspector.get_columns('activity_logs')}
    
    if 'entity_id' not in columns:
        return
    
    current_type = str(columns['entity_id']['type'])
    
    # اگر قبلاً Integer است، نیازی به تغییر نیست
    if 'INT' in current_type.upper():
        print("✅ ستون entity_id قبلاً Integer است، نیازی به تغییر نیست")
        return
    
    print("🔄 در حال تبدیل entity_id از String به Integer...")
    
    # حذف index
    indexes = [idx['name'] for idx in inspector.get_indexes('activity_logs')]
    if 'ix_activity_logs_entity_id' in indexes:
        op.drop_index('ix_activity_logs_entity_id', table_name='activity_logs')
    
    # تبدیل داده‌های string که قابل تبدیل به integer هستند
    # داده‌هایی که UUID هستند یا قابل تبدیل نیستند، NULL می‌شوند
    try:
        bind.execute(sa.text("""
            UPDATE activity_logs 
            SET entity_id = NULL 
            WHERE entity_id IS NOT NULL 
              AND entity_id NOT REGEXP '^[0-9]+$'
        """))
        print("✅ داده‌های غیر عددی به NULL تبدیل شدند")
        
        # تبدیل string های عددی به integer
        bind.execute(sa.text("""
            UPDATE activity_logs 
            SET entity_id = CAST(entity_id AS UNSIGNED) 
            WHERE entity_id IS NOT NULL 
              AND entity_id REGEXP '^[0-9]+$'
        """))
        print("✅ داده‌های عددی به integer تبدیل شدند")
    except Exception as e:
        print(f"⚠️  خطا در تبدیل داده‌ها (ادامه می‌دهیم): {e}")
    
    # تغییر نوع ستون
    try:
        op.alter_column('activity_logs', 'entity_id',
                       existing_type=sa.String(36),
                       type_=sa.Integer(),
                       existing_nullable=True,
                       existing_server_default=None)
        print("✅ نوع ستون entity_id به Integer بازگردانده شد")
    except Exception as e:
        print(f"⚠️  خطا در تغییر نوع ستون: {e}")
        try:
            bind.execute(sa.text("""
                ALTER TABLE activity_logs 
                MODIFY COLUMN entity_id INT NULL
            """))
            print("✅ نوع ستون entity_id به Integer بازگردانده شد (روش جایگزین)")
        except Exception as e2:
            print(f"❌ خطا در روش جایگزین: {e2}")
            raise
    
    # ایجاد مجدد index
    op.create_index('ix_activity_logs_entity_id', 'activity_logs', ['entity_id'], unique=False)
    print("✅ ایندکس entity_id ایجاد شد")

