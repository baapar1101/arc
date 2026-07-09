"""documents timestamp columns -> TIMESTAMPTZ (UTC semantics)

Revision ID: 20260711_000002_documents_timestamptz
Revises: 20260711_000001_business_display_timezone
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260711_000002_documents_timestamptz"
down_revision = "20260711_000001_business_display_timezone"
branch_labels = None
depends_on = None

_COLUMNS = ("registered_at", "created_at", "updated_at")


def upgrade() -> None:
	for col in _COLUMNS:
		op.alter_column(
			"documents",
			col,
			existing_type=sa.DateTime(),
			type_=sa.DateTime(timezone=True),
			postgresql_using=f"{col} AT TIME ZONE 'UTC'",
			existing_nullable=False,
		)


def downgrade() -> None:
	for col in _COLUMNS:
		op.alter_column(
			"documents",
			col,
			existing_type=sa.DateTime(timezone=True),
			type_=sa.DateTime(),
			postgresql_using=f"{col} AT TIME ZONE 'UTC'",
			existing_nullable=False,
		)
