"""جداول مانیتورینگ سیستم"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import mysql


def upgrade():
    # جدول monitoring_metrics
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

    # جدول monitoring_service_status
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

    # جدول monitoring_alerts
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


def downgrade():
    op.drop_index('ix_monitoring_alert_status_created', table_name='monitoring_alerts')
    op.drop_index('ix_monitoring_alerts_created_at', table_name='monitoring_alerts')
    op.drop_index('ix_monitoring_alerts_status', table_name='monitoring_alerts')
    op.drop_index('ix_monitoring_alerts_severity', table_name='monitoring_alerts')
    op.drop_index('ix_monitoring_alerts_alert_type', table_name='monitoring_alerts')
    op.drop_table('monitoring_alerts')
    
    op.drop_index('ix_monitoring_service_name_check', table_name='monitoring_service_status')
    op.drop_index('ix_monitoring_service_status_last_check', table_name='monitoring_service_status')
    op.drop_index('ix_monitoring_service_status_service_name', table_name='monitoring_service_status')
    op.drop_table('monitoring_service_status')
    
    op.drop_index('ix_monitoring_metrics_name_timestamp', table_name='monitoring_metrics')
    op.drop_index('ix_monitoring_metrics_type_timestamp', table_name='monitoring_metrics')
    op.drop_index('ix_monitoring_metrics_timestamp', table_name='monitoring_metrics')
    op.drop_index('ix_monitoring_metrics_metric_name', table_name='monitoring_metrics')
    op.drop_index('ix_monitoring_metrics_metric_type', table_name='monitoring_metrics')
    op.drop_table('monitoring_metrics')

