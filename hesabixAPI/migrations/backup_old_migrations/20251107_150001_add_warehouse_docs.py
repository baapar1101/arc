from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = '20251107_150001_add_warehouse_docs'
down_revision: Union[str, None] = 'ac9e4b3dcffc'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)

    tables = inspector.get_table_names()

    if 'warehouse_documents' not in tables:
        op.create_table(
            'warehouse_documents',
            sa.Column('id', sa.Integer(), primary_key=True, autoincrement=True),
            sa.Column('business_id', sa.Integer(), nullable=False),
            sa.Column('fiscal_year_id', sa.Integer(), nullable=True),
            sa.Column('code', sa.String(length=64), nullable=False, unique=True),
            sa.Column('document_date', sa.Date(), nullable=False),
            sa.Column('status', sa.String(length=16), nullable=False, server_default='draft'),
            sa.Column('doc_type', sa.String(length=32), nullable=False),
            sa.Column('warehouse_id_from', sa.Integer(), nullable=True),
            sa.Column('warehouse_id_to', sa.Integer(), nullable=True),
            sa.Column('source_type', sa.String(length=32), nullable=True),
            sa.Column('source_document_id', sa.Integer(), nullable=True),
            sa.Column('extra_info', sa.JSON(), nullable=True),
            sa.Column('created_by_user_id', sa.Integer(), nullable=True),
            sa.Column('created_at', sa.DateTime(), nullable=False, server_default=sa.text('CURRENT_TIMESTAMP')),
            sa.Column('updated_at', sa.DateTime(), nullable=False, server_default=sa.text('CURRENT_TIMESTAMP')),
        )
        try:
            op.create_index('ix_wh_docs_business_date', 'warehouse_documents', ['business_id', 'document_date'])
            op.create_index('ix_wh_docs_code', 'warehouse_documents', ['code'])
        except Exception:
            pass

    if 'warehouse_document_lines' not in tables:
        op.create_table(
            'warehouse_document_lines',
            sa.Column('id', sa.Integer(), primary_key=True, autoincrement=True),
            sa.Column('warehouse_document_id', sa.Integer(), sa.ForeignKey('warehouse_documents.id', ondelete='CASCADE'), nullable=False),
            sa.Column('product_id', sa.Integer(), nullable=False),
            sa.Column('warehouse_id', sa.Integer(), nullable=True),
            sa.Column('movement', sa.String(length=8), nullable=False),
            sa.Column('quantity', sa.Numeric(18, 6), nullable=False),
            sa.Column('cost_price', sa.Numeric(18, 6), nullable=True),
            sa.Column('cogs_amount', sa.Numeric(18, 6), nullable=True),
            sa.Column('extra_info', sa.JSON(), nullable=True),
        )
        try:
            op.create_index('ix_wh_lines_doc', 'warehouse_document_lines', ['warehouse_document_id'])
            op.create_index('ix_wh_lines_product', 'warehouse_document_lines', ['product_id'])
            op.create_index('ix_wh_lines_warehouse', 'warehouse_document_lines', ['warehouse_id'])
        except Exception:
            pass


def downgrade() -> None:
    try:
        op.drop_index('ix_wh_lines_warehouse', table_name='warehouse_document_lines')
        op.drop_index('ix_wh_lines_product', table_name='warehouse_document_lines')
        op.drop_index('ix_wh_lines_doc', table_name='warehouse_document_lines')
    except Exception:
        pass
    try:
        op.drop_table('warehouse_document_lines')
    except Exception:
        pass
    try:
        op.drop_index('ix_wh_docs_code', table_name='warehouse_documents')
        op.drop_index('ix_wh_docs_business_date', table_name='warehouse_documents')
    except Exception:
        pass
    try:
        op.drop_table('warehouse_documents')
    except Exception:
        pass


