"""fix telegram_link_tokens date columns to timestamp

Revision ID: 20260724_000004_telegram_link_tokens_timestamps
Revises: 20260724_000003_announcement_navigation
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260724_000004_telegram_link_tokens_timestamps"
down_revision = "20260724_000003_announcement_navigation"
branch_labels = None
depends_on = None


def upgrade() -> None:
	# expires_at: end-of-day so same-day tokens stay valid after date→timestamp conversion
	op.alter_column(
		"telegram_link_tokens",
		"expires_at",
		existing_type=sa.Date(),
		type_=sa.DateTime(),
		existing_nullable=False,
		postgresql_using="(expires_at::timestamp + interval '1 day' - interval '1 second')",
	)
	for col in ("used_at", "created_at"):
		op.alter_column(
			"telegram_link_tokens",
			col,
			existing_type=sa.Date(),
			type_=sa.DateTime(),
			existing_nullable=col != "created_at",
			postgresql_using=f"{col}::timestamp",
		)


def downgrade() -> None:
	for col in ("expires_at", "used_at", "created_at"):
		op.alter_column(
			"telegram_link_tokens",
			col,
			existing_type=sa.DateTime(),
			type_=sa.Date(),
			existing_nullable=col != "created_at" and col != "expires_at",
			postgresql_using=f"{col}::date",
		)
