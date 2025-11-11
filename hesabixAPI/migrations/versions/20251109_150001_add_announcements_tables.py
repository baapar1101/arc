"""add announcements and user_announcements tables

Revision ID: 20251109_150001_add_announcements_tables
Revises: 20251109_120001_add_payment_gateways
Create Date: 2025-11-09 15:00:01
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '20251109_150001_add_announcements_tables'
down_revision = '20251109_120001_add_payment_gateways'
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    existing_tables = set(inspector.get_table_names())

    if 'announcements' not in existing_tables:
        op.create_table(
            'announcements',
            sa.Column('id', sa.Integer(), primary_key=True, autoincrement=True),
            sa.Column('title', sa.String(length=200), nullable=False),
            sa.Column('body', sa.Text(), nullable=False),
            sa.Column('level', sa.String(length=16), nullable=False, server_default='info'),
            sa.Column('is_pinned', sa.Boolean(), nullable=False, server_default=sa.text('0')),
            sa.Column('is_active', sa.Boolean(), nullable=False, server_default=sa.text('0')),
            sa.Column('starts_at', sa.DateTime(), nullable=True),
            sa.Column('ends_at', sa.DateTime(), nullable=True),
            sa.Column('audience_filters', sa.JSON(), nullable=True),
            sa.Column('created_by', sa.Integer(), sa.ForeignKey('users.id', ondelete='SET NULL'), nullable=True),
            sa.Column('created_at', sa.DateTime(), nullable=False, server_default=sa.func.now()),
            sa.Column('updated_at', sa.DateTime(), nullable=False, server_default=sa.func.now()),
        )
        op.create_index('ix_ann_title', 'announcements', ['title'])
        op.create_index('ix_ann_level', 'announcements', ['level'])
        op.create_index('ix_ann_is_pinned', 'announcements', ['is_pinned'])
        op.create_index('ix_ann_is_active', 'announcements', ['is_active'])
        op.create_index('ix_ann_starts_at', 'announcements', ['starts_at'])
        op.create_index('ix_ann_ends_at', 'announcements', ['ends_at'])
        op.create_index('ix_ann_active_schedule', 'announcements', ['is_active', 'starts_at', 'ends_at'])
        op.create_index('ix_ann_pinned_updated', 'announcements', ['is_pinned', 'updated_at'])

    if 'user_announcements' not in existing_tables:
        op.create_table(
            'user_announcements',
            sa.Column('id', sa.Integer(), primary_key=True, autoincrement=True),
            sa.Column('user_id', sa.Integer(), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False),
            sa.Column('announcement_id', sa.Integer(), sa.ForeignKey('announcements.id', ondelete='CASCADE'), nullable=False),
            sa.Column('first_seen_at', sa.DateTime(), nullable=True),
            sa.Column('read_at', sa.DateTime(), nullable=True),
            sa.Column('dismissed_at', sa.DateTime(), nullable=True),
            sa.Column('created_at', sa.DateTime(), nullable=False, server_default=sa.func.now()),
            sa.Column('updated_at', sa.DateTime(), nullable=False, server_default=sa.func.now()),
        )
        op.create_index('ix_user_ann_user_id', 'user_announcements', ['user_id'])
        op.create_index('ix_user_ann_announcement_id', 'user_announcements', ['announcement_id'])
        op.create_unique_constraint('uq_user_announcement', 'user_announcements', ['user_id', 'announcement_id'])


def downgrade() -> None:
    op.drop_constraint('uq_user_announcement', 'user_announcements', type_='unique')
    op.drop_index('ix_user_ann_announcement_id', table_name='user_announcements')
    op.drop_index('ix_user_ann_user_id', table_name='user_announcements')
    op.drop_table('user_announcements')

    op.drop_index('ix_ann_pinned_updated', table_name='announcements')
    op.drop_index('ix_ann_active_schedule', table_name='announcements')
    op.drop_index('ix_ann_ends_at', table_name='announcements')
    op.drop_index('ix_ann_starts_at', table_name='announcements')
    op.drop_index('ix_ann_is_active', table_name='announcements')
    op.drop_index('ix_ann_is_pinned', table_name='announcements')
    op.drop_index('ix_ann_level', table_name='announcements')
    op.drop_index('ix_ann_title', table_name='announcements')
    op.drop_table('announcements')


