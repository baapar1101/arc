"""جداول product_boms, product_bom_items, product_bom_outputs, product_bom_operations"""
from alembic import op
import sqlalchemy as sa


def upgrade():
    # جدول product_boms
    op.create_table(
        'product_boms',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('business_id', sa.Integer(), nullable=False),
        sa.Column('product_id', sa.Integer(), nullable=False),
        sa.Column('version', sa.String(length=64), nullable=False),
        sa.Column('name', sa.String(length=255), nullable=False),
        sa.Column('is_default', sa.Boolean(), nullable=False, server_default='0'),
        sa.Column('effective_from', sa.Date(), nullable=True),
        sa.Column('effective_to', sa.Date(), nullable=True),
        sa.Column('yield_percent', sa.Numeric(precision=5, scale=2), nullable=True),
        sa.Column('wastage_percent', sa.Numeric(precision=5, scale=2), nullable=True),
        sa.Column('status', sa.String(length=16), nullable=False, server_default='draft'),
        sa.Column('notes', sa.Text(), nullable=True),
        sa.Column('created_by', sa.Integer(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['business_id'], ['businesses.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['product_id'], ['products.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('business_id', 'product_id', 'version', name='uq_product_bom_version_per_product')
    )
    op.create_index(op.f('ix_product_boms_business_id'), 'product_boms', ['business_id'], unique=False)
    op.create_index(op.f('ix_product_boms_product_id'), 'product_boms', ['product_id'], unique=False)
    op.create_index(op.f('ix_product_boms_is_default'), 'product_boms', ['is_default'], unique=False)
    op.create_index(op.f('ix_product_boms_status'), 'product_boms', ['status'], unique=False)

    # جدول product_bom_items
    op.create_table(
        'product_bom_items',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('bom_id', sa.Integer(), nullable=False),
        sa.Column('line_no', sa.Integer(), nullable=False),
        sa.Column('component_product_id', sa.Integer(), nullable=False),
        sa.Column('qty_per', sa.Numeric(precision=18, scale=6), nullable=False),
        sa.Column('uom', sa.String(length=32), nullable=True),
        sa.Column('wastage_percent', sa.Numeric(precision=5, scale=2), nullable=True),
        sa.Column('is_optional', sa.Boolean(), nullable=False, server_default='0'),
        sa.Column('substitute_group', sa.String(length=64), nullable=True),
        sa.Column('suggested_warehouse_id', sa.Integer(), nullable=True),
        sa.ForeignKeyConstraint(['bom_id'], ['product_boms.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['component_product_id'], ['products.id'], ondelete='RESTRICT'),
        sa.ForeignKeyConstraint(['suggested_warehouse_id'], ['warehouses.id'], ondelete='SET NULL'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('bom_id', 'line_no', name='uq_bom_items_line')
    )
    op.create_index(op.f('ix_product_bom_items_bom_id'), 'product_bom_items', ['bom_id'], unique=False)
    op.create_index(op.f('ix_product_bom_items_component_product_id'), 'product_bom_items', ['component_product_id'], unique=False)

    # جدول product_bom_outputs
    op.create_table(
        'product_bom_outputs',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('bom_id', sa.Integer(), nullable=False),
        sa.Column('line_no', sa.Integer(), nullable=False),
        sa.Column('output_product_id', sa.Integer(), nullable=False),
        sa.Column('ratio', sa.Numeric(precision=18, scale=6), nullable=False),
        sa.Column('uom', sa.String(length=32), nullable=True),
        sa.ForeignKeyConstraint(['bom_id'], ['product_boms.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['output_product_id'], ['products.id'], ondelete='RESTRICT'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('bom_id', 'line_no', name='uq_bom_outputs_line')
    )
    op.create_index(op.f('ix_product_bom_outputs_bom_id'), 'product_bom_outputs', ['bom_id'], unique=False)
    op.create_index(op.f('ix_product_bom_outputs_output_product_id'), 'product_bom_outputs', ['output_product_id'], unique=False)

    # جدول product_bom_operations
    op.create_table(
        'product_bom_operations',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('bom_id', sa.Integer(), nullable=False),
        sa.Column('line_no', sa.Integer(), nullable=False),
        sa.Column('operation_name', sa.String(length=255), nullable=False),
        sa.Column('cost_fixed', sa.Numeric(precision=18, scale=2), nullable=True),
        sa.Column('cost_per_unit', sa.Numeric(precision=18, scale=6), nullable=True),
        sa.Column('cost_uom', sa.String(length=32), nullable=True),
        sa.Column('work_center', sa.String(length=128), nullable=True),
        sa.ForeignKeyConstraint(['bom_id'], ['product_boms.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('bom_id', 'line_no', name='uq_bom_operations_line')
    )
    op.create_index(op.f('ix_product_bom_operations_bom_id'), 'product_bom_operations', ['bom_id'], unique=False)


def downgrade():
    op.drop_index(op.f('ix_product_bom_operations_bom_id'), table_name='product_bom_operations')
    op.drop_table('product_bom_operations')
    
    op.drop_index(op.f('ix_product_bom_outputs_output_product_id'), table_name='product_bom_outputs')
    op.drop_index(op.f('ix_product_bom_outputs_bom_id'), table_name='product_bom_outputs')
    op.drop_table('product_bom_outputs')
    
    op.drop_index(op.f('ix_product_bom_items_component_product_id'), table_name='product_bom_items')
    op.drop_index(op.f('ix_product_bom_items_bom_id'), table_name='product_bom_items')
    op.drop_table('product_bom_items')
    
    op.drop_index(op.f('ix_product_boms_status'), table_name='product_boms')
    op.drop_index(op.f('ix_product_boms_is_default'), table_name='product_boms')
    op.drop_index(op.f('ix_product_boms_product_id'), table_name='product_boms')
    op.drop_index(op.f('ix_product_boms_business_id'), table_name='product_boms')
    op.drop_table('product_boms')

