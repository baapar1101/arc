"""add marketplace tables

Revision ID: 20251110_101500
Revises: 20251108_232101_add_wallet_tables
Create Date: 2025-11-10 10:15:00.000000
"""
from __future__ import annotations

from typing import Sequence, Union
from datetime import datetime, timedelta

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = "20251110_101500"
down_revision: Union[str, None] = "20251108_232101_add_wallet_tables"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _table_exists(conn, name: str) -> bool:
	inspector = sa.inspect(conn)
	return name in inspector.get_table_names()


def upgrade() -> None:
	conn = op.get_bind()

	# marketplace_plugins
	if not _table_exists(conn, "marketplace_plugins"):
		op.create_table(
			"marketplace_plugins",
			sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
			sa.Column("code", sa.String(length=100), nullable=False),
			sa.Column("name", sa.String(length=200), nullable=False),
			sa.Column("description", sa.Text(), nullable=True),
			sa.Column("category", sa.String(length=100), nullable=True),
			sa.Column("icon_url", sa.String(length=500), nullable=True),
			sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("1")),
			sa.Column("created_at", sa.DateTime(), nullable=False, default=datetime.utcnow),
			sa.Column("updated_at", sa.DateTime(), nullable=False, default=datetime.utcnow),
			sa.UniqueConstraint("code", name="uq_marketplace_plugins_code"),
		)

	# marketplace_plugin_plans
	if not _table_exists(conn, "marketplace_plugin_plans"):
		op.create_table(
			"marketplace_plugin_plans",
			sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
			sa.Column("plugin_id", sa.Integer(), sa.ForeignKey("marketplace_plugins.id", ondelete="CASCADE"), nullable=False),
			sa.Column("period", sa.String(length=20), nullable=False),
			sa.Column("price", sa.Numeric(18, 2), nullable=False, server_default=sa.text("0")),
			sa.Column("currency_id", sa.Integer(), sa.ForeignKey("currencies.id", ondelete="RESTRICT"), nullable=False),
			sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("1")),
			sa.Column("created_at", sa.DateTime(), nullable=False, default=datetime.utcnow),
			sa.Column("updated_at", sa.DateTime(), nullable=False, default=datetime.utcnow),
		)
		op.create_index("ix_mkp_plans_plugin_id", "marketplace_plugin_plans", ["plugin_id"])

	# marketplace_invoices (create first to avoid foreign key dependency issue)
	if not _table_exists(conn, "marketplace_invoices"):
		op.create_table(
			"marketplace_invoices",
			sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
			sa.Column("order_id", sa.Integer(), nullable=False),  # FK added later
			sa.Column("business_id", sa.Integer(), sa.ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False),
			sa.Column("code", sa.String(length=50), nullable=False),
			sa.Column("total", sa.Numeric(18, 2), nullable=False, server_default=sa.text("0")),
			sa.Column("currency_id", sa.Integer(), sa.ForeignKey("currencies.id", ondelete="RESTRICT"), nullable=False),
			sa.Column("status", sa.String(length=20), nullable=False, server_default=sa.text("'issued'")),
			sa.Column("issued_at", sa.DateTime(), nullable=False, default=datetime.utcnow),
			sa.Column("paid_at", sa.DateTime(), nullable=True),
			sa.Column("extra_info", sa.Text(), nullable=True),
			sa.Column("created_at", sa.DateTime(), nullable=False, default=datetime.utcnow),
			sa.Column("updated_at", sa.DateTime(), nullable=False, default=datetime.utcnow),
		)
		op.create_index("ix_mkp_invoices_business_id", "marketplace_invoices", ["business_id"])

	# marketplace_orders
	if not _table_exists(conn, "marketplace_orders"):
		op.create_table(
			"marketplace_orders",
			sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
			sa.Column("business_id", sa.Integer(), sa.ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False),
			sa.Column("plugin_id", sa.Integer(), sa.ForeignKey("marketplace_plugins.id", ondelete="RESTRICT"), nullable=False),
			sa.Column("plan_id", sa.Integer(), sa.ForeignKey("marketplace_plugin_plans.id", ondelete="RESTRICT"), nullable=False),
			sa.Column("quantity", sa.Integer(), nullable=False, server_default=sa.text("1")),
			sa.Column("unit_price", sa.Numeric(18, 2), nullable=False, server_default=sa.text("0")),
			sa.Column("total_price", sa.Numeric(18, 2), nullable=False, server_default=sa.text("0")),
			sa.Column("currency_id", sa.Integer(), sa.ForeignKey("currencies.id", ondelete="RESTRICT"), nullable=False),
			sa.Column("status", sa.String(length=20), nullable=False, server_default=sa.text("'pending'")),
			sa.Column("wallet_transaction_id", sa.Integer(), sa.ForeignKey("wallet_transactions.id", ondelete="SET NULL"), nullable=True),
			sa.Column("invoice_id", sa.Integer(), sa.ForeignKey("marketplace_invoices.id", ondelete="SET NULL"), nullable=True),
			sa.Column("external_ref", sa.String(length=100), nullable=True),
			sa.Column("extra_info", sa.Text(), nullable=True),
			sa.Column("created_at", sa.DateTime(), nullable=False, default=datetime.utcnow),
			sa.Column("updated_at", sa.DateTime(), nullable=False, default=datetime.utcnow),
		)
		op.create_index("ix_mkp_orders_business_id", "marketplace_orders", ["business_id"])
		op.create_index("ix_mkp_orders_plugin_id", "marketplace_orders", ["plugin_id"])
		op.create_index("ix_mkp_orders_plan_id", "marketplace_orders", ["plan_id"])

	# Add foreign key from marketplace_invoices to marketplace_orders
	if _table_exists(conn, "marketplace_invoices") and _table_exists(conn, "marketplace_orders"):
		# Check if FK already exists
		inspector = sa.inspect(conn)
		fks = [fk['name'] for fk in inspector.get_foreign_keys("marketplace_invoices")]
		if not any("order_id" in fk for fk in inspector.get_foreign_keys("marketplace_invoices")):
			op.create_foreign_key(
				"fk_marketplace_invoices_order_id",
				"marketplace_invoices",
				"marketplace_orders",
				["order_id"],
				["id"],
				ondelete="CASCADE"
			)
		op.create_index("ix_mkp_invoices_order_id", "marketplace_invoices", ["order_id"])

	# business_plugins
	if not _table_exists(conn, "business_plugins"):
		op.create_table(
			"business_plugins",
			sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
			sa.Column("business_id", sa.Integer(), sa.ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False),
			sa.Column("plugin_id", sa.Integer(), sa.ForeignKey("marketplace_plugins.id", ondelete="RESTRICT"), nullable=False),
			sa.Column("plan_id", sa.Integer(), sa.ForeignKey("marketplace_plugin_plans.id", ondelete="RESTRICT"), nullable=False),
			sa.Column("status", sa.String(length=20), nullable=False, server_default=sa.text("'active'")),
			sa.Column("starts_at", sa.DateTime(), nullable=False, default=datetime.utcnow),
			sa.Column("ends_at", sa.DateTime(), nullable=True),
			sa.Column("auto_renew", sa.Boolean(), nullable=False, server_default=sa.text("0")),
			sa.Column("extra_info", sa.Text(), nullable=True),
			sa.Column("created_at", sa.DateTime(), nullable=False, default=datetime.utcnow),
			sa.Column("updated_at", sa.DateTime(), nullable=False, default=datetime.utcnow),
			sa.UniqueConstraint("business_id", "plugin_id", name="uq_business_plugin_unique"),
		)
		op.create_index("ix_business_plugins_business_id", "business_plugins", ["business_id"])
		op.create_index("ix_business_plugins_plugin_id", "business_plugins", ["plugin_id"])
		op.create_index("ix_business_plugins_plan_id", "business_plugins", ["plan_id"])


def downgrade() -> None:
	# Drop in reverse dependency order
	for name in (
		"business_plugins",
		"marketplace_invoices",
		"marketplace_orders",
		"marketplace_plugin_plans",
		"marketplace_plugins",
	):
		try:
			op.drop_table(name)
		except Exception:
			pass


