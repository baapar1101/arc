"""Product variant core tables (additive, default-off).

Revision ID: 20261101_000002_product_variants_core
Revises: 20261101_000001_digipay_credit_plugin
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20261101_000002_product_variants_core"
down_revision = "20261101_000001_digipay_credit_plugin"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "products",
        sa.Column(
            "variant_mode",
            sa.String(length=16),
            nullable=False,
            server_default="none",
            comment="none=بدون تفکیک موجودی، inventory=تفکیک با ویژگی انباری",
        ),
    )
    op.create_check_constraint(
        "ck_products_variant_mode",
        "products",
        "variant_mode IN ('none', 'inventory')",
    )

    op.create_table(
        "product_attribute_options",
        sa.Column("id", sa.BigInteger(), autoincrement=True, nullable=False),
        sa.Column("business_id", sa.Integer(), nullable=False),
        sa.Column("attribute_id", sa.Integer(), nullable=False),
        sa.Column("code", sa.String(length=64), nullable=False),
        sa.Column("label", sa.String(length=255), nullable=False),
        sa.Column("normalized_label", sa.String(length=255), nullable=False),
        sa.Column("sort_order", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["attribute_id"], ["product_attributes.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("attribute_id", "code", name="uq_product_attribute_options_attr_code"),
        sa.UniqueConstraint(
            "attribute_id",
            "normalized_label",
            name="uq_product_attribute_options_attr_normalized",
        ),
        sa.UniqueConstraint(
            "id",
            "business_id",
            "attribute_id",
            name="uq_product_attribute_options_id_business_attr",
        ),
    )
    op.create_index(
        "ix_product_attribute_options_business_id",
        "product_attribute_options",
        ["business_id"],
    )
    op.create_index(
        "ix_product_attribute_options_attribute_id",
        "product_attribute_options",
        ["attribute_id"],
    )

    op.create_table(
        "product_variant_dimensions",
        sa.Column("id", sa.BigInteger(), autoincrement=True, nullable=False),
        sa.Column("business_id", sa.Integer(), nullable=False),
        sa.Column("product_id", sa.Integer(), nullable=False),
        sa.Column("attribute_id", sa.Integer(), nullable=False),
        sa.Column("is_required", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("sort_order", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["product_id"], ["products.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["attribute_id"], ["product_attributes.id"], ondelete="RESTRICT"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "product_id",
            "attribute_id",
            name="uq_product_variant_dimensions_product_attr",
        ),
    )
    op.create_index(
        "ix_product_variant_dimensions_business_product",
        "product_variant_dimensions",
        ["business_id", "product_id"],
    )

    op.create_table(
        "product_variants",
        sa.Column("id", sa.BigInteger(), autoincrement=True, nullable=False),
        sa.Column("business_id", sa.Integer(), nullable=False),
        sa.Column("product_id", sa.Integer(), nullable=False),
        sa.Column("code", sa.String(length=64), nullable=True),
        sa.Column("display_title", sa.String(length=255), nullable=True),
        sa.Column("barcode", sa.String(length=128), nullable=True),
        sa.Column("combination_key", sa.String(length=512), nullable=False),
        sa.Column("row_version", sa.BigInteger(), nullable=False, server_default="1"),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["product_id"], ["products.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "product_id",
            "combination_key",
            name="uq_product_variants_product_combination",
        ),
        sa.UniqueConstraint(
            "id",
            "business_id",
            "product_id",
            name="uq_product_variants_id_business_product",
        ),
    )
    op.create_index(
        "ix_product_variants_business_product_active",
        "product_variants",
        ["business_id", "product_id", "is_active"],
    )
    op.create_index(
        "uq_product_variants_business_code",
        "product_variants",
        ["business_id", "code"],
        unique=True,
        postgresql_where=sa.text("code IS NOT NULL"),
        sqlite_where=sa.text("code IS NOT NULL"),
    )
    op.create_index(
        "uq_product_variants_business_barcode",
        "product_variants",
        ["business_id", "barcode"],
        unique=True,
        postgresql_where=sa.text("barcode IS NOT NULL"),
        sqlite_where=sa.text("barcode IS NOT NULL"),
    )

    op.create_table(
        "product_variant_values",
        sa.Column("variant_id", sa.BigInteger(), nullable=False),
        sa.Column("attribute_id", sa.Integer(), nullable=False),
        sa.Column("business_id", sa.Integer(), nullable=False),
        sa.Column("option_id", sa.BigInteger(), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["variant_id"], ["product_variants.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["attribute_id"], ["product_attributes.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["option_id"], ["product_attribute_options.id"], ondelete="RESTRICT"),
        sa.PrimaryKeyConstraint("variant_id", "attribute_id"),
        sa.UniqueConstraint(
            "variant_id",
            "option_id",
            name="uq_product_variant_values_variant_option",
        ),
    )
    op.create_index(
        "ix_product_variant_values_business_id",
        "product_variant_values",
        ["business_id"],
    )
    op.create_index(
        "ix_product_variant_values_option_id",
        "product_variant_values",
        ["option_id"],
    )

    op.create_table(
        "invoice_item_line_variant_allocations",
        sa.Column("id", sa.BigInteger(), autoincrement=True, nullable=False),
        sa.Column("business_id", sa.Integer(), nullable=False),
        sa.Column("invoice_item_line_id", sa.Integer(), nullable=False),
        sa.Column("product_id", sa.Integer(), nullable=False),
        sa.Column("variant_id", sa.BigInteger(), nullable=False),
        sa.Column("quantity", sa.Numeric(18, 6), nullable=False),
        sa.Column("unit_price", sa.Numeric(18, 2), nullable=True),
        sa.Column("attributes_snapshot", sa.JSON(), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.CheckConstraint("quantity > 0", name="ck_invoice_line_variant_alloc_qty_positive"),
        sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["invoice_item_line_id"], ["invoice_item_lines.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["product_id"], ["products.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["variant_id"], ["product_variants.id"], ondelete="RESTRICT"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "invoice_item_line_id",
            "variant_id",
            name="uq_invoice_line_variant_alloc_line_variant",
        ),
    )
    op.create_index(
        "ix_invoice_line_variant_alloc_business_variant",
        "invoice_item_line_variant_allocations",
        ["business_id", "variant_id"],
    )

    op.create_table(
        "warehouse_line_variant_allocations",
        sa.Column("id", sa.BigInteger(), autoincrement=True, nullable=False),
        sa.Column("business_id", sa.Integer(), nullable=False),
        sa.Column("warehouse_document_line_id", sa.Integer(), nullable=False),
        sa.Column("product_id", sa.Integer(), nullable=False),
        sa.Column("variant_id", sa.BigInteger(), nullable=False),
        sa.Column("source_document_allocation_id", sa.BigInteger(), nullable=True),
        sa.Column("quantity", sa.Numeric(18, 6), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.CheckConstraint("quantity > 0", name="ck_warehouse_line_variant_alloc_qty_positive"),
        sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(
            ["warehouse_document_line_id"],
            ["warehouse_document_lines.id"],
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(["product_id"], ["products.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["variant_id"], ["product_variants.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(
            ["source_document_allocation_id"],
            ["invoice_item_line_variant_allocations.id"],
            ondelete="SET NULL",
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "warehouse_document_line_id",
            "variant_id",
            name="uq_warehouse_line_variant_alloc_line_variant",
        ),
    )
    op.create_index(
        "ix_warehouse_line_variant_alloc_business_variant",
        "warehouse_line_variant_allocations",
        ["business_id", "variant_id"],
    )
    op.create_index(
        "ix_warehouse_line_variant_alloc_business_line",
        "warehouse_line_variant_allocations",
        ["business_id", "warehouse_document_line_id"],
    )

    op.create_table(
        "inventory_variant_balances",
        sa.Column("business_id", sa.Integer(), nullable=False),
        sa.Column("warehouse_id", sa.Integer(), nullable=False),
        sa.Column("product_id", sa.Integer(), nullable=False),
        sa.Column("variant_id", sa.BigInteger(), nullable=False),
        sa.Column("quantity", sa.Numeric(18, 6), nullable=False, server_default="0"),
        sa.Column("version", sa.BigInteger(), nullable=False, server_default="0"),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["warehouse_id"], ["warehouses.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["product_id"], ["products.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["variant_id"], ["product_variants.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint(
            "business_id",
            "warehouse_id",
            "product_id",
            "variant_id",
        ),
    )


def downgrade() -> None:
    op.drop_table("inventory_variant_balances")
    op.drop_table("warehouse_line_variant_allocations")
    op.drop_table("invoice_item_line_variant_allocations")
    op.drop_table("product_variant_values")
    op.drop_index("uq_product_variants_business_barcode", table_name="product_variants")
    op.drop_index("uq_product_variants_business_code", table_name="product_variants")
    op.drop_index("ix_product_variants_business_product_active", table_name="product_variants")
    op.drop_table("product_variants")
    op.drop_index(
        "ix_product_variant_dimensions_business_product",
        table_name="product_variant_dimensions",
    )
    op.drop_table("product_variant_dimensions")
    op.drop_index("ix_product_attribute_options_attribute_id", table_name="product_attribute_options")
    op.drop_index("ix_product_attribute_options_business_id", table_name="product_attribute_options")
    op.drop_table("product_attribute_options")
    op.drop_constraint("ck_products_variant_mode", "products", type_="check")
    op.drop_column("products", "variant_mode")
