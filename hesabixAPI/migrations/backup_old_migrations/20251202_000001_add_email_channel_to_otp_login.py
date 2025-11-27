"""add_email_channel_to_otp_login

Revision ID: 20251202_000001
Revises: 20251126_171000
Create Date: 2025-12-02 00:00:01

"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '20251202_000001'
down_revision = '20251126_171000'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # تغییر mobile به nullable و اضافه کردن email
    op.alter_column('otp_login_sessions', 'mobile',
                    existing_type=sa.String(length=32),
                    nullable=True)
    
    # اضافه کردن فیلد email
    op.add_column('otp_login_sessions', sa.Column('email', sa.String(length=255), nullable=True))
    op.create_index(op.f('ix_otp_login_sessions_email'), 'otp_login_sessions', ['email'], unique=False)
    
    # اضافه کردن فیلد channel
    op.add_column('otp_login_sessions', sa.Column('channel', sa.String(length=20), nullable=False, server_default='sms'))
    
    # اضافه کردن فیلد last_otp_sent_at برای rate limiting
    op.add_column('otp_login_sessions', sa.Column('last_otp_sent_at', sa.DateTime(), nullable=True))


def downgrade() -> None:
    # حذف فیلدها
    op.drop_column('otp_login_sessions', 'last_otp_sent_at')
    op.drop_column('otp_login_sessions', 'channel')
    op.drop_index(op.f('ix_otp_login_sessions_email'), table_name='otp_login_sessions')
    op.drop_column('otp_login_sessions', 'email')
    
    # برگشت mobile به not null (اما ممکن است مشکل ایجاد کند اگر داده‌های null وجود داشته باشد)
    op.alter_column('otp_login_sessions', 'mobile',
                    existing_type=sa.String(length=32),
                    nullable=False)

