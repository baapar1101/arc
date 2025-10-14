from __future__ import annotations

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '20251014_000401_add_payment_refs_to_document_lines'
down_revision = '20251014_000301_add_product_id_to_document_lines'
branch_labels = None
depends_on = None


def upgrade() -> None:
	with op.batch_alter_table('document_lines') as batch_op:
		batch_op.add_column(sa.Column('bank_account_id', sa.Integer(), nullable=True))
		batch_op.add_column(sa.Column('cash_register_id', sa.Integer(), nullable=True))
		batch_op.add_column(sa.Column('petty_cash_id', sa.Integer(), nullable=True))
		batch_op.add_column(sa.Column('check_id', sa.Integer(), nullable=True))

		batch_op.create_foreign_key('fk_document_lines_bank_account_id_bank_accounts', 'bank_accounts', ['bank_account_id'], ['id'], ondelete='SET NULL')
		batch_op.create_foreign_key('fk_document_lines_cash_register_id_cash_registers', 'cash_registers', ['cash_register_id'], ['id'], ondelete='SET NULL')
		batch_op.create_foreign_key('fk_document_lines_petty_cash_id_petty_cash', 'petty_cash', ['petty_cash_id'], ['id'], ondelete='SET NULL')
		batch_op.create_foreign_key('fk_document_lines_check_id_checks', 'checks', ['check_id'], ['id'], ondelete='SET NULL')

		batch_op.create_index('ix_document_lines_bank_account_id', ['bank_account_id'])
		batch_op.create_index('ix_document_lines_cash_register_id', ['cash_register_id'])
		batch_op.create_index('ix_document_lines_petty_cash_id', ['petty_cash_id'])
		batch_op.create_index('ix_document_lines_check_id', ['check_id'])


def downgrade() -> None:
	with op.batch_alter_table('document_lines') as batch_op:
		batch_op.drop_index('ix_document_lines_check_id')
		batch_op.drop_index('ix_document_lines_petty_cash_id')
		batch_op.drop_index('ix_document_lines_cash_register_id')
		batch_op.drop_index('ix_document_lines_bank_account_id')

		batch_op.drop_constraint('fk_document_lines_check_id_checks', type_='foreignkey')
		batch_op.drop_constraint('fk_document_lines_petty_cash_id_petty_cash', type_='foreignkey')
		batch_op.drop_constraint('fk_document_lines_cash_register_id_cash_registers', type_='foreignkey')
		batch_op.drop_constraint('fk_document_lines_bank_account_id_bank_accounts', type_='foreignkey')

		batch_op.drop_column('check_id')
		batch_op.drop_column('petty_cash_id')
		batch_op.drop_column('cash_register_id')
		batch_op.drop_column('bank_account_id')


