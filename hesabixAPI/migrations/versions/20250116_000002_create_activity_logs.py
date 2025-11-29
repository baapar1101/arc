"""ایجاد جدول activity_logs در صورت عدم وجود

revision: 20250116_000002_create_activity_logs
down_revision: 20250116_000001
branch_labels: None
depends_on: None

این میگریشن جدول activity_logs را ایجاد می‌کند در صورتی که وجود نداشته باشد.
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa
from sqlalchemy import inspect


# revision identifiers, used by Alembic.
revision = '20250116_000002'
down_revision = '20250116_000001'
branch_labels = None
depends_on = None


def _table_exists(table_name: str) -> bool:
    """بررسی وجود جدول"""
    bind = op.get_bind()
    inspector = inspect(bind)
    return table_name in inspector.get_table_names()


def upgrade():
    """ایجاد جدول activity_logs در صورت عدم وجود"""
    if not _table_exists('activity_logs'):
        op.create_table(
            'activity_logs',
            sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
            sa.Column('user_id', sa.Integer(), nullable=True),
            sa.Column('business_id', sa.Integer(), nullable=True),
            sa.Column('category', sa.String(length=50), nullable=False),
            sa.Column('action', sa.String(length=50), nullable=False),
            sa.Column('entity_type', sa.String(length=50), nullable=True),
            sa.Column('entity_id', sa.Integer(), nullable=True),
            sa.Column('description', sa.Text(), nullable=False),
            sa.Column('before_data', sa.JSON(), nullable=True),
            sa.Column('after_data', sa.JSON(), nullable=True),
            sa.Column('extra_info', sa.JSON(), nullable=True),
            sa.Column('created_at', sa.DateTime(), nullable=False),
            sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='SET NULL'),
            sa.ForeignKeyConstraint(['business_id'], ['businesses.id'], ondelete='CASCADE'),
            sa.PrimaryKeyConstraint('id')
        )
        op.create_index(op.f('ix_activity_logs_user_id'), 'activity_logs', ['user_id'], unique=False)
        op.create_index(op.f('ix_activity_logs_business_id'), 'activity_logs', ['business_id'], unique=False)
        op.create_index(op.f('ix_activity_logs_category'), 'activity_logs', ['category'], unique=False)
        op.create_index(op.f('ix_activity_logs_action'), 'activity_logs', ['action'], unique=False)
        op.create_index(op.f('ix_activity_logs_entity_type'), 'activity_logs', ['entity_type'], unique=False)
        op.create_index(op.f('ix_activity_logs_entity_id'), 'activity_logs', ['entity_id'], unique=False)
        op.create_index(op.f('ix_activity_logs_created_at'), 'activity_logs', ['created_at'], unique=False)


def downgrade():
    """حذف جدول activity_logs"""
    if _table_exists('activity_logs'):
        op.drop_index(op.f('ix_activity_logs_created_at'), table_name='activity_logs')
        op.drop_index(op.f('ix_activity_logs_entity_id'), table_name='activity_logs')
        op.drop_index(op.f('ix_activity_logs_entity_type'), table_name='activity_logs')
        op.drop_index(op.f('ix_activity_logs_action'), table_name='activity_logs')
        op.drop_index(op.f('ix_activity_logs_category'), table_name='activity_logs')
        op.drop_index(op.f('ix_activity_logs_business_id'), table_name='activity_logs')
        op.drop_index(op.f('ix_activity_logs_user_id'), table_name='activity_logs')
        op.drop_table('activity_logs')

