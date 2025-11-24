"""fix_telegram_chat_id_bigint

Revision ID: 20251124_200000
Revises: 20251110_090001_add_notifications_and_telegram
Create Date: 2025-11-24 20:00:00

"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '20251124_200000'
down_revision = '20251110_090001_add_notifications_and_telegram'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # تغییر نوع ستون telegram_chat_id از Integer به BigInteger
    # چون chat_id تلگرام می‌تواند بزرگ‌تر از INT max (2147483647) باشد
    op.alter_column(
        'users',
        'telegram_chat_id',
        existing_type=sa.Integer(),
        type_=sa.BigInteger(),
        existing_nullable=True,
        existing_server_default=None
    )


def downgrade() -> None:
    # برگشت به Integer (اما ممکن است برای chat_id‌های بزرگ مشکل ایجاد کند)
    op.alter_column(
        'users',
        'telegram_chat_id',
        existing_type=sa.BigInteger(),
        type_=sa.Integer(),
        existing_nullable=True,
        existing_server_default=None
    )

