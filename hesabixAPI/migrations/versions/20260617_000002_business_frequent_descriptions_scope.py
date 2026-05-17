"""ستون scope برای تفکیک لیست شرح‌های پرتکرار به‌ازای بخش

Revision ID: 20260617_000002_business_frequent_descriptions_scope
Revises: 20260617_000001_business_frequent_descriptions
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260617_000002_business_frequent_descriptions_scope"
down_revision = "20260617_000001_business_frequent_descriptions"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.add_column(
		"business_frequent_descriptions",
		sa.Column(
			"scope",
			sa.String(length=64),
			nullable=False,
			server_default=sa.text("'general'"),
		),
	)
	op.create_index(
		"ix_business_frequent_descriptions_business_scope",
		"business_frequent_descriptions",
		["business_id", "scope"],
		unique=False,
	)


def downgrade() -> None:
	op.drop_index(
		"ix_business_frequent_descriptions_business_scope",
		table_name="business_frequent_descriptions",
	)
	op.drop_column("business_frequent_descriptions", "scope")
