"""افزودن data_type و options به جدول product_attributes

revision: 20251202_000001_add_data_type_to_product_attributes
down_revision: 20250120_000001
branch_labels: None
depends_on: None

این میگریشن فیلدهای زیر را به جدول product_attributes اضافه می‌کند:
1. data_type - نوع داده (text, number, date, select, boolean)
2. options - گزینه‌های select (JSON)

همه ویژگی‌های موجود به data_type='text' تنظیم می‌شوند.
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.mysql import JSON


# revision identifiers, used by Alembic.
revision = '20251202_000001'
down_revision = '20250120_000001'
branch_labels = None
depends_on = None


def upgrade():
    conn = op.get_bind()
    inspector = sa.inspect(conn)
    columns = [col['name'] for col in inspector.get_columns('product_attributes')]
    
    # افزودن ستون data_type با مقدار پیش‌فرض 'text'
    if 'data_type' not in columns:
        op.add_column('product_attributes',
            sa.Column('data_type', sa.String(length=32), nullable=False, server_default='text', 
                      comment='نوع داده: text, number, date, select, boolean')
        )
    
    # افزودن ستون options برای گزینه‌های select
    if 'options' not in columns:
        op.add_column('product_attributes',
            sa.Column('options', JSON, nullable=True, 
                      comment='گزینه‌های select (فقط برای نوع select)')
        )
    
    # اطمینان از اینکه همه رکوردهای موجود data_type دارند
    # اگر ستون از قبل وجود داشت، مقادیر NULL یا خالی را به 'text' تنظیم می‌کنیم
    if 'data_type' in columns:
        op.execute("""
            UPDATE product_attributes 
            SET data_type = 'text' 
            WHERE data_type IS NULL OR data_type = ''
        """)


def downgrade():
    # حذف ستون‌ها
    op.drop_column('product_attributes', 'options')
    op.drop_column('product_attributes', 'data_type')

