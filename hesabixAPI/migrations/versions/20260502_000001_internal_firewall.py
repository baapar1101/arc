"""جداول فایروال داخلی، لاگ درخواست و ممیزی

Revision ID: 20260502_000001_internal_firewall
Revises: 20260501_000001_auth_security_events_captcha_ip
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260502_000001_internal_firewall"
down_revision = "20260501_000001_auth_security_events_captcha_ip"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.create_table(
		"firewall_rules",
		sa.Column("id", sa.BigInteger(), autoincrement=True, nullable=False),
		sa.Column("enabled", sa.Boolean(), nullable=False),
		sa.Column("action", sa.String(length=8), nullable=False),
		sa.Column("ip_cidr", sa.String(length=64), nullable=False),
		sa.Column("path_prefix", sa.String(length=512), nullable=True),
		sa.Column("http_methods", sa.String(length=128), nullable=True),
		sa.Column("priority", sa.Integer(), nullable=False),
		sa.Column("expires_at", sa.DateTime(), nullable=True),
		sa.Column("note", sa.Text(), nullable=True),
		sa.Column("source", sa.String(length=32), nullable=False),
		sa.Column("created_by_user_id", sa.BigInteger(), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.PrimaryKeyConstraint("id"),
	)
	op.create_index("ix_firewall_rules_enabled_priority", "firewall_rules", ["enabled", "priority"])
	op.create_index("ix_firewall_rules_expires_at", "firewall_rules", ["expires_at"])

	op.create_table(
		"firewall_request_logs",
		sa.Column("id", sa.BigInteger(), autoincrement=True, nullable=False),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("client_ip", sa.String(length=45), nullable=False),
		sa.Column("method", sa.String(length=16), nullable=False),
		sa.Column("path", sa.String(length=1024), nullable=False),
		sa.Column("user_agent", sa.String(length=512), nullable=True),
		sa.Column("rule_id", sa.BigInteger(), nullable=True),
		sa.PrimaryKeyConstraint("id"),
	)
	op.create_index("ix_firewall_req_logs_created", "firewall_request_logs", ["created_at"])
	op.create_index("ix_firewall_req_logs_ip_created", "firewall_request_logs", ["client_ip", "created_at"])

	op.create_table(
		"firewall_audit_logs",
		sa.Column("id", sa.BigInteger(), autoincrement=True, nullable=False),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("event_type", sa.String(length=64), nullable=False),
		sa.Column("actor_user_id", sa.BigInteger(), nullable=True),
		sa.Column("ip_cidr", sa.String(length=64), nullable=True),
		sa.Column("rule_id", sa.BigInteger(), nullable=True),
		sa.Column("details", sa.Text(), nullable=True),
		sa.PrimaryKeyConstraint("id"),
	)
	op.create_index("ix_firewall_audit_created", "firewall_audit_logs", ["created_at"])


def downgrade() -> None:
	op.drop_index("ix_firewall_audit_created", table_name="firewall_audit_logs")
	op.drop_table("firewall_audit_logs")
	op.drop_index("ix_firewall_req_logs_ip_created", table_name="firewall_request_logs")
	op.drop_index("ix_firewall_req_logs_created", table_name="firewall_request_logs")
	op.drop_table("firewall_request_logs")
	op.drop_index("ix_firewall_rules_expires_at", table_name="firewall_rules")
	op.drop_index("ix_firewall_rules_enabled_priority", table_name="firewall_rules")
	op.drop_table("firewall_rules")
