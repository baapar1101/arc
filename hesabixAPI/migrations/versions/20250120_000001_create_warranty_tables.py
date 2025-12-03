"""ایجاد جداول سیستم گارانتی

revision: 20250120_000001_create_warranty_tables
down_revision: 20250119_000001
branch_labels: None
depends_on: None

این میگریشن جداول زیر را ایجاد می‌کند:
1. warranty_codes - کدهای گارانتی
2. warranty_settings - تنظیمات گارانتی برای هر کسب و کار
3. warranty_activations - فعال‌سازی‌های گارانتی
4. warranty_tracking - تاریخچه رهگیری گارانتی
5. warranty_tracking_links - لینک‌های رهگیری یکتا برای Person
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.mysql import JSON


# revision identifiers, used by Alembic.
revision = '20250120_000001'
down_revision = '20250119_000001'
branch_labels = None
depends_on = None


def upgrade():
    # جدول warranty_settings
    op.create_table(
        'warranty_settings',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('business_id', sa.Integer(), nullable=False),
        sa.Column('code_format', sa.String(20), nullable=False, server_default='random', comment='فرمت کد: random, sequential, custom'),
        sa.Column('code_prefix', sa.String(20), nullable=True, server_default='WR', comment='پیشوند کد'),
        sa.Column('serial_format', sa.String(20), nullable=False, server_default='random', comment='فرمت سریال: random, custom'),
        sa.Column('serial_length', sa.Integer(), nullable=True, server_default='12', comment='طول سریال برای رندوم'),
        sa.Column('require_serial_verification', sa.Boolean(), nullable=False, server_default='0', comment='نیاز به تأیید سریال کالا'),
        sa.Column('require_product_instance_match', sa.Boolean(), nullable=False, server_default='0', comment='نیاز به تطابق با product_instance'),
        sa.Column('max_activation_attempts', sa.Integer(), nullable=True, comment='حداکثر تلاش برای فعال‌سازی'),
        sa.Column('activation_lockout_duration_minutes', sa.Integer(), nullable=True, comment='مدت قفل شدن پس از تلاش‌های ناموفق'),
        sa.Column('require_customer_registration', sa.Boolean(), nullable=False, server_default='0', comment='الزام ثبت مشتری در سیستم'),
        sa.Column('auto_link_to_person', sa.Boolean(), nullable=False, server_default='1', comment='اتصال خودکار به Person'),
        sa.Column('enable_tracking_link', sa.Boolean(), nullable=False, server_default='1', comment='فعال‌سازی لینک رهگیری'),
        sa.Column('tracking_link_expires_days', sa.Integer(), nullable=True, comment='مدت اعتبار لینک رهگیری'),
        sa.Column('enable_sms_notification', sa.Boolean(), nullable=False, server_default='0', comment='ارسال SMS هنگام فعال‌سازی'),
        sa.Column('enable_email_notification', sa.Boolean(), nullable=False, server_default='0', comment='ارسال ایمیل هنگام فعال‌سازی'),
        sa.Column('security_features', sa.JSON(), nullable=True, comment='تنظیمات امنیتی'),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['business_id'], ['businesses.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('business_id', name='uq_warranty_settings_business')
    )
    op.create_index(op.f('ix_warranty_settings_business_id'), 'warranty_settings', ['business_id'], unique=True)

    # جدول warranty_codes
    op.create_table(
        'warranty_codes',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('business_id', sa.Integer(), nullable=False),
        sa.Column('code', sa.String(50), nullable=False, comment='کد گارانتی یکتا'),
        sa.Column('warranty_serial', sa.String(50), nullable=False, comment='سریال گارانتی یکتا'),
        sa.Column('product_id', sa.Integer(), nullable=False),
        sa.Column('product_instance_id', sa.Integer(), nullable=True, comment='شناسه instance کالا (بعد از فعال‌سازی)'),
        sa.Column('status', sa.String(20), nullable=False, server_default='generated', comment='وضعیت: generated, activated, expired, used, revoked'),
        sa.Column('generated_by_user_id', sa.Integer(), nullable=True),
        sa.Column('generated_at', sa.DateTime(), nullable=False),
        sa.Column('activated_at', sa.DateTime(), nullable=True),
        sa.Column('activated_by_person_id', sa.Integer(), nullable=True, comment='شناسه Person مشتری'),
        sa.Column('activated_by_customer_info', sa.JSON(), nullable=True, comment='اطلاعات مشتری غیرثبت‌شده'),
        sa.Column('expires_at', sa.DateTime(), nullable=True),
        sa.Column('warranty_duration_days', sa.Integer(), nullable=False, comment='مدت گارانتی به روز'),
        sa.Column('tracking_link_code', sa.String(50), nullable=True, comment='کد یکتا برای لینک رهگیری'),
        sa.Column('metadata', sa.JSON(), nullable=True, comment='اطلاعات اضافی'),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['business_id'], ['businesses.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['product_id'], ['products.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['product_instance_id'], ['product_instances.id'], ondelete='SET NULL'),
        sa.ForeignKeyConstraint(['generated_by_user_id'], ['users.id'], ondelete='SET NULL'),
        sa.ForeignKeyConstraint(['activated_by_person_id'], ['persons.id'], ondelete='SET NULL'),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_warranty_codes_business_id'), 'warranty_codes', ['business_id'], unique=False)
    op.create_index(op.f('ix_warranty_codes_code'), 'warranty_codes', ['code'], unique=True)
    op.create_index(op.f('ix_warranty_codes_warranty_serial'), 'warranty_codes', ['business_id', 'warranty_serial'], unique=True)
    op.create_index(op.f('ix_warranty_codes_product_id'), 'warranty_codes', ['product_id'], unique=False)
    op.create_index(op.f('ix_warranty_codes_status'), 'warranty_codes', ['status'], unique=False)
    op.create_index(op.f('ix_warranty_codes_tracking_link_code'), 'warranty_codes', ['tracking_link_code'], unique=False)

    # جدول warranty_activations
    op.create_table(
        'warranty_activations',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('warranty_code_id', sa.Integer(), nullable=False),
        sa.Column('person_id', sa.Integer(), nullable=True),
        sa.Column('product_instance_id', sa.Integer(), nullable=True),
        sa.Column('warranty_serial', sa.String(50), nullable=False, comment='سریال گارانتی وارد شده'),
        sa.Column('product_serial', sa.String(128), nullable=True, comment='سریال کالا وارد شده'),
        sa.Column('customer_name', sa.String(255), nullable=False),
        sa.Column('customer_phone', sa.String(20), nullable=False),
        sa.Column('customer_email', sa.String(255), nullable=True),
        sa.Column('activation_date', sa.DateTime(), nullable=False),
        sa.Column('ip_address', sa.String(45), nullable=True),
        sa.Column('user_agent', sa.Text(), nullable=True),
        sa.Column('verification_method', sa.String(50), nullable=True, comment='روش تأیید: serial_match, product_instance_match, manual'),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['warranty_code_id'], ['warranty_codes.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['person_id'], ['persons.id'], ondelete='SET NULL'),
        sa.ForeignKeyConstraint(['product_instance_id'], ['product_instances.id'], ondelete='SET NULL'),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_warranty_activations_warranty_code_id'), 'warranty_activations', ['warranty_code_id'], unique=False)
    op.create_index(op.f('ix_warranty_activations_person_id'), 'warranty_activations', ['person_id'], unique=False)

    # جدول warranty_tracking
    op.create_table(
        'warranty_tracking',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('warranty_code_id', sa.Integer(), nullable=False),
        sa.Column('product_instance_id', sa.Integer(), nullable=True),
        sa.Column('person_id', sa.Integer(), nullable=True),
        sa.Column('event_type', sa.String(50), nullable=False, comment='نوع رویداد: activation, repair_request, repair_completed, replacement, expired, revoked'),
        sa.Column('description', sa.Text(), nullable=True),
        sa.Column('performed_by_user_id', sa.Integer(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['warranty_code_id'], ['warranty_codes.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['product_instance_id'], ['product_instances.id'], ondelete='SET NULL'),
        sa.ForeignKeyConstraint(['person_id'], ['persons.id'], ondelete='SET NULL'),
        sa.ForeignKeyConstraint(['performed_by_user_id'], ['users.id'], ondelete='SET NULL'),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_warranty_tracking_warranty_code_id'), 'warranty_tracking', ['warranty_code_id'], unique=False)
    op.create_index(op.f('ix_warranty_tracking_person_id'), 'warranty_tracking', ['person_id'], unique=False)
    op.create_index(op.f('ix_warranty_tracking_event_type'), 'warranty_tracking', ['event_type'], unique=False)

    # جدول warranty_tracking_links
    op.create_table(
        'warranty_tracking_links',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('warranty_code_id', sa.Integer(), nullable=False),
        sa.Column('person_id', sa.Integer(), nullable=False),
        sa.Column('link_code', sa.String(50), nullable=False, comment='کد یکتا لینک'),
        sa.Column('expires_at', sa.DateTime(), nullable=True, comment='تاریخ انقضا'),
        sa.Column('is_active', sa.Boolean(), nullable=False, server_default='1'),
        sa.Column('access_count', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('last_accessed_at', sa.DateTime(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['warranty_code_id'], ['warranty_codes.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['person_id'], ['persons.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_warranty_tracking_links_link_code'), 'warranty_tracking_links', ['link_code'], unique=True)
    op.create_index(op.f('ix_warranty_tracking_links_person_id'), 'warranty_tracking_links', ['person_id'], unique=False)
    op.create_index(op.f('ix_warranty_tracking_links_warranty_code_id'), 'warranty_tracking_links', ['warranty_code_id'], unique=False)


def downgrade():
    op.drop_table('warranty_tracking_links')
    op.drop_table('warranty_tracking')
    op.drop_table('warranty_activations')
    op.drop_table('warranty_codes')
    op.drop_table('warranty_settings')

