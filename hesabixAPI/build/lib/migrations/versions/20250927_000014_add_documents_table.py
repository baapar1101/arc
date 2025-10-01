from __future__ import annotations

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '20250927_000014_add_documents_table'
down_revision = '20250927_000013_add_currencies_and_business_currencies'
branch_labels = None
depends_on = None


def upgrade() -> None:
	# Create documents table
	op.create_table(
		'documents',
		sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
		sa.Column('code', sa.String(length=50), nullable=False),
		sa.Column('business_id', sa.Integer(), nullable=False),
		sa.Column('currency_id', sa.Integer(), nullable=False),
		sa.Column('created_by_user_id', sa.Integer(), nullable=False),
		sa.Column('registered_at', sa.DateTime(), nullable=False),
		sa.Column('document_date', sa.Date(), nullable=False),
		sa.Column('document_type', sa.String(length=50), nullable=False),
		sa.Column('is_proforma', sa.Boolean(), nullable=False, server_default=sa.text('0')),
		sa.Column('extra_info', sa.JSON(), nullable=True),
		sa.Column('developer_settings', sa.JSON(), nullable=True),
		sa.Column('created_at', sa.DateTime(), nullable=False),
		sa.Column('updated_at', sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(['business_id'], ['businesses.id'], ondelete='CASCADE'),
		sa.ForeignKeyConstraint(['currency_id'], ['currencies.id'], ondelete='RESTRICT'),
		sa.ForeignKeyConstraint(['created_by_user_id'], ['users.id'], ondelete='RESTRICT'),
		sa.PrimaryKeyConstraint('id'),
		mysql_charset='utf8mb4'
	)

	# Unique per business code
	op.create_unique_constraint('uq_documents_business_code', 'documents', ['business_id', 'code'])

	# Indexes
	op.create_index('ix_documents_code', 'documents', ['code'])
	op.create_index('ix_documents_business_id', 'documents', ['business_id'])
	op.create_index('ix_documents_currency_id', 'documents', ['currency_id'])
	op.create_index('ix_documents_created_by_user_id', 'documents', ['created_by_user_id'])


def downgrade() -> None:
	op.drop_index('ix_documents_created_by_user_id', table_name='documents')
	op.drop_index('ix_documents_currency_id', table_name='documents')
	op.drop_index('ix_documents_business_id', table_name='documents')
	op.drop_index('ix_documents_code', table_name='documents')
	op.drop_constraint('uq_documents_business_code', 'documents', type_='unique')
	op.drop_table('documents')


