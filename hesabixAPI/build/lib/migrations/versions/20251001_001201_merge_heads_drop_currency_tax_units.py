from __future__ import annotations

from alembic import op  # noqa: F401
import sqlalchemy as sa  # noqa: F401


# revision identifiers, used by Alembic.
revision = '20251001_001201_merge_heads_drop_currency_tax_units'
down_revision = (
    '20251001_001101_drop_price_list_currency_default_unit',
    '9f9786ae7191',
)
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Merge only; no operations.
    pass


def downgrade() -> None:
    # Merge only; no operations.
    pass


