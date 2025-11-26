"""add_telegram_ai_sessions

Revision ID: 20250125_000001
Revises: 20251124_200001
Create Date: 2025-01-25 00:00:01.000000

"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import mysql

# revision identifiers, used by Alembic.
revision = '20250125_000001'
down_revision = '20251124_200001'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # بررسی وجود جدول قبل از ایجاد
    from sqlalchemy import inspect
    conn = op.get_bind()
    inspector = inspect(conn)
    tables = inspector.get_table_names()
    
    if 'telegram_ai_sessions' in tables:
        # جدول از قبل وجود دارد، فقط ایندکس‌ها را بررسی می‌کنیم
        existing_indexes = [idx['name'] for idx in inspector.get_indexes('telegram_ai_sessions')]
        if 'ix_telegram_ai_sessions_user_id' not in existing_indexes:
            op.create_index(op.f('ix_telegram_ai_sessions_user_id'), 'telegram_ai_sessions', ['user_id'], unique=False)
        if 'ix_telegram_ai_sessions_chat_id' not in existing_indexes:
            op.create_index(op.f('ix_telegram_ai_sessions_chat_id'), 'telegram_ai_sessions', ['chat_id'], unique=False)
        if 'ix_telegram_ai_sessions_session_id' not in existing_indexes:
            op.create_index(op.f('ix_telegram_ai_sessions_session_id'), 'telegram_ai_sessions', ['session_id'], unique=False)
        if 'ix_telegram_ai_sessions_business_id' not in existing_indexes:
            op.create_index(op.f('ix_telegram_ai_sessions_business_id'), 'telegram_ai_sessions', ['business_id'], unique=False)
        if 'ix_telegram_ai_sessions_user_chat_active' not in existing_indexes:
            op.create_index('ix_telegram_ai_sessions_user_chat_active', 'telegram_ai_sessions', ['user_id', 'chat_id', 'is_active'], unique=False)
        return
    
    # ایجاد جدول telegram_ai_sessions
    op.create_table(
        'telegram_ai_sessions',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('chat_id', sa.BigInteger(), nullable=False),
        sa.Column('session_id', sa.Integer(), nullable=True),
        sa.Column('business_id', sa.Integer(), nullable=True),
        sa.Column('is_active', sa.Boolean(), nullable=False, server_default='1'),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['session_id'], ['ai_chat_sessions.id'], ondelete='SET NULL'),
        sa.ForeignKeyConstraint(['business_id'], ['businesses.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('user_id', 'chat_id', 'session_id', name='uq_telegram_ai_sessions_user_chat_session')
    )
    
    # ایجاد ایندکس‌ها
    op.create_index(op.f('ix_telegram_ai_sessions_user_id'), 'telegram_ai_sessions', ['user_id'], unique=False)
    op.create_index(op.f('ix_telegram_ai_sessions_chat_id'), 'telegram_ai_sessions', ['chat_id'], unique=False)
    op.create_index(op.f('ix_telegram_ai_sessions_session_id'), 'telegram_ai_sessions', ['session_id'], unique=False)
    op.create_index(op.f('ix_telegram_ai_sessions_business_id'), 'telegram_ai_sessions', ['business_id'], unique=False)
    op.create_index('ix_telegram_ai_sessions_user_chat_active', 'telegram_ai_sessions', ['user_id', 'chat_id', 'is_active'], unique=False)


def downgrade() -> None:
    # حذف ایندکس‌ها
    op.drop_index('ix_telegram_ai_sessions_user_chat_active', table_name='telegram_ai_sessions')
    op.drop_index(op.f('ix_telegram_ai_sessions_business_id'), table_name='telegram_ai_sessions')
    op.drop_index(op.f('ix_telegram_ai_sessions_session_id'), table_name='telegram_ai_sessions')
    op.drop_index(op.f('ix_telegram_ai_sessions_chat_id'), table_name='telegram_ai_sessions')
    op.drop_index(op.f('ix_telegram_ai_sessions_user_id'), table_name='telegram_ai_sessions')
    
    # حذف جدول
    op.drop_table('telegram_ai_sessions')

