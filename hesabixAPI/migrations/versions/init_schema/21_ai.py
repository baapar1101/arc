"""جداول AI: ai_configs, ai_plans, user_ai_subscriptions, ai_invoices, ai_usage_logs, ai_chat_sessions, ai_chat_messages, ai_prompts"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import mysql


def upgrade():
    # جدول ai_configs
    op.create_table(
        'ai_configs',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('provider', sa.String(length=50), nullable=False, server_default='openai'),
        sa.Column('model_name', sa.String(length=100), nullable=False, server_default='gpt-4'),
        sa.Column('api_base_url', sa.String(length=500), nullable=True),
        sa.Column('api_key', sa.Text(), nullable=True),
        sa.Column('max_tokens', sa.Integer(), nullable=False, server_default='4000'),
        sa.Column('temperature', sa.Numeric(precision=3, scale=2), nullable=False, server_default='0.70'),
        sa.Column('is_active', sa.Boolean(), nullable=False, server_default='1'),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.PrimaryKeyConstraint('id')
    )

    # جدول ai_plans
    op.create_table(
        'ai_plans',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('code', sa.String(length=50), nullable=False),
        sa.Column('name', sa.String(length=255), nullable=False),
        sa.Column('description', sa.Text(), nullable=True),
        sa.Column('plan_type', sa.String(length=50), nullable=False),
        sa.Column('pricing_config', sa.Text(), nullable=True),
        sa.Column('usage_limits', sa.Text(), nullable=True),
        sa.Column('features', sa.Text(), nullable=True),
        sa.Column('tokens_limit', sa.Integer(), nullable=True),
        sa.Column('monthly_tokens_limit', sa.Integer(), nullable=True),
        sa.Column('is_active', sa.Boolean(), nullable=False, server_default='1'),
        sa.Column('auto_renew', sa.Boolean(), nullable=False, server_default='0'),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('code', name='uq_ai_plans_code')
    )
    op.create_index(op.f('ix_ai_plans_code'), 'ai_plans', ['code'], unique=True)

    # جدول user_ai_subscriptions
    op.create_table(
        'user_ai_subscriptions',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('business_id', sa.Integer(), nullable=True),
        sa.Column('plan_id', sa.Integer(), nullable=False),
        sa.Column('subscription_type', sa.String(length=50), nullable=False),
        sa.Column('tokens_used', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('tokens_limit', sa.Integer(), nullable=True),
        sa.Column('period_start', sa.DateTime(), nullable=False),
        sa.Column('period_end', sa.DateTime(), nullable=True),
        sa.Column('expires_at', sa.DateTime(), nullable=True),
        sa.Column('is_active', sa.Boolean(), nullable=False, server_default='1'),
        sa.Column('auto_renew', sa.Boolean(), nullable=False, server_default='0'),
        sa.Column('last_reset_at', sa.DateTime(), nullable=True),
        sa.Column('wallet_balance_required', sa.Numeric(precision=18, scale=2), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['business_id'], ['businesses.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['plan_id'], ['ai_plans.id'], ondelete='RESTRICT'),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_user_ai_subscriptions_user_id'), 'user_ai_subscriptions', ['user_id'], unique=False)
    op.create_index(op.f('ix_user_ai_subscriptions_business_id'), 'user_ai_subscriptions', ['business_id'], unique=False)
    op.create_index(op.f('ix_user_ai_subscriptions_plan_id'), 'user_ai_subscriptions', ['plan_id'], unique=False)

    # جدول ai_invoices
    op.create_table(
        'ai_invoices',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('subscription_id', sa.Integer(), nullable=True),
        sa.Column('business_id', sa.Integer(), nullable=False),
        sa.Column('plan_id', sa.Integer(), nullable=True),
        sa.Column('invoice_type', sa.String(length=50), nullable=False),
        sa.Column('code', sa.String(length=50), nullable=False),
        sa.Column('total', sa.Numeric(precision=18, scale=2), nullable=False),
        sa.Column('currency_id', sa.Integer(), nullable=False),
        sa.Column('status', sa.String(length=50), nullable=False, server_default='issued'),
        sa.Column('issued_at', sa.DateTime(), nullable=False),
        sa.Column('paid_at', sa.DateTime(), nullable=True),
        sa.Column('wallet_transaction_id', sa.Integer(), nullable=True),
        sa.Column('document_id', sa.Integer(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['subscription_id'], ['user_ai_subscriptions.id'], ondelete='SET NULL'),
        sa.ForeignKeyConstraint(['business_id'], ['businesses.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['plan_id'], ['ai_plans.id'], ondelete='SET NULL'),
        sa.ForeignKeyConstraint(['currency_id'], ['currencies.id'], ondelete='RESTRICT'),
        sa.ForeignKeyConstraint(['wallet_transaction_id'], ['wallet_transactions.id'], ondelete='SET NULL'),
        sa.ForeignKeyConstraint(['document_id'], ['documents.id'], ondelete='SET NULL'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('code', name='uq_ai_invoices_code')
    )
    op.create_index(op.f('ix_ai_invoices_subscription_id'), 'ai_invoices', ['subscription_id'], unique=False)
    op.create_index(op.f('ix_ai_invoices_business_id'), 'ai_invoices', ['business_id'], unique=False)
    op.create_index(op.f('ix_ai_invoices_plan_id'), 'ai_invoices', ['plan_id'], unique=False)
    op.create_index(op.f('ix_ai_invoices_code'), 'ai_invoices', ['code'], unique=True)
    op.create_index(op.f('ix_ai_invoices_wallet_transaction_id'), 'ai_invoices', ['wallet_transaction_id'], unique=False)
    op.create_index(op.f('ix_ai_invoices_document_id'), 'ai_invoices', ['document_id'], unique=False)

    # جدول ai_usage_logs
    op.create_table(
        'ai_usage_logs',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('business_id', sa.Integer(), nullable=True),
        sa.Column('subscription_id', sa.Integer(), nullable=True),
        sa.Column('invoice_id', sa.Integer(), nullable=True),
        sa.Column('provider', sa.String(length=50), nullable=False),
        sa.Column('model', sa.String(length=100), nullable=False),
        sa.Column('input_tokens', sa.Integer(), nullable=False),
        sa.Column('output_tokens', sa.Integer(), nullable=False),
        sa.Column('cost', sa.Numeric(precision=18, scale=2), nullable=False, server_default='0'),
        sa.Column('payment_method', sa.String(length=50), nullable=False),
        sa.Column('wallet_transaction_id', sa.Integer(), nullable=True),
        sa.Column('document_id', sa.Integer(), nullable=True),
        sa.Column('context', sa.Text(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['business_id'], ['businesses.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['subscription_id'], ['user_ai_subscriptions.id'], ondelete='SET NULL'),
        sa.ForeignKeyConstraint(['invoice_id'], ['ai_invoices.id'], ondelete='SET NULL'),
        sa.ForeignKeyConstraint(['wallet_transaction_id'], ['wallet_transactions.id'], ondelete='SET NULL'),
        sa.ForeignKeyConstraint(['document_id'], ['documents.id'], ondelete='SET NULL'),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_ai_usage_logs_user_id'), 'ai_usage_logs', ['user_id'], unique=False)
    op.create_index(op.f('ix_ai_usage_logs_business_id'), 'ai_usage_logs', ['business_id'], unique=False)
    op.create_index(op.f('ix_ai_usage_logs_subscription_id'), 'ai_usage_logs', ['subscription_id'], unique=False)
    op.create_index(op.f('ix_ai_usage_logs_invoice_id'), 'ai_usage_logs', ['invoice_id'], unique=False)
    op.create_index(op.f('ix_ai_usage_logs_wallet_transaction_id'), 'ai_usage_logs', ['wallet_transaction_id'], unique=False)
    op.create_index(op.f('ix_ai_usage_logs_document_id'), 'ai_usage_logs', ['document_id'], unique=False)
    op.create_index(op.f('ix_ai_usage_logs_created_at'), 'ai_usage_logs', ['created_at'], unique=False)

    # جدول ai_chat_sessions
    op.create_table(
        'ai_chat_sessions',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('business_id', sa.Integer(), nullable=True),
        sa.Column('title', sa.String(length=255), nullable=False, server_default='جلسه چت جدید'),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['business_id'], ['businesses.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_ai_chat_sessions_user_id'), 'ai_chat_sessions', ['user_id'], unique=False)
    op.create_index(op.f('ix_ai_chat_sessions_business_id'), 'ai_chat_sessions', ['business_id'], unique=False)

    # جدول ai_chat_messages
    op.create_table(
        'ai_chat_messages',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('session_id', sa.Integer(), nullable=False),
        sa.Column('role', sa.String(length=50), nullable=False),
        sa.Column('content', sa.Text(), nullable=False),
        sa.Column('function_calls', sa.Text(), nullable=True),
        sa.Column('function_results', sa.Text(), nullable=True),
        sa.Column('tokens_used', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['session_id'], ['ai_chat_sessions.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_ai_chat_messages_session_id'), 'ai_chat_messages', ['session_id'], unique=False)
    op.create_index(op.f('ix_ai_chat_messages_created_at'), 'ai_chat_messages', ['created_at'], unique=False)

    # جدول ai_prompts
    op.create_table(
        'ai_prompts',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('role', sa.String(length=50), nullable=False),
        sa.Column('prompt_type', sa.String(length=50), nullable=False),
        sa.Column('title', sa.String(length=255), nullable=False),
        sa.Column('content', sa.Text(), nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=True),
        sa.Column('is_default', sa.Boolean(), nullable=False, server_default='0'),
        sa.Column('is_active', sa.Boolean(), nullable=False, server_default='1'),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_ai_prompts_role'), 'ai_prompts', ['role'], unique=False)
    op.create_index(op.f('ix_ai_prompts_user_id'), 'ai_prompts', ['user_id'], unique=False)


def downgrade():
    op.drop_index(op.f('ix_ai_prompts_user_id'), table_name='ai_prompts')
    op.drop_index(op.f('ix_ai_prompts_role'), table_name='ai_prompts')
    op.drop_table('ai_prompts')
    
    op.drop_index(op.f('ix_ai_chat_messages_created_at'), table_name='ai_chat_messages')
    op.drop_index(op.f('ix_ai_chat_messages_session_id'), table_name='ai_chat_messages')
    op.drop_table('ai_chat_messages')
    
    op.drop_index(op.f('ix_ai_chat_sessions_business_id'), table_name='ai_chat_sessions')
    op.drop_index(op.f('ix_ai_chat_sessions_user_id'), table_name='ai_chat_sessions')
    op.drop_table('ai_chat_sessions')
    
    op.drop_index(op.f('ix_ai_usage_logs_created_at'), table_name='ai_usage_logs')
    op.drop_index(op.f('ix_ai_usage_logs_document_id'), table_name='ai_usage_logs')
    op.drop_index(op.f('ix_ai_usage_logs_wallet_transaction_id'), table_name='ai_usage_logs')
    op.drop_index(op.f('ix_ai_usage_logs_invoice_id'), table_name='ai_usage_logs')
    op.drop_index(op.f('ix_ai_usage_logs_subscription_id'), table_name='ai_usage_logs')
    op.drop_index(op.f('ix_ai_usage_logs_business_id'), table_name='ai_usage_logs')
    op.drop_index(op.f('ix_ai_usage_logs_user_id'), table_name='ai_usage_logs')
    op.drop_table('ai_usage_logs')
    
    op.drop_index(op.f('ix_ai_invoices_document_id'), table_name='ai_invoices')
    op.drop_index(op.f('ix_ai_invoices_wallet_transaction_id'), table_name='ai_invoices')
    op.drop_index(op.f('ix_ai_invoices_code'), table_name='ai_invoices')
    op.drop_index(op.f('ix_ai_invoices_plan_id'), table_name='ai_invoices')
    op.drop_index(op.f('ix_ai_invoices_business_id'), table_name='ai_invoices')
    op.drop_index(op.f('ix_ai_invoices_subscription_id'), table_name='ai_invoices')
    op.drop_table('ai_invoices')
    
    op.drop_index(op.f('ix_user_ai_subscriptions_plan_id'), table_name='user_ai_subscriptions')
    op.drop_index(op.f('ix_user_ai_subscriptions_business_id'), table_name='user_ai_subscriptions')
    op.drop_index(op.f('ix_user_ai_subscriptions_user_id'), table_name='user_ai_subscriptions')
    op.drop_table('user_ai_subscriptions')
    
    op.drop_index(op.f('ix_ai_plans_code'), table_name='ai_plans')
    op.drop_table('ai_plans')
    
    op.drop_table('ai_configs')

