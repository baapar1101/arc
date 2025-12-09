"""merge multiple heads before repair shop

Revision ID: a23683863c8a
Revises: 20250203_000001, 20250115_000001, 20250129_120000
Create Date: 2025-02-04 00:00:00.000000

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = 'a23683863c8a'
down_revision = ('20250203_000001', '20250115_000001', '20250129_120000')
branch_labels = None
depends_on = None


def upgrade() -> None:
    # این یک میگریشن merge است و نیازی به کد ندارد
    pass


def downgrade() -> None:
    # این یک میگریشن merge است و نیازی به کد ندارد
    pass

