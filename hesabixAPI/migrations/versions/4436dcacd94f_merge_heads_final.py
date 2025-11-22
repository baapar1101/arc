"""merge_heads_final

Revision ID: 4436dcacd94f
Revises: 693b298a0f74, 20250121_000001_add_ai_expense_account
Create Date: 2025-11-21 20:56:42.989106

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '4436dcacd94f'
down_revision = ('693b298a0f74', '20250121_000001_add_ai_expense_account')
branch_labels = None
depends_on = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
