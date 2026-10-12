"""Quick-sales stock shortage override and discrepancy cases.

Revision ID: 20261012_000001_quick_sales_stock_shortage
Revises: 20261003_000001_product_bundles
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20261012_000001_quick_sales_stock_shortage"
down_revision = "20261003_000001_product_bundles"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "quick_sales_settings",
        sa.Column(
            "enable_stock_shortage_override",
            sa.Boolean(),
            nullable=False,
            server_default=sa.text("false"),
        ),
    )
    op.create_table(
        "inventory_discrepancy_cases",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("business_id", sa.Integer(), nullable=False),
        sa.Column("invoice_document_id", sa.Integer(), nullable=False),
        sa.Column("warehouse_document_id", sa.Integer(), nullable=True),
        sa.Column("resolution_document_id", sa.Integer(), nullable=True),
        sa.Column("status", sa.String(length=24), nullable=False),
        sa.Column("source_type", sa.String(length=32), nullable=False),
        sa.Column("request_token", sa.String(length=80), nullable=False),
        sa.Column("reason_code", sa.String(length=48), nullable=False),
        sa.Column("reason_note", sa.Text(), nullable=True),
        sa.Column("created_by_user_id", sa.Integer(), nullable=False),
        sa.Column("resolved_by_user_id", sa.Integer(), nullable=True),
        sa.Column("resolution_type", sa.String(length=48), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.Column("resolved_at", sa.DateTime(), nullable=True),
        sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["invoice_document_id"], ["documents.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["warehouse_document_id"], ["warehouse_documents.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["resolution_document_id"], ["goods_expense_income_documents.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("business_id", "request_token", name="uq_inventory_discrepancy_request"),
    )
    for column in ("business_id", "invoice_document_id", "warehouse_document_id", "resolution_document_id", "status"):
        op.create_index(f"ix_inventory_discrepancy_cases_{column}", "inventory_discrepancy_cases", [column])
    op.create_table(
        "inventory_discrepancy_lines",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("case_id", sa.Integer(), nullable=False),
        sa.Column("product_id", sa.Integer(), nullable=False),
        sa.Column("warehouse_id", sa.Integer(), nullable=False),
        sa.Column("invoice_item_line_id", sa.Integer(), nullable=True),
        sa.Column("available_quantity", sa.Numeric(18, 6), nullable=False),
        sa.Column("requested_quantity", sa.Numeric(18, 6), nullable=False),
        sa.Column("shortage_quantity", sa.Numeric(18, 6), nullable=False),
        sa.Column("resolved_quantity", sa.Numeric(18, 6), nullable=False),
        sa.Column("resolution_unit_cost", sa.Numeric(18, 6), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["case_id"], ["inventory_discrepancy_cases.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["product_id"], ["products.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["warehouse_id"], ["warehouses.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["invoice_item_line_id"], ["invoice_item_lines.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
    )
    for column in ("case_id", "product_id", "warehouse_id"):
        op.create_index(f"ix_inventory_discrepancy_lines_{column}", "inventory_discrepancy_lines", [column])


def downgrade() -> None:
    for column in ("warehouse_id", "product_id", "case_id"):
        op.drop_index(f"ix_inventory_discrepancy_lines_{column}", table_name="inventory_discrepancy_lines")
    op.drop_table("inventory_discrepancy_lines")
    for column in ("status", "resolution_document_id", "warehouse_document_id", "invoice_document_id", "business_id"):
        op.drop_index(f"ix_inventory_discrepancy_cases_{column}", table_name="inventory_discrepancy_cases")
    op.drop_table("inventory_discrepancy_cases")
    op.drop_column("quick_sales_settings", "enable_stock_shortage_override")
