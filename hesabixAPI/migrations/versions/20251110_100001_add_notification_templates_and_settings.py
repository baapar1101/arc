"""add notification templates and user settings

Revision ID: 20251110_100001_add_notification_templates_and_settings
Revises: 20251110_090001_add_notifications_and_telegram
Create Date: 2025-11-10 10:00:01
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = '20251110_100001_add_notification_templates_and_settings'
down_revision = '20251110_090001_add_notifications_and_telegram'
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    existing_tables = set(inspector.get_table_names())

    if 'notification_templates' not in existing_tables:
        op.create_table(
            'notification_templates',
            sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
            sa.Column('event_key', sa.String(length=100), nullable=False),
            sa.Column('channel', sa.String(length=32), nullable=False),
            sa.Column('locale', sa.String(length=10), nullable=True),
            sa.Column('subject', sa.String(length=200), nullable=True),
            sa.Column('body', sa.Text(), nullable=False),
            sa.Column('is_active', sa.Boolean(), nullable=False, server_default=sa.text('1')),
            sa.Column('created_at', sa.DateTime(), nullable=False),
            sa.Column('updated_at', sa.DateTime(), nullable=False),
            sa.PrimaryKeyConstraint('id'),
            sa.UniqueConstraint('event_key', 'channel', 'locale', name='uq_template_key_channel_locale')
        )
        op.create_index(op.f('ix_notification_templates_event_key'), 'notification_templates', ['event_key'], unique=False)
        op.create_index(op.f('ix_notification_templates_channel'), 'notification_templates', ['channel'], unique=False)
        op.create_index(op.f('ix_notification_templates_locale'), 'notification_templates', ['locale'], unique=False)
        op.create_index(op.f('ix_notification_templates_is_active'), 'notification_templates', ['is_active'], unique=False)

    if 'user_notification_settings' not in existing_tables:
        op.create_table(
            'user_notification_settings',
            sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
            sa.Column('user_id', sa.Integer(), nullable=False),
            sa.Column('channel', sa.String(length=32), nullable=False),
            sa.Column('event_key', sa.String(length=100), nullable=True),
            sa.Column('enabled', sa.Boolean(), nullable=False, server_default=sa.text('1')),
            sa.Column('created_at', sa.DateTime(), nullable=False),
            sa.Column('updated_at', sa.DateTime(), nullable=False),
            sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
            sa.PrimaryKeyConstraint('id'),
            sa.UniqueConstraint('user_id', 'channel', 'event_key', name='uq_user_channel_event')
        )
        op.create_index(op.f('ix_user_notification_settings_user_id'), 'user_notification_settings', ['user_id'], unique=False)
        op.create_index(op.f('ix_user_notification_settings_channel'), 'user_notification_settings', ['channel'], unique=False)
        op.create_index(op.f('ix_user_notification_settings_event_key'), 'user_notification_settings', ['event_key'], unique=False)
        op.create_index(op.f('ix_user_notification_settings_enabled'), 'user_notification_settings', ['enabled'], unique=False)
        op.create_index('ix_user_settings_user_channel', 'user_notification_settings', ['user_id', 'channel'], unique=False)


def downgrade() -> None:
    op.drop_index('ix_user_settings_user_channel', table_name='user_notification_settings')
    op.drop_index(op.f('ix_user_notification_settings_enabled'), table_name='user_notification_settings')
    op.drop_index(op.f('ix_user_notification_settings_event_key'), table_name='user_notification_settings')
    op.drop_index(op.f('ix_user_notification_settings_channel'), table_name='user_notification_settings')
    op.drop_index(op.f('ix_user_notification_settings_user_id'), table_name='user_notification_settings')
    op.drop_table('user_notification_settings')

    op.drop_index(op.f('ix_notification_templates_is_active'), table_name='notification_templates')
    op.drop_index(op.f('ix_notification_templates_locale'), table_name='notification_templates')
    op.drop_index(op.f('ix_notification_templates_channel'), table_name='notification_templates')
    op.drop_index(op.f('ix_notification_templates_event_key'), table_name='notification_templates')
    op.drop_table('notification_templates')


