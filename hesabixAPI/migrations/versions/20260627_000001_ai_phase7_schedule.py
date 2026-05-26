"""فاز ۷: زمان‌بندی ارزیابی خودکار AI

Revision ID: 20260627_000001_ai_phase7_schedule
Revises: 20260626_000002_ai_pgvector_optional
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260627_000001_ai_phase7_schedule"
down_revision = "20260626_000002_ai_pgvector_optional"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "ai_eval_schedule",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("enabled", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column("cron_expression", sa.String(64), nullable=False, server_default="0 3 * * *"),
        sa.Column("timezone", sa.String(64), nullable=False, server_default="Asia/Tehran"),
        sa.Column("business_id", sa.Integer(), sa.ForeignKey("businesses.id", ondelete="SET NULL"), nullable=True),
        sa.Column("min_pass_rate", sa.Integer(), nullable=False, server_default="70"),
        sa.Column("last_run_id", sa.Integer(), sa.ForeignKey("ai_eval_runs.id", ondelete="SET NULL"), nullable=True),
        sa.Column("last_run_at", sa.DateTime(), nullable=True),
        sa.Column("last_pass_rate", sa.Integer(), nullable=True),
        sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=sa.text("NOW()")),
    )
    op.execute(
        """
        INSERT INTO ai_eval_schedule (id, enabled, cron_expression, timezone, min_pass_rate)
        SELECT 1, false, '0 3 * * *', 'Asia/Tehran', 70
        WHERE NOT EXISTS (SELECT 1 FROM ai_eval_schedule WHERE id = 1)
        """
    )


def downgrade() -> None:
    op.drop_table("ai_eval_schedule")
