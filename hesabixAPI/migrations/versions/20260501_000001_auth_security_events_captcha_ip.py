"""رویدادهای امنیت احراز هویت و ستون IP برای کپچا

Revision ID: 20260501_000001_auth_security_events_captcha_ip
Revises: 20260430_000001_business_invoice_profit_fifo_shortage_mode
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260501_000001_auth_security_events_captcha_ip"
down_revision = "20260430_000001_business_invoice_profit_fifo_shortage_mode"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.create_table(
		"auth_security_events",
		sa.Column("id", sa.BigInteger(), autoincrement=True, nullable=False),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("event_type", sa.String(length=64), nullable=False),
		sa.Column("client_ip", sa.String(length=45), nullable=True),
		sa.Column("account_key", sa.String(length=32), nullable=True),
		sa.Column("detail_json", sa.Text(), nullable=True),
		sa.PrimaryKeyConstraint("id"),
	)
	op.create_index("ix_auth_security_events_created_at", "auth_security_events", ["created_at"])
	op.create_index("ix_auth_security_events_event_type", "auth_security_events", ["event_type"])
	op.create_index("ix_auth_security_events_client_ip", "auth_security_events", ["client_ip"])
	op.create_index("ix_auth_security_events_account_key", "auth_security_events", ["account_key"])
	op.create_index(
		"ix_auth_sec_type_created",
		"auth_security_events",
		["event_type", "created_at"],
	)
	op.create_index(
		"ix_auth_sec_acct_created",
		"auth_security_events",
		["account_key", "created_at"],
	)

	op.add_column("captchas", sa.Column("client_ip", sa.String(length=45), nullable=True))


def downgrade() -> None:
	op.drop_column("captchas", "client_ip")
	op.drop_index("ix_auth_sec_acct_created", table_name="auth_security_events")
	op.drop_index("ix_auth_sec_type_created", table_name="auth_security_events")
	op.drop_index("ix_auth_security_events_account_key", table_name="auth_security_events")
	op.drop_index("ix_auth_security_events_client_ip", table_name="auth_security_events")
	op.drop_index("ix_auth_security_events_event_type", table_name="auth_security_events")
	op.drop_index("ix_auth_security_events_created_at", table_name="auth_security_events")
	op.drop_table("auth_security_events")
