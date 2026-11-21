"""Add immutable snapshot storage to daily distribution plan publications.

Revision ID: 20261121_000002_dist_plan_snapshot
Revises: 20261121_000001_dist_plan_locks

This additive migration does not modify historical CRM records or plans.
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20261121_000002_plan_snapshot"
down_revision = "20261121_000001_dist_plan_locks"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "distribution_daily_plan_locks",
        sa.Column("plan_snapshot", sa.JSON(), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("distribution_daily_plan_locks", "plan_snapshot")
