"""افزونه پرداخت اعتباری دیجی‌پی: جداول تنظیمات، خرید و تسویه + seed بازار.

Revision ID: 20261101_000001_digipay_credit_plugin
Revises: 20261030_000002_telephony_operator_privacy
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql
from sqlalchemy.orm import sessionmaker

revision = "20261101_000001_digipay_credit_plugin"
down_revision = "20261030_000002_telephony_operator_privacy"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.create_table(
		"digipay_settings",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("environment", sa.String(length=16), nullable=False, server_default="sandbox"),
		sa.Column("username_encrypted", sa.Text(), nullable=True),
		sa.Column("password_encrypted", sa.Text(), nullable=True),
		sa.Column("client_id_encrypted", sa.Text(), nullable=True),
		sa.Column("client_secret_encrypted", sa.Text(), nullable=True),
		sa.Column("person_id", sa.Integer(), nullable=True),
		sa.Column("settlement_bank_account_id", sa.Integer(), nullable=True),
		sa.Column("commission_percent", sa.Numeric(7, 3), nullable=False, server_default="0"),
		sa.Column("vat_on_commission_percent", sa.Numeric(7, 3), nullable=False, server_default="10"),
		sa.Column("seller_id", sa.String(length=120), nullable=True),
		sa.Column("auto_deliver_in_store", sa.Boolean(), nullable=False, server_default=sa.text("true")),
		sa.Column("extra_settings", postgresql.JSONB(astext_type=sa.Text()), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["person_id"], ["persons.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["settlement_bank_account_id"], ["bank_accounts.id"], ondelete="SET NULL"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("business_id", name="uq_digipay_settings_business"),
	)
	op.create_index("ix_digipay_settings_business_id", "digipay_settings", ["business_id"])

	op.create_table(
		"digipay_settlements",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("document_id", sa.Integer(), nullable=True),
		sa.Column("bank_account_id", sa.Integer(), nullable=False),
		sa.Column("settlement_date", sa.Date(), nullable=False),
		sa.Column("gross_amount", sa.Numeric(18, 2), nullable=False),
		sa.Column("commission_amount", sa.Numeric(18, 2), nullable=False, server_default="0"),
		sa.Column("vat_amount", sa.Numeric(18, 2), nullable=False, server_default="0"),
		sa.Column("net_amount", sa.Numeric(18, 2), nullable=False),
		sa.Column("notes", sa.Text(), nullable=True),
		sa.Column("created_by_user_id", sa.Integer(), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["document_id"], ["documents.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["bank_account_id"], ["bank_accounts.id"], ondelete="RESTRICT"),
		sa.ForeignKeyConstraint(["created_by_user_id"], ["users.id"], ondelete="SET NULL"),
		sa.PrimaryKeyConstraint("id"),
	)
	op.create_index("ix_digipay_settlements_business_id", "digipay_settlements", ["business_id"])

	op.create_table(
		"digipay_purchases",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("provider_id", sa.String(length=80), nullable=False),
		sa.Column("ticket", sa.String(length=255), nullable=True),
		sa.Column("redirect_url", sa.Text(), nullable=True),
		sa.Column("amount", sa.Numeric(18, 2), nullable=False),
		sa.Column("cash_amount", sa.Numeric(18, 2), nullable=False, server_default="0"),
		sa.Column("credit_amount", sa.Numeric(18, 2), nullable=False, server_default="0"),
		sa.Column("cell_number", sa.String(length=20), nullable=True),
		sa.Column("tracking_code", sa.String(length=80), nullable=True),
		sa.Column("ticket_type", sa.Integer(), nullable=True),
		sa.Column("payment_gateway", sa.Integer(), nullable=True),
		sa.Column("status", sa.String(length=24), nullable=False, server_default="pending"),
		sa.Column("source", sa.String(length=32), nullable=False, server_default="quick_sales"),
		sa.Column("invoice_id", sa.Integer(), nullable=True),
		sa.Column("receipt_document_id", sa.Integer(), nullable=True),
		sa.Column("settlement_id", sa.Integer(), nullable=True),
		sa.Column("basket_json", postgresql.JSONB(astext_type=sa.Text()), nullable=True),
		sa.Column("extra_info", postgresql.JSONB(astext_type=sa.Text()), nullable=True),
		sa.Column("verified_at", sa.DateTime(), nullable=True),
		sa.Column("delivered_at", sa.DateTime(), nullable=True),
		sa.Column("created_by_user_id", sa.Integer(), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["invoice_id"], ["documents.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["receipt_document_id"], ["documents.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["settlement_id"], ["digipay_settlements.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["created_by_user_id"], ["users.id"], ondelete="SET NULL"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("business_id", "provider_id", name="uq_digipay_purchases_provider"),
	)
	op.create_index("ix_digipay_purchases_business_id", "digipay_purchases", ["business_id"])
	op.create_index("ix_digipay_purchases_provider_id", "digipay_purchases", ["provider_id"])
	op.create_index("ix_digipay_purchases_tracking_code", "digipay_purchases", ["tracking_code"])
	op.create_index("ix_digipay_purchases_status", "digipay_purchases", ["status"])
	op.create_index("ix_digipay_purchases_invoice_id", "digipay_purchases", ["invoice_id"])
	op.create_index("ix_digipay_purchases_settlement_id", "digipay_purchases", ["settlement_id"])

	conn = op.get_bind()
	insp = sa.inspect(conn)
	if "marketplace_plugins" in insp.get_table_names():
		Session = sessionmaker(bind=conn)
		db = Session()
		try:
			from adapters.db.seed_data.marketplace_plugins_seed import ensure_default_marketplace_plugins

			result = ensure_default_marketplace_plugins(db)
			if result.get("ok"):
				db.commit()
			else:
				db.rollback()
		except Exception:
			db.rollback()
			raise
		finally:
			db.close()


def downgrade() -> None:
	op.drop_index("ix_digipay_purchases_settlement_id", table_name="digipay_purchases")
	op.drop_index("ix_digipay_purchases_invoice_id", table_name="digipay_purchases")
	op.drop_index("ix_digipay_purchases_status", table_name="digipay_purchases")
	op.drop_index("ix_digipay_purchases_tracking_code", table_name="digipay_purchases")
	op.drop_index("ix_digipay_purchases_provider_id", table_name="digipay_purchases")
	op.drop_index("ix_digipay_purchases_business_id", table_name="digipay_purchases")
	op.drop_table("digipay_purchases")
	op.drop_index("ix_digipay_settlements_business_id", table_name="digipay_settlements")
	op.drop_table("digipay_settlements")
	op.drop_index("ix_digipay_settings_business_id", table_name="digipay_settings")
	op.drop_table("digipay_settings")
