"""add system_settings table

جدول system_settings برای تنظیمات سیستمی (ثبت‌نام، تایید ایمیل، حداکثر کاربران و ...) استفاده می‌شود.
در init_schema این جدول وجود نداشت و کد به آن وابسته است.

Revision ID: 20250209_000000
Revises: 16a08b3cf47c
Create Date: 2025-02-09

"""
from alembic import op
import sqlalchemy as sa


revision = '20250209_000000'
down_revision = '16a08b3cf47c'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        'system_settings',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('key', sa.String(length=100), nullable=False),
        sa.Column('value_string', sa.String(length=255), nullable=True),
        sa.Column('value_int', sa.Integer(), nullable=True),
        sa.Column('value_json', sa.Text(), nullable=True),
        sa.Column('created_at', sa.DateTime(), server_default=sa.text('NOW()'), nullable=False),
        sa.Column('updated_at', sa.DateTime(), server_default=sa.text('NOW()'), nullable=False),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('key', name='uq_system_settings_key'),
    )
    op.create_index(op.f('ix_system_settings_key'), 'system_settings', ['key'], unique=False)


def downgrade() -> None:
    op.drop_index(op.f('ix_system_settings_key'), table_name='system_settings')
    op.drop_table('system_settings')
