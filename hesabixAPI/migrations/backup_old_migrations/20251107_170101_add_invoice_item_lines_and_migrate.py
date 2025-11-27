from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = '20251107_170101_add_invoice_item_lines_and_migrate'
down_revision: Union[str, None] = '20251107_150001_add_warehouse_docs'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)

    if 'invoice_item_lines' not in inspector.get_table_names():
        op.create_table(
            'invoice_item_lines',
            sa.Column('id', sa.Integer(), primary_key=True, autoincrement=True),
            sa.Column('document_id', sa.Integer(), sa.ForeignKey('documents.id', ondelete='CASCADE'), nullable=False),
            sa.Column('product_id', sa.Integer(), nullable=False),
            sa.Column('quantity', sa.Numeric(18, 6), nullable=False),
            sa.Column('description', sa.Text(), nullable=True),
            sa.Column('extra_info', sa.JSON(), nullable=True),
        )
        try:
            op.create_index('ix_invoice_item_lines_doc', 'invoice_item_lines', ['document_id'])
            op.create_index('ix_invoice_item_lines_product', 'invoice_item_lines', ['product_id'])
        except Exception:
            pass

    # migrate existing product rows from document_lines
    # copy rows where product_id is not null
    try:
        op.execute(
            """
            INSERT INTO invoice_item_lines (document_id, product_id, quantity, description, extra_info)
            SELECT document_id, product_id, quantity, description, extra_info
            FROM document_lines
            WHERE product_id IS NOT NULL
            """
        )
        # delete copied rows from document_lines
        op.execute("DELETE FROM document_lines WHERE product_id IS NOT NULL")
    except Exception:
        # best-effort migration; ignore if structure differs
        pass


def downgrade() -> None:
    # optional: move back into document_lines
    try:
        op.execute(
            """
            INSERT INTO document_lines (document_id, product_id, quantity, description, extra_info, debit, credit)
            SELECT document_id, product_id, quantity, description, extra_info, 0, 0
            FROM invoice_item_lines
            """
        )
    except Exception:
        pass
    try:
        op.drop_index('ix_invoice_item_lines_product', table_name='invoice_item_lines')
        op.drop_index('ix_invoice_item_lines_doc', table_name='invoice_item_lines')
    except Exception:
        pass
    try:
        op.drop_table('invoice_item_lines')
    except Exception:
        pass


