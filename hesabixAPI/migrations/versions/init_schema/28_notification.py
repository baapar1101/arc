"""جداول notification_templates, user_notification_settings, notification_outbox, notification_delivery_attempts"""
from alembic import op
import sqlalchemy as sa


def upgrade():
    # جدول notification_templates
    op.create_table(
        'notification_templates',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('event_key', sa.String(length=100), nullable=False),
        sa.Column('channel', sa.String(length=32), nullable=False),
        sa.Column('locale', sa.String(length=10), nullable=True),
        sa.Column('subject', sa.String(length=200), nullable=True),
        sa.Column('body', sa.Text(), nullable=False),
        sa.Column('is_active', sa.Boolean(), nullable=False, server_default='1'),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('event_key', 'channel', 'locale', name='uq_template_key_channel_locale')
    )
    op.create_index(op.f('ix_notification_templates_event_key'), 'notification_templates', ['event_key'], unique=False)
    op.create_index(op.f('ix_notification_templates_channel'), 'notification_templates', ['channel'], unique=False)
    op.create_index(op.f('ix_notification_templates_locale'), 'notification_templates', ['locale'], unique=False)
    op.create_index(op.f('ix_notification_templates_is_active'), 'notification_templates', ['is_active'], unique=False)

    # جدول user_notification_settings
    op.create_table(
        'user_notification_settings',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('channel', sa.String(length=32), nullable=False),
        sa.Column('event_key', sa.String(length=100), nullable=True),
        sa.Column('enabled', sa.Boolean(), nullable=False, server_default='1'),
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

    # جدول notification_outbox
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
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_notification_outbox_user_id'), 'notification_outbox', ['user_id'], unique=False)
    op.create_index(op.f('ix_notification_outbox_channel'), 'notification_outbox', ['channel'], unique=False)
    op.create_index(op.f('ix_notification_outbox_event_key'), 'notification_outbox', ['event_key'], unique=False)
    op.create_index(op.f('ix_notification_outbox_status'), 'notification_outbox', ['status'], unique=False)
    op.create_index(op.f('ix_notification_outbox_next_attempt_at'), 'notification_outbox', ['next_attempt_at'], unique=False)
    op.create_index('ix_outbox_pending_next', 'notification_outbox', ['status', 'next_attempt_at'], unique=False)

    # جدول notification_delivery_attempts
    op.create_table(
        'notification_delivery_attempts',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('outbox_id', sa.Integer(), nullable=False),
        sa.Column('channel', sa.String(length=32), nullable=False),
        sa.Column('success', sa.Boolean(), nullable=False, server_default='0'),
        sa.Column('error_message', sa.Text(), nullable=True),
        sa.Column('performed_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['outbox_id'], ['notification_outbox.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_notification_delivery_attempts_outbox_id'), 'notification_delivery_attempts', ['outbox_id'], unique=False)
    op.create_index(op.f('ix_notification_delivery_attempts_channel'), 'notification_delivery_attempts', ['channel'], unique=False)
    op.create_index(op.f('ix_notification_delivery_attempts_success'), 'notification_delivery_attempts', ['success'], unique=False)
    op.create_index(op.f('ix_notification_delivery_attempts_performed_at'), 'notification_delivery_attempts', ['performed_at'], unique=False)


def downgrade():
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

