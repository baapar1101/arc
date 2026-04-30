# noqa: D100
"""Users: last_activity_at و signature_file_id (هم‌سو با مدل)."""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op
from sqlalchemy import inspect

revision = "20260607_000001_users_last_activity_signature"
down_revision = "20260606_000001_business_crm_allow_web_chat_voice"
branch_labels = None
depends_on = None


def upgrade() -> None:
	bind = op.get_bind()
	insp = inspect(bind)
	col_names = {c["name"] for c in insp.get_columns("users")}
	if "last_activity_at" not in col_names:
		op.add_column("users", sa.Column("last_activity_at", sa.DateTime(), nullable=True))
		op.create_index("ix_users_last_activity_at", "users", ["last_activity_at"], unique=False)
	if "signature_file_id" not in col_names:
		op.add_column(
			"users",
			sa.Column("signature_file_id", sa.String(length=36), nullable=True),
		)


def downgrade() -> None:
	bind = op.get_bind()
	insp = inspect(bind)
	col_names = {c["name"] for c in insp.get_columns("users")}
	if "signature_file_id" in col_names:
		op.drop_column("users", "signature_file_id")
	if "last_activity_at" in col_names:
		op.drop_index("ix_users_last_activity_at", table_name="users")
		op.drop_column("users", "last_activity_at")
