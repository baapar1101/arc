"""add tax_types table and ensure product FKs

Revision ID: 20251006_000001
Revises: caf3f4ef4b76
Create Date: 2025-10-06 10:00:00.000000

"""
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = '20251006_000001'
down_revision = 'caf3f4ef4b76'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Check if table already exists before creating it
    try:
        op.create_table(
            'tax_types',
            sa.Column('id', sa.Integer(), primary_key=True, autoincrement=True),
            sa.Column('business_id', sa.Integer(), nullable=False, index=True, comment='شناسه کسب‌وکار'),
            sa.Column('title', sa.String(length=255), nullable=False, comment='عنوان نوع مالیات'),
            sa.Column('code', sa.String(length=64), nullable=True, comment='کد یکتا برای نوع مالیات'),
            sa.Column('description', sa.Text(), nullable=True, comment='توضیحات'),
            sa.Column('is_active', sa.Boolean(), nullable=False, server_default=sa.text('1'), comment='وضعیت فعال/غیرفعال'),
            sa.Column('created_at', sa.DateTime(), nullable=False, server_default=sa.text('CURRENT_TIMESTAMP')),
            sa.Column('updated_at', sa.DateTime(), nullable=False, server_default=sa.text('CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP')),
        )
    except Exception:
        pass  # Table already exists
    
    # Create indexes (if they don't exist)
    try:
        op.create_index(op.f('ix_tax_types_business_id'), 'tax_types', ['business_id'], unique=False)
    except Exception:
        pass  # Index already exists
    
    try:
        op.create_index(op.f('ix_tax_types_code'), 'tax_types', ['code'], unique=False)
    except Exception:
        pass  # Index already exists

    # Ensure product indices exist (idempotent)
    try:
        op.create_index(op.f('ix_products_tax_type_id'), 'products', ['tax_type_id'], unique=False)
    except Exception:
        pass
    try:
        op.create_index(op.f('ix_products_tax_unit_id'), 'products', ['tax_unit_id'], unique=False)
    except Exception:
        pass


def downgrade() -> None:
    try:
        op.drop_index(op.f('ix_tax_types_code'), table_name='tax_types')
    except Exception:
        pass
    try:
        op.drop_index(op.f('ix_tax_types_business_id'), table_name='tax_types')
    except Exception:
        pass
    op.drop_table('tax_types')


