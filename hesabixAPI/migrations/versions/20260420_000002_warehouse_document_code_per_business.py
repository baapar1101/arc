"""یکتایی کد حواله انبار به‌صورت (business_id, code) — جلوگیری از تداخل بین کسب‌وکارها

Revision ID: 20260420_000002_warehouse_document_code_per_business
Revises: 20260420_000001_distribution_field_sales_tables
"""

from __future__ import annotations

from alembic import op

revision = "20260420_000002_warehouse_document_code_per_business"
down_revision = "20260420_000001_distribution_field_sales_tables"
branch_labels = None
depends_on = None


def upgrade() -> None:
	# حذف یکتایی فقط روی code (تداخل کد WH-... بین businessها)
	op.drop_index(op.f("ix_warehouse_documents_code"), table_name="warehouse_documents")
	op.create_unique_constraint(
		"uq_warehouse_documents_business_id_code",
		"warehouse_documents",
		["business_id", "code"],
	)


def downgrade() -> None:
	op.drop_constraint(
		"uq_warehouse_documents_business_id_code",
		"warehouse_documents",
		type_="unique",
	)
	op.create_index(
		op.f("ix_warehouse_documents_code"),
		"warehouse_documents",
		["code"],
		unique=True,
	)
