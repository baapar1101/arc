"""merge all current heads

Revision ID: 4d60f85a6561
Revises: 20250106_000001, 20251204_000001, 20251205_000001, 20251206_000001_remove_phone_email_from_repair_orders
Create Date: 2025-12-06 03:00:23.397072

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '4d60f85a6561'
down_revision = ('20250106_000001', '20251204_000001', '20251205_000001', '20251206_000001_remove_phone_email_from_repair_orders')
branch_labels = None
depends_on = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
