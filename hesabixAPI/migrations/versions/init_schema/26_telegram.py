"""جداول telegram_link_tokens, telegram_ai_sessions"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import mysql


def upgrade():
    # جدول telegram_link_tokens
    op.create_table(
        'telegram_link_tokens',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('token', sa.String(length=128), nullable=False),
        sa.Column('expires_at', sa.DateTime(), nullable=False),
        sa.Column('used_at', sa.DateTime(), nullable=True),
        sa.Column('created_ip', sa.String(length=64), nullable=True),
        sa.Column('user_agent', sa.String(length=255), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_telegram_link_tokens_user_id'), 'telegram_link_tokens', ['user_id'], unique=False)
    op.create_index(op.f('ix_telegram_link_tokens_token'), 'telegram_link_tokens', ['token'], unique=True)
    op.create_index(op.f('ix_telegram_link_tokens_expires_at'), 'telegram_link_tokens', ['expires_at'], unique=False)
    op.create_index('ix_telegram_link_validity', 'telegram_link_tokens', ['expires_at', 'used_at'], unique=False)

    # جدول telegram_ai_sessions
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
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_telegram_ai_sessions_user_id'), 'telegram_ai_sessions', ['user_id'], unique=False)
    op.create_index(op.f('ix_telegram_ai_sessions_chat_id'), 'telegram_ai_sessions', ['chat_id'], unique=False)
    op.create_index(op.f('ix_telegram_ai_sessions_session_id'), 'telegram_ai_sessions', ['session_id'], unique=False)
    op.create_index(op.f('ix_telegram_ai_sessions_business_id'), 'telegram_ai_sessions', ['business_id'], unique=False)
    op.create_index('ix_telegram_ai_sessions_user_chat_active', 'telegram_ai_sessions', ['user_id', 'chat_id', 'is_active'], unique=False)


def downgrade():
    op.drop_index('ix_telegram_ai_sessions_user_chat_active', table_name='telegram_ai_sessions')
    op.drop_index(op.f('ix_telegram_ai_sessions_business_id'), table_name='telegram_ai_sessions')
    op.drop_index(op.f('ix_telegram_ai_sessions_session_id'), table_name='telegram_ai_sessions')
    op.drop_index(op.f('ix_telegram_ai_sessions_chat_id'), table_name='telegram_ai_sessions')
    op.drop_index(op.f('ix_telegram_ai_sessions_user_id'), table_name='telegram_ai_sessions')
    op.drop_table('telegram_ai_sessions')
    
    op.drop_index('ix_telegram_link_validity', table_name='telegram_link_tokens')
    op.drop_index(op.f('ix_telegram_link_tokens_expires_at'), table_name='telegram_link_tokens')
    op.drop_index(op.f('ix_telegram_link_tokens_token'), table_name='telegram_link_tokens')
    op.drop_index(op.f('ix_telegram_link_tokens_user_id'), table_name='telegram_link_tokens')
    op.drop_table('telegram_link_tokens')

