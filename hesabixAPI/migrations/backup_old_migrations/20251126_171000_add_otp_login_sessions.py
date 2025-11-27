"""add_otp_login_sessions

Revision ID: 20251126_171000
Revises: 20251126_170943
Create Date: 2025-11-26 17:10:00.000000

"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import mysql

# revision identifiers, used by Alembic.
revision = '20251126_171000'
down_revision = '20251126_170943'
branch_labels = None
depends_on = None


def upgrade() -> None:
    from sqlalchemy import inspect
    conn = op.get_bind()
    inspector = inspect(conn)
    
    # ایجاد جدول otp_login_sessions
    tables = inspector.get_table_names()
    if 'otp_login_sessions' not in tables:
        op.create_table('otp_login_sessions',
            sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
            sa.Column('session_id', sa.String(length=128), nullable=False),
            sa.Column('mobile', sa.String(length=32), nullable=False),
            sa.Column('user_id', sa.Integer(), nullable=True),
            sa.Column('otp_code_hash', sa.String(length=128), nullable=False),
            sa.Column('attempts', sa.Integer(), nullable=False, server_default='0'),
            sa.Column('expires_at', sa.DateTime(), nullable=False),
            sa.Column('verified_at', sa.DateTime(), nullable=True),
            sa.Column('ip_address', sa.String(length=64), nullable=True),
            sa.Column('user_agent', sa.String(length=255), nullable=True),
            sa.Column('created_at', sa.DateTime(), nullable=False),
            sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
            sa.PrimaryKeyConstraint('id')
        )
        # ایجاد ایندکس‌ها
        op.create_index(op.f('ix_otp_login_sessions_session_id'), 'otp_login_sessions', ['session_id'], unique=True)
        op.create_index(op.f('ix_otp_login_sessions_mobile'), 'otp_login_sessions', ['mobile'], unique=False)
        op.create_index(op.f('ix_otp_login_sessions_user_id'), 'otp_login_sessions', ['user_id'], unique=False)
        op.create_index(op.f('ix_otp_login_sessions_expires_at'), 'otp_login_sessions', ['expires_at'], unique=False)
        op.create_index('ix_otp_login_validity', 'otp_login_sessions', ['expires_at', 'verified_at'], unique=False)


def downgrade() -> None:
    # حذف جدول otp_login_sessions
    op.drop_index('ix_otp_login_validity', table_name='otp_login_sessions')
    op.drop_index(op.f('ix_otp_login_sessions_expires_at'), table_name='otp_login_sessions')
    op.drop_index(op.f('ix_otp_login_sessions_user_id'), table_name='otp_login_sessions')
    op.drop_index(op.f('ix_otp_login_sessions_mobile'), table_name='otp_login_sessions')
    op.drop_index(op.f('ix_otp_login_sessions_session_id'), table_name='otp_login_sessions')
    op.drop_table('otp_login_sessions')

