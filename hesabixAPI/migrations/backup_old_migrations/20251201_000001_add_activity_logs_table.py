from __future__ import annotations

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import mysql


# revision identifiers, used by Alembic.
revision = '20251201_000001_add_activity_logs_table'
down_revision = None  # باید آخرین revision را قرار دهیم
branch_labels = None
depends_on = None


def upgrade() -> None:
	# Create activity_logs table
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
		sa.PrimaryKeyConstraint('id'),
		mysql_charset='utf8mb4'
	)
	
	# Indexes
	op.create_index('ix_activity_logs_user_id', 'activity_logs', ['user_id'])
	op.create_index('ix_activity_logs_business_id', 'activity_logs', ['business_id'])
	op.create_index('ix_activity_logs_category', 'activity_logs', ['category'])
	op.create_index('ix_activity_logs_action', 'activity_logs', ['action'])
	op.create_index('ix_activity_logs_entity_type', 'activity_logs', ['entity_type'])
	op.create_index('ix_activity_logs_entity_id', 'activity_logs', ['entity_id'])
	op.create_index('ix_activity_logs_created_at', 'activity_logs', ['created_at'])
	
	# Composite indexes for common queries
	op.create_index('ix_activity_logs_business_category_action', 'activity_logs', ['business_id', 'category', 'action'])
	op.create_index('ix_activity_logs_business_entity', 'activity_logs', ['business_id', 'entity_type', 'entity_id'])
	op.create_index('ix_activity_logs_user_created', 'activity_logs', ['user_id', 'created_at'])
	op.create_index('ix_activity_logs_business_created', 'activity_logs', ['business_id', 'created_at'])


def downgrade() -> None:
	# Drop indexes
	op.drop_index('ix_activity_logs_business_created', table_name='activity_logs')
	op.drop_index('ix_activity_logs_user_created', table_name='activity_logs')
	op.drop_index('ix_activity_logs_business_entity', table_name='activity_logs')
	op.drop_index('ix_activity_logs_business_category_action', table_name='activity_logs')
	op.drop_index('ix_activity_logs_created_at', table_name='activity_logs')
	op.drop_index('ix_activity_logs_entity_id', table_name='activity_logs')
	op.drop_index('ix_activity_logs_entity_type', table_name='activity_logs')
	op.drop_index('ix_activity_logs_action', table_name='activity_logs')
	op.drop_index('ix_activity_logs_category', table_name='activity_logs')
	op.drop_index('ix_activity_logs_business_id', table_name='activity_logs')
	op.drop_index('ix_activity_logs_user_id', table_name='activity_logs')
	
	# Drop table
	op.drop_table('activity_logs')

