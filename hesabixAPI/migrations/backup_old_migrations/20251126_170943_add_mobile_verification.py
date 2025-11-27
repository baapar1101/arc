"""add_mobile_verification

Revision ID: 20251126_170943
Revises: 20251124_200001
Create Date: 2025-11-26 17:09:43.000000

"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import mysql

# revision identifiers, used by Alembic.
revision = '20251126_170943'
down_revision = '20250125_000001'
branch_labels = None
depends_on = None


def upgrade() -> None:
    from sqlalchemy import inspect
    conn = op.get_bind()
    inspector = inspect(conn)
    
    # اضافه کردن فیلد mobile_verified به جدول users
    columns = [col['name'] for col in inspector.get_columns('users')]
    if 'mobile_verified' not in columns:
        op.add_column('users', sa.Column('mobile_verified', sa.Boolean(), nullable=False, server_default='0'))
    
    # ایجاد ایندکس برای mobile_verified (اختیاری)
    indexes = [idx['name'] for idx in inspector.get_indexes('users')]
    if 'ix_users_mobile_verified' not in indexes:
        op.create_index(op.f('ix_users_mobile_verified'), 'users', ['mobile_verified'], unique=False)
    
    # ایجاد جدول mobile_verification_tokens
    tables = inspector.get_table_names()
    if 'mobile_verification_tokens' not in tables:
        op.create_table('mobile_verification_tokens',
            sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
            sa.Column('user_id', sa.Integer(), nullable=False),
            sa.Column('mobile', sa.String(length=32), nullable=False),
            sa.Column('otp_code_hash', sa.String(length=128), nullable=False),
            sa.Column('expires_at', sa.DateTime(), nullable=False),
            sa.Column('verified_at', sa.DateTime(), nullable=True),
            sa.Column('attempts', sa.Integer(), nullable=False, server_default='0'),
            sa.Column('created_at', sa.DateTime(), nullable=False),
            sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
            sa.PrimaryKeyConstraint('id')
        )
        # ایجاد ایندکس‌ها
        op.create_index(op.f('ix_mobile_verification_tokens_user_id'), 'mobile_verification_tokens', ['user_id'], unique=False)
        op.create_index(op.f('ix_mobile_verification_tokens_mobile'), 'mobile_verification_tokens', ['mobile'], unique=False)
        op.create_index(op.f('ix_mobile_verification_tokens_otp_code_hash'), 'mobile_verification_tokens', ['otp_code_hash'], unique=False)
        op.create_index(op.f('ix_mobile_verification_tokens_expires_at'), 'mobile_verification_tokens', ['expires_at'], unique=False)
        op.create_index('ix_mobile_verification_validity', 'mobile_verification_tokens', ['expires_at', 'verified_at'], unique=False)


def downgrade() -> None:
    # حذف جدول mobile_verification_tokens
    op.drop_index('ix_mobile_verification_validity', table_name='mobile_verification_tokens')
    op.drop_index(op.f('ix_mobile_verification_tokens_expires_at'), table_name='mobile_verification_tokens')
    op.drop_index(op.f('ix_mobile_verification_tokens_otp_code_hash'), table_name='mobile_verification_tokens')
    op.drop_index(op.f('ix_mobile_verification_tokens_mobile'), table_name='mobile_verification_tokens')
    op.drop_index(op.f('ix_mobile_verification_tokens_user_id'), table_name='mobile_verification_tokens')
    op.drop_table('mobile_verification_tokens')
    
    # حذف فیلد mobile_verified از users
    op.drop_index(op.f('ix_users_mobile_verified'), table_name='users')
    op.drop_column('users', 'mobile_verified')

