"""لاگ کارهای مدیر سیستم.

Revision ID: 20261110_000004_admin_audit_logs
Revises: 20261110_000003_crm_sequence_cadence, 20261110_000001_procurement_plugin
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20261110_000004_admin_audit_logs"
down_revision = (
	"20261110_000003_crm_sequence_cadence",
	"20261110_000001_procurement_plugin",
)
branch_labels = None
depends_on = None


def upgrade() -> None:
	conn = op.get_bind()
	inspector = sa.inspect(conn)
	if "admin_audit_logs" in set(inspector.get_table_names()):
		return
	op.create_table(
		"admin_audit_logs",
		sa.Column("id", sa.BigInteger(), primary_key=True, autoincrement=True),
		sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
		sa.Column("actor_user_id", sa.BigInteger(), nullable=True),
		sa.Column("action", sa.String(length=64), nullable=False),
		sa.Column("target_type", sa.String(length=64), nullable=True),
		sa.Column("target_id", sa.String(length=64), nullable=True),
		sa.Column("summary", sa.String(length=500), nullable=False),
		sa.Column("metadata_json", sa.Text(), nullable=True),
		sa.Column("client_ip", sa.String(length=64), nullable=True),
	)
	op.create_index("ix_admin_audit_logs_created", "admin_audit_logs", ["created_at"])
	op.create_index("ix_admin_audit_logs_action_created", "admin_audit_logs", ["action", "created_at"])
	op.create_index("ix_admin_audit_logs_actor", "admin_audit_logs", ["actor_user_id"])


def downgrade() -> None:
	op.drop_index("ix_admin_audit_logs_actor", table_name="admin_audit_logs")
	op.drop_index("ix_admin_audit_logs_action_created", table_name="admin_audit_logs")
	op.drop_index("ix_admin_audit_logs_created", table_name="admin_audit_logs")
	op.drop_table("admin_audit_logs")
