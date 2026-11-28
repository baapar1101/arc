"""Add nullable immutable publication snapshot storage.

Existing publications deliberately retain NULL; no historical plan is
fabricated from mutable current data.
"""
import sqlalchemy as sa
from alembic import op

revision = "20261128_000001_plan_snapshot"
down_revision = "20261125_000001_safe_upstream"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column("distribution_daily_plan_locks",
                  sa.Column("plan_snapshot", sa.JSON(), nullable=True))


def downgrade():
    # Refuse destructive rollback once snapshot data is in use.
    table = sa.table("distribution_daily_plan_locks",
                     sa.column("plan_snapshot", sa.JSON()))
    count = op.get_bind().execute(
        sa.select(sa.func.count()).select_from(table).where(
            table.c.plan_snapshot.is_not(None)
        )
    ).scalar_one()
    if count:
        raise RuntimeError("Cannot downgrade: stored distribution plan snapshots exist")
    op.drop_column("distribution_daily_plan_locks", "plan_snapshot")
