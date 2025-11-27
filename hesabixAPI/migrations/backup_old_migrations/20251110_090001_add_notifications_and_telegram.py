"""add_notifications_and_telegram

Revision ID: 20251110_090001_add_notifications_and_telegram
Revises: 20251109_160001_merge_heads_announcements
Create Date: 2025-11-10 09:00:01

"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '20251110_090001_add_notifications_and_telegram'
down_revision = '20251109_160001_merge_heads_announcements'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # users: telegram fields
    op.add_column('users', sa.Column('telegram_chat_id', sa.Integer(), nullable=True))
    op.add_column('users', sa.Column('telegram_connected_at', sa.DateTime(), nullable=True))
    op.create_index(op.f('ix_users_telegram_chat_id'), 'users', ['telegram_chat_id'], unique=False)

    # telegram_link_tokens
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
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('token'),
    )
    op.create_index(op.f('ix_telegram_link_tokens_user_id'), 'telegram_link_tokens', ['user_id'], unique=False)
    op.create_index(op.f('ix_telegram_link_tokens_token'), 'telegram_link_tokens', ['token'], unique=True)
    op.create_index('ix_telegram_link_validity', 'telegram_link_tokens', ['expires_at', 'used_at'], unique=False)

    # notification_outbox
    op.create_table(
        'notification_outbox',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('channel', sa.String(length=32), nullable=False),
        sa.Column('event_key', sa.String(length=100), nullable=False),
        sa.Column('payload', sa.JSON(), nullable=False),
        sa.Column('locale', sa.String(length=10), nullable=True),
        sa.Column('status', sa.String(length=16), nullable=False, server_default='pending'),
        sa.Column('error_message', sa.Text(), nullable=True),
        sa.Column('retry_count', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('next_attempt_at', sa.DateTime(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index(op.f('ix_notification_outbox_user_id'), 'notification_outbox', ['user_id'], unique=False)
    op.create_index(op.f('ix_notification_outbox_channel'), 'notification_outbox', ['channel'], unique=False)
    op.create_index(op.f('ix_notification_outbox_event_key'), 'notification_outbox', ['event_key'], unique=False)
    op.create_index(op.f('ix_notification_outbox_status'), 'notification_outbox', ['status'], unique=False)
    op.create_index(op.f('ix_notification_outbox_next_attempt_at'), 'notification_outbox', ['next_attempt_at'], unique=False)
    op.create_index('ix_outbox_pending_next', 'notification_outbox', ['status', 'next_attempt_at'], unique=False)

    # notification_delivery_attempts
    op.create_table(
        'notification_delivery_attempts',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('outbox_id', sa.Integer(), nullable=False),
        sa.Column('channel', sa.String(length=32), nullable=False),
        sa.Column('success', sa.Boolean(), nullable=False),
        sa.Column('error_message', sa.Text(), nullable=True),
        sa.Column('performed_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['outbox_id'], ['notification_outbox.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index(op.f('ix_notification_delivery_attempts_outbox_id'), 'notification_delivery_attempts', ['outbox_id'], unique=False)
    op.create_index(op.f('ix_notification_delivery_attempts_channel'), 'notification_delivery_attempts', ['channel'], unique=False)
    op.create_index(op.f('ix_notification_delivery_attempts_success'), 'notification_delivery_attempts', ['success'], unique=False)
    op.create_index(op.f('ix_notification_delivery_attempts_performed_at'), 'notification_delivery_attempts', ['performed_at'], unique=False)


def downgrade() -> None:
    op.drop_index(op.f('ix_notification_delivery_attempts_performed_at'), table_name='notification_delivery_attempts')
    op.drop_index(op.f('ix_notification_delivery_attempts_success'), table_name='notification_delivery_attempts')
    op.drop_index(op.f('ix_notification_delivery_attempts_channel'), table_name='notification_delivery_attempts')
    op.drop_index(op.f('ix_notification_delivery_attempts_outbox_id'), table_name='notification_delivery_attempts')
    op.drop_table('notification_delivery_attempts')

    op.drop_index('ix_outbox_pending_next', table_name='notification_outbox')
    op.drop_index(op.f('ix_notification_outbox_next_attempt_at'), table_name='notification_outbox')
    op.drop_index(op.f('ix_notification_outbox_status'), table_name='notification_outbox')
    op.drop_index(op.f('ix_notification_outbox_event_key'), table_name='notification_outbox')
    op.drop_index(op.f('ix_notification_outbox_channel'), table_name='notification_outbox')
    op.drop_index(op.f('ix_notification_outbox_user_id'), table_name='notification_outbox')
    op.drop_table('notification_outbox')

    op.drop_index('ix_telegram_link_validity', table_name='telegram_link_tokens')
    op.drop_index(op.f('ix_telegram_link_tokens_token'), table_name='telegram_link_tokens')
    op.drop_index(op.f('ix_telegram_link_tokens_user_id'), table_name='telegram_link_tokens')
    op.drop_table('telegram_link_tokens')

    op.drop_index(op.f('ix_users_telegram_chat_id'), table_name='users')
    op.drop_column('users', 'telegram_connected_at')
    op.drop_column('users', 'telegram_chat_id')


