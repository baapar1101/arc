"""جداول storage_plans, business_storage_subscriptions, storage_invoices, storage_usage_transactions"""
from alembic import op
import sqlalchemy as sa


def upgrade():
    # جدول storage_plans
    op.create_table(
        'storage_plans',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('name', sa.String(length=200), nullable=False),
        sa.Column('code', sa.String(length=100), nullable=False),
        sa.Column('storage_limit_gb', sa.Numeric(precision=10, scale=3), nullable=False),
        sa.Column('period', sa.String(length=20), nullable=False),
        sa.Column('period_months', sa.Integer(), nullable=True),
        sa.Column('price', sa.Numeric(precision=18, scale=2), nullable=False, server_default='0'),
        sa.Column('price_per_gb', sa.Numeric(precision=18, scale=2), nullable=True),
        sa.Column('is_free', sa.Boolean(), nullable=False, server_default='0'),
        sa.Column('is_active', sa.Boolean(), nullable=False, server_default='1'),
        sa.Column('currency_id', sa.Integer(), nullable=False),
        sa.Column('description', sa.Text(), nullable=True),
        sa.Column('grace_period_days', sa.Integer(), nullable=False, server_default='30'),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['currency_id'], ['currencies.id'], ondelete='RESTRICT'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('code', name='uq_storage_plans_code')
    )
    op.create_index(op.f('ix_storage_plans_code'), 'storage_plans', ['code'], unique=False)

    # جدول business_storage_subscriptions
    op.create_table(
        'business_storage_subscriptions',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('business_id', sa.Integer(), nullable=False),
        sa.Column('plan_id', sa.Integer(), nullable=False),
        sa.Column('status', sa.String(length=20), nullable=False, server_default='active'),
        sa.Column('starts_at', sa.DateTime(), nullable=False),
        sa.Column('ends_at', sa.DateTime(), nullable=True),
        sa.Column('auto_renew', sa.Boolean(), nullable=False, server_default='0'),
        sa.Column('grace_period_ends_at', sa.DateTime(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['business_id'], ['businesses.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['plan_id'], ['storage_plans.id'], ondelete='RESTRICT'),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_business_storage_subscriptions_business_id'), 'business_storage_subscriptions', ['business_id'], unique=False)
    op.create_index(op.f('ix_business_storage_subscriptions_plan_id'), 'business_storage_subscriptions', ['plan_id'], unique=False)

    # جدول storage_invoices
    op.create_table(
        'storage_invoices',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('business_id', sa.Integer(), nullable=False),
        sa.Column('subscription_id', sa.Integer(), nullable=True),
        sa.Column('code', sa.String(length=50), nullable=False),
        sa.Column('invoice_type', sa.String(length=20), nullable=False),
        sa.Column('total', sa.Numeric(precision=18, scale=2), nullable=False, server_default='0'),
        sa.Column('currency_id', sa.Integer(), nullable=False),
        sa.Column('status', sa.String(length=20), nullable=False, server_default='issued'),
        sa.Column('issued_at', sa.DateTime(), nullable=False),
        sa.Column('paid_at', sa.DateTime(), nullable=True),
        sa.Column('wallet_transaction_id', sa.Integer(), nullable=True),
        sa.Column('extra_info', sa.JSON(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['business_id'], ['businesses.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['subscription_id'], ['business_storage_subscriptions.id'], ondelete='SET NULL'),
        sa.ForeignKeyConstraint(['currency_id'], ['currencies.id'], ondelete='RESTRICT'),
        sa.ForeignKeyConstraint(['wallet_transaction_id'], ['wallet_transactions.id'], ondelete='SET NULL'),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_storage_invoices_business_id'), 'storage_invoices', ['business_id'], unique=False)
    op.create_index(op.f('ix_storage_invoices_subscription_id'), 'storage_invoices', ['subscription_id'], unique=False)
    op.create_index(op.f('ix_storage_invoices_code'), 'storage_invoices', ['code'], unique=False)
    op.create_index(op.f('ix_storage_invoices_wallet_transaction_id'), 'storage_invoices', ['wallet_transaction_id'], unique=False)

    # جدول storage_usage_transactions
    op.create_table(
        'storage_usage_transactions',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('business_id', sa.Integer(), nullable=False),
        sa.Column('file_storage_id', sa.String(length=36), nullable=True),
        sa.Column('usage_gb', sa.Numeric(precision=10, scale=6), nullable=False),
        sa.Column('transaction_type', sa.String(length=20), nullable=False),
        sa.Column('subscription_id', sa.Integer(), nullable=True),
        sa.Column('invoice_id', sa.Integer(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['business_id'], ['businesses.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['file_storage_id'], ['file_storage.id'], ondelete='SET NULL'),
        sa.ForeignKeyConstraint(['subscription_id'], ['business_storage_subscriptions.id'], ondelete='SET NULL'),
        sa.ForeignKeyConstraint(['invoice_id'], ['storage_invoices.id'], ondelete='SET NULL'),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_storage_usage_transactions_business_id'), 'storage_usage_transactions', ['business_id'], unique=False)
    op.create_index(op.f('ix_storage_usage_transactions_file_storage_id'), 'storage_usage_transactions', ['file_storage_id'], unique=False)
    op.create_index(op.f('ix_storage_usage_transactions_subscription_id'), 'storage_usage_transactions', ['subscription_id'], unique=False)
    op.create_index(op.f('ix_storage_usage_transactions_invoice_id'), 'storage_usage_transactions', ['invoice_id'], unique=False)


def downgrade():
    op.drop_index(op.f('ix_storage_usage_transactions_invoice_id'), table_name='storage_usage_transactions')
    op.drop_index(op.f('ix_storage_usage_transactions_subscription_id'), table_name='storage_usage_transactions')
    op.drop_index(op.f('ix_storage_usage_transactions_file_storage_id'), table_name='storage_usage_transactions')
    op.drop_index(op.f('ix_storage_usage_transactions_business_id'), table_name='storage_usage_transactions')
    op.drop_table('storage_usage_transactions')
    
    op.drop_index(op.f('ix_storage_invoices_wallet_transaction_id'), table_name='storage_invoices')
    op.drop_index(op.f('ix_storage_invoices_code'), table_name='storage_invoices')
    op.drop_index(op.f('ix_storage_invoices_subscription_id'), table_name='storage_invoices')
    op.drop_index(op.f('ix_storage_invoices_business_id'), table_name='storage_invoices')
    op.drop_table('storage_invoices')
    
    op.drop_index(op.f('ix_business_storage_subscriptions_plan_id'), table_name='business_storage_subscriptions')
    op.drop_index(op.f('ix_business_storage_subscriptions_business_id'), table_name='business_storage_subscriptions')
    op.drop_table('business_storage_subscriptions')
    
    op.drop_index(op.f('ix_storage_plans_code'), table_name='storage_plans')
    op.drop_table('storage_plans')

