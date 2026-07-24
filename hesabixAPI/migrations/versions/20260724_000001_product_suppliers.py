"""تأمین‌کنندگان کالا

Revision ID: 20260724_000001_product_suppliers
Revises: 20260721_000001_support_billing
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260724_000001_product_suppliers"
down_revision = "20260721_000001_support_billing"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.create_table(
		"product_suppliers",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("product_id", sa.Integer(), nullable=False),
		sa.Column("person_id", sa.Integer(), nullable=True),
		sa.Column("name", sa.String(length=255), nullable=False),
		sa.Column("website", sa.String(length=512), nullable=True),
		sa.Column("phone", sa.String(length=64), nullable=True),
		sa.Column("email", sa.String(length=255), nullable=True),
		sa.Column("notes", sa.Text(), nullable=True),
		sa.Column("is_preferred", sa.Boolean(), nullable=False, server_default=sa.text("false")),
		sa.Column("sort_order", sa.Integer(), nullable=False, server_default="0"),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["product_id"], ["products.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["person_id"], ["persons.id"], ondelete="SET NULL"),
		sa.PrimaryKeyConstraint("id"),
	)
	op.create_index("ix_product_suppliers_business_id", "product_suppliers", ["business_id"])
	op.create_index("ix_product_suppliers_product_id", "product_suppliers", ["product_id"])
	op.create_index("ix_product_suppliers_person_id", "product_suppliers", ["person_id"])

	op.create_table(
		"product_supplier_social_contacts",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("supplier_id", sa.Integer(), nullable=False),
		sa.Column("platform_key", sa.String(length=64), nullable=False),
		sa.Column("custom_label", sa.String(length=128), nullable=True),
		sa.Column("value", sa.Text(), nullable=False),
		sa.Column("sort_order", sa.Integer(), nullable=False, server_default="0"),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["supplier_id"], ["product_suppliers.id"], ondelete="CASCADE"),
		sa.PrimaryKeyConstraint("id"),
	)
	op.create_index(
		"ix_product_supplier_social_contacts_supplier_id",
		"product_supplier_social_contacts",
		["supplier_id"],
	)


def downgrade() -> None:
	op.drop_index("ix_product_supplier_social_contacts_supplier_id", table_name="product_supplier_social_contacts")
	op.drop_table("product_supplier_social_contacts")
	op.drop_index("ix_product_suppliers_person_id", table_name="product_suppliers")
	op.drop_index("ix_product_suppliers_product_id", table_name="product_suppliers")
	op.drop_index("ix_product_suppliers_business_id", table_name="product_suppliers")
	op.drop_table("product_suppliers")
