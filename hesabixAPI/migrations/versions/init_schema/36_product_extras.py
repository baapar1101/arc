"""جداول product_instances, product_attributes, product_attribute_links, price_lists, price_items"""
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
    op.create_index(op.f('ix_product_instances_business_id'), 'product_instances', ['business_id'], unique=False)
    op.create_index(op.f('ix_product_instances_product_id'), 'product_instances', ['product_id'], unique=False)
    op.create_index(op.f('ix_product_instances_warehouse_id'), 'product_instances', ['warehouse_id'], unique=False)
    op.create_index(op.f('ix_product_instances_current_invoice_id'), 'product_instances', ['current_invoice_id'], unique=False)
    op.create_index('idx_product_instances_product', 'product_instances', ['product_id'], unique=False)
    op.create_index('idx_product_instances_warehouse', 'product_instances', ['warehouse_id'], unique=False)
    op.create_index('idx_product_instances_status', 'product_instances', ['status'], unique=False)

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
    
    op.drop_index('idx_product_instances_status', table_name='product_instances')
    op.drop_index('idx_product_instances_warehouse', table_name='product_instances')
    op.drop_index('idx_product_instances_product', table_name='product_instances')
    op.drop_index(op.f('ix_product_instances_current_invoice_id'), table_name='product_instances')
    op.drop_index(op.f('ix_product_instances_warehouse_id'), table_name='product_instances')
    op.drop_index(op.f('ix_product_instances_product_id'), table_name='product_instances')
    op.drop_index(op.f('ix_product_instances_business_id'), table_name='product_instances')
    op.drop_table('product_instances')
    
    op.drop_index(op.f('ix_product_attribute_links_attribute_id'), table_name='product_attribute_links')
    op.drop_index(op.f('ix_product_attribute_links_product_id'), table_name='product_attribute_links')
    op.drop_table('product_attribute_links')
    
    op.drop_index(op.f('ix_product_attributes_title'), table_name='product_attributes')
    op.drop_index(op.f('ix_product_attributes_business_id'), table_name='product_attributes')
    op.drop_table('product_attributes')

