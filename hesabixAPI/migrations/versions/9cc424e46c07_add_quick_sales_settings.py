"""add_quick_sales_settings

Revision ID: 9cc424e46c07
Revises: 20250112_000000
Create Date: 2025-01-28 12:33:00.000000

"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import mysql
from sqlalchemy import inspect


# revision identifiers, used by Alembic.
revision = '9cc424e46c07'
down_revision = '20250112_000000'
branch_labels = None
depends_on = None


def upgrade() -> None:
    """ایجاد جدول quick_sales_settings در صورت عدم وجود"""
    conn = op.get_bind()
    inspector = inspect(conn)
    
    # بررسی وجود جدول quick_sales_settings
    tables = inspector.get_table_names()
    if 'quick_sales_settings' not in tables:
        # جدول quick_sales_settings
        op.create_table(
        'quick_sales_settings',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('business_id', sa.Integer(), nullable=False),
        sa.Column('default_anonymous_customer_id', sa.Integer(), nullable=True, comment='شناسه مشتری پیش‌فرض برای فروش ناشناس'),
        sa.Column('auto_create_anonymous_customer', sa.Boolean(), nullable=False, server_default='1', comment='ایجاد خودکار مشتری ناشناس در صورت عدم وجود'),
        sa.Column('anonymous_customer_name', sa.String(length=255), nullable=True, comment='نام مشتری ناشناس'),
        sa.Column('default_warehouse_id', sa.Integer(), nullable=True, comment='انبار پیش‌فرض برای فروش سریع'),
        sa.Column('default_cash_register_id', sa.Integer(), nullable=True, comment='صندوق پیش‌فرض برای پرداخت نقدی'),
        sa.Column('default_currency_id', sa.Integer(), nullable=True, comment='ارز پیش‌فرض برای فاکتورهای فروش سریع'),
        sa.Column('auto_print', sa.Boolean(), nullable=False, server_default='0', comment='چاپ خودکار پس از ثبت'),
        sa.Column('print_template_id', sa.Integer(), nullable=True, comment='قالب چاپ پیش‌فرض'),
        sa.Column('auto_post_warehouse', sa.Boolean(), nullable=False, server_default='1', comment='قطعی خودکار حواله انبار'),
        sa.Column('show_inventory', sa.Boolean(), nullable=False, server_default='1', comment='نمایش موجودی در صفحه فروش سریع'),
        sa.Column('auto_create_payment_document', sa.Boolean(), nullable=False, server_default='1', comment='ثبت خودکار سند پرداخت جداگانه'),
        sa.Column('show_purchase_price', sa.Boolean(), nullable=False, server_default='0', comment='نمایش قیمت خرید'),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['business_id'], ['businesses.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['default_anonymous_customer_id'], ['persons.id'], ondelete='SET NULL'),
        sa.ForeignKeyConstraint(['default_warehouse_id'], ['warehouses.id'], ondelete='SET NULL'),
        sa.ForeignKeyConstraint(['default_cash_register_id'], ['cash_registers.id'], ondelete='SET NULL'),
        sa.ForeignKeyConstraint(['default_currency_id'], ['currencies.id'], ondelete='SET NULL'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('business_id', name='uq_quick_sales_settings_business')
        )
    
    # بررسی وجود ایندکس
    if 'quick_sales_settings' in tables:
        indexes = [idx['name'] for idx in inspector.get_indexes('quick_sales_settings')]
        if 'ix_quick_sales_settings_business_id' not in indexes:
            op.create_index(op.f('ix_quick_sales_settings_business_id'), 'quick_sales_settings', ['business_id'], unique=False)


def downgrade() -> None:
    op.drop_index(op.f('ix_quick_sales_settings_business_id'), table_name='quick_sales_settings')
    op.drop_table('quick_sales_settings')
