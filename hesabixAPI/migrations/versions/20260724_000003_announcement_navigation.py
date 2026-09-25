"""announcement navigation metadata for in-app notifications

Revision ID: 20260724_000003_announcement_navigation
Revises: 20260724_000002_support_ticket_last_message_at
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260724_000003_announcement_navigation"
down_revision = "20260724_000002_support_ticket_last_message_at"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("announcements", sa.Column("deep_link", sa.String(length=512), nullable=True))
    op.add_column("announcements", sa.Column("ticket_id", sa.Integer(), nullable=True))
    op.add_column("announcements", sa.Column("event_key", sa.String(length=128), nullable=True))
    op.create_index("ix_announcements_ticket_id", "announcements", ["ticket_id"])
    op.create_index("ix_announcements_event_key", "announcements", ["event_key"])


def downgrade() -> None:
    op.drop_index("ix_announcements_event_key", table_name="announcements")
    op.drop_index("ix_announcements_ticket_id", table_name="announcements")
    op.drop_column("announcements", "event_key")
    op.drop_column("announcements", "ticket_id")
    op.drop_column("announcements", "deep_link")
