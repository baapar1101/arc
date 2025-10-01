"""create_tax_units_table

Revision ID: 9f9786ae7191
Revises: caf3f4ef4b76
Create Date: 2025-09-30 14:47:28.281817

"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy import inspect


# revision identifiers, used by Alembic.
revision = '9f9786ae7191'
down_revision = 'caf3f4ef4b76'
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()
    inspector = inspect(bind)

    created_tax_units = False
    if not inspector.has_table('tax_units'):
        op.create_table(
            'tax_units',
            sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
            sa.Column('business_id', sa.Integer(), nullable=False, comment='شناسه کسب\u200cوکار'),
            sa.Column('name', sa.String(length=255), nullable=False, comment='نام واحد مالیاتی'),
            sa.Column('code', sa.String(length=64), nullable=False, comment='کد واحد مالیاتی'),
            sa.Column('description', sa.Text(), nullable=True, comment='توضیحات'),
            sa.Column('tax_rate', sa.Numeric(precision=5, scale=2), nullable=True, comment='نرخ مالیات (درصد)'),
            sa.Column('is_active', sa.Boolean(), nullable=False, server_default=sa.text('1'), comment='وضعیت فعال/غیرفعال'),
            sa.Column('created_at', sa.DateTime(), nullable=False),
            sa.Column('updated_at', sa.DateTime(), nullable=False),
            sa.PrimaryKeyConstraint('id'),
            mysql_charset='utf8mb4'
        )
        created_tax_units = True

    if created_tax_units:
        # Create indexes
        op.create_index(op.f('ix_tax_units_business_id'), 'tax_units', ['business_id'], unique=False)

        # Add foreign key constraint to products table
        op.create_foreign_key(None, 'products', 'tax_units', ['tax_unit_id'], ['id'], ondelete='SET NULL')


def downgrade() -> None:
    # Drop foreign key constraint from products table
    op.drop_constraint(None, 'products', type_='foreignkey')
    
    # Drop indexes
    op.drop_index(op.f('ix_tax_units_business_id'), table_name='tax_units')
    
    # Drop tax_units table
    op.drop_table('tax_units')
