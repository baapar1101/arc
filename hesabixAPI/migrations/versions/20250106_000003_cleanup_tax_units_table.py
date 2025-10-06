"""cleanup tax_units table: drop business_id, tax_rate, is_active

Revision ID: 20250106_000003
Revises: 7891282548e9
Create Date: 2025-10-06 12:55:00.000000

"""
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = '20250106_000003'
down_revision = '7891282548e9'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Drop columns if exist (idempotent behavior)
    try:
        op.drop_index('ix_tax_units_business_id', table_name='tax_units')
    except Exception:
        pass

    for col in ('business_id', 'tax_rate', 'is_active'):
        try:
            op.drop_column('tax_units', col)
        except Exception:
            pass


def downgrade() -> None:
    # Recreate columns (best-effort)
    try:
        op.add_column('tax_units', sa.Column('business_id', sa.Integer(), nullable=False, comment='شناسه کسب‌وکار'))
        op.create_index('ix_tax_units_business_id', 'tax_units', ['business_id'])
    except Exception:
        pass

    try:
        op.add_column('tax_units', sa.Column('tax_rate', sa.Numeric(5, 2), nullable=True, comment='نرخ مالیات (درصد)'))
    except Exception:
        pass

    try:
        op.add_column('tax_units', sa.Column('is_active', sa.Boolean(), nullable=False, server_default=sa.text('1'), comment='وضعیت فعال/غیرفعال'))
    except Exception:
        pass


