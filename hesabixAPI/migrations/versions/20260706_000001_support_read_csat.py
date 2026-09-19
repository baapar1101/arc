"""support ticket read tracking and CSAT

Revision ID: 20260706_000001_support_read_csat
Revises: 20260705_000002_support_phase3
Create Date: 2026-07-06
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260706_000001_support_read_csat"
down_revision = "20260705_000002_support_phase3"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("support_tickets", sa.Column("user_last_read_at", sa.DateTime(), nullable=True))
    op.add_column("support_tickets", sa.Column("operator_last_read_at", sa.DateTime(), nullable=True))
    op.add_column("support_tickets", sa.Column("csat_rating", sa.SmallInteger(), nullable=True))
    op.add_column("support_tickets", sa.Column("csat_comment", sa.Text(), nullable=True))
    op.add_column("support_tickets", sa.Column("csat_submitted_at", sa.DateTime(), nullable=True))


def downgrade() -> None:
    op.drop_column("support_tickets", "csat_submitted_at")
    op.drop_column("support_tickets", "csat_comment")
    op.drop_column("support_tickets", "csat_rating")
    op.drop_column("support_tickets", "operator_last_read_at")
    op.drop_column("support_tickets", "user_last_read_at")
