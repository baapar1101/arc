"""merge_heads

Revision ID: 27f209ffe151
Revises: 20250115_000001_add_ping_pong_scores_table, 20250126_000001_add_gift_credit_account, 755d6bd2d6d7
Create Date: 2025-11-17 18:19:18.176186

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '27f209ffe151'
down_revision = ('20250115_000001_add_ping_pong_scores_table', '20250126_000001_add_gift_credit_account', '755d6bd2d6d7')
branch_labels = None
depends_on = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
