"""merge warranty and product_attributes branches

Revision ID: 8cb61ffb0637
Revises: 20250120_000002, 20251202_000001
Create Date: 2025-12-02 08:52:41.973910

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '8cb61ffb0637'
down_revision = ('20250120_000002', '20251202_000001')
branch_labels = None
depends_on = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
