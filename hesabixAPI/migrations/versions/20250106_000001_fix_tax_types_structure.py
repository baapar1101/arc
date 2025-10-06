"""fix tax_types structure - remove business_id and make it global

Revision ID: 20250106_000001
Revises: 20251006_000001
Create Date: 2025-01-06 12:00:00.000000

"""
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = '20250106_000001'
down_revision = '20251006_000001'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # First, clear existing data to avoid conflicts
    op.execute("DELETE FROM tax_types")
    
    # Drop the business_id column (if it exists)
    try:
        op.drop_column('tax_types', 'business_id')
    except Exception:
        pass  # Column doesn't exist
    
    # Make code column NOT NULL and UNIQUE
    try:
        op.alter_column('tax_types', 'code', 
                       existing_type=sa.String(length=64),
                       nullable=False)
    except Exception:
        pass  # Already NOT NULL
    
    try:
        op.create_unique_constraint('uq_tax_types_code', 'tax_types', ['code'])
    except Exception:
        pass  # Constraint already exists
    
    # Add tax_rate column (if it doesn't exist)
    try:
        op.add_column('tax_types', sa.Column('tax_rate', sa.Numeric(5, 2), nullable=True, comment='نرخ مالیات (درصد)'))
    except Exception:
        pass  # Column already exists
    
    # Drop the old business_id index (if it exists)
    try:
        op.drop_index('ix_tax_types_business_id', table_name='tax_types')
    except Exception:
        pass


def downgrade() -> None:
    # Add business_id column back
    op.add_column('tax_types', sa.Column('business_id', sa.Integer(), nullable=False, comment='شناسه کسب‌وکار'))
    
    # Remove unique constraint on code
    op.drop_constraint('uq_tax_types_code', 'tax_types', type_='unique')
    
    # Make code nullable again
    op.alter_column('tax_types', 'code', nullable=True)
    
    # Remove tax_rate column
    op.drop_column('tax_types', 'tax_rate')
    
    # Recreate business_id index
    op.create_index('ix_tax_types_business_id', 'tax_types', ['business_id'], unique=False)
