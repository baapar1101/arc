"""جداول support: support_categories, support_priorities, support_statuses, support_tickets, support_messages"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import mysql


def upgrade():
    # جدول support_categories
    op.create_table(
        'support_categories',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('name', sa.String(length=100), nullable=False),
        sa.Column('description', sa.Text(), nullable=True),
        sa.Column('is_active', sa.Boolean(), nullable=False, server_default='1'),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_support_categories_name'), 'support_categories', ['name'], unique=False)

    # جدول support_priorities
    op.create_table(
        'support_priorities',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('name', sa.String(length=50), nullable=False),
        sa.Column('description', sa.Text(), nullable=True),
        sa.Column('color', sa.String(length=7), nullable=True),
        sa.Column('order', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_support_priorities_name'), 'support_priorities', ['name'], unique=False)

    # جدول support_statuses
    op.create_table(
        'support_statuses',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('name', sa.String(length=50), nullable=False),
        sa.Column('description', sa.Text(), nullable=True),
        sa.Column('color', sa.String(length=7), nullable=True),
        sa.Column('is_final', sa.Boolean(), nullable=False, server_default='0'),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_support_statuses_name'), 'support_statuses', ['name'], unique=False)

    # جدول support_tickets
    op.create_table(
        'support_tickets',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('title', sa.String(length=255), nullable=False),
        sa.Column('description', sa.Text(), nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('category_id', sa.Integer(), nullable=False),
        sa.Column('priority_id', sa.Integer(), nullable=False),
        sa.Column('status_id', sa.Integer(), nullable=False),
        sa.Column('assigned_operator_id', sa.Integer(), nullable=True),
        sa.Column('is_internal', sa.Boolean(), nullable=False, server_default='0'),
        sa.Column('closed_at', sa.DateTime(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['category_id'], ['support_categories.id'], ondelete='RESTRICT'),
        sa.ForeignKeyConstraint(['priority_id'], ['support_priorities.id'], ondelete='RESTRICT'),
        sa.ForeignKeyConstraint(['status_id'], ['support_statuses.id'], ondelete='RESTRICT'),
        sa.ForeignKeyConstraint(['assigned_operator_id'], ['users.id'], ondelete='SET NULL'),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_support_tickets_title'), 'support_tickets', ['title'], unique=False)
    op.create_index(op.f('ix_support_tickets_user_id'), 'support_tickets', ['user_id'], unique=False)
    op.create_index(op.f('ix_support_tickets_category_id'), 'support_tickets', ['category_id'], unique=False)
    op.create_index(op.f('ix_support_tickets_priority_id'), 'support_tickets', ['priority_id'], unique=False)
    op.create_index(op.f('ix_support_tickets_status_id'), 'support_tickets', ['status_id'], unique=False)
    op.create_index(op.f('ix_support_tickets_assigned_operator_id'), 'support_tickets', ['assigned_operator_id'], unique=False)

    # جدول support_messages
    op.create_table(
        'support_messages',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('ticket_id', sa.Integer(), nullable=False),
        sa.Column('sender_id', sa.Integer(), nullable=False),
        sa.Column('sender_type', mysql.ENUM('user', 'operator', 'system', name='sender_type'), nullable=False),
        sa.Column('content', sa.Text(), nullable=False),
        sa.Column('is_internal', sa.Boolean(), nullable=False, server_default='0'),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['ticket_id'], ['support_tickets.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['sender_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_support_messages_ticket_id'), 'support_messages', ['ticket_id'], unique=False)
    op.create_index(op.f('ix_support_messages_sender_id'), 'support_messages', ['sender_id'], unique=False)
    op.create_index(op.f('ix_support_messages_sender_type'), 'support_messages', ['sender_type'], unique=False)


def downgrade():
    op.drop_index(op.f('ix_support_messages_sender_type'), table_name='support_messages')
    op.drop_index(op.f('ix_support_messages_sender_id'), table_name='support_messages')
    op.drop_index(op.f('ix_support_messages_ticket_id'), table_name='support_messages')
    op.drop_table('support_messages')
    
    op.drop_index(op.f('ix_support_tickets_assigned_operator_id'), table_name='support_tickets')
    op.drop_index(op.f('ix_support_tickets_status_id'), table_name='support_tickets')
    op.drop_index(op.f('ix_support_tickets_priority_id'), table_name='support_tickets')
    op.drop_index(op.f('ix_support_tickets_category_id'), table_name='support_tickets')
    op.drop_index(op.f('ix_support_tickets_user_id'), table_name='support_tickets')
    op.drop_index(op.f('ix_support_tickets_title'), table_name='support_tickets')
    op.drop_table('support_tickets')
    
    op.drop_index(op.f('ix_support_statuses_name'), table_name='support_statuses')
    op.drop_table('support_statuses')
    
    op.drop_index(op.f('ix_support_priorities_name'), table_name='support_priorities')
    op.drop_table('support_priorities')
    
    op.drop_index(op.f('ix_support_categories_name'), table_name='support_categories')
    op.drop_table('support_categories')

