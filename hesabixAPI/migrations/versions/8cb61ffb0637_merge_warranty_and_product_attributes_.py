"""merge warranty and product attributes branches

Revision ID: 8cb61ffb0637
Revises: 20250120_000002, 20251202_000001
Create Date: 2025-01-20 00:00:00.000000

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '8cb61ffb0637'
down_revision = ('20250120_000002', '20251202_000001')
branch_labels = None
depends_on = None


def upgrade() -> None:
    # این یک میگریشن merge است و نیازی به کد ندارد
    pass


def downgrade() -> None:
    # این یک میگریشن merge است و نیازی به کد ندارد
    pass


