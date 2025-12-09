"""create repair shop tables

Revision ID: 20250205_000001_create_repair_shop_tables
Revises: 
Create Date: 2025-02-05 00:00:01.000000

"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import mysql

# revision identifiers, used by Alembic.
revision = '20250205_000001_create_repair_shop_tables'
down_revision = 'a23683863c8a'  # آخرین migration موجود
branch_labels = None
depends_on = None


def upgrade():
    """ایجاد جداول افزونه مدیریت تعمیرگاه (idempotent)"""
    from sqlalchemy import inspect
    
    bind = op.get_bind()
    inspector = inspect(bind)
    existing_tables = inspector.get_table_names()
    
    # جدول تنظیمات تعمیرگاه
    if 'repair_shop_settings' not in existing_tables:
        op.create_table(
        'repair_shop_settings',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('business_id', sa.Integer(), nullable=False),
        sa.Column('receipt_code_format', sa.String(length=20), nullable=False, server_default='sequential', comment='فرمت کد: random, sequential, custom'),
        sa.Column('receipt_code_prefix', sa.String(length=10), nullable=False, server_default='REC', comment='پیشوند کد رسید'),
        sa.Column('auto_send_sms_on_receive', sa.Boolean(), nullable=False, server_default='0'),
        sa.Column('auto_send_sms_on_status_change', sa.Boolean(), nullable=False, server_default='0'),
        sa.Column('auto_send_email_on_receive', sa.Boolean(), nullable=False, server_default='0'),
        sa.Column('auto_send_email_on_status_change', sa.Boolean(), nullable=False, server_default='0'),
        sa.Column('sms_templates', mysql.JSON(), nullable=True, comment='قالب‌های پیامک'),
        sa.Column('email_templates', mysql.JSON(), nullable=True, comment='قالب‌های ایمیل'),
        sa.Column('default_service_product_id', sa.Integer(), nullable=True, comment='محصول پیش‌فرض خدمات تعمیر'),
        sa.Column('default_warehouse_id', sa.Integer(), nullable=True, comment='انبار پیش‌فرض قطعات'),
        sa.Column('extra_settings', mysql.JSON(), nullable=True, comment='تنظیمات اضافی'),
        sa.Column('created_at', sa.DateTime(), nullable=False, server_default=sa.text('CURRENT_TIMESTAMP')),
        sa.Column('updated_at', sa.DateTime(), nullable=False, server_default=sa.text('CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP')),
        sa.PrimaryKeyConstraint('id'),
        sa.ForeignKeyConstraint(['business_id'], ['businesses.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['default_service_product_id'], ['products.id'], ondelete='SET NULL'),
        sa.ForeignKeyConstraint(['default_warehouse_id'], ['warehouses.id'], ondelete='SET NULL'),
        sa.UniqueConstraint('business_id', name='uq_repair_shop_settings_business'),
        mysql_engine='InnoDB',
        mysql_charset='utf8mb4',
        mysql_collate='utf8mb4_general_ci'
    )
    op.create_index('ix_repair_shop_settings_business_id', 'repair_shop_settings', ['business_id'], unique=True)
    
    # جدول تعمیرکاران
    op.create_table(
        'repair_technicians',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('business_id', sa.Integer(), nullable=False),
        sa.Column('person_id', sa.Integer(), nullable=False, comment='شناسه Person (از جدول اشخاص)'),
        sa.Column('code', sa.String(length=50), nullable=False, comment='کد تعمیرکار'),
        sa.Column('commission_type', sa.String(length=20), nullable=False, server_default='percentage', comment='نوع حق‌الزحمه: fixed, percentage, case_by_case'),
        sa.Column('commission_value', sa.Numeric(precision=18, scale=2), nullable=False, server_default='0', comment='مبلغ فیکس یا درصد'),
        sa.Column('is_active', sa.Boolean(), nullable=False, server_default='1'),
        sa.Column('extra_info', mysql.JSON(), nullable=True, comment='اطلاعات اضافی'),
        sa.Column('created_at', sa.DateTime(), nullable=False, server_default=sa.text('CURRENT_TIMESTAMP')),
        sa.Column('updated_at', sa.DateTime(), nullable=False, server_default=sa.text('CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP')),
        sa.PrimaryKeyConstraint('id'),
        sa.ForeignKeyConstraint(['business_id'], ['businesses.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['person_id'], ['persons.id'], ondelete='RESTRICT'),
        sa.UniqueConstraint('business_id', 'code', name='uq_repair_technicians_business_code'),
        mysql_engine='InnoDB',
        mysql_charset='utf8mb4',
        mysql_collate='utf8mb4_general_ci'
    )
    op.create_index('idx_repair_technicians_business_id', 'repair_technicians', ['business_id'])
    op.create_index('idx_repair_technicians_person_id', 'repair_technicians', ['person_id'])
    op.create_index('idx_repair_technicians_is_active', 'repair_technicians', ['is_active'])
    
    # جدول سفارشات تعمیر
    op.create_table(
        'repair_orders',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('business_id', sa.Integer(), nullable=False),
        sa.Column('code', sa.String(length=50), nullable=False, comment='کد یکتا رسید'),
        sa.Column('customer_person_id', sa.Integer(), nullable=False, comment='مشتری از جدول persons'),
        sa.Column('customer_phone', sa.String(length=20), nullable=True, comment='شماره تماس مشتری'),
        sa.Column('customer_email', sa.String(length=255), nullable=True, comment='ایمیل مشتری'),
        sa.Column('product_id', sa.Integer(), nullable=True, comment='کالا از جدول products'),
        sa.Column('product_name', sa.String(length=255), nullable=False, comment='نام کالا'),
        sa.Column('product_serial', sa.String(length=100), nullable=True, comment='سریال کالا'),
        sa.Column('warranty_code_id', sa.Integer(), nullable=True, comment='کد گارانتی'),
        sa.Column('status', sa.String(length=50), nullable=False, server_default='received', comment='وضعیت'),
        sa.Column('problem_description', sa.Text(), nullable=False, comment='شرح مشکل'),
        sa.Column('customer_notes', sa.Text(), nullable=True, comment='یادداشت مشتری'),
        sa.Column('technician_notes', sa.Text(), nullable=True, comment='یادداشت تعمیرکار'),
        sa.Column('assigned_technician_id', sa.Integer(), nullable=True, comment='تعمیرکار اختصاص داده شده'),
        sa.Column('estimated_cost', sa.Numeric(precision=18, scale=2), nullable=True, comment='هزینه برآوردی'),
        sa.Column('final_cost', sa.Numeric(precision=18, scale=2), nullable=False, server_default='0', comment='هزینه نهایی'),
        sa.Column('parts_cost', sa.Numeric(precision=18, scale=2), nullable=False, server_default='0', comment='هزینه قطعات'),
        sa.Column('labor_cost', sa.Numeric(precision=18, scale=2), nullable=False, server_default='0', comment='دستمزد تعمیر'),
        sa.Column('technician_commission', sa.Numeric(precision=18, scale=2), nullable=False, server_default='0', comment='حق‌الزحمه تعمیرکار'),
        sa.Column('received_at', sa.DateTime(), nullable=False, server_default=sa.text('CURRENT_TIMESTAMP'), comment='تاریخ دریافت'),
        sa.Column('estimated_delivery_at', sa.DateTime(), nullable=True, comment='تاریخ تحویل تقریبی'),
        sa.Column('completed_at', sa.DateTime(), nullable=True, comment='تاریخ اتمام تعمیر'),
        sa.Column('delivered_at', sa.DateTime(), nullable=True, comment='تاریخ تحویل کالا'),
        sa.Column('fiscal_year_id', sa.Integer(), nullable=False),
        sa.Column('currency_id', sa.Integer(), nullable=False),
        sa.Column('created_by_user_id', sa.Integer(), nullable=False),
        sa.Column('extra_info', mysql.JSON(), nullable=True, comment='اطلاعات اضافی'),
        sa.Column('created_at', sa.DateTime(), nullable=False, server_default=sa.text('CURRENT_TIMESTAMP')),
        sa.Column('updated_at', sa.DateTime(), nullable=False, server_default=sa.text('CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP')),
        sa.PrimaryKeyConstraint('id'),
        sa.ForeignKeyConstraint(['business_id'], ['businesses.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['customer_person_id'], ['persons.id'], ondelete='RESTRICT'),
        sa.ForeignKeyConstraint(['product_id'], ['products.id'], ondelete='SET NULL'),
        sa.ForeignKeyConstraint(['warranty_code_id'], ['warranty_codes.id'], ondelete='SET NULL'),
        sa.ForeignKeyConstraint(['assigned_technician_id'], ['repair_technicians.id'], ondelete='SET NULL'),
        sa.ForeignKeyConstraint(['fiscal_year_id'], ['fiscal_years.id'], ondelete='RESTRICT'),
        sa.ForeignKeyConstraint(['currency_id'], ['currencies.id'], ondelete='RESTRICT'),
        sa.ForeignKeyConstraint(['created_by_user_id'], ['users.id'], ondelete='RESTRICT'),
        sa.UniqueConstraint('business_id', 'code', name='uq_repair_orders_business_code'),
        mysql_engine='InnoDB',
        mysql_charset='utf8mb4',
        mysql_collate='utf8mb4_general_ci'
    )
    op.create_index('idx_repair_orders_business_id', 'repair_orders', ['business_id'])
    op.create_index('idx_repair_orders_status', 'repair_orders', ['status'])
    op.create_index('idx_repair_orders_customer', 'repair_orders', ['customer_person_id'])
    op.create_index('idx_repair_orders_technician', 'repair_orders', ['assigned_technician_id'])
    op.create_index('idx_repair_orders_warranty', 'repair_orders', ['warranty_code_id'])
    op.create_index('idx_repair_orders_received_at', 'repair_orders', ['received_at'])
    
    # جدول قطعات استفاده شده
    op.create_table(
        'repair_order_parts',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('repair_order_id', sa.Integer(), nullable=False),
        sa.Column('product_id', sa.Integer(), nullable=False, comment='قطعه از جدول products'),
        sa.Column('quantity', sa.Numeric(precision=18, scale=6), nullable=False, comment='تعداد'),
        sa.Column('unit_price', sa.Numeric(precision=18, scale=2), nullable=False, comment='قیمت واحد'),
        sa.Column('total_price', sa.Numeric(precision=18, scale=2), nullable=False, comment='قیمت کل'),
        sa.Column('warehouse_id', sa.Integer(), nullable=True, comment='انبار خروج قطعه'),
        sa.Column('description', sa.String(length=500), nullable=True, comment='توضیحات'),
        sa.Column('created_at', sa.DateTime(), nullable=False, server_default=sa.text('CURRENT_TIMESTAMP')),
        sa.PrimaryKeyConstraint('id'),
        sa.ForeignKeyConstraint(['repair_order_id'], ['repair_orders.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['product_id'], ['products.id'], ondelete='RESTRICT'),
        sa.ForeignKeyConstraint(['warehouse_id'], ['warehouses.id'], ondelete='SET NULL'),
        mysql_engine='InnoDB',
        mysql_charset='utf8mb4',
        mysql_collate='utf8mb4_general_ci'
    )
    op.create_index('idx_repair_order_parts_repair_order_id', 'repair_order_parts', ['repair_order_id'])
    op.create_index('idx_repair_order_parts_product_id', 'repair_order_parts', ['product_id'])
    
    # جدول تاریخچه وضعیت‌ها
    op.create_table(
        'repair_order_statuses',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('repair_order_id', sa.Integer(), nullable=False),
        sa.Column('status', sa.String(length=50), nullable=False, comment='وضعیت جدید'),
        sa.Column('notes', sa.Text(), nullable=True, comment='یادداشت تغییر وضعیت'),
        sa.Column('created_by_user_id', sa.Integer(), nullable=False),
        sa.Column('created_at', sa.DateTime(), nullable=False, server_default=sa.text('CURRENT_TIMESTAMP')),
        sa.Column('sms_sent', sa.Boolean(), nullable=False, server_default='0', comment='آیا پیامک ارسال شده'),
        sa.Column('sms_sent_at', sa.DateTime(), nullable=True, comment='زمان ارسال پیامک'),
        sa.Column('email_sent', sa.Boolean(), nullable=False, server_default='0', comment='آیا ایمیل ارسال شده'),
        sa.Column('email_sent_at', sa.DateTime(), nullable=True, comment='زمان ارسال ایمیل'),
        sa.PrimaryKeyConstraint('id'),
        sa.ForeignKeyConstraint(['repair_order_id'], ['repair_orders.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['created_by_user_id'], ['users.id'], ondelete='RESTRICT'),
        mysql_engine='InnoDB',
        mysql_charset='utf8mb4',
        mysql_collate='utf8mb4_general_ci'
    )
    op.create_index('idx_repair_order_statuses_repair_order_id', 'repair_order_statuses', ['repair_order_id'])
    op.create_index('idx_repair_order_statuses_created_at', 'repair_order_statuses', ['created_at'])
    
    # جدول ضمائم
    if 'repair_order_attachments' not in existing_tables:
        op.create_table(
            'repair_order_attachments',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('repair_order_id', sa.Integer(), nullable=False),
        sa.Column('file_storage_id', sa.String(length=36), nullable=False, comment='شناسه فایل در file_storage'),
        sa.Column('file_type', sa.String(length=50), nullable=False, comment='نوع فایل: image, video, document'),
        sa.Column('attachment_type', sa.String(length=50), nullable=False, comment='نوع ضمیمه: before_repair, during_repair, after_repair'),
        sa.Column('description', sa.String(length=500), nullable=True, comment='توضیحات'),
        sa.Column('uploaded_by_user_id', sa.Integer(), nullable=False),
        sa.Column('created_at', sa.DateTime(), nullable=False, server_default=sa.text('CURRENT_TIMESTAMP')),
        sa.PrimaryKeyConstraint('id'),
        sa.ForeignKeyConstraint(['repair_order_id'], ['repair_orders.id'], ondelete='CASCADE'),
        # Note: file_storage.id is VARCHAR(36), so we don't add FK constraint here
        sa.ForeignKeyConstraint(['uploaded_by_user_id'], ['users.id'], ondelete='RESTRICT'),
            mysql_engine='InnoDB',
            mysql_charset='utf8mb4',
            mysql_collate='utf8mb4_general_ci'
        )
    op.create_index('idx_repair_order_attachments_repair_order_id', 'repair_order_attachments', ['repair_order_id'])
    op.create_index('idx_repair_order_attachments_type', 'repair_order_attachments', ['attachment_type'])
    op.create_index('idx_repair_order_attachments_file_storage_id', 'repair_order_attachments', ['file_storage_id'])
    
    # جدول لینک به فاکتور
    if 'repair_invoices' not in existing_tables:
        op.create_table(
            'repair_invoices',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('repair_order_id', sa.Integer(), nullable=False, comment='سفارش تعمیر'),
        sa.Column('document_id', sa.Integer(), nullable=False, comment='فاکتور فروش'),
        sa.Column('invoice_type', sa.String(length=50), nullable=False, comment='نوع فاکتور: repair_service, parts_only, both'),
        sa.Column('created_at', sa.DateTime(), nullable=False, server_default=sa.text('CURRENT_TIMESTAMP')),
        sa.PrimaryKeyConstraint('id'),
        sa.ForeignKeyConstraint(['repair_order_id'], ['repair_orders.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['document_id'], ['documents.id'], ondelete='RESTRICT'),
            mysql_engine='InnoDB',
            mysql_charset='utf8mb4',
            mysql_collate='utf8mb4_general_ci'
        )
        op.create_index('idx_repair_invoices_repair_order_id', 'repair_invoices', ['repair_order_id'])
        op.create_index('idx_repair_invoices_document_id', 'repair_invoices', ['document_id'])


def downgrade():
    """حذف جداول افزونه مدیریت تعمیرگاه"""
    op.drop_table('repair_invoices')
    op.drop_table('repair_order_attachments')
    op.drop_table('repair_order_statuses')
    op.drop_table('repair_order_parts')
    op.drop_table('repair_orders')
    op.drop_table('repair_technicians')
    op.drop_table('repair_shop_settings')

