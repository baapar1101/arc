"""add warehouse document settings to quick sales

Revision ID: 20251203_000001
Revises: 20251202_000003
Create Date: 2025-12-03 00:00:00.000000

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '20251203_000001'
down_revision = '20251202_000003'
branch_labels = None
depends_on = None


def upgrade():
    # اضافه کردن فیلد enable_warehouse_document
    op.add_column(
        'quick_sales_settings',
        sa.Column(
            'enable_warehouse_document',
            sa.Boolean(),
            nullable=False,
            server_default='1',
            comment='فعال/غیرفعال کردن صدور حواله انبار'
        )
    )
    
    # اضافه کردن فیلد warehouse_document_type
    op.add_column(
        'quick_sales_settings',
        sa.Column(
            'warehouse_document_type',
            sa.String(20),
            nullable=False,
            server_default='posted',
            comment='نوع سند حواله انبار: draft یا posted'
        )
    )
    
    # به‌روزرسانی مقادیر موجود بر اساس auto_post_warehouse
    # اگر auto_post_warehouse = True باشد، warehouse_document_type = 'posted'
    # اگر auto_post_warehouse = False باشد، warehouse_document_type = 'draft'
    op.execute("""
        UPDATE quick_sales_settings 
        SET warehouse_document_type = CASE 
            WHEN auto_post_warehouse = 1 THEN 'posted'
            ELSE 'draft'
        END
    """)


def downgrade():
    # حذف فیلدهای جدید
    op.drop_column('quick_sales_settings', 'warehouse_document_type')
    op.drop_column('quick_sales_settings', 'enable_warehouse_document')

