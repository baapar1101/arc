from __future__ import annotations

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '20250929_000501_add_products_and_pricing'
down_revision = '20250929_000401_drop_is_active_from_product_attributes'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Create products table (with existence check)
    connection = op.get_bind()
    
    # Check if products table exists
    result = connection.execute(sa.text("""
        SELECT COUNT(*) 
        FROM information_schema.tables 
        WHERE table_schema = DATABASE() 
        AND table_name = 'products'
    """)).fetchone()
    
    if result[0] == 0:
        op.create_table(
            'products',
            sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
            sa.Column('business_id', sa.Integer(), nullable=False),
            sa.Column('item_type', sa.Enum('کالا', 'خدمت', name='product_item_type_enum'), nullable=False),
            sa.Column('code', sa.String(length=64), nullable=False),
            sa.Column('name', sa.String(length=255), nullable=False),
            sa.Column('description', sa.Text(), nullable=True),
            sa.Column('category_id', sa.Integer(), nullable=True),
            sa.Column('main_unit_id', sa.Integer(), nullable=True),
            sa.Column('secondary_unit_id', sa.Integer(), nullable=True),
            sa.Column('unit_conversion_factor', sa.Numeric(18, 6), nullable=True),
            sa.Column('base_sales_price', sa.Numeric(18, 2), nullable=True),
            sa.Column('base_sales_note', sa.Text(), nullable=True),
            sa.Column('base_purchase_price', sa.Numeric(18, 2), nullable=True),
            sa.Column('base_purchase_note', sa.Text(), nullable=True),
            sa.Column('track_inventory', sa.Boolean(), nullable=False, server_default=sa.text('0')),
            sa.Column('reorder_point', sa.Integer(), nullable=True),
            sa.Column('min_order_qty', sa.Integer(), nullable=True),
            sa.Column('lead_time_days', sa.Integer(), nullable=True),
            sa.Column('is_sales_taxable', sa.Boolean(), nullable=False, server_default=sa.text('0')),
            sa.Column('is_purchase_taxable', sa.Boolean(), nullable=False, server_default=sa.text('0')),
            sa.Column('sales_tax_rate', sa.Numeric(5, 2), nullable=True),
            sa.Column('purchase_tax_rate', sa.Numeric(5, 2), nullable=True),
            sa.Column('tax_type_id', sa.Integer(), nullable=True),
            sa.Column('tax_code', sa.String(length=100), nullable=True),
            sa.Column('tax_unit_id', sa.Integer(), nullable=True),
            sa.Column('created_at', sa.DateTime(), nullable=False),
            sa.Column('updated_at', sa.DateTime(), nullable=False),
            sa.PrimaryKeyConstraint('id'),
            mysql_charset='utf8mb4'
        )
    
    # Create constraints and indexes (with existence checks)
    try:
        op.create_unique_constraint('uq_products_business_code', 'products', ['business_id', 'code'])
    except Exception:
        pass  # Constraint already exists
    
    try:
        op.create_index('ix_products_business_id', 'products', ['business_id'])
    except Exception:
        pass  # Index already exists
    
    try:
        op.create_index('ix_products_name', 'products', ['name'])
    except Exception:
        pass  # Index already exists
    
    try:
        op.create_foreign_key(None, 'products', 'businesses', ['business_id'], ['id'], ondelete='CASCADE')
    except Exception:
        pass  # Foreign key already exists
    
    try:
        op.create_foreign_key(None, 'products', 'categories', ['category_id'], ['id'], ondelete='SET NULL')
    except Exception:
        pass  # Foreign key already exists

    # Create price_lists table (with existence check)
    result = connection.execute(sa.text("""
        SELECT COUNT(*) 
        FROM information_schema.tables 
        WHERE table_schema = DATABASE() 
        AND table_name = 'price_lists'
    """)).fetchone()
    
    if result[0] == 0:
        op.create_table(
            'price_lists',
            sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
            sa.Column('business_id', sa.Integer(), nullable=False),
            sa.Column('name', sa.String(length=255), nullable=False),
            sa.Column('currency_id', sa.Integer(), nullable=True),
            sa.Column('default_unit_id', sa.Integer(), nullable=True),
            sa.Column('is_active', sa.Boolean(), nullable=False, server_default=sa.text('1')),
            sa.Column('created_at', sa.DateTime(), nullable=False),
            sa.Column('updated_at', sa.DateTime(), nullable=False),
            sa.PrimaryKeyConstraint('id'),
            mysql_charset='utf8mb4'
        )
    
    try:
        op.create_unique_constraint('uq_price_lists_business_name', 'price_lists', ['business_id', 'name'])
    except Exception:
        pass  # Constraint already exists
    
    try:
        op.create_index('ix_price_lists_business_id', 'price_lists', ['business_id'])
    except Exception:
        pass  # Index already exists
    
    try:
        op.create_foreign_key(None, 'price_lists', 'businesses', ['business_id'], ['id'], ondelete='CASCADE')
    except Exception:
        pass  # Foreign key already exists
    
    try:
        op.create_foreign_key(None, 'price_lists', 'currencies', ['currency_id'], ['id'], ondelete='RESTRICT')
    except Exception:
        pass  # Foreign key already exists

    # Create price_items table (with existence check)
    result = connection.execute(sa.text("""
        SELECT COUNT(*) 
        FROM information_schema.tables 
        WHERE table_schema = DATABASE() 
        AND table_name = 'price_items'
    """)).fetchone()
    
    if result[0] == 0:
        op.create_table(
            'price_items',
            sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
            sa.Column('price_list_id', sa.Integer(), nullable=False),
            sa.Column('product_id', sa.Integer(), nullable=False),
            sa.Column('unit_id', sa.Integer(), nullable=True),
            sa.Column('currency_id', sa.Integer(), nullable=True),
            sa.Column('tier_name', sa.String(length=64), nullable=False),
            sa.Column('min_qty', sa.Numeric(18, 3), nullable=False, server_default=sa.text('0')),
            sa.Column('price', sa.Numeric(18, 2), nullable=False),
            sa.Column('created_at', sa.DateTime(), nullable=False),
            sa.Column('updated_at', sa.DateTime(), nullable=False),
            sa.PrimaryKeyConstraint('id'),
            mysql_charset='utf8mb4'
        )
    
    try:
        op.create_unique_constraint('uq_price_items_unique_tier', 'price_items', ['price_list_id', 'product_id', 'unit_id', 'tier_name', 'min_qty'])
    except Exception:
        pass  # Constraint already exists
    
    try:
        op.create_index('ix_price_items_price_list_id', 'price_items', ['price_list_id'])
    except Exception:
        pass  # Index already exists
    
    try:
        op.create_index('ix_price_items_product_id', 'price_items', ['product_id'])
    except Exception:
        pass  # Index already exists
    
    try:
        op.create_foreign_key(None, 'price_items', 'price_lists', ['price_list_id'], ['id'], ondelete='CASCADE')
    except Exception:
        pass  # Foreign key already exists
    
    try:
        op.create_foreign_key(None, 'price_items', 'products', ['product_id'], ['id'], ondelete='CASCADE')
    except Exception:
        pass  # Foreign key already exists
    
    try:
        op.create_foreign_key(None, 'price_items', 'currencies', ['currency_id'], ['id'], ondelete='RESTRICT')
    except Exception:
        pass  # Foreign key already exists

    # Create product_attribute_links table (with existence check)
    result = connection.execute(sa.text("""
        SELECT COUNT(*) 
        FROM information_schema.tables 
        WHERE table_schema = DATABASE() 
        AND table_name = 'product_attribute_links'
    """)).fetchone()
    
    if result[0] == 0:
        op.create_table(
            'product_attribute_links',
            sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
            sa.Column('product_id', sa.Integer(), nullable=False),
            sa.Column('attribute_id', sa.Integer(), nullable=False),
            sa.Column('created_at', sa.DateTime(), nullable=False),
            sa.Column('updated_at', sa.DateTime(), nullable=False),
            sa.PrimaryKeyConstraint('id'),
            mysql_charset='utf8mb4'
        )
    
    try:
        op.create_unique_constraint('uq_product_attribute_links_unique', 'product_attribute_links', ['product_id', 'attribute_id'])
    except Exception:
        pass  # Constraint already exists
    
    try:
        op.create_index('ix_product_attribute_links_product_id', 'product_attribute_links', ['product_id'])
    except Exception:
        pass  # Index already exists
    
    try:
        op.create_index('ix_product_attribute_links_attribute_id', 'product_attribute_links', ['attribute_id'])
    except Exception:
        pass  # Index already exists
    
    try:
        op.create_foreign_key(None, 'product_attribute_links', 'products', ['product_id'], ['id'], ondelete='CASCADE')
    except Exception:
        pass  # Foreign key already exists
    
    try:
        op.create_foreign_key(None, 'product_attribute_links', 'product_attributes', ['attribute_id'], ['id'], ondelete='CASCADE')
    except Exception:
        pass  # Foreign key already exists


def downgrade() -> None:
    # Drop links and pricing first due to FKs
    op.drop_constraint('uq_product_attribute_links_unique', 'product_attribute_links', type_='unique')
    op.drop_table('product_attribute_links')

    op.drop_constraint('uq_price_items_unique_tier', 'price_items', type_='unique')
    op.drop_table('price_items')

    op.drop_constraint('uq_price_lists_business_name', 'price_lists', type_='unique')
    op.drop_table('price_lists')

    op.drop_constraint('uq_products_business_code', 'products', type_='unique')
    op.drop_table('products')


