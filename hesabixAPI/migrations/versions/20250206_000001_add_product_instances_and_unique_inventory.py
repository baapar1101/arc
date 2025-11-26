"""add product instances and unique inventory

Revision ID: 20250206_000001_add_product_instances_and_unique_inventory
Revises: 20251124_150001_add_product_tax_codes
Create Date: 2025-02-06 00:00:01.000000

Note: This migration was created on 2025-02-06 but depends on a later migration (20251124).
This is intentional as it was merged after the later migration was created.

"""

from alembic import op
import sqlalchemy as sa
from sqlalchemy import inspect


# revision identifiers, used by Alembic.
revision = "20250206_000001_add_product_instances_and_unique_inventory"
down_revision = "20251124_150001_add_product_tax_codes"
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()
    inspector = inspect(bind)
    
    # بررسی و افزودن فیلدهای جدید به جدول products
    products_columns = {c['name'] for c in inspector.get_columns('products')}
    
    if 'inventory_mode' not in products_columns:
        op.add_column(
            "products",
            sa.Column("inventory_mode", sa.String(length=16), nullable=True, server_default="bulk", comment="حالت موجودی: bulk (فله‌ای) یا unique (یونیک)"),
        )
    
    if 'track_serial' not in products_columns:
        op.add_column(
            "products",
            sa.Column("track_serial", sa.Boolean(), nullable=False, server_default="false", comment="ردیابی سریال نامبر برای کالاهای یونیک"),
        )
    
    if 'track_barcode' not in products_columns:
        op.add_column(
            "products",
            sa.Column("track_barcode", sa.Boolean(), nullable=False, server_default="false", comment="ردیابی بارکد برای کالاهای یونیک"),
        )
    
    # بررسی و ایجاد جدول product_instances
    tables = set(inspector.get_table_names())
    
    if 'product_instances' not in tables:
        op.create_table(
            "product_instances",
            sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
            sa.Column("business_id", sa.Integer(), nullable=False),
            sa.Column("product_id", sa.Integer(), nullable=False),
            sa.Column("serial_number", sa.String(length=128), nullable=False, comment="شماره سریال یکتا"),
            sa.Column("barcode", sa.String(length=128), nullable=True, comment="بارکد یکتا (اختیاری)"),
            sa.Column("warehouse_id", sa.Integer(), nullable=True),
            sa.Column("status", sa.String(length=16), nullable=False, server_default="available", comment="وضعیت: available, sold, warranty, defective"),
            sa.Column("custom_attributes", sa.JSON(), nullable=True, comment="ویژگی‌های کالا مانند رنگ، سایز، مدل و ..."),
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
    
    # بررسی و افزودن فیلد instance_ids به warehouse_document_lines
    if 'warehouse_document_lines' in tables:
        warehouse_document_lines_columns = {c['name'] for c in inspector.get_columns('warehouse_document_lines')}
        if 'instance_ids' not in warehouse_document_lines_columns:
            op.add_column(
                "warehouse_document_lines",
                sa.Column("instance_ids", sa.JSON(), nullable=True, comment="لیست ID کالاهای یونیک (برای inventory_mode=unique)"),
            )


def downgrade() -> None:
    bind = op.get_bind()
    inspector = inspect(bind)
    tables = set(inspector.get_table_names())
    
    # حذف فیلد instance_ids از warehouse_document_lines
    if 'warehouse_document_lines' in tables:
        warehouse_document_lines_columns = {c['name'] for c in inspector.get_columns('warehouse_document_lines')}
        if 'instance_ids' in warehouse_document_lines_columns:
            try:
                op.drop_column("warehouse_document_lines", "instance_ids")
            except Exception:
                pass
    
    # حذف جدول product_instances
    if 'product_instances' in tables:
        try:
            op.drop_table("product_instances")
        except Exception:
            pass
    
    # حذف فیلدهای جدید از products
    if 'products' in tables:
        products_columns = {c['name'] for c in inspector.get_columns('products')}
        if 'track_barcode' in products_columns:
            try:
                op.drop_column("products", "track_barcode")
            except Exception:
                pass
        if 'track_serial' in products_columns:
            try:
                op.drop_column("products", "track_serial")
            except Exception:
                pass
        if 'inventory_mode' in products_columns:
            try:
                op.drop_column("products", "inventory_mode")
            except Exception:
                pass

