"""add wallet tables (accounts, transactions, payouts, settings)

Revision ID: 20251108_232101_add_wallet_tables
Revises: 20251108_231201_add_system_settings
Create Date: 2025-11-08 23:21:01.000001

"""

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '20251108_232101_add_wallet_tables'
down_revision = '20251108_231201_add_system_settings'
branch_labels = None
depends_on = None


def upgrade() -> None:
	bind = op.get_bind()
	inspector = sa.inspect(bind)
	tables = inspector.get_table_names()

	if 'wallet_accounts' not in tables:
		op.create_table(
			'wallet_accounts',
			sa.Column('id', sa.Integer(), primary_key=True, autoincrement=True),
			sa.Column('business_id', sa.Integer(), sa.ForeignKey('businesses.id', ondelete='CASCADE'), nullable=False),
			sa.Column('available_balance', sa.Numeric(18, 2), nullable=False, server_default=sa.text('0')),
			sa.Column('pending_balance', sa.Numeric(18, 2), nullable=False, server_default=sa.text('0')),
			sa.Column('status', sa.String(length=20), nullable=False, server_default='active'),
			sa.Column('created_at', sa.DateTime(), nullable=False),
			sa.Column('updated_at', sa.DateTime(), nullable=False),
			sa.UniqueConstraint('business_id', name='uq_wallet_accounts_business'),
		)
		try:
			op.create_index('ix_wallet_accounts_business_id', 'wallet_accounts', ['business_id'])
		except Exception:
			pass

	if 'wallet_transactions' not in tables:
		op.create_table(
			'wallet_transactions',
			sa.Column('id', sa.Integer(), primary_key=True, autoincrement=True),
			sa.Column('business_id', sa.Integer(), sa.ForeignKey('businesses.id', ondelete='CASCADE'), nullable=False),
			sa.Column('type', sa.String(length=50), nullable=False),
			sa.Column('status', sa.String(length=20), nullable=False, server_default='pending'),
			sa.Column('amount', sa.Numeric(18, 2), nullable=False, server_default=sa.text('0')),
			sa.Column('fee_amount', sa.Numeric(18, 2), nullable=True),
			sa.Column('description', sa.String(length=500), nullable=True),
			sa.Column('external_ref', sa.String(length=100), nullable=True),
			sa.Column('document_id', sa.Integer(), sa.ForeignKey('documents.id', ondelete='SET NULL'), nullable=True),
			sa.Column('extra_info', sa.Text(), nullable=True),
			sa.Column('created_at', sa.DateTime(), nullable=False),
			sa.Column('updated_at', sa.DateTime(), nullable=False),
		)
		try:
			op.create_index('ix_wallet_tx_business_id', 'wallet_transactions', ['business_id'])
			op.create_index('ix_wallet_tx_document_id', 'wallet_transactions', ['document_id'])
			op.create_index('ix_wallet_tx_type', 'wallet_transactions', ['type'])
			op.create_index('ix_wallet_tx_status', 'wallet_transactions', ['status'])
		except Exception:
			pass

	if 'wallet_payouts' not in tables:
		op.create_table(
			'wallet_payouts',
			sa.Column('id', sa.Integer(), primary_key=True, autoincrement=True),
			sa.Column('business_id', sa.Integer(), sa.ForeignKey('businesses.id', ondelete='CASCADE'), nullable=False),
			sa.Column('bank_account_id', sa.Integer(), sa.ForeignKey('bank_accounts.id', ondelete='RESTRICT'), nullable=False),
			sa.Column('gross_amount', sa.Numeric(18, 2), nullable=False, server_default=sa.text('0')),
			sa.Column('fees', sa.Numeric(18, 2), nullable=False, server_default=sa.text('0')),
			sa.Column('net_amount', sa.Numeric(18, 2), nullable=False, server_default=sa.text('0')),
			sa.Column('status', sa.String(length=20), nullable=False, server_default='requested'),
			sa.Column('schedule_type', sa.String(length=20), nullable=False, server_default='manual'),
			sa.Column('external_ref', sa.String(length=100), nullable=True),
			sa.Column('extra_info', sa.Text(), nullable=True),
			sa.Column('created_at', sa.DateTime(), nullable=False),
			sa.Column('updated_at', sa.DateTime(), nullable=False),
		)
		try:
			op.create_index('ix_wallet_payouts_business_id', 'wallet_payouts', ['business_id'])
			op.create_index('ix_wallet_payouts_bank_account_id', 'wallet_payouts', ['bank_account_id'])
			op.create_index('ix_wallet_payouts_status', 'wallet_payouts', ['status'])
		except Exception:
			pass

	if 'wallet_settings' not in tables:
		op.create_table(
			'wallet_settings',
			sa.Column('id', sa.Integer(), primary_key=True, autoincrement=True),
			sa.Column('business_id', sa.Integer(), sa.ForeignKey('businesses.id', ondelete='CASCADE'), nullable=False),
			sa.Column('mode', sa.String(length=20), nullable=False, server_default='manual'),
			sa.Column('frequency', sa.String(length=20), nullable=True),
			sa.Column('threshold_amount', sa.Numeric(18, 2), nullable=True),
			sa.Column('min_reserve', sa.Numeric(18, 2), nullable=True),
			sa.Column('default_bank_account_id', sa.Integer(), sa.ForeignKey('bank_accounts.id', ondelete='SET NULL'), nullable=True),
			sa.Column('created_at', sa.DateTime(), nullable=False),
			sa.Column('updated_at', sa.DateTime(), nullable=False),
			sa.UniqueConstraint('business_id', name='uq_wallet_settings_business'),
		)
		try:
			op.create_index('ix_wallet_settings_business_id', 'wallet_settings', ['business_id'])
		except Exception:
			pass


def downgrade() -> None:
	for name in ['wallet_settings', 'wallet_payouts', 'wallet_transactions', 'wallet_accounts']:
		try:
			op.drop_table(name)
		except Exception:
			pass


