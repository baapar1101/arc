"""جداول products و جداول مرتبط"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import mysql


def upgrade():
    # جدول product_attributes
    op.create_table(
        'product_attributes',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('business_id', sa.Integer(), nullable=False),
        sa.Column('title', sa.String(length=255), nullable=False),
        sa.Column('description', sa.Text(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['business_id'], ['businesses.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('business_id', 'title', name='uq_product_attributes_business_title')
    )
    op.create_index(op.f('ix_product_attributes_business_id'), 'product_attributes', ['business_id'], unique=False)
    op.create_index(op.f('ix_product_attributes_title'), 'product_attributes', ['title'], unique=False)

    # جدول warehouses (قبل از products چون products به آن وابسته است)
    op.create_table(
        'warehouses',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('business_id', sa.Integer(), nullable=False),
        sa.Column('code', sa.String(length=64), nullable=False),
        sa.Column('name', sa.String(length=255), nullable=False),
        sa.Column('description', sa.Text(), nullable=True),
        sa.Column('warehouse_keeper', sa.String(length=255), nullable=True),
        sa.Column('phone', sa.String(length=32), nullable=True),
        sa.Column('address', sa.Text(), nullable=True),
        sa.Column('postal_code', sa.String(length=16), nullable=True),
        sa.Column('is_default', sa.Boolean(), nullable=False, server_default='0'),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['business_id'], ['businesses.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('business_id', 'code', name='uq_warehouses_business_code')
    )
    op.create_index(op.f('ix_warehouses_business_id'), 'warehouses', ['business_id'], unique=False)
    op.create_index(op.f('ix_warehouses_code'), 'warehouses', ['code'], unique=False)
    op.create_index(op.f('ix_warehouses_name'), 'warehouses', ['name'], unique=False)
    op.create_index(op.f('ix_warehouses_is_default'), 'warehouses', ['is_default'], unique=False)

    # جدول products
    op.create_table(
        'products',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('business_id', sa.Integer(), nullable=False),
        sa.Column('item_type', mysql.ENUM('کالا', 'خدمت', name='product_item_type_enum'), nullable=False, server_default='کالا'),
        sa.Column('code', sa.String(length=64), nullable=False),
        sa.Column('name', sa.String(length=255), nullable=False),
        sa.Column('description', sa.Text(), nullable=True),
        sa.Column('category_id', sa.Integer(), nullable=True),
        sa.Column('main_unit', sa.String(length=32), nullable=True),
        sa.Column('secondary_unit', sa.String(length=32), nullable=True),
        sa.Column('unit_conversion_factor', sa.Numeric(precision=18, scale=6), nullable=True),
        sa.Column('base_sales_price', sa.Numeric(precision=18, scale=2), nullable=True),
        sa.Column('base_sales_note', sa.Text(), nullable=True),
        sa.Column('base_purchase_price', sa.Numeric(precision=18, scale=2), nullable=True),
        sa.Column('base_purchase_note', sa.Text(), nullable=True),
        sa.Column('track_inventory', sa.Boolean(), nullable=False, server_default='0'),
        sa.Column('reorder_point', sa.Integer(), nullable=True),
        sa.Column('min_order_qty', sa.Integer(), nullable=True),
        sa.Column('lead_time_days', sa.Integer(), nullable=True),
        sa.Column('inventory_mode', sa.String(length=16), nullable=True, server_default='bulk'),
        sa.Column('track_serial', sa.Boolean(), nullable=False, server_default='0'),
        sa.Column('track_barcode', sa.Boolean(), nullable=False, server_default='0'),
        sa.Column('is_sales_taxable', sa.Boolean(), nullable=False, server_default='0'),
        sa.Column('is_purchase_taxable', sa.Boolean(), nullable=False, server_default='0'),
        sa.Column('sales_tax_rate', sa.Numeric(precision=5, scale=2), nullable=True),
        sa.Column('purchase_tax_rate', sa.Numeric(precision=5, scale=2), nullable=True),
        sa.Column('tax_type_id', sa.Integer(), nullable=True),
        sa.Column('tax_code', sa.String(length=100), nullable=True),
        sa.Column('tax_unit_id', sa.Integer(), nullable=True),
        sa.Column('image_file_id', sa.String(length=36), nullable=True),
        sa.Column('default_warehouse_id', sa.Integer(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['business_id'], ['businesses.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['category_id'], ['categories.id'], ondelete='SET NULL'),
        sa.ForeignKeyConstraint(['image_file_id'], ['file_storage.id'], ondelete='SET NULL'),
        sa.ForeignKeyConstraint(['default_warehouse_id'], ['warehouses.id'], ondelete='SET NULL'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('business_id', 'code', name='uq_products_business_code')
    )
    op.create_index(op.f('ix_products_business_id'), 'products', ['business_id'], unique=False)
    op.create_index(op.f('ix_products_name'), 'products', ['name'], unique=False)
    op.create_index(op.f('ix_products_category_id'), 'products', ['category_id'], unique=False)
    op.create_index(op.f('ix_products_main_unit'), 'products', ['main_unit'], unique=False)
    op.create_index(op.f('ix_products_secondary_unit'), 'products', ['secondary_unit'], unique=False)
    op.create_index(op.f('ix_products_tax_type_id'), 'products', ['tax_type_id'], unique=False)
    op.create_index(op.f('ix_products_tax_unit_id'), 'products', ['tax_unit_id'], unique=False)
    op.create_index(op.f('ix_products_image_file_id'), 'products', ['image_file_id'], unique=False)
    op.create_index(op.f('ix_products_default_warehouse_id'), 'products', ['default_warehouse_id'], unique=False)

    # جدول product_attribute_links
    op.create_table(
        'product_attribute_links',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('product_id', sa.Integer(), nullable=False),
        sa.Column('attribute_id', sa.Integer(), nullable=False),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['product_id'], ['products.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['attribute_id'], ['product_attributes.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('product_id', 'attribute_id', name='uq_product_attribute_links_unique')
    )
    op.create_index(op.f('ix_product_attribute_links_product_id'), 'product_attribute_links', ['product_id'], unique=False)
    op.create_index(op.f('ix_product_attribute_links_attribute_id'), 'product_attribute_links', ['attribute_id'], unique=False)

    # جدول product_instances
    op.create_table(
        'product_instances',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('business_id', sa.Integer(), nullable=False),
        sa.Column('product_id', sa.Integer(), nullable=False),
        sa.Column('serial_number', sa.String(length=128), nullable=False),
        sa.Column('barcode', sa.String(length=128), nullable=True),
        sa.Column('warehouse_id', sa.Integer(), nullable=True),
        sa.Column('status', sa.String(length=16), nullable=False, server_default='available'),
        sa.Column('custom_attributes', sa.JSON(), nullable=True),
        sa.Column('entry_date', sa.Date(), nullable=False),
        sa.Column('last_movement_date', sa.Date(), nullable=True),
        sa.Column('current_invoice_id', sa.Integer(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['business_id'], ['businesses.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['product_id'], ['products.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['warehouse_id'], ['warehouses.id'], ondelete='SET NULL'),
        sa.ForeignKeyConstraint(['current_invoice_id'], ['documents.id'], ondelete='SET NULL'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('business_id', 'serial_number', name='uq_product_instances_business_serial'),
        sa.UniqueConstraint('business_id', 'barcode', name='uq_product_instances_business_barcode')
    )
    op.create_index('idx_product_instances_product', 'product_instances', ['product_id'], unique=False)
    op.create_index('idx_product_instances_warehouse', 'product_instances', ['warehouse_id'], unique=False)
    op.create_index('idx_product_instances_status', 'product_instances', ['status'], unique=False)
    op.create_index(op.f('ix_product_instances_business_id'), 'product_instances', ['business_id'], unique=False)

    # جدول price_lists
    op.create_table(
        'price_lists',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('business_id', sa.Integer(), nullable=False),
        sa.Column('name', sa.String(length=255), nullable=False),
        sa.Column('is_active', sa.Boolean(), nullable=False, server_default='1'),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['business_id'], ['businesses.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('business_id', 'name', name='uq_price_lists_business_name')
    )
    op.create_index(op.f('ix_price_lists_business_id'), 'price_lists', ['business_id'], unique=False)
    op.create_index(op.f('ix_price_lists_name'), 'price_lists', ['name'], unique=False)

    # جدول price_items
    op.create_table(
        'price_items',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('price_list_id', sa.Integer(), nullable=False),
        sa.Column('product_id', sa.Integer(), nullable=False),
        sa.Column('unit_id', sa.Integer(), nullable=True),
        sa.Column('currency_id', sa.Integer(), nullable=False),
        sa.Column('tier_name', sa.String(length=64), nullable=False),
        sa.Column('min_qty', sa.Numeric(precision=18, scale=3), nullable=False, server_default='0'),
        sa.Column('price', sa.Numeric(precision=18, scale=2), nullable=False),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['price_list_id'], ['price_lists.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['product_id'], ['products.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['currency_id'], ['currencies.id'], ondelete='RESTRICT'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('price_list_id', 'product_id', 'unit_id', 'tier_name', 'min_qty', 'currency_id', name='uq_price_items_unique_tier_currency')
    )
    op.create_index(op.f('ix_price_items_price_list_id'), 'price_items', ['price_list_id'], unique=False)
    op.create_index(op.f('ix_price_items_product_id'), 'price_items', ['product_id'], unique=False)
    op.create_index(op.f('ix_price_items_unit_id'), 'price_items', ['unit_id'], unique=False)
    op.create_index(op.f('ix_price_items_currency_id'), 'price_items', ['currency_id'], unique=False)


def downgrade():
    op.drop_index(op.f('ix_price_items_currency_id'), table_name='price_items')
    op.drop_index(op.f('ix_price_items_unit_id'), table_name='price_items')
    op.drop_index(op.f('ix_price_items_product_id'), table_name='price_items')
    op.drop_index(op.f('ix_price_items_price_list_id'), table_name='price_items')
    op.drop_table('price_items')
    
    op.drop_index(op.f('ix_price_lists_name'), table_name='price_lists')
    op.drop_index(op.f('ix_price_lists_business_id'), table_name='price_lists')
    op.drop_table('price_lists')
    
    op.drop_index(op.f('ix_product_instances_business_id'), table_name='product_instances')
    op.drop_index('idx_product_instances_status', table_name='product_instances')
    op.drop_index('idx_product_instances_warehouse', table_name='product_instances')
    op.drop_index('idx_product_instances_product', table_name='product_instances')
    op.drop_table('product_instances')
    
    op.drop_index(op.f('ix_product_attribute_links_attribute_id'), table_name='product_attribute_links')
    op.drop_index(op.f('ix_product_attribute_links_product_id'), table_name='product_attribute_links')
    op.drop_table('product_attribute_links')
    
    op.drop_index(op.f('ix_products_default_warehouse_id'), table_name='products')
    op.drop_index(op.f('ix_products_image_file_id'), table_name='products')
    op.drop_index(op.f('ix_products_tax_unit_id'), table_name='products')
    op.drop_index(op.f('ix_products_tax_type_id'), table_name='products')
    op.drop_index(op.f('ix_products_secondary_unit'), table_name='products')
    op.drop_index(op.f('ix_products_main_unit'), table_name='products')
    op.drop_index(op.f('ix_products_category_id'), table_name='products')
    op.drop_index(op.f('ix_products_name'), table_name='products')
    op.drop_index(op.f('ix_products_business_id'), table_name='products')
    op.drop_table('products')
    
    op.drop_index(op.f('ix_warehouses_is_default'), table_name='warehouses')
    op.drop_index(op.f('ix_warehouses_name'), table_name='warehouses')
    op.drop_index(op.f('ix_warehouses_code'), table_name='warehouses')
    op.drop_index(op.f('ix_warehouses_business_id'), table_name='warehouses')
    op.drop_table('warehouses')
    
    op.drop_index(op.f('ix_product_attributes_title'), table_name='product_attributes')
    op.drop_index(op.f('ix_product_attributes_business_id'), table_name='product_attributes')
    op.drop_table('product_attributes')

