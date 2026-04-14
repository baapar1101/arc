"""seed_support_data

Revision ID: 20250102_000001
Revises: 5553f8745c6e
Create Date: 2025-01-02 00:00:01.000000

"""
from alembic import op
import sqlalchemy as sa
from datetime import datetime

# revision identifiers, used by Alembic.
revision = '20250102_000001'
down_revision = '5553f8745c6e'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # اضافه کردن دسته‌بندی‌های اولیه
    categories_table = sa.table('support_categories',
        sa.column('id', sa.Integer),
        sa.column('name', sa.String),
        sa.column('description', sa.Text),
        sa.column('is_active', sa.Boolean),
        sa.column('created_at', sa.DateTime),
        sa.column('updated_at', sa.DateTime)
    )
    
    categories_data = [
        {
            'name': 'مشکل فنی',
            'description': 'مشکلات فنی و باگ‌ها',
            'is_active': True,
            'created_at': datetime.utcnow(),
            'updated_at': datetime.utcnow()
        },
        {
            'name': 'درخواست ویژگی',
            'description': 'درخواست ویژگی‌های جدید',
            'is_active': True,
            'created_at': datetime.utcnow(),
            'updated_at': datetime.utcnow()
        },
        {
            'name': 'سوال',
            'description': 'سوالات عمومی',
            'is_active': True,
            'created_at': datetime.utcnow(),
            'updated_at': datetime.utcnow()
        },
        {
            'name': 'شکایت',
            'description': 'شکایات و انتقادات',
            'is_active': True,
            'created_at': datetime.utcnow(),
            'updated_at': datetime.utcnow()
        },
        {
            'name': 'سایر',
            'description': 'سایر موارد',
            'is_active': True,
            'created_at': datetime.utcnow(),
            'updated_at': datetime.utcnow()
        }
    ]
    
    op.bulk_insert(categories_table, categories_data)
    
    # اضافه کردن اولویت‌های اولیه
    priorities_table = sa.table('support_priorities',
        sa.column('id', sa.Integer),
        sa.column('name', sa.String),
        sa.column('description', sa.Text),
        sa.column('color', sa.String),
        sa.column('order', sa.Integer),
        sa.column('created_at', sa.DateTime),
        sa.column('updated_at', sa.DateTime)
    )
    
    priorities_data = [
        {
            'name': 'کم',
            'description': 'اولویت کم',
            'color': '#28a745',
            'order': 1,
            'created_at': datetime.utcnow(),
            'updated_at': datetime.utcnow()
        },
        {
            'name': 'متوسط',
            'description': 'اولویت متوسط',
            'color': '#ffc107',
            'order': 2,
            'created_at': datetime.utcnow(),
            'updated_at': datetime.utcnow()
        },
        {
            'name': 'بالا',
            'description': 'اولویت بالا',
            'color': '#fd7e14',
            'order': 3,
            'created_at': datetime.utcnow(),
            'updated_at': datetime.utcnow()
        },
        {
            'name': 'فوری',
            'description': 'اولویت فوری',
            'color': '#dc3545',
            'order': 4,
            'created_at': datetime.utcnow(),
            'updated_at': datetime.utcnow()
        }
    ]
    
    op.bulk_insert(priorities_table, priorities_data)
    
    # اضافه کردن وضعیت‌های اولیه
    statuses_table = sa.table('support_statuses',
        sa.column('id', sa.Integer),
        sa.column('name', sa.String),
        sa.column('description', sa.Text),
        sa.column('color', sa.String),
        sa.column('is_final', sa.Boolean),
        sa.column('created_at', sa.DateTime),
        sa.column('updated_at', sa.DateTime)
    )
    
    statuses_data = [
        {
            'name': 'باز',
            'description': 'تیکت باز و در انتظار پاسخ',
            'color': '#007bff',
            'is_final': False,
            'created_at': datetime.utcnow(),
            'updated_at': datetime.utcnow()
        },
        {
            'name': 'در حال پیگیری',
            'description': 'تیکت در حال بررسی',
            'color': '#6f42c1',
            'is_final': False,
            'created_at': datetime.utcnow(),
            'updated_at': datetime.utcnow()
        },
        {
            'name': 'در انتظار کاربر',
            'description': 'در انتظار پاسخ کاربر',
            'color': '#17a2b8',
            'is_final': False,
            'created_at': datetime.utcnow(),
            'updated_at': datetime.utcnow()
        },
        {
            'name': 'بسته',
            'description': 'تیکت بسته شده',
            'color': '#6c757d',
            'is_final': True,
            'created_at': datetime.utcnow(),
            'updated_at': datetime.utcnow()
        },
        {
            'name': 'حل شده',
            'description': 'مشکل حل شده',
            'color': '#28a745',
            'is_final': True,
            'created_at': datetime.utcnow(),
            'updated_at': datetime.utcnow()
        }
    ]
    
    op.bulk_insert(statuses_table, statuses_data)


def downgrade() -> None:
    # حذف داده‌های اضافه شده
    op.execute("DELETE FROM support_statuses")
    op.execute("DELETE FROM support_priorities")
    op.execute("DELETE FROM support_categories")
