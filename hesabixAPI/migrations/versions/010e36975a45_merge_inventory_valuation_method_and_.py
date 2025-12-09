"""merge inventory valuation method and other migrations

Revision ID: 010e36975a45
Revises: 20240101_120000, 483a0bf37370
Create Date: 2025-01-14 00:00:00.000000

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '010e36975a45'
down_revision = ('20240101_120000', '483a0bf37370')
branch_labels = None
depends_on = None


def upgrade() -> None:
    # این یک میگریشن merge است و نیازی به کد ندارد
    pass


def downgrade() -> None:
    # این یک میگریشن merge است و نیازی به کد ندارد
    pass

