"""
ایجاد سیستم نوتیفیکیشن جامع برای کسب‌وکارها

این migration شامل:
- business_notification_templates: قالب‌های نوتیفیکیشن هر کسب‌وکار
- notification_event_types: تعریف انواع رویدادها و متغیرهای قابل استفاده
- notification_moderation_queue: صف بررسی و تایید قالب‌ها
- notification_send_logs: لاگ کامل ارسال نوتیفیکیشن‌ها
- notification_daily_stats: آمار روزانه برای Rate Limiting
"""

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import mysql


revision = '20250106_000001'
down_revision = '20250205_000002_seed_repair_shop_plugin'
branch_labels = None
depends_on = None


def upgrade():
    # ================== notification_event_types ==================
    op.create_table(
        'notification_event_types',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        
        # شناسایی
        sa.Column('code', sa.String(100), nullable=False, unique=True, index=True),
        sa.Column('name', sa.String(200), nullable=False),
        sa.Column('description', sa.Text(), nullable=True),
        sa.Column('category', sa.String(50), nullable=True),
        
        # متغیرهای قابل استفاده
        sa.Column('available_variables', mysql.JSON(), nullable=True),
        
        # قالب پیش‌فرض پیشنهادی
        sa.Column('default_sms_template', sa.Text(), nullable=True),
        sa.Column('default_email_template', sa.Text(), nullable=True),
        sa.Column('default_email_subject', sa.String(200), nullable=True),
        
        # وضعیت
        sa.Column('is_active', sa.Boolean(), nullable=False, server_default='1'),
        sa.Column('requires_approval', sa.Boolean(), nullable=False, server_default='1'),
        
        sa.Column('created_at', sa.DateTime(), nullable=False, server_default=sa.text('CURRENT_TIMESTAMP')),
        sa.Column('updated_at', sa.DateTime(), nullable=False, server_default=sa.text('CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP')),
        
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index('ix_event_types_category', 'notification_event_types', ['category'])
    op.create_index('ix_event_types_active', 'notification_event_types', ['is_active'])
    
    # ================== business_notification_templates ==================
    op.create_table(
        'business_notification_templates',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('business_id', sa.Integer(), nullable=False),
        
        # شناسایی قالب
        sa.Column('code', sa.String(100), nullable=False),
        sa.Column('name', sa.String(200), nullable=False),
        sa.Column('description', sa.Text(), nullable=True),
        
        # نوع رویداد و کانال
        sa.Column('event_type', sa.String(100), nullable=False),
        sa.Column('channel', sa.Enum('sms', 'email', name='notification_channel'), nullable=False),
        sa.Column('recipient_type', sa.Enum('customer', 'supplier', 'employee', name='recipient_type'), nullable=False, server_default='customer'),
        
        # محتوای قالب
        sa.Column('subject', sa.String(200), nullable=True),
        sa.Column('body', sa.Text(), nullable=False),
        
        # متغیرهای قابل استفاده
        sa.Column('available_variables', mysql.JSON(), nullable=True),
        
        # وضعیت و تایید
        sa.Column('status', sa.Enum('draft', 'pending_approval', 'approved', 'rejected', 'suspended', name='template_status'), nullable=False, server_default='draft'),
        sa.Column('is_active', sa.Boolean(), nullable=False, server_default='0'),
        
        # اطلاعات تایید
        sa.Column('approval_status', sa.Enum('pending', 'ai_approved', 'admin_approved', 'rejected', name='approval_status'), nullable=False, server_default='pending'),
        sa.Column('approved_by_ai', sa.Boolean(), nullable=False, server_default='0'),
        sa.Column('approved_by_admin_id', sa.Integer(), nullable=True),
        sa.Column('ai_confidence_score', sa.Numeric(5, 2), nullable=True),
        sa.Column('ai_review_notes', sa.Text(), nullable=True),
        sa.Column('admin_review_notes', sa.Text(), nullable=True),
        sa.Column('approved_at', sa.DateTime(), nullable=True),
        sa.Column('rejected_at', sa.DateTime(), nullable=True),
        sa.Column('rejection_reason', sa.Text(), nullable=True),
        
        # محدودیت‌ها
        sa.Column('daily_limit', sa.Integer(), nullable=False, server_default='100'),
        sa.Column('is_automated', sa.Boolean(), nullable=False, server_default='0'),
        
        # متادیتا
        sa.Column('created_by_user_id', sa.Integer(), nullable=False),
        sa.Column('created_at', sa.DateTime(), nullable=False, server_default=sa.text('CURRENT_TIMESTAMP')),
        sa.Column('updated_at', sa.DateTime(), nullable=False, server_default=sa.text('CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP')),
        
        sa.PrimaryKeyConstraint('id'),
        sa.ForeignKeyConstraint(['business_id'], ['businesses.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['approved_by_admin_id'], ['users.id'], ondelete='SET NULL'),
        sa.UniqueConstraint('business_id', 'code', name='uk_business_template_code')
    )
    op.create_index('ix_business_templates_business', 'business_notification_templates', ['business_id'])
    op.create_index('ix_business_templates_event_type', 'business_notification_templates', ['event_type'])
    op.create_index('ix_business_templates_status', 'business_notification_templates', ['status'])
    op.create_index('ix_business_templates_approval', 'business_notification_templates', ['approval_status'])
    op.create_index('ix_business_templates_active', 'business_notification_templates', ['is_active'])
    
    # ================== notification_moderation_queue ==================
    op.create_table(
        'notification_moderation_queue',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        
        sa.Column('template_id', sa.Integer(), nullable=False),
        sa.Column('business_id', sa.Integer(), nullable=False),
        
        # وضعیت بررسی
        sa.Column('status', sa.Enum('pending', 'ai_reviewing', 'ai_reviewed', 'admin_reviewing', 'completed', name='moderation_status'), nullable=False, server_default='pending'),
        
        # نتیجه بررسی AI
        sa.Column('ai_reviewed_at', sa.DateTime(), nullable=True),
        sa.Column('ai_decision', sa.Enum('approve', 'reject', 'review_required', name='ai_decision'), nullable=True),
        sa.Column('ai_confidence', sa.Numeric(5, 2), nullable=True),
        sa.Column('ai_flags', mysql.JSON(), nullable=True),
        sa.Column('ai_suggestions', sa.Text(), nullable=True),
        
        # بررسی مدیر
        sa.Column('admin_reviewed_at', sa.DateTime(), nullable=True),
        sa.Column('reviewed_by_admin_id', sa.Integer(), nullable=True),
        sa.Column('admin_decision', sa.Enum('approve', 'reject', name='admin_decision'), nullable=True),
        sa.Column('admin_notes', sa.Text(), nullable=True),
        
        # اولویت
        sa.Column('priority', sa.Integer(), nullable=False, server_default='0'),
        
        sa.Column('created_at', sa.DateTime(), nullable=False, server_default=sa.text('CURRENT_TIMESTAMP')),
        sa.Column('completed_at', sa.DateTime(), nullable=True),
        
        sa.PrimaryKeyConstraint('id'),
        sa.ForeignKeyConstraint(['template_id'], ['business_notification_templates.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['business_id'], ['businesses.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['reviewed_by_admin_id'], ['users.id'], ondelete='SET NULL')
    )
    op.create_index('ix_moderation_queue_status', 'notification_moderation_queue', ['status'])
    op.create_index('ix_moderation_queue_priority', 'notification_moderation_queue', ['priority'], mysql_length={'priority': None})
    op.create_index('ix_moderation_queue_business', 'notification_moderation_queue', ['business_id'])
    
    # ================== notification_send_logs ==================
    op.create_table(
        'notification_send_logs',
        sa.Column('id', sa.BigInteger(), autoincrement=True, nullable=False),
        
        # شناسایی
        sa.Column('business_id', sa.Integer(), nullable=False),
        sa.Column('template_id', sa.Integer(), nullable=True),
        
        # گیرنده
        sa.Column('recipient_type', sa.Enum('person', 'user', name='recipient_type_enum'), nullable=False),
        sa.Column('recipient_id', sa.Integer(), nullable=False),
        sa.Column('recipient_identifier', sa.String(100), nullable=True),
        
        # محتوا
        sa.Column('channel', sa.Enum('sms', 'email', name='send_channel'), nullable=False),
        sa.Column('subject', sa.String(200), nullable=True),
        sa.Column('body', sa.Text(), nullable=False),
        
        # Context استفاده شده
        sa.Column('context_data', mysql.JSON(), nullable=True),
        
        # وضعیت ارسال
        sa.Column('status', sa.Enum('pending', 'sent', 'failed', 'rejected', name='send_status'), nullable=False, server_default='pending'),
        sa.Column('sent_at', sa.DateTime(), nullable=True),
        sa.Column('failed_at', sa.DateTime(), nullable=True),
        sa.Column('failure_reason', sa.Text(), nullable=True),
        
        # اطلاعات ارسال
        sa.Column('provider_name', sa.String(50), nullable=True),
        sa.Column('provider_message_id', sa.String(200), nullable=True),
        sa.Column('cost', sa.Numeric(10, 2), nullable=True),
        
        # متادیتا
        sa.Column('triggered_by_user_id', sa.Integer(), nullable=True),
        sa.Column('event_type', sa.String(100), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False, server_default=sa.text('CURRENT_TIMESTAMP')),
        
        sa.PrimaryKeyConstraint('id'),
        sa.ForeignKeyConstraint(['business_id'], ['businesses.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['template_id'], ['business_notification_templates.id'], ondelete='SET NULL')
    )
    op.create_index('ix_send_logs_business_date', 'notification_send_logs', ['business_id', 'created_at'])
    op.create_index('ix_send_logs_recipient', 'notification_send_logs', ['recipient_type', 'recipient_id'])
    op.create_index('ix_send_logs_status', 'notification_send_logs', ['status'])
    op.create_index('ix_send_logs_template', 'notification_send_logs', ['template_id'])
    
    # ================== notification_daily_stats ==================
    op.create_table(
        'notification_daily_stats',
        sa.Column('id', sa.BigInteger(), autoincrement=True, nullable=False),
        
        sa.Column('business_id', sa.Integer(), nullable=False),
        sa.Column('template_id', sa.Integer(), nullable=True),
        sa.Column('date', sa.Date(), nullable=False),
        sa.Column('channel', sa.Enum('sms', 'email', name='stats_channel'), nullable=False),
        
        # آمار
        sa.Column('total_sent', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('total_failed', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('total_cost', sa.Numeric(10, 2), nullable=False, server_default='0'),
        
        sa.Column('created_at', sa.DateTime(), nullable=False, server_default=sa.text('CURRENT_TIMESTAMP')),
        sa.Column('updated_at', sa.DateTime(), nullable=False, server_default=sa.text('CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP')),
        
        sa.PrimaryKeyConstraint('id'),
        sa.ForeignKeyConstraint(['business_id'], ['businesses.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['template_id'], ['business_notification_templates.id'], ondelete='SET NULL'),
        sa.UniqueConstraint('business_id', 'template_id', 'date', 'channel', name='uk_daily_stats')
    )
    op.create_index('ix_daily_stats_business_date', 'notification_daily_stats', ['business_id', 'date'])


def downgrade():
    # حذف جداول به ترتیب معکوس
    op.drop_table('notification_daily_stats')
    op.drop_table('notification_send_logs')
    op.drop_table('notification_moderation_queue')
    op.drop_table('business_notification_templates')
    op.drop_table('notification_event_types')
    
    # حذف ENUMs
    op.execute("DROP TYPE IF EXISTS notification_channel")
    op.execute("DROP TYPE IF EXISTS recipient_type")
    op.execute("DROP TYPE IF EXISTS template_status")
    op.execute("DROP TYPE IF EXISTS approval_status")
    op.execute("DROP TYPE IF EXISTS moderation_status")
    op.execute("DROP TYPE IF EXISTS ai_decision")
    op.execute("DROP TYPE IF EXISTS admin_decision")
    op.execute("DROP TYPE IF EXISTS recipient_type_enum")
    op.execute("DROP TYPE IF EXISTS send_channel")
    op.execute("DROP TYPE IF EXISTS send_status")
    op.execute("DROP TYPE IF EXISTS stats_channel")

