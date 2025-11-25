"""add_email_verification

Revision ID: 20251124_200001
Revises: 20251124_200000
Create Date: 2025-11-24 20:00:01.000000

"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import mysql

# revision identifiers, used by Alembic.
revision = '20251124_200001'
down_revision = '20251124_200000'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # اضافه کردن فیلد email_verified به جدول users
    op.add_column('users', sa.Column('email_verified', sa.Boolean(), nullable=False, server_default='0'))
    op.create_index(op.f('ix_users_email_verified'), 'users', ['email_verified'], unique=False)
    
    # ایجاد جدول email_verification_tokens
    op.create_table('email_verification_tokens',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('email', sa.String(length=255), nullable=False),
        sa.Column('token_hash', sa.String(length=128), nullable=False),
        sa.Column('expires_at', sa.DateTime(), nullable=False),
        sa.Column('used_at', sa.DateTime(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('token_hash')
    )
    op.create_index(op.f('ix_email_verification_tokens_user_id'), 'email_verification_tokens', ['user_id'], unique=False)
    op.create_index(op.f('ix_email_verification_tokens_email'), 'email_verification_tokens', ['email'], unique=False)
    op.create_index(op.f('ix_email_verification_tokens_token_hash'), 'email_verification_tokens', ['token_hash'], unique=True)


def downgrade() -> None:
    # حذف جدول email_verification_tokens
    op.drop_index(op.f('ix_email_verification_tokens_token_hash'), table_name='email_verification_tokens')
    op.drop_index(op.f('ix_email_verification_tokens_email'), table_name='email_verification_tokens')
    op.drop_index(op.f('ix_email_verification_tokens_user_id'), table_name='email_verification_tokens')
    op.drop_table('email_verification_tokens')
    
    # حذف فیلد email_verified از جدول users
    op.drop_index(op.f('ix_users_email_verified'), table_name='users')
    op.drop_column('users', 'email_verified')


