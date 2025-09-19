from __future__ import annotations

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = "20250117_000005"
down_revision = "20250117_000004"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Add geographic fields to businesses table
    op.add_column('businesses', sa.Column('country', sa.String(length=100), nullable=True))
    op.add_column('businesses', sa.Column('province', sa.String(length=100), nullable=True))
    op.add_column('businesses', sa.Column('city', sa.String(length=100), nullable=True))
    op.add_column('businesses', sa.Column('postal_code', sa.String(length=20), nullable=True))


def downgrade() -> None:
    # Drop geographic columns
    op.drop_column('businesses', 'postal_code')
    op.drop_column('businesses', 'city')
    op.drop_column('businesses', 'province')
    op.drop_column('businesses', 'country')
