"""جداول marketplace_plugins, marketplace_plugin_plans, marketplace_orders, marketplace_invoices, business_plugins"""
from alembic import op
import sqlalchemy as sa


def upgrade():
    # جدول marketplace_plugins
    op.create_table(
        'marketplace_plugins',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('code', sa.String(length=100), nullable=False),
        sa.Column('name', sa.String(length=200), nullable=False),
        sa.Column('description', sa.Text(), nullable=True),
        sa.Column('category', sa.String(length=100), nullable=True),
        sa.Column('icon_url', sa.String(length=500), nullable=True),
        sa.Column('is_active', sa.Boolean(), nullable=False, server_default='1'),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('code', name='uq_marketplace_plugins_code')
    )

    # جدول marketplace_plugin_plans
    op.create_table(
        'marketplace_plugin_plans',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('plugin_id', sa.Integer(), nullable=False),
        sa.Column('period', sa.String(length=20), nullable=False),
        sa.Column('price', sa.Numeric(precision=18, scale=2), nullable=False, server_default='0'),
        sa.Column('currency_id', sa.Integer(), nullable=False),
        sa.Column('is_active', sa.Boolean(), nullable=False, server_default='1'),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['plugin_id'], ['marketplace_plugins.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['currency_id'], ['currencies.id'], ondelete='RESTRICT'),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_marketplace_plugin_plans_plugin_id'), 'marketplace_plugin_plans', ['plugin_id'], unique=False)

    # جدول marketplace_orders
    op.create_table(
        'marketplace_orders',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('business_id', sa.Integer(), nullable=False),
        sa.Column('plugin_id', sa.Integer(), nullable=False),
        sa.Column('plan_id', sa.Integer(), nullable=False),
        sa.Column('quantity', sa.Integer(), nullable=False, server_default='1'),
        sa.Column('unit_price', sa.Numeric(precision=18, scale=2), nullable=False, server_default='0'),
        sa.Column('total_price', sa.Numeric(precision=18, scale=2), nullable=False, server_default='0'),
        sa.Column('currency_id', sa.Integer(), nullable=False),
        sa.Column('status', sa.String(length=20), nullable=False, server_default='pending'),
        sa.Column('wallet_transaction_id', sa.Integer(), nullable=True),
        sa.Column('invoice_id', sa.Integer(), nullable=True),
        sa.Column('external_ref', sa.String(length=100), nullable=True),
        sa.Column('extra_info', sa.Text(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['business_id'], ['businesses.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['plugin_id'], ['marketplace_plugins.id'], ondelete='RESTRICT'),
        sa.ForeignKeyConstraint(['plan_id'], ['marketplace_plugin_plans.id'], ondelete='RESTRICT'),
        sa.ForeignKeyConstraint(['currency_id'], ['currencies.id'], ondelete='RESTRICT'),
        sa.ForeignKeyConstraint(['wallet_transaction_id'], ['wallet_transactions.id'], ondelete='SET NULL'),
        sa.ForeignKeyConstraint(['invoice_id'], ['marketplace_invoices.id'], ondelete='SET NULL'),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_marketplace_orders_business_id'), 'marketplace_orders', ['business_id'], unique=False)
    op.create_index(op.f('ix_marketplace_orders_plugin_id'), 'marketplace_orders', ['plugin_id'], unique=False)
    op.create_index(op.f('ix_marketplace_orders_plan_id'), 'marketplace_orders', ['plan_id'], unique=False)
    op.create_index(op.f('ix_marketplace_orders_wallet_transaction_id'), 'marketplace_orders', ['wallet_transaction_id'], unique=False)
    op.create_index(op.f('ix_marketplace_orders_invoice_id'), 'marketplace_orders', ['invoice_id'], unique=False)

    # جدول marketplace_invoices
    op.create_table(
        'marketplace_invoices',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('order_id', sa.Integer(), nullable=False),
        sa.Column('business_id', sa.Integer(), nullable=False),
        sa.Column('code', sa.String(length=50), nullable=False),
        sa.Column('total', sa.Numeric(precision=18, scale=2), nullable=False, server_default='0'),
        sa.Column('currency_id', sa.Integer(), nullable=False),
        sa.Column('status', sa.String(length=20), nullable=False, server_default='issued'),
        sa.Column('issued_at', sa.DateTime(), nullable=False),
        sa.Column('paid_at', sa.DateTime(), nullable=True),
        sa.Column('extra_info', sa.Text(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['order_id'], ['marketplace_orders.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['business_id'], ['businesses.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['currency_id'], ['currencies.id'], ondelete='RESTRICT'),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_marketplace_invoices_order_id'), 'marketplace_invoices', ['order_id'], unique=False)
    op.create_index(op.f('ix_marketplace_invoices_business_id'), 'marketplace_invoices', ['business_id'], unique=False)

    # جدول business_plugins
    op.create_table(
        'business_plugins',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('business_id', sa.Integer(), nullable=False),
        sa.Column('plugin_id', sa.Integer(), nullable=False),
        sa.Column('plan_id', sa.Integer(), nullable=False),
        sa.Column('status', sa.String(length=20), nullable=False, server_default='active'),
        sa.Column('starts_at', sa.DateTime(), nullable=False),
        sa.Column('ends_at', sa.DateTime(), nullable=True),
        sa.Column('auto_renew', sa.Boolean(), nullable=False, server_default='0'),
        sa.Column('extra_info', sa.Text(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['business_id'], ['businesses.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['plugin_id'], ['marketplace_plugins.id'], ondelete='RESTRICT'),
        sa.ForeignKeyConstraint(['plan_id'], ['marketplace_plugin_plans.id'], ondelete='RESTRICT'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('business_id', 'plugin_id', name='uq_business_plugin_unique')
    )
    op.create_index(op.f('ix_business_plugins_business_id'), 'business_plugins', ['business_id'], unique=False)
    op.create_index(op.f('ix_business_plugins_plugin_id'), 'business_plugins', ['plugin_id'], unique=False)
    op.create_index(op.f('ix_business_plugins_plan_id'), 'business_plugins', ['plan_id'], unique=False)


def downgrade():
    op.drop_index(op.f('ix_business_plugins_plan_id'), table_name='business_plugins')
    op.drop_index(op.f('ix_business_plugins_plugin_id'), table_name='business_plugins')
    op.drop_index(op.f('ix_business_plugins_business_id'), table_name='business_plugins')
    op.drop_table('business_plugins')
    
    op.drop_index(op.f('ix_marketplace_invoices_business_id'), table_name='marketplace_invoices')
    op.drop_index(op.f('ix_marketplace_invoices_order_id'), table_name='marketplace_invoices')
    op.drop_table('marketplace_invoices')
    
    op.drop_index(op.f('ix_marketplace_orders_invoice_id'), table_name='marketplace_orders')
    op.drop_index(op.f('ix_marketplace_orders_wallet_transaction_id'), table_name='marketplace_orders')
    op.drop_index(op.f('ix_marketplace_orders_plan_id'), table_name='marketplace_orders')
    op.drop_index(op.f('ix_marketplace_orders_plugin_id'), table_name='marketplace_orders')
    op.drop_index(op.f('ix_marketplace_orders_business_id'), table_name='marketplace_orders')
    op.drop_table('marketplace_orders')
    
    op.drop_index(op.f('ix_marketplace_plugin_plans_plugin_id'), table_name='marketplace_plugin_plans')
    op.drop_table('marketplace_plugin_plans')
    
    op.drop_table('marketplace_plugins')

