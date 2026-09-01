"""فاز بعدی پخش: ترتیب روزمحور مسیر، بدون تداخل با روزهای دیگر.

Revision ID: 20260901_000002_distribution_day_sort
Revises: 20260901_000001_distribution_phase4_ops
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260901_000002_distribution_day_sort"
down_revision = "20260901_000001_distribution_phase4_ops"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.add_column(
		"distribution_routes",
		sa.Column("plan_sort_overrides", sa.JSON(), nullable=True),
	)


def downgrade() -> None:
	op.drop_column("distribution_routes", "plan_sort_overrides")
