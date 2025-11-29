"""create_missing_monitoring_and_zohal_tables

Revision ID: 449131e7b816
Revises: 010e36975a45
Create Date: 2025-11-29 15:25:50.132435

"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy import inspect


# revision identifiers, used by Alembic.
revision = '449131e7b816'
down_revision = '010e36975a45'
branch_labels = None
depends_on = None


def _table_exists(table_name: str) -> bool:
    """بررسی وجود جدول"""
    bind = op.get_bind()
    inspector = inspect(bind)
    return table_name in inspector.get_table_names()


def upgrade() -> None:
    # جداول monitoring
    if not _table_exists('monitoring_metrics'):
        op.create_table(
            'monitoring_metrics',
            sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
            sa.Column('metric_type', sa.String(length=50), nullable=False),
            sa.Column('metric_name', sa.String(length=100), nullable=False),
            sa.Column('value', sa.Numeric(precision=15, scale=2), nullable=False),
            sa.Column('unit', sa.String(length=20), nullable=True),
            sa.Column('timestamp', sa.DateTime(), nullable=False),
            sa.Column('extra_data', sa.JSON(), nullable=True),
            sa.PrimaryKeyConstraint('id')
        )
        op.create_index('ix_monitoring_metrics_metric_type', 'monitoring_metrics', ['metric_type'])
        op.create_index('ix_monitoring_metrics_metric_name', 'monitoring_metrics', ['metric_name'])
        op.create_index('ix_monitoring_metrics_timestamp', 'monitoring_metrics', ['timestamp'])
        op.create_index('ix_monitoring_metrics_type_timestamp', 'monitoring_metrics', ['metric_type', 'timestamp'])
        op.create_index('ix_monitoring_metrics_name_timestamp', 'monitoring_metrics', ['metric_name', 'timestamp'])

    if not _table_exists('monitoring_service_status'):
        op.create_table(
            'monitoring_service_status',
            sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
            sa.Column('service_name', sa.String(length=50), nullable=False),
            sa.Column('status', sa.String(length=20), nullable=False),
            sa.Column('uptime_seconds', sa.Integer(), nullable=True),
            sa.Column('version', sa.String(length=50), nullable=True),
            sa.Column('extra_data', sa.JSON(), nullable=True),
            sa.Column('last_check', sa.DateTime(), nullable=False),
            sa.PrimaryKeyConstraint('id')
        )
        op.create_index('ix_monitoring_service_status_service_name', 'monitoring_service_status', ['service_name'])
        op.create_index('ix_monitoring_service_status_last_check', 'monitoring_service_status', ['last_check'])
        op.create_index('ix_monitoring_service_name_check', 'monitoring_service_status', ['service_name', 'last_check'])

    if not _table_exists('monitoring_alerts'):
        op.create_table(
            'monitoring_alerts',
            sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
            sa.Column('alert_type', sa.String(length=50), nullable=False),
            sa.Column('severity', sa.String(length=20), nullable=False),
            sa.Column('title', sa.String(length=200), nullable=False),
            sa.Column('message', sa.Text(), nullable=True),
            sa.Column('metric_name', sa.String(length=100), nullable=True),
            sa.Column('threshold_value', sa.Numeric(precision=15, scale=2), nullable=True),
            sa.Column('current_value', sa.Numeric(precision=15, scale=2), nullable=True),
            sa.Column('status', sa.String(length=20), nullable=False, server_default='active'),
            sa.Column('created_at', sa.DateTime(), nullable=False),
            sa.Column('acknowledged_at', sa.DateTime(), nullable=True),
            sa.Column('acknowledged_by', sa.Integer(), nullable=True),
            sa.Column('resolved_at', sa.DateTime(), nullable=True),
            sa.PrimaryKeyConstraint('id')
        )
        op.create_index('ix_monitoring_alerts_alert_type', 'monitoring_alerts', ['alert_type'])
        op.create_index('ix_monitoring_alerts_severity', 'monitoring_alerts', ['severity'])
        op.create_index('ix_monitoring_alerts_status', 'monitoring_alerts', ['status'])
        op.create_index('ix_monitoring_alerts_created_at', 'monitoring_alerts', ['created_at'])
        op.create_index('ix_monitoring_alert_status_created', 'monitoring_alerts', ['status', 'created_at'])

    # جداول zohal
    if not _table_exists('zohal_services'):
        op.create_table(
            'zohal_services',
            sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
            sa.Column('service_code', sa.String(length=100), nullable=False),
            sa.Column('service_path', sa.String(length=255), nullable=False),
            sa.Column('service_name', sa.String(length=255), nullable=False),
            sa.Column('service_category', sa.String(length=50), nullable=False),
            sa.Column('description', sa.Text(), nullable=True),
            sa.Column('is_active', sa.Boolean(), nullable=False, server_default='1'),
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

    if not _table_exists('zohal_service_logs'):
        op.create_table(
            'zohal_service_logs',
            sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
            sa.Column('business_id', sa.Integer(), nullable=False),
            sa.Column('service_id', sa.Integer(), nullable=False),
            sa.Column('user_id', sa.Integer(), nullable=True),
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


def downgrade() -> None:
    if _table_exists('zohal_service_logs'):
        op.drop_index(op.f('ix_zohal_service_logs_status'), table_name='zohal_service_logs')
        op.drop_index(op.f('ix_zohal_service_logs_created_at'), table_name='zohal_service_logs')
        op.drop_index(op.f('ix_zohal_service_logs_document_id'), table_name='zohal_service_logs')
        op.drop_index(op.f('ix_zohal_service_logs_wallet_transaction_id'), table_name='zohal_service_logs')
        op.drop_index(op.f('ix_zohal_service_logs_currency_id'), table_name='zohal_service_logs')
        op.drop_index(op.f('ix_zohal_service_logs_user_id'), table_name='zohal_service_logs')
        op.drop_index(op.f('ix_zohal_service_logs_service_id'), table_name='zohal_service_logs')
        op.drop_index(op.f('ix_zohal_service_logs_business_id'), table_name='zohal_service_logs')
        op.drop_table('zohal_service_logs')
    
    if _table_exists('zohal_services'):
        op.drop_index(op.f('ix_zohal_services_currency_id'), table_name='zohal_services')
        op.drop_index(op.f('ix_zohal_services_service_category'), table_name='zohal_services')
        op.drop_index(op.f('ix_zohal_services_service_code'), table_name='zohal_services')
        op.drop_table('zohal_services')
    
    if _table_exists('monitoring_alerts'):
        op.drop_index('ix_monitoring_alert_status_created', table_name='monitoring_alerts')
        op.drop_index('ix_monitoring_alerts_created_at', table_name='monitoring_alerts')
        op.drop_index('ix_monitoring_alerts_status', table_name='monitoring_alerts')
        op.drop_index('ix_monitoring_alerts_severity', table_name='monitoring_alerts')
        op.drop_index('ix_monitoring_alerts_alert_type', table_name='monitoring_alerts')
        op.drop_table('monitoring_alerts')
    
    if _table_exists('monitoring_service_status'):
        op.drop_index('ix_monitoring_service_name_check', table_name='monitoring_service_status')
        op.drop_index('ix_monitoring_service_status_last_check', table_name='monitoring_service_status')
        op.drop_index('ix_monitoring_service_status_service_name', table_name='monitoring_service_status')
        op.drop_table('monitoring_service_status')
    
    if _table_exists('monitoring_metrics'):
        op.drop_index('ix_monitoring_metrics_name_timestamp', table_name='monitoring_metrics')
        op.drop_index('ix_monitoring_metrics_type_timestamp', table_name='monitoring_metrics')
        op.drop_index('ix_monitoring_metrics_timestamp', table_name='monitoring_metrics')
        op.drop_index('ix_monitoring_metrics_metric_name', table_name='monitoring_metrics')
        op.drop_index('ix_monitoring_metrics_metric_type', table_name='monitoring_metrics')
        op.drop_table('monitoring_metrics')
