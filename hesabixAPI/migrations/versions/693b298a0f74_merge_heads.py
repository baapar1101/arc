"""merge_heads

Revision ID: 693b298a0f74
Revises: 20251120_000001_add_default_warehouse_to_products, 20251120_053716_add_ai_tables
Create Date: 2025-11-21 20:08:40.368182

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '693b298a0f74'
down_revision = ('20251120_000001_add_default_warehouse_to_products', '20251120_053716_add_ai_tables')
branch_labels = None
depends_on = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
