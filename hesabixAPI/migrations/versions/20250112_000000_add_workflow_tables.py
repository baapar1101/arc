"""add_workflow_tables

Revision ID: 20250112_000000
Revises: 20240101_120000
Create Date: 2025-01-12 00:00:00.000000

"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import mysql


# revision identifiers, used by Alembic.
revision = '20250112_000000'
down_revision = '20240101_120000'
branch_labels = None
depends_on = None


def upgrade() -> None:
    """ایجاد جداول workflow"""
    
    # جدول workflows
    op.create_table(
        'workflows',
        sa.Column('id', sa.Integer(), nullable=False, autoincrement=True),
        sa.Column('business_id', sa.Integer(), nullable=False),
        sa.Column('name', sa.String(length=255), nullable=False),
        sa.Column('description', sa.Text(), nullable=True),
        sa.Column('status', sa.String(length=50), nullable=False, server_default='پیش\u200cنویس'),
        sa.Column('workflow_data', sa.JSON(), nullable=False),
        sa.Column('settings', sa.JSON(), nullable=True),
        sa.Column('created_by_user_id', sa.Integer(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False, server_default=sa.text('CURRENT_TIMESTAMP')),
        sa.Column('updated_at', sa.DateTime(), nullable=False, server_default=sa.text('CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP')),
        sa.ForeignKeyConstraint(['business_id'], ['businesses.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['created_by_user_id'], ['users.id'], ondelete='SET NULL'),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_workflows_business_id'), 'workflows', ['business_id'], unique=False)
    op.create_index(op.f('ix_workflows_name'), 'workflows', ['name'], unique=False)
    op.create_index(op.f('ix_workflows_status'), 'workflows', ['status'], unique=False)
    op.create_index(op.f('ix_workflows_created_by_user_id'), 'workflows', ['created_by_user_id'], unique=False)
    op.create_index('idx_workflows_business_status', 'workflows', ['business_id', 'status'], unique=False)
    
    # جدول workflow_executions
    op.create_table(
        'workflow_executions',
        sa.Column('id', sa.Integer(), nullable=False, autoincrement=True),
        sa.Column('workflow_id', sa.Integer(), nullable=False),
        sa.Column('status', sa.String(length=50), nullable=False, server_default='در انتظار'),
        sa.Column('trigger_data', sa.JSON(), nullable=True),
        sa.Column('execution_data', sa.JSON(), nullable=True),
        sa.Column('error_message', sa.Text(), nullable=True),
        sa.Column('started_at', sa.DateTime(), nullable=True),
        sa.Column('completed_at', sa.DateTime(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False, server_default=sa.text('CURRENT_TIMESTAMP')),
        sa.ForeignKeyConstraint(['workflow_id'], ['workflows.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_workflow_executions_workflow_id'), 'workflow_executions', ['workflow_id'], unique=False)
    op.create_index(op.f('ix_workflow_executions_status'), 'workflow_executions', ['status'], unique=False)
    op.create_index('idx_workflow_executions_workflow_status', 'workflow_executions', ['workflow_id', 'status'], unique=False)
    op.create_index('idx_workflow_executions_created', 'workflow_executions', ['created_at'], unique=False)
    
    # جدول workflow_logs
    op.create_table(
        'workflow_logs',
        sa.Column('id', sa.Integer(), nullable=False, autoincrement=True),
        sa.Column('execution_id', sa.Integer(), nullable=False),
        sa.Column('node_id', sa.String(length=100), nullable=True),
        sa.Column('level', sa.String(length=20), nullable=False, server_default='info'),
        sa.Column('message', sa.Text(), nullable=False),
        sa.Column('data', sa.JSON(), nullable=True),
        sa.Column('timestamp', sa.DateTime(), nullable=False, server_default=sa.text('CURRENT_TIMESTAMP')),
        sa.ForeignKeyConstraint(['execution_id'], ['workflow_executions.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_workflow_logs_execution_id'), 'workflow_logs', ['execution_id'], unique=False)
    op.create_index(op.f('ix_workflow_logs_node_id'), 'workflow_logs', ['node_id'], unique=False)
    op.create_index(op.f('ix_workflow_logs_level'), 'workflow_logs', ['level'], unique=False)
    op.create_index(op.f('ix_workflow_logs_timestamp'), 'workflow_logs', ['timestamp'], unique=False)
    op.create_index('idx_workflow_logs_execution_timestamp', 'workflow_logs', ['execution_id', 'timestamp'], unique=False)


def downgrade() -> None:
    """حذف جداول workflow"""
    op.drop_index('idx_workflow_logs_execution_timestamp', table_name='workflow_logs')
    op.drop_index(op.f('ix_workflow_logs_timestamp'), table_name='workflow_logs')
    op.drop_index(op.f('ix_workflow_logs_level'), table_name='workflow_logs')
    op.drop_index(op.f('ix_workflow_logs_node_id'), table_name='workflow_logs')
    op.drop_index(op.f('ix_workflow_logs_execution_id'), table_name='workflow_logs')
    op.drop_table('workflow_logs')
    
    op.drop_index('idx_workflow_executions_created', table_name='workflow_executions')
    op.drop_index('idx_workflow_executions_workflow_status', table_name='workflow_executions')
    op.drop_index(op.f('ix_workflow_executions_status'), table_name='workflow_executions')
    op.drop_index(op.f('ix_workflow_executions_workflow_id'), table_name='workflow_executions')
    op.drop_table('workflow_executions')
    
    op.drop_index('idx_workflows_business_status', table_name='workflows')
    op.drop_index(op.f('ix_workflows_created_by_user_id'), table_name='workflows')
    op.drop_index(op.f('ix_workflows_status'), table_name='workflows')
    op.drop_index(op.f('ix_workflows_name'), table_name='workflows')
    op.drop_index(op.f('ix_workflows_business_id'), table_name='workflows')
    op.drop_table('workflows')

