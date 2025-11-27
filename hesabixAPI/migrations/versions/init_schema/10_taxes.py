"""جداول مالیاتی: tax_types, tax_units, tax_settings, product_tax_codes"""
from alembic import op
import sqlalchemy as sa


def upgrade():
    # جدول tax_types
    op.create_table(
        'tax_types',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('title', sa.String(length=255), nullable=False),
        sa.Column('code', sa.String(length=64), nullable=False),
        sa.Column('description', sa.Text(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_tax_types_code'), 'tax_types', ['code'], unique=True)

    # جدول tax_units
    op.create_table(
        'tax_units',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('name', sa.String(length=255), nullable=False),
        sa.Column('code', sa.String(length=64), nullable=False),
        sa.Column('description', sa.Text(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.PrimaryKeyConstraint('id')
    )

    # جدول tax_settings
    op.create_table(
        'tax_settings',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('business_id', sa.Integer(), nullable=False),
        sa.Column('created_by_user_id', sa.Integer(), nullable=True),
        sa.Column('tax_memory_id', sa.String(length=128), nullable=True),
        sa.Column('economic_code', sa.String(length=64), nullable=True),
        sa.Column('private_key', sa.Text(), nullable=True),
        sa.Column('public_key', sa.Text(), nullable=True),
        sa.Column('certificate', sa.Text(), nullable=True),
        sa.Column('certificate_request', sa.Text(), nullable=True),
        sa.Column('sandbox_mode', sa.Boolean(), nullable=False, server_default='0'),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['business_id'], ['businesses.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['created_by_user_id'], ['users.id'], ondelete='SET NULL'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('business_id', name='uq_tax_settings_business')
    )
    op.create_index(op.f('ix_tax_settings_business_id'), 'tax_settings', ['business_id'], unique=False)
    op.create_index(op.f('ix_tax_settings_created_by_user_id'), 'tax_settings', ['created_by_user_id'], unique=False)

    # جدول product_tax_codes
    op.create_table(
        'product_tax_codes',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('code', sa.String(length=32), nullable=False),
        sa.Column('description', sa.String(length=1024), nullable=False),
        sa.Column('vat_rate', sa.String(length=16), nullable=True),
        sa.Column('taxable_status', sa.String(length=64), nullable=True),
        sa.Column('run_date', sa.String(length=32), nullable=True),
        sa.Column('expiration_date', sa.String(length=32), nullable=True),
        sa.Column('create_date', sa.String(length=32), nullable=True),
        sa.Column('last_edit_date', sa.String(length=32), nullable=True),
        sa.Column('source_type', sa.String(length=128), nullable=True),
        sa.Column('pricing_description', sa.String(length=1024), nullable=True),
        sa.Column('source_filename', sa.String(length=255), nullable=True),
        sa.Column('source_checksum', sa.String(length=64), nullable=True),
        sa.Column('imported_at', sa.DateTime(), nullable=False),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_product_tax_codes_code'), 'product_tax_codes', ['code'], unique=True)


def downgrade():
    op.drop_index(op.f('ix_product_tax_codes_code'), table_name='product_tax_codes')
    op.drop_table('product_tax_codes')
    
    op.drop_index(op.f('ix_tax_settings_created_by_user_id'), table_name='tax_settings')
    op.drop_index(op.f('ix_tax_settings_business_id'), table_name='tax_settings')
    op.drop_table('tax_settings')
    
    op.drop_table('tax_units')
    
    op.drop_index(op.f('ix_tax_types_code'), table_name='tax_types')
    op.drop_table('tax_types')

