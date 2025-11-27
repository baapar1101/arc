"""جداول wallet_accounts, wallet_transactions, wallet_payouts, wallet_settings"""
from alembic import op
import sqlalchemy as sa


def upgrade():
    # جدول wallet_accounts
    op.create_table(
        'wallet_accounts',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('business_id', sa.Integer(), nullable=False),
        sa.Column('available_balance', sa.Numeric(precision=18, scale=2), nullable=False, server_default='0'),
        sa.Column('pending_balance', sa.Numeric(precision=18, scale=2), nullable=False, server_default='0'),
        sa.Column('status', sa.String(length=20), nullable=False, server_default='active'),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['business_id'], ['businesses.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('business_id', name='uq_wallet_accounts_business')
    )
    op.create_index(op.f('ix_wallet_accounts_business_id'), 'wallet_accounts', ['business_id'], unique=False)

    # جدول wallet_transactions
    op.create_table(
        'wallet_transactions',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('business_id', sa.Integer(), nullable=False),
        sa.Column('type', sa.String(length=50), nullable=False),
        sa.Column('status', sa.String(length=20), nullable=False, server_default='pending'),
        sa.Column('amount', sa.Numeric(precision=18, scale=2), nullable=False, server_default='0'),
        sa.Column('fee_amount', sa.Numeric(precision=18, scale=2), nullable=True),
        sa.Column('description', sa.String(length=500), nullable=True),
        sa.Column('external_ref', sa.String(length=100), nullable=True),
        sa.Column('document_id', sa.Integer(), nullable=True),
        sa.Column('extra_info', sa.Text(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['business_id'], ['businesses.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['document_id'], ['documents.id'], ondelete='SET NULL'),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_wallet_transactions_business_id'), 'wallet_transactions', ['business_id'], unique=False)
    op.create_index(op.f('ix_wallet_transactions_document_id'), 'wallet_transactions', ['document_id'], unique=False)
    op.create_index(op.f('ix_wallet_transactions_type'), 'wallet_transactions', ['type'], unique=False)
    op.create_index(op.f('ix_wallet_transactions_status'), 'wallet_transactions', ['status'], unique=False)

    # جدول wallet_payouts
    op.create_table(
        'wallet_payouts',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('business_id', sa.Integer(), nullable=False),
        sa.Column('bank_account_id', sa.Integer(), nullable=False),
        sa.Column('gross_amount', sa.Numeric(precision=18, scale=2), nullable=False, server_default='0'),
        sa.Column('fees', sa.Numeric(precision=18, scale=2), nullable=False, server_default='0'),
        sa.Column('net_amount', sa.Numeric(precision=18, scale=2), nullable=False, server_default='0'),
        sa.Column('status', sa.String(length=20), nullable=False, server_default='requested'),
        sa.Column('schedule_type', sa.String(length=20), nullable=False, server_default='manual'),
        sa.Column('external_ref', sa.String(length=100), nullable=True),
        sa.Column('extra_info', sa.Text(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['business_id'], ['businesses.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['bank_account_id'], ['bank_accounts.id'], ondelete='RESTRICT'),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_wallet_payouts_business_id'), 'wallet_payouts', ['business_id'], unique=False)
    op.create_index(op.f('ix_wallet_payouts_bank_account_id'), 'wallet_payouts', ['bank_account_id'], unique=False)

    # جدول wallet_settings
    op.create_table(
        'wallet_settings',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('business_id', sa.Integer(), nullable=False),
        sa.Column('mode', sa.String(length=20), nullable=False, server_default='manual'),
        sa.Column('frequency', sa.String(length=20), nullable=True),
        sa.Column('threshold_amount', sa.Numeric(precision=18, scale=2), nullable=True),
        sa.Column('min_reserve', sa.Numeric(precision=18, scale=2), nullable=True),
        sa.Column('default_bank_account_id', sa.Integer(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['business_id'], ['businesses.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['default_bank_account_id'], ['bank_accounts.id'], ondelete='SET NULL'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('business_id', name='uq_wallet_settings_business')
    )
    op.create_index(op.f('ix_wallet_settings_business_id'), 'wallet_settings', ['business_id'], unique=False)


def downgrade():
    op.drop_index(op.f('ix_wallet_settings_business_id'), table_name='wallet_settings')
    op.drop_table('wallet_settings')
    
    op.drop_index(op.f('ix_wallet_payouts_bank_account_id'), table_name='wallet_payouts')
    op.drop_index(op.f('ix_wallet_payouts_business_id'), table_name='wallet_payouts')
    op.drop_table('wallet_payouts')
    
    op.drop_index(op.f('ix_wallet_transactions_status'), table_name='wallet_transactions')
    op.drop_index(op.f('ix_wallet_transactions_type'), table_name='wallet_transactions')
    op.drop_index(op.f('ix_wallet_transactions_document_id'), table_name='wallet_transactions')
    op.drop_index(op.f('ix_wallet_transactions_business_id'), table_name='wallet_transactions')
    op.drop_table('wallet_transactions')
    
    op.drop_index(op.f('ix_wallet_accounts_business_id'), table_name='wallet_accounts')
    op.drop_table('wallet_accounts')

