"""add product instances and unique inventory

Revision ID: 20250206_000001_add_product_instances_and_unique_inventory
Revises: 20251124_150001_add_product_tax_codes
Create Date: 2025-02-06 00:00:01.000000

"""

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


# revision identifiers, used by Alembic.
revision = "20250206_000001_add_product_instances_and_unique_inventory"
down_revision = "20251124_150001_add_product_tax_codes"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # افزودن فیلدهای جدید به جدول products
    op.add_column(
        "products",
        sa.Column("inventory_mode", sa.String(length=16), nullable=True, server_default="bulk", comment="حالت موجودی: bulk (فله‌ای) یا unique (یونیک)"),
    )
    op.add_column(
        "products",
        sa.Column("track_serial", sa.Boolean(), nullable=False, server_default="false", comment="ردیابی سریال نامبر برای کالاهای یونیک"),
    )
    op.add_column(
        "products",
        sa.Column("track_barcode", sa.Boolean(), nullable=False, server_default="false", comment="ردیابی بارکد برای کالاهای یونیک"),
    )
    
    # ایجاد جدول product_instances
    op.create_table(
        "product_instances",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("business_id", sa.Integer(), nullable=False),
        sa.Column("product_id", sa.Integer(), nullable=False),
        sa.Column("serial_number", sa.String(length=128), nullable=False, comment="شماره سریال یکتا"),
        sa.Column("barcode", sa.String(length=128), nullable=True, comment="بارکد یکتا (اختیاری)"),
        sa.Column("warehouse_id", sa.Integer(), nullable=True),
        sa.Column("status", sa.String(length=16), nullable=False, server_default="available", comment="وضعیت: available, sold, warranty, defective"),
        sa.Column("custom_attributes", postgresql.JSON(astext_type=sa.Text()), nullable=True, comment="ویژگی‌های کالا مانند رنگ، سایز، مدل و ..."),
        sa.Column("entry_date", sa.Date(), nullable=False, server_default=sa.text("CURRENT_DATE"), comment="تاریخ ورود به انبار"),
        sa.Column("last_movement_date", sa.Date(), nullable=True, comment="تاریخ آخرین جابجایی"),
        sa.Column("current_invoice_id", sa.Integer(), nullable=True, comment="فاکتور فروش (اگر فروخته شده)"),
        sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.text("CURRENT_TIMESTAMP")),
        sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=sa.text("CURRENT_TIMESTAMP")),
        sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["product_id"], ["products.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["warehouse_id"], ["warehouses.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["current_invoice_id"], ["documents.id"], ondelete="SET NULL"),
        sa.UniqueConstraint("business_id", "serial_number", name="uq_product_instances_business_serial"),
        sa.UniqueConstraint("business_id", "barcode", name="uq_product_instances_business_barcode"),
    )
    
    # ایجاد ایندکس‌ها
    op.create_index("idx_product_instances_product", "product_instances", ["product_id"])
    op.create_index("idx_product_instances_warehouse", "product_instances", ["warehouse_id"])
    op.create_index("idx_product_instances_status", "product_instances", ["status"])
    op.create_index("idx_product_instances_business", "product_instances", ["business_id"])
    
    # افزودن فیلد instance_ids به warehouse_document_lines
    op.add_column(
        "warehouse_document_lines",
        sa.Column("instance_ids", postgresql.JSON(astext_type=sa.Text()), nullable=True, comment="لیست ID کالاهای یونیک (برای inventory_mode=unique)"),
    )


def downgrade() -> None:
    # حذف فیلد instance_ids از warehouse_document_lines
    op.drop_column("warehouse_document_lines", "instance_ids")
    
    # حذف جدول product_instances
    op.drop_table("product_instances")
    
    # حذف فیلدهای جدید از products
    op.drop_column("products", "track_barcode")
    op.drop_column("products", "track_serial")
    op.drop_column("products", "inventory_mode")

