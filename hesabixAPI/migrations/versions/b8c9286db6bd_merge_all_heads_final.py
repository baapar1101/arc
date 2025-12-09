"""merge all heads final

Revision ID: b8c9286db6bd
Revises: 20250112_000000, 9cc424e46c07, 20250128_150000, 483a0bf37370
Create Date: 2025-01-15 00:00:00.000000

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = 'b8c9286db6bd'
down_revision = (
    '20250112_000000',
    '9cc424e46c07', 
    '20250128_150000',
    '483a0bf37370'
)
branch_labels = None
depends_on = None


def upgrade() -> None:
    # این یک میگریشن merge است و نیازی به کد ندارد
    pass


def downgrade() -> None:
    # این یک میگریشن merge است و نیازی به کد ندارد
    pass

