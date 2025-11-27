"""merge_heads_latest

Revision ID: 023c8d2d2222
Revises: 4436dcacd94f, 20250122_000001_add_last_reset_at_and_expires_at_to_ai_subscriptions
Create Date: 2025-11-22 09:58:57.848397

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '023c8d2d2222'
down_revision = ('4436dcacd94f', '20250122_000001_add_last_reset_at_and_expires_at_to_ai_subscriptions')
branch_labels = None
depends_on = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
