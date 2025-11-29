"""جداول zohal_services و zohal_service_logs"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import mysql


def upgrade():
    # جدول zohal_services
    op.create_table(
        'zohal_services',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('service_code', sa.String(length=100), nullable=False),
        sa.Column('service_path', sa.String(length=255), nullable=False),
        sa.Column('service_name', sa.String(length=255), nullable=False),
        sa.Column('service_category', sa.String(length=50), nullable=False),
        sa.Column('description', sa.Text(), nullable=True),
        sa.Column('is_active', sa.Boolean(), nullable=False, server_default='true'),
        sa.Column('base_price', sa.Numeric(precision=18, scale=2), nullable=False),
        sa.Column('currency_id', sa.Integer(), nullable=False),
        sa.Column('request_schema', sa.JSON(), nullable=True),
        sa.Column('response_schema', sa.JSON(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['currency_id'], ['currencies.id'], ondelete='RESTRICT'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('service_code', name='uq_zohal_services_code')
    )
    op.create_index(op.f('ix_zohal_services_service_code'), 'zohal_services', ['service_code'], unique=True)
    op.create_index(op.f('ix_zohal_services_service_category'), 'zohal_services', ['service_category'], unique=False)
    op.create_index(op.f('ix_zohal_services_currency_id'), 'zohal_services', ['currency_id'], unique=False)

    # جدول zohal_service_logs
    op.create_table(
        'zohal_service_logs',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('business_id', sa.Integer(), nullable=False),
        sa.Column('service_id', sa.Integer(), nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('request_data', sa.JSON(), nullable=False),
        sa.Column('response_data', sa.JSON(), nullable=False),
        sa.Column('status', sa.String(length=20), nullable=False, server_default='pending'),
        sa.Column('error_message', sa.Text(), nullable=True),
        sa.Column('amount_charged', sa.Numeric(precision=18, scale=2), nullable=False),
        sa.Column('currency_id', sa.Integer(), nullable=False),
        sa.Column('wallet_transaction_id', sa.Integer(), nullable=True),
        sa.Column('document_id', sa.Integer(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['business_id'], ['businesses.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['service_id'], ['zohal_services.id'], ondelete='RESTRICT'),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='SET NULL'),
        sa.ForeignKeyConstraint(['currency_id'], ['currencies.id'], ondelete='RESTRICT'),
        sa.ForeignKeyConstraint(['wallet_transaction_id'], ['wallet_transactions.id'], ondelete='SET NULL'),
        sa.ForeignKeyConstraint(['document_id'], ['documents.id'], ondelete='SET NULL'),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_zohal_service_logs_business_id'), 'zohal_service_logs', ['business_id'], unique=False)
    op.create_index(op.f('ix_zohal_service_logs_service_id'), 'zohal_service_logs', ['service_id'], unique=False)
    op.create_index(op.f('ix_zohal_service_logs_user_id'), 'zohal_service_logs', ['user_id'], unique=False)
    op.create_index(op.f('ix_zohal_service_logs_currency_id'), 'zohal_service_logs', ['currency_id'], unique=False)
    op.create_index(op.f('ix_zohal_service_logs_wallet_transaction_id'), 'zohal_service_logs', ['wallet_transaction_id'], unique=False)
    op.create_index(op.f('ix_zohal_service_logs_document_id'), 'zohal_service_logs', ['document_id'], unique=False)
    op.create_index(op.f('ix_zohal_service_logs_created_at'), 'zohal_service_logs', ['created_at'], unique=False)
    op.create_index(op.f('ix_zohal_service_logs_status'), 'zohal_service_logs', ['status'], unique=False)


def downgrade():
    op.drop_index(op.f('ix_zohal_service_logs_status'), table_name='zohal_service_logs')
    op.drop_index(op.f('ix_zohal_service_logs_created_at'), table_name='zohal_service_logs')
    op.drop_index(op.f('ix_zohal_service_logs_document_id'), table_name='zohal_service_logs')
    op.drop_index(op.f('ix_zohal_service_logs_wallet_transaction_id'), table_name='zohal_service_logs')
    op.drop_index(op.f('ix_zohal_service_logs_currency_id'), table_name='zohal_service_logs')
    op.drop_index(op.f('ix_zohal_service_logs_user_id'), table_name='zohal_service_logs')
    op.drop_index(op.f('ix_zohal_service_logs_service_id'), table_name='zohal_service_logs')
    op.drop_index(op.f('ix_zohal_service_logs_business_id'), table_name='zohal_service_logs')
    op.drop_table('zohal_service_logs')
    
    op.drop_index(op.f('ix_zohal_services_currency_id'), table_name='zohal_services')
    op.drop_index(op.f('ix_zohal_services_service_category'), table_name='zohal_services')
    op.drop_index(op.f('ix_zohal_services_service_code'), table_name='zohal_services')
    op.drop_table('zohal_services')

