"""add is_active to products

Revision ID: 20260101_000001
Revises: 20251223_002500
Create Date: 2026-01-01 20:38:41.000000

"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy import inspect

# revision identifiers, used by Alembic.
revision = '20260101_000001'
down_revision = '20251223_002500_create_ai_voice_interactions'  # آخرین migration موجود
branch_labels = None
depends_on = None


def upgrade() -> None:
    # بررسی وجود فیلد قبل از اضافه کردن (idempotent)
    bind = op.get_bind()
    inspector = inspect(bind)
    
    # بررسی وجود جدول products
    if 'products' in inspector.get_table_names():
        columns = [col['name'] for col in inspector.get_columns('products')]
        
        # اگر فیلد is_active وجود ندارد، آن را اضافه کن
        if 'is_active' not in columns:
            op.add_column(
                'products',
                sa.Column('is_active', sa.Boolean(), nullable=False, server_default=sa.text('1'), comment='آیا محصول فعال است؟')
            )


def downgrade() -> None:
    # حذف فیلد is_active
    bind = op.get_bind()
    inspector = inspect(bind)
    
    if 'products' in inspector.get_table_names():
        columns = [col['name'] for col in inspector.get_columns('products')]
        
        if 'is_active' in columns:
            op.drop_column('products', 'is_active')

