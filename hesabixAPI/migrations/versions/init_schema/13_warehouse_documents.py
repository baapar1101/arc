"""جداول warehouse_documents و warehouse_document_lines"""
from alembic import op
import sqlalchemy as sa


def upgrade():
    # جدول warehouse_documents
    op.create_table(
        'warehouse_documents',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('business_id', sa.Integer(), nullable=False),
        sa.Column('fiscal_year_id', sa.Integer(), nullable=True),
        sa.Column('code', sa.String(length=64), nullable=False),
        sa.Column('document_date', sa.Date(), nullable=False),
        sa.Column('status', sa.String(length=16), nullable=False, server_default='draft'),
        sa.Column('doc_type', sa.String(length=32), nullable=False),
        sa.Column('warehouse_id_from', sa.Integer(), nullable=True),
        sa.Column('warehouse_id_to', sa.Integer(), nullable=True),
        sa.Column('source_type', sa.String(length=32), nullable=True),
        sa.Column('source_document_id', sa.Integer(), nullable=True),
        sa.Column('extra_info', sa.JSON(), nullable=True),
        sa.Column('created_by_user_id', sa.Integer(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['business_id'], ['businesses.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['fiscal_year_id'], ['fiscal_years.id'], ondelete='SET NULL'),
        sa.ForeignKeyConstraint(['warehouse_id_from'], ['warehouses.id'], ondelete='SET NULL'),
        sa.ForeignKeyConstraint(['warehouse_id_to'], ['warehouses.id'], ondelete='SET NULL'),
        sa.ForeignKeyConstraint(['source_document_id'], ['documents.id'], ondelete='SET NULL'),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_warehouse_documents_business_id'), 'warehouse_documents', ['business_id'], unique=False)
    op.create_index(op.f('ix_warehouse_documents_fiscal_year_id'), 'warehouse_documents', ['fiscal_year_id'], unique=False)
    op.create_index(op.f('ix_warehouse_documents_code'), 'warehouse_documents', ['code'], unique=True)
    op.create_index(op.f('ix_warehouse_documents_document_date'), 'warehouse_documents', ['document_date'], unique=False)
    op.create_index(op.f('ix_warehouse_documents_warehouse_id_from'), 'warehouse_documents', ['warehouse_id_from'], unique=False)
    op.create_index(op.f('ix_warehouse_documents_warehouse_id_to'), 'warehouse_documents', ['warehouse_id_to'], unique=False)
    op.create_index(op.f('ix_warehouse_documents_source_document_id'), 'warehouse_documents', ['source_document_id'], unique=False)

    # جدول warehouse_document_lines
    op.create_table(
        'warehouse_document_lines',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('warehouse_document_id', sa.Integer(), nullable=False),
        sa.Column('product_id', sa.Integer(), nullable=False),
        sa.Column('warehouse_id', sa.Integer(), nullable=True),
        sa.Column('movement', sa.String(length=8), nullable=False),
        sa.Column('quantity', sa.Numeric(precision=18, scale=6), nullable=False),
        sa.Column('extra_info', sa.JSON(), nullable=True),
        sa.Column('instance_ids', sa.JSON(), nullable=True),
        sa.ForeignKeyConstraint(['warehouse_document_id'], ['warehouse_documents.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['product_id'], ['products.id'], ondelete='RESTRICT'),
        sa.ForeignKeyConstraint(['warehouse_id'], ['warehouses.id'], ondelete='SET NULL'),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_warehouse_document_lines_warehouse_document_id'), 'warehouse_document_lines', ['warehouse_document_id'], unique=False)
    op.create_index(op.f('ix_warehouse_document_lines_product_id'), 'warehouse_document_lines', ['product_id'], unique=False)
    op.create_index(op.f('ix_warehouse_document_lines_warehouse_id'), 'warehouse_document_lines', ['warehouse_id'], unique=False)


def downgrade():
    op.drop_index(op.f('ix_warehouse_document_lines_warehouse_id'), table_name='warehouse_document_lines')
    op.drop_index(op.f('ix_warehouse_document_lines_product_id'), table_name='warehouse_document_lines')
    op.drop_index(op.f('ix_warehouse_document_lines_warehouse_document_id'), table_name='warehouse_document_lines')
    op.drop_table('warehouse_document_lines')
    
    op.drop_index(op.f('ix_warehouse_documents_source_document_id'), table_name='warehouse_documents')
    op.drop_index(op.f('ix_warehouse_documents_warehouse_id_to'), table_name='warehouse_documents')
    op.drop_index(op.f('ix_warehouse_documents_warehouse_id_from'), table_name='warehouse_documents')
    op.drop_index(op.f('ix_warehouse_documents_document_date'), table_name='warehouse_documents')
    op.drop_index(op.f('ix_warehouse_documents_code'), table_name='warehouse_documents')
    op.drop_index(op.f('ix_warehouse_documents_fiscal_year_id'), table_name='warehouse_documents')
    op.drop_index(op.f('ix_warehouse_documents_business_id'), table_name='warehouse_documents')
    op.drop_table('warehouse_documents')

