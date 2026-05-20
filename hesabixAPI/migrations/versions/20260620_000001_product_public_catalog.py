"""شبکه انتشار کالا: فیلدهای انتشار عمومی، تماس کاتالوگ، پیام تماس عمومی

Revision ID: 20260620_000001_product_public_catalog
Revises: 20260617_000003_merge_heads_invoice_share_and_frequent_descriptions_scope
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260620_000001_product_public_catalog"
down_revision = "20260617_000003_merge_heads_invoice_share_and_frequent_descriptions_scope"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.add_column(
		"products",
		sa.Column(
			"is_public_catalog",
			sa.Boolean(),
			nullable=False,
			server_default=sa.text("0"),
			comment="انتشار در API عمومی کاتالوگ",
		),
	)
	op.add_column(
		"products",
		sa.Column(
			"catalog_public_uuid",
			sa.String(length=36),
			nullable=True,
			comment="شناسه عمومی پایدار برای لینک/جستجوی کاتالوگ",
		),
	)
	op.create_index(
		"ix_products_catalog_public_uuid",
		"products",
		["catalog_public_uuid"],
		unique=True,
	)
	op.create_index(
		"ix_products_public_catalog_list",
		"products",
		["is_public_catalog", "is_active", "business_id"],
		unique=False,
	)

	op.add_column(
		"businesses",
		sa.Column(
			"public_catalog_show_contact",
			sa.Boolean(),
			nullable=False,
			server_default=sa.text("0"),
			comment="نمایش تلفن/موبایل در API عمومی کاتالوگ",
		),
	)

	op.create_table(
		"public_catalog_contact_messages",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("product_catalog_uuid", sa.String(length=36), nullable=True),
		sa.Column("sender_name", sa.String(length=200), nullable=False),
		sa.Column("sender_contact", sa.String(length=200), nullable=False),
		sa.Column("message", sa.Text(), nullable=False),
		sa.Column("client_ip", sa.String(length=64), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.text("CURRENT_TIMESTAMP")),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.PrimaryKeyConstraint("id"),
	)
	op.create_index(
		"ix_public_catalog_contact_messages_business_id",
		"public_catalog_contact_messages",
		["business_id"],
		unique=False,
	)
	op.create_index(
		"ix_public_catalog_contact_messages_created_at",
		"public_catalog_contact_messages",
		["created_at"],
		unique=False,
	)


def downgrade() -> None:
	op.drop_index("ix_public_catalog_contact_messages_created_at", table_name="public_catalog_contact_messages")
	op.drop_index("ix_public_catalog_contact_messages_business_id", table_name="public_catalog_contact_messages")
	op.drop_table("public_catalog_contact_messages")

	op.drop_column("businesses", "public_catalog_show_contact")

	op.drop_index("ix_products_public_catalog_list", table_name="products")
	op.drop_index("ix_products_catalog_public_uuid", table_name="products")
	op.drop_column("products", "catalog_public_uuid")
	op.drop_column("products", "is_public_catalog")
