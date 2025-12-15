"""بهینه‌سازی Indexes برای جداول support_tickets

Revision ID: 20250108_000001_optimize_ticket_indexes
Revises: 20251207_000001_change_activity_logs_entity_id_to_string
Create Date: 2025-01-08 10:00:00.000000

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '20250108_000001_optimize_ticket_indexes'
down_revision = '20251207_000001_change_activity_logs_entity_id_to_string'
branch_labels = None
depends_on = None


def upgrade():
    """
    اضافه کردن Indexes ترکیبی برای بهبود Performance جستجو و فیلتر تیکت‌ها
    """
    
    # Index برای جستجوهای رایج اپراتور (status, priority, created_at)
    try:
        op.create_index(
            'ix_tickets_status_priority_created',
            'support_tickets',
            ['status_id', 'priority_id', sa.text('created_at DESC')],
            unique=False
        )
        print("✅ Index ix_tickets_status_priority_created ایجاد شد")
    except Exception as e:
        print(f"⚠️  خطا در ایجاد ix_tickets_status_priority_created (ممکن است وجود داشته باشد): {e}")
    
    # Index برای تیکت‌های تخصیص داده شده (برای نمایش تیکت‌های من)
    try:
        op.create_index(
            'ix_tickets_assigned_operator_updated',
            'support_tickets',
            ['assigned_operator_id', sa.text('updated_at DESC')],
            unique=False
        )
        print("✅ Index ix_tickets_assigned_operator_updated ایجاد شد")
    except Exception as e:
        print(f"⚠️  خطا در ایجاد ix_tickets_assigned_operator_updated (ممکن است وجود داشته باشد): {e}")
    
    # Index برای تیکت‌های بدون اپراتور (برای تخصیص سریع)
    # در MySQL نمی‌توانیم WHERE clause در index استفاده کنیم، پس از partial index استفاده نمی‌کنیم
    # اما می‌توانیم index بر اساس priority و created_at ایجاد کنیم
    try:
        op.create_index(
            'ix_tickets_priority_created',
            'support_tickets',
            ['priority_id', sa.text('created_at DESC')],
            unique=False
        )
        print("✅ Index ix_tickets_priority_created ایجاد شد")
    except Exception as e:
        print(f"⚠️  خطا در ایجاد ix_tickets_priority_created (ممکن است وجود داشته باشد): {e}")
    
    # Index برای جستجو بر اساس کاربر
    try:
        op.create_index(
            'ix_tickets_user_created',
            'support_tickets',
            ['user_id', sa.text('created_at DESC')],
            unique=False
        )
        print("✅ Index ix_tickets_user_created ایجاد شد")
    except Exception as e:
        print(f"⚠️  خطا در ایجاد ix_tickets_user_created (ممکن است وجود داشته باشد): {e}")
    
    # Index برای فیلترهای ترکیبی رایج (category, status, updated_at)
    try:
        op.create_index(
            'ix_tickets_category_status_updated',
            'support_tickets',
            ['category_id', 'status_id', sa.text('updated_at DESC')],
            unique=False
        )
        print("✅ Index ix_tickets_category_status_updated ایجاد شد")
    except Exception as e:
        print(f"⚠️  خطا در ایجاد ix_tickets_category_status_updated (ممکن است وجود داشته باشد): {e}")
    
    # Index برای جستجو بر اساس updated_at (برای نمایش آخرین تغییرات)
    try:
        op.create_index(
            'ix_tickets_updated_at',
            'support_tickets',
            [sa.text('updated_at DESC')],
            unique=False
        )
        print("✅ Index ix_tickets_updated_at ایجاد شد")
    except Exception as e:
        print(f"⚠️  خطا در ایجاد ix_tickets_updated_at (ممکن است وجود داشته باشد): {e}")


def downgrade():
    """
    حذف Indexes اضافه شده
    """
    try:
        op.drop_index('ix_tickets_updated_at', table_name='support_tickets')
        print("✅ Index ix_tickets_updated_at حذف شد")
    except Exception:
        pass
    
    try:
        op.drop_index('ix_tickets_category_status_updated', table_name='support_tickets')
        print("✅ Index ix_tickets_category_status_updated حذف شد")
    except Exception:
        pass
    
    try:
        op.drop_index('ix_tickets_user_created', table_name='support_tickets')
        print("✅ Index ix_tickets_user_created حذف شد")
    except Exception:
        pass
    
    try:
        op.drop_index('ix_tickets_priority_created', table_name='support_tickets')
        print("✅ Index ix_tickets_priority_created حذف شد")
    except Exception:
        pass
    
    try:
        op.drop_index('ix_tickets_assigned_operator_updated', table_name='support_tickets')
        print("✅ Index ix_tickets_assigned_operator_updated حذف شد")
    except Exception:
        pass
    
    try:
        op.drop_index('ix_tickets_status_priority_created', table_name='support_tickets')
        print("✅ Index ix_tickets_status_priority_created حذف شد")
    except Exception:
        pass



