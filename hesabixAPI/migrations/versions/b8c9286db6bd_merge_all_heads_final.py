"""merge_all_heads_final

Revision ID: b8c9286db6bd
Revises: 48f89768a316, add_default_price_list_to_quick_sales
Create Date: 2025-11-29 14:04:12.197735

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = 'b8c9286db6bd'
down_revision = ('48f89768a316', 'add_default_price_list_to_quick_sales')
branch_labels = None
depends_on = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
