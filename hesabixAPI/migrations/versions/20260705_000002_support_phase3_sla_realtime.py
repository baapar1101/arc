"""support phase3 SLA policies and ticket SLA columns

Revision ID: 20260705_000002_support_phase3
Revises: 20260705_000001_merge_heads
Create Date: 2026-07-05
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260705_000002_support_phase3"
down_revision = "20260705_000001_merge_heads"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "support_sla_policies",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("name", sa.String(length=100), nullable=False),
        sa.Column("priority_id", sa.Integer(), nullable=True),
        sa.Column("first_response_minutes", sa.Integer(), nullable=False),
        sa.Column("resolution_minutes", sa.Integer(), nullable=False),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.text("NOW()")),
        sa.ForeignKeyConstraint(["priority_id"], ["support_priorities.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_support_sla_policies_priority_id", "support_sla_policies", ["priority_id"])

    op.add_column("support_tickets", sa.Column("first_response_due_at", sa.DateTime(), nullable=True))
    op.add_column("support_tickets", sa.Column("resolution_due_at", sa.DateTime(), nullable=True))
    op.add_column("support_tickets", sa.Column("first_responded_at", sa.DateTime(), nullable=True))
    op.add_column(
        "support_tickets",
        sa.Column("sla_breached", sa.Boolean(), nullable=False, server_default=sa.text("false")),
    )

    op.create_index(
        "ix_support_tickets_sla_open",
        "support_tickets",
        ["sla_breached", "resolution_due_at"],
        postgresql_where=sa.text("sla_breached = false AND closed_at IS NULL"),
    )
    op.create_index(
        "ix_support_tickets_status_priority_created",
        "support_tickets",
        ["status_id", "priority_id", "created_at"],
    )
    op.create_index(
        "ix_support_tickets_assigned_updated",
        "support_tickets",
        ["assigned_operator_id", "updated_at"],
        postgresql_where=sa.text("assigned_operator_id IS NOT NULL"),
    )

    conn = op.get_bind()
    priorities = conn.execute(sa.text("SELECT id, name, \"order\" FROM support_priorities ORDER BY \"order\", id")).fetchall()
    defaults = [
        (15, 240),
        (60, 480),
        (240, 1440),
        (480, 4320),
    ]
    for idx, row in enumerate(priorities):
        fr, res = defaults[min(idx, len(defaults) - 1)]
        conn.execute(
            sa.text(
                "INSERT INTO support_sla_policies (name, priority_id, first_response_minutes, resolution_minutes, is_active) "
                "VALUES (:name, :pid, :fr, :res, true)"
            ),
            {"name": f"SLA — {row[1]}", "pid": row[0], "fr": fr, "res": res},
        )


def downgrade() -> None:
    op.drop_index("ix_support_tickets_assigned_updated", table_name="support_tickets")
    op.drop_index("ix_support_tickets_status_priority_created", table_name="support_tickets")
    op.drop_index("ix_support_tickets_sla_open", table_name="support_tickets")
    op.drop_column("support_tickets", "sla_breached")
    op.drop_column("support_tickets", "first_responded_at")
    op.drop_column("support_tickets", "resolution_due_at")
    op.drop_column("support_tickets", "first_response_due_at")
    op.drop_index("ix_support_sla_policies_priority_id", table_name="support_sla_policies")
    op.drop_table("support_sla_policies")
