"""توکن لینک واریز اختصاصی برای ارسال به مشتری.

Revision ID: 20261107_000001_pay_page_requests
Revises: 20261105_000008_advanced_production_labor
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20261107_000001_pay_page_requests"
down_revision = "20261105_000008_advanced_production_labor"
branch_labels = None
depends_on = None


def upgrade() -> None:
	conn = op.get_bind()
	if "business_pay_page_requests" in set(sa.inspect(conn).get_table_names()):
		return
	op.create_table(
		"business_pay_page_requests",
		sa.Column("token", sa.String(length=48), primary_key=True),
		sa.Column(
			"business_id",
			sa.Integer(),
			sa.ForeignKey("businesses.id", ondelete="CASCADE"),
			nullable=False,
		),
		sa.Column(
			"pay_page_id",
			sa.Integer(),
			sa.ForeignKey("business_pay_pages.id", ondelete="CASCADE"),
			nullable=False,
		),
		sa.Column("amount", sa.Numeric(18, 2), nullable=True),
		sa.Column("amount_locked", sa.Boolean(), nullable=False, server_default="0"),
		sa.Column("payer_name", sa.String(length=30), nullable=True),
		sa.Column("payer_mobile", sa.String(length=20), nullable=True),
		sa.Column("payer_note", sa.Text(), nullable=True),
		sa.Column(
			"created_by_user_id",
			sa.Integer(),
			sa.ForeignKey("users.id", ondelete="SET NULL"),
			nullable=True,
		),
		sa.Column("status", sa.String(length=20), nullable=False, server_default="open"),
		sa.Column(
			"paid_wallet_transaction_id",
			sa.Integer(),
			sa.ForeignKey("wallet_transactions.id", ondelete="SET NULL"),
			nullable=True,
		),
		sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
		sa.Column("expires_at", sa.DateTime(), nullable=True),
	)
	op.create_index("ix_pay_page_requests_business", "business_pay_page_requests", ["business_id"])
	op.create_index("ix_pay_page_requests_page", "business_pay_page_requests", ["pay_page_id"])
	op.create_index("ix_pay_page_requests_status", "business_pay_page_requests", ["status"])


def downgrade() -> None:
	conn = op.get_bind()
	if "business_pay_page_requests" not in set(sa.inspect(conn).get_table_names()):
		return
	op.drop_index("ix_pay_page_requests_status", table_name="business_pay_page_requests")
	op.drop_index("ix_pay_page_requests_page", table_name="business_pay_page_requests")
	op.drop_index("ix_pay_page_requests_business", table_name="business_pay_page_requests")
	op.drop_table("business_pay_page_requests")
