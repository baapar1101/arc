"""add_mobile_verified_column

Revision ID: 483a0bf37370
Revises: 20250101_000000
Create Date: 2025-11-27 05:00:53.660415

"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy import inspect


# revision identifiers, used by Alembic.
revision = '483a0bf37370'
down_revision = '20250101_000000'
branch_labels = None
depends_on = None


def upgrade() -> None:
    """افزودن ستون mobile_verified به جدول users در صورت عدم وجود"""
    conn = op.get_bind()
    inspector = inspect(conn)
    
    # بررسی وجود ستون mobile_verified
    columns = [col['name'] for col in inspector.get_columns('users')]
    if 'mobile_verified' not in columns:
        op.add_column('users', sa.Column('mobile_verified', sa.Boolean(), nullable=False, server_default='0'))
    
    # بررسی وجود ایندکس
    indexes = [idx['name'] for idx in inspector.get_indexes('users')]
    if 'ix_users_mobile_verified' not in indexes:
        op.create_index(op.f('ix_users_mobile_verified'), 'users', ['mobile_verified'], unique=False)


def downgrade() -> None:
    """حذف ستون mobile_verified از جدول users"""
    conn = op.get_bind()
    inspector = inspect(conn)
    
    # بررسی وجود ایندکس
    indexes = [idx['name'] for idx in inspector.get_indexes('users')]
    if 'ix_users_mobile_verified' in indexes:
        op.drop_index(op.f('ix_users_mobile_verified'), table_name='users')
    
    # بررسی وجود ستون
    columns = [col['name'] for col in inspector.get_columns('users')]
    if 'mobile_verified' in columns:
        op.drop_column('users', 'mobile_verified')
