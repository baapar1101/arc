"""support ticket events table

Revision ID: 20260627_000001_support_ticket_events
Revises: 20260704_000001_ai_model_reasoning_effort
Create Date: 2026-06-27
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260627_000001_support_ticket_events"
down_revision = "20260704_000001_ai_model_reasoning_effort"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "support_ticket_events",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("ticket_id", sa.Integer(), nullable=False),
        sa.Column("actor_id", sa.Integer(), nullable=True),
        sa.Column("event_type", sa.String(length=50), nullable=False),
        sa.Column("old_value", sa.JSON(), nullable=True),
        sa.Column("new_value", sa.JSON(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.text("NOW()")),
        sa.ForeignKeyConstraint(["actor_id"], ["users.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["ticket_id"], ["support_tickets.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_support_ticket_events_ticket_created",
        "support_ticket_events",
        ["ticket_id", "created_at"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index("ix_support_ticket_events_ticket_created", table_name="support_ticket_events")
    op.drop_table("support_ticket_events")
