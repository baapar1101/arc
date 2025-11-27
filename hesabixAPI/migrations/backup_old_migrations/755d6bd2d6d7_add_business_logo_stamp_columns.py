"""add_business_logo_stamp_columns

Revision ID: 755d6bd2d6d7
Revises: a3a3a1b6669f
Create Date: 2025-11-14 13:27:21.561890

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '755d6bd2d6d7'
down_revision = 'a3a3a1b6669f'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # افزودن ستون‌های لوگو و مهر به جدول businesses (با چک کردن وجود قبلی)
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    existing_columns = [col['name'] for col in inspector.get_columns('businesses')]

    if 'logo_file_id' not in existing_columns:
        op.add_column(
            'businesses',
            sa.Column('logo_file_id', sa.String(length=36), nullable=True),
        )
    if 'stamp_file_id' not in existing_columns:
        op.add_column(
            'businesses',
            sa.Column('stamp_file_id', sa.String(length=36), nullable=True),
        )


def downgrade() -> None:
    # حذف ستون‌ها در صورت برگشت
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    existing_columns = [col['name'] for col in inspector.get_columns('businesses')]

    if 'stamp_file_id' in existing_columns:
        op.drop_column('businesses', 'stamp_file_id')
    if 'logo_file_id' in existing_columns:
        op.drop_column('businesses', 'logo_file_id')
