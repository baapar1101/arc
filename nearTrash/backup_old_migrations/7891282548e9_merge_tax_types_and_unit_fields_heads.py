"""merge tax_types and unit fields heads

Revision ID: 7891282548e9
Revises: 20250106_000002, b2b68cf299a3
Create Date: 2025-10-06 20:20:43.839460

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '7891282548e9'
down_revision = ('20250106_000002', 'b2b68cf299a3')
branch_labels = None
depends_on = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
