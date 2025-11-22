"""add last_reset_at and expires_at to AI subscriptions

Revision ID: 20250122_000001_add_last_reset_at_and_expires_at_to_ai_subscriptions
Revises: 20250121_000001_add_ai_expense_account
Create Date: 2025-01-22 00:00:01.000001
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = "20250122_000001_add_last_reset_at_and_expires_at_to_ai_subscriptions"
down_revision: Union[str, None] = "20250121_000001_add_ai_expense_account"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # اضافه کردن فیلد expires_at
    op.add_column(
        'user_ai_subscriptions',
        sa.Column('expires_at', sa.DateTime(), nullable=True)
    )
    
    # اضافه کردن فیلد last_reset_at
    op.add_column(
        'user_ai_subscriptions',
        sa.Column('last_reset_at', sa.DateTime(), nullable=True)
    )
    
    # کپی کردن period_end به expires_at برای رکوردهای موجود
    op.execute("""
        UPDATE user_ai_subscriptions 
        SET expires_at = period_end 
        WHERE period_end IS NOT NULL AND expires_at IS NULL
    """)


def downgrade() -> None:
    # حذف فیلدها
    op.drop_column('user_ai_subscriptions', 'last_reset_at')
    op.drop_column('user_ai_subscriptions', 'expires_at')

