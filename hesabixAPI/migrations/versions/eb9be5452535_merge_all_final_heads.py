"""merge_all_final_heads

Revision ID: eb9be5452535
Revises: 023c8d2d2222, 20250123_000001_add_description_to_categories
Create Date: 2025-11-23 11:30:51.042386

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = 'eb9be5452535'
down_revision = ('023c8d2d2222', '20250123_000001_add_description_to_categories')
branch_labels = None
depends_on = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
