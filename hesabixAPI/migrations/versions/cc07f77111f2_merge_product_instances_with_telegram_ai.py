"""merge_product_instances_with_telegram_ai

Revision ID: cc07f77111f2
Revises: 20250206_000001_add_product_instances_and_unique_inventory, bce59a9d4fc4
Create Date: 2025-11-26 02:42:13.469532

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = 'cc07f77111f2'
down_revision = ('20250206_000001_add_product_instances_and_unique_inventory', 'bce59a9d4fc4')
branch_labels = None
depends_on = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
