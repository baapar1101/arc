"""Commercial lot / expiry tracking (opt-in per product).

Revision ID: 20261102_000004_inventory_lots_expiry
Revises: 20261102_000003_oa_commercial_upgrade
"""
from __future__ import annotations

import json

import sqlalchemy as sa
from alembic import op

from adapters.db.seed_data.notification_event_types_seed import (
    INVENTORY_EXPIRY_EVENT_CODES,
    NOTIFICATION_EVENT_TYPES_ROWS,
)

revision = "20261102_000004_inventory_lots_expiry"
down_revision = "20261102_000003_oa_commercial_upgrade"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "products",
        sa.Column("track_expiry", sa.Boolean(), nullable=False, server_default=sa.false()),
    )
    op.add_column(
        "products",
        sa.Column(
            "lot_policy",
            sa.String(length=16),
            nullable=False,
            server_default="optional",
            comment="optional=لات اختیاری، required=لات اجباری",
        ),
    )
    op.create_check_constraint(
        "ck_products_lot_policy",
        "products",
        "lot_policy IN ('optional', 'required')",
    )
    op.add_column("products", sa.Column("shelf_life_days", sa.Integer(), nullable=True))
    op.add_column("products", sa.Column("best_before_offset_days", sa.Integer(), nullable=True))
    op.add_column("products", sa.Column("removal_offset_days", sa.Integer(), nullable=True))
    op.add_column("products", sa.Column("alert_offset_days", sa.Integer(), nullable=True))
    op.add_column(
        "products",
        sa.Column(
            "expired_sale_policy",
            sa.String(length=24),
            nullable=False,
            server_default="block",
        ),
    )
    op.create_check_constraint(
        "ck_products_expired_sale_policy",
        "products",
        "expired_sale_policy IN ('block', 'manager_confirm')",
    )
    op.add_column(
        "products",
        sa.Column(
            "min_remaining_shelf_life_days",
            sa.Integer(),
            nullable=False,
            server_default="0",
        ),
    )

    op.add_column("product_instances", sa.Column("manufacturing_date", sa.Date(), nullable=True))
    op.add_column("product_instances", sa.Column("expiry_date", sa.Date(), nullable=True))

    op.add_column("distribution_van_lots", sa.Column("manufacturing_date", sa.Date(), nullable=True))
    op.add_column(
        "production_order_materials",
        sa.Column("manufacturing_date", sa.Date(), nullable=True),
    )
    op.add_column("production_order_materials", sa.Column("expiry_date", sa.Date(), nullable=True))
    op.add_column(
        "production_order_outputs",
        sa.Column("manufacturing_date", sa.Date(), nullable=True),
    )
    op.add_column("production_order_outputs", sa.Column("expiry_date", sa.Date(), nullable=True))

    op.create_table(
        "inventory_lots",
        sa.Column("id", sa.BigInteger(), autoincrement=True, nullable=False),
        sa.Column("business_id", sa.Integer(), nullable=False),
        sa.Column("product_id", sa.Integer(), nullable=False),
        sa.Column("variant_id", sa.BigInteger(), nullable=True),
        sa.Column("lot_code", sa.String(length=64), nullable=False, server_default="-"),
        sa.Column("identity_key", sa.String(length=255), nullable=False),
        sa.Column("manufacturing_date", sa.Date(), nullable=True),
        sa.Column("expiry_date", sa.Date(), nullable=True),
        sa.Column("best_before_date", sa.Date(), nullable=True),
        sa.Column("removal_date", sa.Date(), nullable=True),
        sa.Column("alert_date", sa.Date(), nullable=True),
        sa.Column("is_undated", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["product_id"], ["products.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["variant_id"], ["product_variants.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("business_id", "identity_key", name="uq_inventory_lots_business_identity"),
    )
    op.create_index("ix_inventory_lots_business_id", "inventory_lots", ["business_id"])
    op.create_index("ix_inventory_lots_product_id", "inventory_lots", ["product_id"])
    op.create_index("ix_inventory_lots_variant_id", "inventory_lots", ["variant_id"])
    op.create_index("ix_inventory_lots_business_product", "inventory_lots", ["business_id", "product_id"])
    op.create_index("ix_inventory_lots_business_expiry", "inventory_lots", ["business_id", "expiry_date"])
    op.create_index("ix_inventory_lots_business_alert", "inventory_lots", ["business_id", "alert_date"])

    op.create_table(
        "invoice_item_line_lot_allocations",
        sa.Column("id", sa.BigInteger(), autoincrement=True, nullable=False),
        sa.Column("business_id", sa.Integer(), nullable=False),
        sa.Column("invoice_item_line_id", sa.Integer(), nullable=False),
        sa.Column("product_id", sa.Integer(), nullable=False),
        sa.Column("lot_id", sa.BigInteger(), nullable=False),
        sa.Column("quantity", sa.Numeric(18, 6), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.CheckConstraint("quantity > 0", name="ck_invoice_line_lot_alloc_qty_positive"),
        sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["invoice_item_line_id"], ["invoice_item_lines.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["product_id"], ["products.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["lot_id"], ["inventory_lots.id"], ondelete="RESTRICT"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "invoice_item_line_id",
            "lot_id",
            name="uq_invoice_line_lot_alloc_line_lot",
        ),
    )
    op.create_index(
        "ix_invoice_line_lot_alloc_business_lot",
        "invoice_item_line_lot_allocations",
        ["business_id", "lot_id"],
    )
    op.create_index(
        "ix_invoice_item_line_lot_allocations_invoice_item_line_id",
        "invoice_item_line_lot_allocations",
        ["invoice_item_line_id"],
    )
    op.create_index(
        "ix_invoice_item_line_lot_allocations_product_id",
        "invoice_item_line_lot_allocations",
        ["product_id"],
    )

    op.create_table(
        "warehouse_line_lot_allocations",
        sa.Column("id", sa.BigInteger(), autoincrement=True, nullable=False),
        sa.Column("business_id", sa.Integer(), nullable=False),
        sa.Column("warehouse_document_line_id", sa.Integer(), nullable=False),
        sa.Column("product_id", sa.Integer(), nullable=False),
        sa.Column("lot_id", sa.BigInteger(), nullable=False),
        sa.Column("source_document_allocation_id", sa.BigInteger(), nullable=True),
        sa.Column("quantity", sa.Numeric(18, 6), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.CheckConstraint("quantity > 0", name="ck_warehouse_line_lot_alloc_qty_positive"),
        sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(
            ["warehouse_document_line_id"],
            ["warehouse_document_lines.id"],
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(["product_id"], ["products.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["lot_id"], ["inventory_lots.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(
            ["source_document_allocation_id"],
            ["invoice_item_line_lot_allocations.id"],
            ondelete="SET NULL",
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "warehouse_document_line_id",
            "lot_id",
            name="uq_warehouse_line_lot_alloc_line_lot",
        ),
    )
    op.create_index(
        "ix_warehouse_line_lot_alloc_business_lot",
        "warehouse_line_lot_allocations",
        ["business_id", "lot_id"],
    )
    op.create_index(
        "ix_warehouse_line_lot_alloc_business_line",
        "warehouse_line_lot_allocations",
        ["business_id", "warehouse_document_line_id"],
    )

    conn = op.get_bind()
    insp = sa.inspect(conn)
    if "notification_event_types" in insp.get_table_names():
        existing = {
            r[0]
            for r in conn.execute(sa.text("SELECT code FROM notification_event_types")).fetchall()
        }
        rows = [
            r
            for r in NOTIFICATION_EVENT_TYPES_ROWS
            if r["code"] in INVENTORY_EXPIRY_EVENT_CODES and r["code"] not in existing
        ]
        for row in rows:
            conn.execute(
                sa.text(
                    """
                    INSERT INTO notification_event_types (
                        code, name, description, category, available_variables,
                        default_sms_template, default_email_template, default_email_subject,
                        is_active, requires_approval, created_at, updated_at
                    ) VALUES (
                        :code, :name, :description, :category, CAST(:vars AS JSONB),
                        :dst, :det, :des,
                        true, true, NOW(), NOW()
                    )
                    ON CONFLICT (code) DO NOTHING
                    """
                ),
                {
                    "code": row["code"],
                    "name": row["name"],
                    "description": row.get("description"),
                    "category": row.get("category"),
                    "vars": json.dumps(row.get("available_variables") or [], ensure_ascii=False),
                    "dst": row.get("default_sms_template"),
                    "det": row.get("default_email_template"),
                    "des": row.get("default_email_subject"),
                },
            )


def downgrade() -> None:
    op.drop_table("warehouse_line_lot_allocations")
    op.drop_table("invoice_item_line_lot_allocations")
    op.drop_table("inventory_lots")
    op.drop_column("production_order_outputs", "expiry_date")
    op.drop_column("production_order_outputs", "manufacturing_date")
    op.drop_column("production_order_materials", "expiry_date")
    op.drop_column("production_order_materials", "manufacturing_date")
    op.drop_column("distribution_van_lots", "manufacturing_date")
    op.drop_column("product_instances", "expiry_date")
    op.drop_column("product_instances", "manufacturing_date")
    op.drop_constraint("ck_products_expired_sale_policy", "products", type_="check")
    op.drop_constraint("ck_products_lot_policy", "products", type_="check")
    op.drop_column("products", "min_remaining_shelf_life_days")
    op.drop_column("products", "expired_sale_policy")
    op.drop_column("products", "alert_offset_days")
    op.drop_column("products", "removal_offset_days")
    op.drop_column("products", "best_before_offset_days")
    op.drop_column("products", "shelf_life_days")
    op.drop_column("products", "lot_policy")
    op.drop_column("products", "track_expiry")
