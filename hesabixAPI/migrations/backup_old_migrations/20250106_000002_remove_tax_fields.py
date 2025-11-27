"""remove is_active and tax_rate fields from tax_types

Revision ID: 20250106_000002
Revises: 20250106_000001
Create Date: 2025-01-06 12:30:00.000000

"""
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = '20250106_000002'
down_revision = '20250106_000001'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Remove is_active column (if it exists)
    try:
        op.drop_column('tax_types', 'is_active')
    except Exception:
        pass  # Column doesn't exist
    
    # Remove tax_rate column (if it exists)
    try:
        op.drop_column('tax_types', 'tax_rate')
    except Exception:
        pass  # Column doesn't exist


def downgrade() -> None:
    # Add tax_rate column back
    op.add_column('tax_types', sa.Column('tax_rate', sa.Numeric(5, 2), nullable=True, comment='نرخ مالیات (درصد)'))
    
    # Add is_active column back
    op.add_column('tax_types', sa.Column('is_active', sa.Boolean(), nullable=False, server_default=sa.text('1'), comment='وضعیت فعال/غیرفعال'))
