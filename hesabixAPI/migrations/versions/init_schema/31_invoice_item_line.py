"""جدول invoice_item_lines"""
from alembic import op
import sqlalchemy as sa


def upgrade():
    op.create_table(
        'invoice_item_lines',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('document_id', sa.Integer(), nullable=False),
        sa.Column('product_id', sa.Integer(), nullable=False),
        sa.Column('quantity', sa.Numeric(precision=18, scale=6), nullable=False),
        sa.Column('description', sa.Text(), nullable=True),
        sa.Column('extra_info', sa.JSON(), nullable=True),
        sa.ForeignKeyConstraint(['document_id'], ['documents.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_invoice_item_lines_document_id'), 'invoice_item_lines', ['document_id'], unique=False)
    op.create_index(op.f('ix_invoice_item_lines_product_id'), 'invoice_item_lines', ['product_id'], unique=False)


def downgrade():
    op.drop_index(op.f('ix_invoice_item_lines_product_id'), table_name='invoice_item_lines')
    op.drop_index(op.f('ix_invoice_item_lines_document_id'), table_name='invoice_item_lines')
    op.drop_table('invoice_item_lines')

