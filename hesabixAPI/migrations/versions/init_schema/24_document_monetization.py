"""جداول document_subscription_plans, business_document_subscriptions, document_usage_policies, document_usage_charges, document_usage_periods, document_usage_cursors"""
from alembic import op
import sqlalchemy as sa


def upgrade():
    # جدول document_subscription_plans
    op.create_table(
        'document_subscription_plans',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('name', sa.String(length=200), nullable=False),
        sa.Column('code', sa.String(length=100), nullable=False),
        sa.Column('description', sa.Text(), nullable=True),
        sa.Column('period_months', sa.Integer(), nullable=False),
        sa.Column('price', sa.Numeric(precision=18, scale=2), nullable=False, server_default='0'),
        sa.Column('currency_id', sa.Integer(), nullable=False),
        sa.Column('is_active', sa.Boolean(), nullable=False, server_default='1'),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['currency_id'], ['currencies.id'], ondelete='RESTRICT'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('code', name='uq_document_subscription_plans_code')
    )
    op.create_index(op.f('ix_document_subscription_plans_code'), 'document_subscription_plans', ['code'], unique=False)

    # جدول business_document_subscriptions
    op.create_table(
        'business_document_subscriptions',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('business_id', sa.Integer(), nullable=False),
        sa.Column('plan_id', sa.Integer(), nullable=False),
        sa.Column('status', sa.String(length=20), nullable=False, server_default='active'),
        sa.Column('starts_at', sa.DateTime(), nullable=False),
        sa.Column('ends_at', sa.DateTime(), nullable=False),
        sa.Column('auto_renew', sa.Boolean(), nullable=False, server_default='0'),
        sa.Column('created_by_user_id', sa.Integer(), nullable=True),
        sa.Column('extra_data', sa.JSON(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['business_id'], ['businesses.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['plan_id'], ['document_subscription_plans.id'], ondelete='RESTRICT'),
        sa.ForeignKeyConstraint(['created_by_user_id'], ['users.id'], ondelete='SET NULL'),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_business_document_subscriptions_business_id'), 'business_document_subscriptions', ['business_id'], unique=False)
    op.create_index(op.f('ix_business_document_subscriptions_plan_id'), 'business_document_subscriptions', ['plan_id'], unique=False)

    # جدول document_usage_policies
    op.create_table(
        'document_usage_policies',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('business_id', sa.Integer(), nullable=False),
        sa.Column('policy_type', sa.String(length=30), nullable=False),
        sa.Column('title', sa.String(length=200), nullable=False),
        sa.Column('priority', sa.Integer(), nullable=False, server_default='100'),
        sa.Column('is_active', sa.Boolean(), nullable=False, server_default='1'),
        sa.Column('config', sa.JSON(), nullable=True),
        sa.Column('starts_at', sa.DateTime(), nullable=True),
        sa.Column('ends_at', sa.DateTime(), nullable=True),
        sa.Column('created_by_user_id', sa.Integer(), nullable=True),
        sa.Column('updated_by_user_id', sa.Integer(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['business_id'], ['businesses.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['created_by_user_id'], ['users.id'], ondelete='SET NULL'),
        sa.ForeignKeyConstraint(['updated_by_user_id'], ['users.id'], ondelete='SET NULL'),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_document_usage_policies_business_id'), 'document_usage_policies', ['business_id'], unique=False)

    # جدول document_usage_charges
    op.create_table(
        'document_usage_charges',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('business_id', sa.Integer(), nullable=False),
        sa.Column('policy_id', sa.Integer(), nullable=True),
        sa.Column('document_id', sa.Integer(), nullable=True),
        sa.Column('charge_type', sa.String(length=30), nullable=False),
        sa.Column('status', sa.String(length=20), nullable=False, server_default='pending'),
        sa.Column('amount', sa.Numeric(precision=18, scale=2), nullable=False, server_default='0'),
        sa.Column('currency_id', sa.Integer(), nullable=False),
        sa.Column('wallet_transaction_id', sa.Integer(), nullable=True),
        sa.Column('description', sa.String(length=500), nullable=True),
        sa.Column('metrics', sa.JSON(), nullable=True),
        sa.Column('period_key', sa.String(length=50), nullable=True),
        sa.Column('period_start', sa.DateTime(), nullable=True),
        sa.Column('period_end', sa.DateTime(), nullable=True),
        sa.Column('issued_by_user_id', sa.Integer(), nullable=True),
        sa.Column('paid_at', sa.DateTime(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['business_id'], ['businesses.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['policy_id'], ['document_usage_policies.id'], ondelete='SET NULL'),
        sa.ForeignKeyConstraint(['document_id'], ['documents.id'], ondelete='SET NULL'),
        sa.ForeignKeyConstraint(['currency_id'], ['currencies.id'], ondelete='RESTRICT'),
        sa.ForeignKeyConstraint(['wallet_transaction_id'], ['wallet_transactions.id'], ondelete='SET NULL'),
        sa.ForeignKeyConstraint(['issued_by_user_id'], ['users.id'], ondelete='SET NULL'),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_document_usage_charges_business_id'), 'document_usage_charges', ['business_id'], unique=False)
    op.create_index(op.f('ix_document_usage_charges_policy_id'), 'document_usage_charges', ['policy_id'], unique=False)
    op.create_index(op.f('ix_document_usage_charges_document_id'), 'document_usage_charges', ['document_id'], unique=False)
    op.create_index(op.f('ix_document_usage_charges_period_key'), 'document_usage_charges', ['period_key'], unique=False)
    op.create_index(op.f('ix_document_usage_charges_wallet_transaction_id'), 'document_usage_charges', ['wallet_transaction_id'], unique=False)

    # جدول document_usage_periods
    op.create_table(
        'document_usage_periods',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('business_id', sa.Integer(), nullable=False),
        sa.Column('policy_id', sa.Integer(), nullable=False),
        sa.Column('period_key', sa.String(length=50), nullable=False),
        sa.Column('cycle', sa.String(length=20), nullable=False),
        sa.Column('period_start', sa.DateTime(), nullable=False),
        sa.Column('period_end', sa.DateTime(), nullable=False),
        sa.Column('documents_count', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('total_amount', sa.Numeric(precision=18, scale=2), nullable=False, server_default='0'),
        sa.Column('status', sa.String(length=20), nullable=False, server_default='open'),
        sa.Column('charge_id', sa.Integer(), nullable=True),
        sa.Column('extra_data', sa.JSON(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['business_id'], ['businesses.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['policy_id'], ['document_usage_policies.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['charge_id'], ['document_usage_charges.id'], ondelete='SET NULL'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('policy_id', 'period_key', name='uq_document_usage_period_policy_key')
    )
    op.create_index(op.f('ix_document_usage_periods_business_id'), 'document_usage_periods', ['business_id'], unique=False)
    op.create_index(op.f('ix_document_usage_periods_policy_id'), 'document_usage_periods', ['policy_id'], unique=False)

    # جدول document_usage_cursors
    op.create_table(
        'document_usage_cursors',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('scope', sa.String(length=20), nullable=False, server_default='global'),
        sa.Column('business_id', sa.Integer(), nullable=True),
        sa.Column('last_document_id', sa.Integer(), nullable=True),
        sa.Column('last_document_created_at', sa.DateTime(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['business_id'], ['businesses.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('scope', 'business_id', name='uq_document_usage_cursor_scope_business')
    )
    op.create_index(op.f('ix_document_usage_cursors_business_id'), 'document_usage_cursors', ['business_id'], unique=False)


def downgrade():
    op.drop_index(op.f('ix_document_usage_cursors_business_id'), table_name='document_usage_cursors')
    op.drop_table('document_usage_cursors')
    
    op.drop_index(op.f('ix_document_usage_periods_policy_id'), table_name='document_usage_periods')
    op.drop_index(op.f('ix_document_usage_periods_business_id'), table_name='document_usage_periods')
    op.drop_table('document_usage_periods')
    
    op.drop_index(op.f('ix_document_usage_charges_wallet_transaction_id'), table_name='document_usage_charges')
    op.drop_index(op.f('ix_document_usage_charges_period_key'), table_name='document_usage_charges')
    op.drop_index(op.f('ix_document_usage_charges_document_id'), table_name='document_usage_charges')
    op.drop_index(op.f('ix_document_usage_charges_policy_id'), table_name='document_usage_charges')
    op.drop_index(op.f('ix_document_usage_charges_business_id'), table_name='document_usage_charges')
    op.drop_table('document_usage_charges')
    
    op.drop_index(op.f('ix_document_usage_policies_business_id'), table_name='document_usage_policies')
    op.drop_table('document_usage_policies')
    
    op.drop_index(op.f('ix_business_document_subscriptions_plan_id'), table_name='business_document_subscriptions')
    op.drop_index(op.f('ix_business_document_subscriptions_business_id'), table_name='business_document_subscriptions')
    op.drop_table('business_document_subscriptions')
    
    op.drop_index(op.f('ix_document_subscription_plans_code'), table_name='document_subscription_plans')
    op.drop_table('document_subscription_plans')

