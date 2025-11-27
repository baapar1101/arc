"""جداول announcements, user_announcements"""
from alembic import op
import sqlalchemy as sa


def upgrade():
    # جدول announcements
    op.create_table(
        'announcements',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('title', sa.String(length=200), nullable=False),
        sa.Column('body', sa.Text(), nullable=False),
        sa.Column('level', sa.String(length=16), nullable=False, server_default='info'),
        sa.Column('is_pinned', sa.Boolean(), nullable=False, server_default='0'),
        sa.Column('is_active', sa.Boolean(), nullable=False, server_default='0'),
        sa.Column('starts_at', sa.DateTime(), nullable=True),
        sa.Column('ends_at', sa.DateTime(), nullable=True),
        sa.Column('audience_filters', sa.JSON(), nullable=True),
        sa.Column('created_by', sa.Integer(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['created_by'], ['users.id'], ondelete='SET NULL'),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_announcements_title'), 'announcements', ['title'], unique=False)
    op.create_index(op.f('ix_announcements_level'), 'announcements', ['level'], unique=False)
    op.create_index(op.f('ix_announcements_is_pinned'), 'announcements', ['is_pinned'], unique=False)
    op.create_index(op.f('ix_announcements_is_active'), 'announcements', ['is_active'], unique=False)
    op.create_index(op.f('ix_announcements_starts_at'), 'announcements', ['starts_at'], unique=False)
    op.create_index(op.f('ix_announcements_ends_at'), 'announcements', ['ends_at'], unique=False)
    op.create_index('ix_ann_active_schedule', 'announcements', ['is_active', 'starts_at', 'ends_at'], unique=False)
    op.create_index('ix_ann_pinned_updated', 'announcements', ['is_pinned', 'updated_at'], unique=False)

    # جدول user_announcements
    op.create_table(
        'user_announcements',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('announcement_id', sa.Integer(), nullable=False),
        sa.Column('first_seen_at', sa.DateTime(), nullable=True),
        sa.Column('read_at', sa.DateTime(), nullable=True),
        sa.Column('dismissed_at', sa.DateTime(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['announcement_id'], ['announcements.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('user_id', 'announcement_id', name='uq_user_announcement')
    )
    op.create_index(op.f('ix_user_announcements_user_id'), 'user_announcements', ['user_id'], unique=False)
    op.create_index(op.f('ix_user_announcements_announcement_id'), 'user_announcements', ['announcement_id'], unique=False)


def downgrade():
    op.drop_index(op.f('ix_user_announcements_announcement_id'), table_name='user_announcements')
    op.drop_index(op.f('ix_user_announcements_user_id'), table_name='user_announcements')
    op.drop_table('user_announcements')
    
    op.drop_index('ix_ann_pinned_updated', table_name='announcements')
    op.drop_index('ix_ann_active_schedule', table_name='announcements')
    op.drop_index(op.f('ix_announcements_ends_at'), table_name='announcements')
    op.drop_index(op.f('ix_announcements_starts_at'), table_name='announcements')
    op.drop_index(op.f('ix_announcements_is_active'), table_name='announcements')
    op.drop_index(op.f('ix_announcements_is_pinned'), table_name='announcements')
    op.drop_index(op.f('ix_announcements_level'), table_name='announcements')
    op.drop_index(op.f('ix_announcements_title'), table_name='announcements')
    op.drop_table('announcements')

