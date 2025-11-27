"""add bank_accounts table

Revision ID: 20251002_000101_add_bank_accounts_table
Revises: 20251001_001201_merge_heads_drop_currency_tax_units
Create Date: 2025-10-02 00:01:01.000001

"""

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '20251002_000101_add_bank_accounts_table'
down_revision = '20251001_001201_merge_heads_drop_currency_tax_units'
branch_labels = None
depends_on = None


def upgrade() -> None:
	bind = op.get_bind()
	inspector = sa.inspect(bind)
	if 'bank_accounts' not in inspector.get_table_names():
		op.create_table(
			'bank_accounts',
			sa.Column('id', sa.Integer(), primary_key=True, autoincrement=True),
			sa.Column('business_id', sa.Integer(), sa.ForeignKey('businesses.id', ondelete='CASCADE'), nullable=False),
			sa.Column('code', sa.String(length=50), nullable=True),
			sa.Column('name', sa.String(length=255), nullable=False),
			sa.Column('description', sa.String(length=500), nullable=True),
			sa.Column('branch', sa.String(length=255), nullable=True),
			sa.Column('account_number', sa.String(length=50), nullable=True),
			sa.Column('sheba_number', sa.String(length=30), nullable=True),
			sa.Column('card_number', sa.String(length=20), nullable=True),
			sa.Column('owner_name', sa.String(length=255), nullable=True),
			sa.Column('pos_number', sa.String(length=50), nullable=True),
			sa.Column('payment_id', sa.String(length=100), nullable=True),
			sa.Column('currency_id', sa.Integer(), sa.ForeignKey('currencies.id', ondelete='RESTRICT'), nullable=False),
			sa.Column('is_active', sa.Boolean(), nullable=False, server_default=sa.text('1')),
			sa.Column('is_default', sa.Boolean(), nullable=False, server_default=sa.text('0')),
			sa.Column('created_at', sa.DateTime(), nullable=False),
			sa.Column('updated_at', sa.DateTime(), nullable=False),
			sa.UniqueConstraint('business_id', 'code', name='uq_bank_accounts_business_code'),
		)
		try:
			op.create_index('ix_bank_accounts_business_id', 'bank_accounts', ['business_id'])
			op.create_index('ix_bank_accounts_currency_id', 'bank_accounts', ['currency_id'])
		except Exception:
			pass
	else:
		# تلاش برای ایجاد ایندکس‌ها اگر وجود ندارند
		existing_indexes = {idx['name'] for idx in inspector.get_indexes('bank_accounts')}
		if 'ix_bank_accounts_business_id' not in existing_indexes:
			try:
				op.create_index('ix_bank_accounts_business_id', 'bank_accounts', ['business_id'])
			except Exception:
				pass
		if 'ix_bank_accounts_currency_id' not in existing_indexes:
			try:
				op.create_index('ix_bank_accounts_currency_id', 'bank_accounts', ['currency_id'])
			except Exception:
				pass


def downgrade() -> None:
	op.drop_index('ix_bank_accounts_currency_id', table_name='bank_accounts')
	op.drop_index('ix_bank_accounts_business_id', table_name='bank_accounts')
	op.drop_table('bank_accounts')


