"""merge heads

Revision ID: a1443c153b47
Revises: 20250102_000001, 20251002_000101_add_bank_accounts_table
Create Date: 2025-10-03 14:25:49.978103

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = 'a1443c153b47'
down_revision = ('20250102_000001', '20251002_000101_add_bank_accounts_table')
branch_labels = None
depends_on = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
