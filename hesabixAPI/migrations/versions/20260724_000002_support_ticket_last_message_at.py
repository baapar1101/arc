"""support ticket last_message_at for inbox sorting

Revision ID: 20260724_000002_support_ticket_last_message_at
Revises: 20260724_000001_product_suppliers
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260724_000002_support_ticket_last_message_at"
down_revision = "20260724_000001_product_suppliers"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("support_tickets", sa.Column("last_message_at", sa.DateTime(), nullable=True))
    op.create_index("ix_support_tickets_last_message_at", "support_tickets", ["last_message_at"])

    op.execute(
        """
        UPDATE support_tickets t
        SET last_message_at = (
            SELECT MAX(m.created_at)
            FROM support_messages m
            WHERE m.ticket_id = t.id AND m.is_internal IS FALSE
        )
        """
    )


def downgrade() -> None:
    op.drop_index("ix_support_tickets_last_message_at", table_name="support_tickets")
    op.drop_column("support_tickets", "last_message_at")
