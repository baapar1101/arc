"""بارکدهای عمومی کالا و جدول ایندکس یکتایی

Revision ID: 20260609_000001_product_general_barcodes
Revises: 20260608_000001_user_ui_preferences
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260609_000001_product_general_barcodes"
down_revision = "20260608_000001_user_ui_preferences"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.add_column(
		"products",
		sa.Column(
			"general_barcodes",
			sa.Text(),
			nullable=True,
			comment="بارکدهای عمومی جدا شده با ویرگول (نمایش و جستجوی جزئی)",
		),
	)
	op.create_table(
		"product_general_barcode_aliases",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("product_id", sa.Integer(), nullable=False),
		sa.Column("token_normalized", sa.String(length=128), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["product_id"], ["products.id"], ondelete="CASCADE"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint(
			"business_id",
			"token_normalized",
			name="uq_product_general_barcode_business_token",
		),
	)
	op.create_index(
		"ix_pgba_business_token",
		"product_general_barcode_aliases",
		["business_id", "token_normalized"],
		unique=False,
	)
	op.create_index(
		op.f("ix_product_general_barcode_aliases_product_id"),
		"product_general_barcode_aliases",
		["product_id"],
		unique=False,
	)


def downgrade() -> None:
	op.drop_index(op.f("ix_product_general_barcode_aliases_product_id"), table_name="product_general_barcode_aliases")
	op.drop_index("ix_pgba_business_token", table_name="product_general_barcode_aliases")
	op.drop_table("product_general_barcode_aliases")
	op.drop_column("products", "general_barcodes")
