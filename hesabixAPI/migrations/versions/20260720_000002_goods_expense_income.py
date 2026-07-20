"""کالای هزینه‌شده / کالای درآمدشده: جداول سند + تنظیمات کسب‌وکار

Revision ID: 20260720_000002_goods_expense_income
Revises: 20260720_000001_business_print_settings_stamp_signature_scale
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260720_000002_goods_expense_income"
down_revision = "20260720_000001_business_print_settings_stamp_signature_scale"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.create_table(
		"goods_expense_income_documents",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("fiscal_year_id", sa.Integer(), nullable=False),
		sa.Column("code", sa.String(length=64), nullable=False),
		sa.Column("document_date", sa.Date(), nullable=False),
		sa.Column("doc_kind", sa.String(length=32), nullable=False),
		sa.Column("status", sa.String(length=32), nullable=False, server_default="draft_ops"),
		sa.Column("effect_account_id", sa.Integer(), nullable=True),
		sa.Column("person_id", sa.Integer(), nullable=True),
		sa.Column("currency_id", sa.Integer(), nullable=False),
		sa.Column("description", sa.Text(), nullable=True),
		sa.Column("warehouse_document_id", sa.Integer(), nullable=True),
		sa.Column("accounting_document_id", sa.Integer(), nullable=True),
		sa.Column("total_amount", sa.Numeric(18, 2), nullable=False, server_default="0"),
		sa.Column("created_by_user_id", sa.Integer(), nullable=True),
		sa.Column("submitted_by_user_id", sa.Integer(), nullable=True),
		sa.Column("allocated_by_user_id", sa.Integer(), nullable=True),
		sa.Column("posted_by_user_id", sa.Integer(), nullable=True),
		sa.Column("cancelled_by_user_id", sa.Integer(), nullable=True),
		sa.Column("submitted_at", sa.DateTime(), nullable=True),
		sa.Column("allocated_at", sa.DateTime(), nullable=True),
		sa.Column("posted_at", sa.DateTime(), nullable=True),
		sa.Column("cancelled_at", sa.DateTime(), nullable=True),
		sa.Column("extra_info", sa.JSON(), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["accounting_document_id"], ["documents.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["currency_id"], ["currencies.id"], ondelete="RESTRICT"),
		sa.ForeignKeyConstraint(["effect_account_id"], ["accounts.id"], ondelete="RESTRICT"),
		sa.ForeignKeyConstraint(["fiscal_year_id"], ["fiscal_years.id"], ondelete="RESTRICT"),
		sa.ForeignKeyConstraint(["person_id"], ["persons.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["warehouse_document_id"], ["warehouse_documents.id"], ondelete="SET NULL"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("business_id", "code", name="uq_gei_docs_business_code"),
	)
	op.create_index("ix_gei_docs_business_id", "goods_expense_income_documents", ["business_id"])
	op.create_index("ix_gei_docs_fiscal_year_id", "goods_expense_income_documents", ["fiscal_year_id"])
	op.create_index("ix_gei_docs_document_date", "goods_expense_income_documents", ["document_date"])
	op.create_index("ix_gei_docs_doc_kind", "goods_expense_income_documents", ["doc_kind"])
	op.create_index("ix_gei_docs_status", "goods_expense_income_documents", ["status"])
	op.create_index("ix_gei_docs_effect_account_id", "goods_expense_income_documents", ["effect_account_id"])
	op.create_index("ix_gei_docs_person_id", "goods_expense_income_documents", ["person_id"])
	op.create_index("ix_gei_docs_warehouse_document_id", "goods_expense_income_documents", ["warehouse_document_id"])
	op.create_index("ix_gei_docs_accounting_document_id", "goods_expense_income_documents", ["accounting_document_id"])

	op.create_table(
		"goods_expense_income_lines",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("document_id", sa.Integer(), nullable=False),
		sa.Column("line_no", sa.Integer(), nullable=False, server_default="1"),
		sa.Column("product_id", sa.Integer(), nullable=False),
		sa.Column("warehouse_id", sa.Integer(), nullable=False),
		sa.Column("quantity", sa.Numeric(18, 6), nullable=False),
		sa.Column("unit_cost", sa.Numeric(18, 6), nullable=False, server_default="0"),
		sa.Column("amount", sa.Numeric(18, 2), nullable=False, server_default="0"),
		sa.Column("description", sa.Text(), nullable=True),
		sa.Column("extra_info", sa.JSON(), nullable=True),
		sa.ForeignKeyConstraint(["document_id"], ["goods_expense_income_documents.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["product_id"], ["products.id"], ondelete="RESTRICT"),
		sa.ForeignKeyConstraint(["warehouse_id"], ["warehouses.id"], ondelete="RESTRICT"),
		sa.PrimaryKeyConstraint("id"),
	)
	op.create_index("ix_gei_lines_document_id", "goods_expense_income_lines", ["document_id"])
	op.create_index("ix_gei_lines_product_id", "goods_expense_income_lines", ["product_id"])
	op.create_index("ix_gei_lines_warehouse_id", "goods_expense_income_lines", ["warehouse_id"])

	op.add_column(
		"businesses",
		sa.Column(
			"goods_expense_income_workflow_mode",
			sa.String(length=20),
			nullable=False,
			server_default="simple",
			comment="simple | two_step",
		),
	)
	op.add_column(
		"businesses",
		sa.Column(
			"goods_expense_income_auto_post_in_simple_mode",
			sa.Boolean(),
			nullable=False,
			server_default=sa.text("true"),
			comment="در حالت simple، ثبت مستقیم قطعی در صورت داشتن مجوز post",
		),
	)
	op.add_column(
		"businesses",
		sa.Column(
			"goods_expense_income_default_expense_account_code",
			sa.String(length=50),
			nullable=False,
			server_default="70407",
		),
	)
	op.add_column(
		"businesses",
		sa.Column(
			"goods_expense_income_default_income_account_code",
			sa.String(length=50),
			nullable=False,
			server_default="60103",
		),
	)
	op.add_column(
		"businesses",
		sa.Column(
			"goods_expense_income_stock_count_mode",
			sa.String(length=32),
			nullable=False,
			server_default="goods_docs",
			comment="goods_docs | physical_adjustment | ask",
		),
	)
	op.add_column(
		"businesses",
		sa.Column(
			"goods_expense_income_allow_manual_unit_cost",
			sa.Boolean(),
			nullable=False,
			server_default=sa.text("false"),
		),
	)
	op.add_column(
		"businesses",
		sa.Column(
			"goods_expense_income_require_person",
			sa.Boolean(),
			nullable=False,
			server_default=sa.text("false"),
		),
	)


def downgrade() -> None:
	op.drop_column("businesses", "goods_expense_income_require_person")
	op.drop_column("businesses", "goods_expense_income_allow_manual_unit_cost")
	op.drop_column("businesses", "goods_expense_income_stock_count_mode")
	op.drop_column("businesses", "goods_expense_income_default_income_account_code")
	op.drop_column("businesses", "goods_expense_income_default_expense_account_code")
	op.drop_column("businesses", "goods_expense_income_auto_post_in_simple_mode")
	op.drop_column("businesses", "goods_expense_income_workflow_mode")
	op.drop_table("goods_expense_income_lines")
	op.drop_table("goods_expense_income_documents")
