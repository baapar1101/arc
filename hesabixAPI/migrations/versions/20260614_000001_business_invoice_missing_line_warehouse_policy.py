"""سیاست انبار برای ردیف‌های فاکتور بدون warehouse_id

Revision ID: 20260614_000001_business_invoice_missing_line_warehouse_policy
Revises: 20260613_000002_received_loan_facility_tables
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260614_000001_business_invoice_missing_line_warehouse_policy"
down_revision = "20260613_000002_received_loan_facility_tables"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.add_column(
		"businesses",
		sa.Column(
			"invoice_missing_line_warehouse_policy",
			sa.String(length=32),
			nullable=False,
			server_default="reject",
			comment="reject | use_default_warehouse",
		),
	)
	op.add_column(
		"businesses",
		sa.Column(
			"invoice_default_warehouse_id",
			sa.Integer(),
			sa.ForeignKey("warehouses.id", ondelete="SET NULL"),
			nullable=True,
			comment="انبار پیش‌فرض برای ردیف‌های انبارداری بدون انبار",
		),
	)
	op.add_column(
		"businesses",
		sa.Column(
			"invoice_default_warehouse_fill_document_header",
			sa.Boolean(),
			nullable=False,
			server_default="1",
			comment="هنگام پر کردن خودکار، انبار سطح فاکتور هم تنظیم شود",
		),
	)
	op.create_index(
		op.f("ix_businesses_invoice_default_warehouse_id"),
		"businesses",
		["invoice_default_warehouse_id"],
		unique=False,
	)


def downgrade() -> None:
	op.drop_index(op.f("ix_businesses_invoice_default_warehouse_id"), table_name="businesses")
	op.drop_column("businesses", "invoice_default_warehouse_fill_document_header")
	op.drop_column("businesses", "invoice_default_warehouse_id")
	op.drop_column("businesses", "invoice_missing_line_warehouse_policy")
