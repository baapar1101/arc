"""convert_unit_fields_to_string

Revision ID: b2b68cf299a3
Revises: c302bc2f2cb8
Create Date: 2025-10-06 11:17:52.851690

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = 'b2b68cf299a3'
down_revision = 'c302bc2f2cb8'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Check if columns already exist before adding them
    try:
        op.add_column('products', sa.Column('main_unit', sa.String(length=32), nullable=True, comment='واحد اصلی شمارش'))
    except Exception:
        pass  # Column already exists
    
    try:
        op.add_column('products', sa.Column('secondary_unit', sa.String(length=32), nullable=True, comment='واحد فرعی شمارش'))
    except Exception:
        pass  # Column already exists
    
    # Create indexes for new columns (if they don't exist)
    try:
        op.create_index('ix_products_main_unit', 'products', ['main_unit'])
    except Exception:
        pass  # Index already exists
    
    try:
        op.create_index('ix_products_secondary_unit', 'products', ['secondary_unit'])
    except Exception:
        pass  # Index already exists
    
    # Drop old integer columns and their indexes (if they exist)
    try:
        op.drop_index('ix_products_main_unit_id', table_name='products')
    except Exception:
        pass  # Index doesn't exist
    
    try:
        op.drop_index('ix_products_secondary_unit_id', table_name='products')
    except Exception:
        pass  # Index doesn't exist
    
    try:
        op.drop_column('products', 'main_unit_id')
    except Exception:
        pass  # Column doesn't exist
    
    try:
        op.drop_column('products', 'secondary_unit_id')
    except Exception:
        pass  # Column doesn't exist


def downgrade() -> None:
    # Add back integer columns
    op.add_column('products', sa.Column('main_unit_id', sa.Integer(), nullable=True))
    op.add_column('products', sa.Column('secondary_unit_id', sa.Integer(), nullable=True))
    
    # Create indexes for integer columns
    op.create_index('ix_products_main_unit_id', 'products', ['main_unit_id'])
    op.create_index('ix_products_secondary_unit_id', 'products', ['secondary_unit_id'])
    
    # Drop string columns and their indexes
    op.drop_index('ix_products_main_unit', table_name='products')
    op.drop_index('ix_products_secondary_unit', table_name='products')
    op.drop_column('products', 'main_unit')
    op.drop_column('products', 'secondary_unit')
