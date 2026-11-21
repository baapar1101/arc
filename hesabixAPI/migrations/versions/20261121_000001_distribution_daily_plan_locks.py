"""Add per-visitor daily distribution plan publication records.

Revision ID: 20261121_000001_dist_plan_locks
Revises: 20261101_000001_sepidar_reconciliation

This migration adds a new table only. Existing distribution settings,
routes, CRM tables, and financial records are left unchanged.
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20261121_000001_dist_plan_locks"
down_revision = "20261101_000001_sepidar_reconciliation"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "distribution_daily_plan_locks",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("business_id", sa.Integer(), sa.ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("plan_date", sa.Date(), nullable=False),
        sa.Column("is_locked", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        sa.Column("published_by_user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True),
        sa.Column("published_at", sa.DateTime(), nullable=False),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.UniqueConstraint("business_id", "user_id", "plan_date", name="uq_dist_daily_plan_lock"),
    )
    op.create_index("ix_distribution_daily_plan_locks_business_id", "distribution_daily_plan_locks", ["business_id"])
    op.create_index("ix_distribution_daily_plan_locks_user_id", "distribution_daily_plan_locks", ["user_id"])
    op.create_index("ix_distribution_daily_plan_locks_plan_date", "distribution_daily_plan_locks", ["plan_date"])


def downgrade() -> None:
    op.drop_index("ix_distribution_daily_plan_locks_plan_date", table_name="distribution_daily_plan_locks")
    op.drop_index("ix_distribution_daily_plan_locks_user_id", table_name="distribution_daily_plan_locks")
    op.drop_index("ix_distribution_daily_plan_locks_business_id", table_name="distribution_daily_plan_locks")
    op.drop_table("distribution_daily_plan_locks")
