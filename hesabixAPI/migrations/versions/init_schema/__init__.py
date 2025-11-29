"""میگریشن اولیه کامل اسکیما

این میگریشن تمام جداول پایگاه داده را ایجاد می‌کند.
جداول در فایل‌های جداگانه سازماندهی شده‌اند برای سهولت بررسی و نگهداری.
"""
from __future__ import annotations

import importlib
import os

# revision identifiers, used by Alembic.
revision = '20250101_000000'
down_revision = None
branch_labels = None
depends_on = None

# لیست فایل‌های میگریشن به ترتیب
MIGRATION_FILES = [
    '01_users',
    '01a_auth_tables',  # جداول احراز هویت (بعد از users چون به users وابسته است)
    '02_currencies',
    '03_businesses',
    '34_business_extras',  # business_print_settings, business_permissions (بعد از businesses)
    '04_persons',
    '35_person_extras',  # person_share_links (بعد از persons)
    '05_fiscal_years',
    '06_accounts',
    '07_categories',
    '08_products',
    '36_product_extras',  # product_instances, product_attributes, product_attribute_links, price_lists, price_items (بعد از products)
    '09_documents',
    '31_invoice_item_line',  # invoice_item_lines (بعد از documents)
    '10_taxes',
    '11_bank_accounts',
    '37_cash_management',  # cash_registers, petty_cash (بعد از currencies و businesses)
    '12_checks',
    '13_warehouse_documents',
    '14_product_bom',
    '15_file_storage',
    '16_support',
    '17_email_config',
    '18_document_numbering',
    '21_ai',  # جداول AI
    '22_activity_log',  # activity_logs
    '23_storage_plan',  # storage_plans, business_storage_subscriptions, storage_invoices, storage_usage_transactions
    '24_document_monetization',  # document_subscription_plans, business_document_subscriptions, document_usage_policies, document_usage_charges, document_usage_periods, document_usage_cursors
    '25_wallet',  # wallet_accounts, wallet_transactions, wallet_payouts, wallet_settings
    '42_zohal',  # zohal_services, zohal_service_logs (بعد از wallet و currencies)
    '26_telegram',  # telegram_link_tokens, telegram_ai_sessions
    '27_system_settings',
    '41_monitoring'  # monitoring_metrics, monitoring_service_status, monitoring_alerts,  # system_settings
    '28_notification',  # notification_templates, user_notification_settings, notification_outbox, notification_delivery_attempts
    '29_marketplace',  # marketplace_plugins, marketplace_plugin_plans, marketplace_orders, marketplace_invoices, business_plugins
    '30_credit',  # business_credit_settings, installment_plan_templates
    '32_report_template',  # report_templates
    '33_announcement',  # announcements, user_announcements
    '38_payment_gateway',  # payment_gateways, business_payment_gateways
    '39_ping_pong',  # ping_pong_scores
    '40_quick_sales_settings',  # quick_sales_settings (بعد از businesses, persons, warehouses, cash_registers, currencies)
    '19_seed_data',  # اطلاعات پایه: پشتیبانی، ارزها، مالیات، تنظیمات
    '20_accounts_chart',  # چارت حساب‌های حسابداری استاندارد
]


def _load_module(module_name: str):
    """بارگذاری ماژول میگریشن"""
    module_path = f'migrations.versions.init_schema.{module_name}'
    return importlib.import_module(module_path)


def upgrade() -> None:
    """اجرای تمام میگریشن‌ها به ترتیب"""
    # ترتیب مهم است - جداول پایه اول
    for module_name in MIGRATION_FILES:
        module = _load_module(module_name)
        module.upgrade()


def downgrade() -> None:
    """حذف تمام جداول به ترتیب معکوس"""
    # ترتیب معکوس برای downgrade
    for module_name in reversed(MIGRATION_FILES):
        module = _load_module(module_name)
        module.downgrade()

