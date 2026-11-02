"""Public pay-page receipt tokens and abuse reports.

Revision ID: 20261102_000002_pay_page_receipts_abuse
Revises: 20261102_000001_oa_letter_templates_formats
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20261102_000002_pay_page_receipts_abuse"
down_revision = "20261102_000001_oa_letter_templates_formats"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.create_table(
		"public_pay_page_receipts",
		sa.Column("token", sa.String(length=48), primary_key=True),
		sa.Column(
			"wallet_transaction_id",
			sa.Integer(),
			sa.ForeignKey("wallet_transactions.id", ondelete="CASCADE"),
			nullable=False,
		),
		sa.Column("username", sa.String(length=30), nullable=False),
		sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
	)
	op.create_unique_constraint(
		"uq_public_pay_page_receipts_tx",
		"public_pay_page_receipts",
		["wallet_transaction_id"],
	)
	op.create_index("ix_public_pay_page_receipts_username", "public_pay_page_receipts", ["username"])

	op.create_table(
		"public_pay_page_abuse_reports",
		sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
		sa.Column(
			"business_id",
			sa.Integer(),
			sa.ForeignKey("businesses.id", ondelete="SET NULL"),
			nullable=True,
		),
		sa.Column("username", sa.String(length=30), nullable=False),
		sa.Column("reason", sa.String(length=40), nullable=False),
		sa.Column("details", sa.Text(), nullable=False),
		sa.Column("reporter_name", sa.String(length=80), nullable=True),
		sa.Column("reporter_mobile", sa.String(length=20), nullable=True),
		sa.Column("page_url", sa.String(length=500), nullable=True),
		sa.Column("ip_address", sa.String(length=64), nullable=True),
		sa.Column("user_agent", sa.String(length=400), nullable=True),
		sa.Column("status", sa.String(length=20), nullable=False, server_default="new"),
		sa.Column("admin_note", sa.Text(), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
		sa.Column("reviewed_at", sa.DateTime(), nullable=True),
		sa.Column(
			"reviewed_by",
			sa.Integer(),
			sa.ForeignKey("users.id", ondelete="SET NULL"),
			nullable=True,
		),
	)
	op.create_index("ix_pay_page_abuse_created_at", "public_pay_page_abuse_reports", ["created_at"])
	op.create_index("ix_pay_page_abuse_status", "public_pay_page_abuse_reports", ["status"])
	op.create_index("ix_pay_page_abuse_business", "public_pay_page_abuse_reports", ["business_id"])


def downgrade() -> None:
	op.drop_index("ix_pay_page_abuse_business", table_name="public_pay_page_abuse_reports")
	op.drop_index("ix_pay_page_abuse_status", table_name="public_pay_page_abuse_reports")
	op.drop_index("ix_pay_page_abuse_created_at", table_name="public_pay_page_abuse_reports")
	op.drop_table("public_pay_page_abuse_reports")
	op.drop_index("ix_public_pay_page_receipts_username", table_name="public_pay_page_receipts")
	op.drop_constraint("uq_public_pay_page_receipts_tx", "public_pay_page_receipts", type_="unique")
	op.drop_table("public_pay_page_receipts")
