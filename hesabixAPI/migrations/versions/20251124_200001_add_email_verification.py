"""add_email_verification

Revision ID: 20251124_200001
Revises: 20251124_200000
Create Date: 2025-11-24 20:00:01.000000

"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import mysql

# revision identifiers, used by Alembic.
revision = '20251124_200001'
down_revision = '20251124_200000'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # اضافه کردن فیلد email_verified به جدول users (اگر وجود نداشته باشد)
    from sqlalchemy import inspect
    conn = op.get_bind()
    inspector = inspect(conn)
    columns = [col['name'] for col in inspector.get_columns('users')]
    
    if 'email_verified' not in columns:
        op.add_column('users', sa.Column('email_verified', sa.Boolean(), nullable=False, server_default='0'))
    
    # ایجاد ایندکس (اگر وجود نداشته باشد)
    indexes = [idx['name'] for idx in inspector.get_indexes('users')]
    if 'ix_users_email_verified' not in indexes:
        op.create_index(op.f('ix_users_email_verified'), 'users', ['email_verified'], unique=False)
    
    # ایجاد جدول email_verification_tokens (اگر وجود نداشته باشد)
    tables = inspector.get_table_names()
    if 'email_verification_tokens' not in tables:
        op.create_table('email_verification_tokens',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('email', sa.String(length=255), nullable=False),
        sa.Column('token_hash', sa.String(length=128), nullable=False),
        sa.Column('expires_at', sa.DateTime(), nullable=False),
        sa.Column('used_at', sa.DateTime(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False),
            sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
            sa.PrimaryKeyConstraint('id'),
            sa.UniqueConstraint('token_hash')
        )
        # ایجاد ایندکس‌ها (اگر وجود نداشته باشند)
        existing_indexes = [idx['name'] for idx in inspector.get_indexes('email_verification_tokens')] if 'email_verification_tokens' in tables else []
        if 'ix_email_verification_tokens_user_id' not in existing_indexes:
            op.create_index(op.f('ix_email_verification_tokens_user_id'), 'email_verification_tokens', ['user_id'], unique=False)
        if 'ix_email_verification_tokens_email' not in existing_indexes:
            op.create_index(op.f('ix_email_verification_tokens_email'), 'email_verification_tokens', ['email'], unique=False)
        if 'ix_email_verification_tokens_token_hash' not in existing_indexes:
            op.create_index(op.f('ix_email_verification_tokens_token_hash'), 'email_verification_tokens', ['token_hash'], unique=True)


def downgrade() -> None:
    from sqlalchemy import inspect
    conn = op.get_bind()
    inspector = inspect(conn)
    tables = inspector.get_table_names()
    
    # حذف جدول email_verification_tokens
    if 'email_verification_tokens' in tables:
        existing_indexes = {idx['name'] for idx in inspector.get_indexes('email_verification_tokens')}
        if 'ix_email_verification_tokens_token_hash' in existing_indexes:
            try:
                op.drop_index(op.f('ix_email_verification_tokens_token_hash'), table_name='email_verification_tokens')
            except Exception:
                pass
        if 'ix_email_verification_tokens_email' in existing_indexes:
            try:
                op.drop_index(op.f('ix_email_verification_tokens_email'), table_name='email_verification_tokens')
            except Exception:
                pass
        if 'ix_email_verification_tokens_user_id' in existing_indexes:
            try:
                op.drop_index(op.f('ix_email_verification_tokens_user_id'), table_name='email_verification_tokens')
            except Exception:
                pass
        try:
            op.drop_table('email_verification_tokens')
        except Exception:
            pass
    
    # حذف فیلد email_verified از جدول users
    if 'users' in tables:
        columns = {col['name'] for col in inspector.get_columns('users')}
        if 'email_verified' in columns:
            existing_indexes = {idx['name'] for idx in inspector.get_indexes('users')}
            if 'ix_users_email_verified' in existing_indexes:
                try:
                    op.drop_index(op.f('ix_users_email_verified'), table_name='users')
                except Exception:
                    pass
            try:
                op.drop_column('users', 'email_verified')
            except Exception:
                pass


