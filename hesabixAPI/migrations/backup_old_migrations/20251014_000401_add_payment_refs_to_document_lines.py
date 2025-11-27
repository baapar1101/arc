from __future__ import annotations

from alembic import op
import sqlalchemy as sa
from sqlalchemy import inspect


# revision identifiers, used by Alembic.
revision = '20251014_000401_add_payment_refs_to_document_lines'
down_revision = '20251014_000301_add_product_id_to_document_lines'
branch_labels = None
depends_on = None


def upgrade() -> None:
	bind = op.get_bind()
	inspector = inspect(bind)
	tables = set(inspector.get_table_names())
	
	# Check if document_lines table exists
	if 'document_lines' not in tables:
		return
		
	# Get existing columns
	cols = {c['name'] for c in inspector.get_columns('document_lines')}
	
	with op.batch_alter_table('document_lines') as batch_op:
		# Only add columns if they don't exist
		if 'bank_account_id' not in cols:
			batch_op.add_column(sa.Column('bank_account_id', sa.Integer(), nullable=True))
		if 'cash_register_id' not in cols:
			batch_op.add_column(sa.Column('cash_register_id', sa.Integer(), nullable=True))
		if 'petty_cash_id' not in cols:
			batch_op.add_column(sa.Column('petty_cash_id', sa.Integer(), nullable=True))
		if 'check_id' not in cols:
			batch_op.add_column(sa.Column('check_id', sa.Integer(), nullable=True))

		# Only create foreign keys if the referenced tables exist
		if 'bank_accounts' in tables and 'bank_account_id' not in cols:
			batch_op.create_foreign_key('fk_document_lines_bank_account_id_bank_accounts', 'bank_accounts', ['bank_account_id'], ['id'], ondelete='SET NULL')
		if 'cash_registers' in tables and 'cash_register_id' not in cols:
			batch_op.create_foreign_key('fk_document_lines_cash_register_id_cash_registers', 'cash_registers', ['cash_register_id'], ['id'], ondelete='SET NULL')
		if 'petty_cash' in tables and 'petty_cash_id' not in cols:
			batch_op.create_foreign_key('fk_document_lines_petty_cash_id_petty_cash', 'petty_cash', ['petty_cash_id'], ['id'], ondelete='SET NULL')
		if 'checks' in tables and 'check_id' not in cols:
			batch_op.create_foreign_key('fk_document_lines_check_id_checks', 'checks', ['check_id'], ['id'], ondelete='SET NULL')

		# Only create indexes if columns were added
		if 'bank_account_id' not in cols:
			batch_op.create_index('ix_document_lines_bank_account_id', ['bank_account_id'])
		if 'cash_register_id' not in cols:
			batch_op.create_index('ix_document_lines_cash_register_id', ['cash_register_id'])
		if 'petty_cash_id' not in cols:
			batch_op.create_index('ix_document_lines_petty_cash_id', ['petty_cash_id'])
		if 'check_id' not in cols:
			batch_op.create_index('ix_document_lines_check_id', ['check_id'])


def downgrade() -> None:
	with op.batch_alter_table('document_lines') as batch_op:
		batch_op.drop_index('ix_document_lines_check_id')
		batch_op.drop_index('ix_document_lines_petty_cash_id')
		batch_op.drop_index('ix_document_lines_cash_register_id')
		batch_op.drop_index('ix_document_lines_bank_account_id')

		# Try to drop foreign keys, ignore if they don't exist
		try:
			batch_op.drop_constraint('fk_document_lines_check_id_checks', type_='foreignkey')
		except Exception:
			pass
		try:
			batch_op.drop_constraint('fk_document_lines_petty_cash_id_petty_cash', type_='foreignkey')
		except Exception:
			pass
		try:
			batch_op.drop_constraint('fk_document_lines_cash_register_id_cash_registers', type_='foreignkey')
		except Exception:
			pass
		try:
			batch_op.drop_constraint('fk_document_lines_bank_account_id_bank_accounts', type_='foreignkey')
		except Exception:
			pass

		batch_op.drop_column('check_id')
		batch_op.drop_column('petty_cash_id')
		batch_op.drop_column('cash_register_id')
		batch_op.drop_column('bank_account_id')


