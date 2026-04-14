from __future__ import annotations

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '20250927_000015_add_document_lines_table'
down_revision = '20250927_000014_add_documents_table'
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.create_table(
		'document_lines',
		sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
		sa.Column('document_id', sa.Integer(), nullable=False),
		sa.Column('debit', sa.Numeric(18, 2), nullable=False, server_default=sa.text('0')), 
		sa.Column('credit', sa.Numeric(18, 2), nullable=False, server_default=sa.text('0')),
		sa.Column('description', sa.Text(), nullable=True),
		sa.Column('extra_info', sa.JSON(), nullable=True),
		sa.Column('developer_data', sa.JSON(), nullable=True),
		sa.Column('created_at', sa.DateTime(), nullable=False),
		sa.Column('updated_at', sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(['document_id'], ['documents.id'], ondelete='CASCADE'),
		sa.PrimaryKeyConstraint('id'),
		mysql_charset='utf8mb4'
	)
	
	op.create_index('ix_document_lines_document_id', 'document_lines', ['document_id'])


def downgrade() -> None:
	op.drop_index('ix_document_lines_document_id', table_name='document_lines')
	op.drop_table('document_lines')


