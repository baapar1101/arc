"""merge inventory_valuation_method and other head

Revision ID: 010e36975a45
Revises: a1b2c3d4e5f6, 20250115_000001
Create Date: 2025-11-29 15:12:44.894992

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '010e36975a45'
down_revision = ('a1b2c3d4e5f6', '20250115_000001')
branch_labels = None
depends_on = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
