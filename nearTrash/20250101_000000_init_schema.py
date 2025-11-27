"""init_schema

Revision ID: 20250101_000000
Revises: None
Create Date: 2025-01-01 00:00:00

میگریشن اولیه کامل اسکیما
این میگریشن تمام جداول پایگاه داده را ایجاد می‌کند.
جداول در فایل‌های جداگانه در فولدر init_schema سازماندهی شده‌اند.
"""
from __future__ import annotations

import importlib

# revision identifiers, used by Alembic.
revision = '20250101_000000'
down_revision = None
branch_labels = None
depends_on = None

# لیست فایل‌های میگریشن به ترتیب
MIGRATION_FILES = [
    '01_users',
    '02_currencies',
    '03_businesses',
    '04_persons',
    '05_fiscal_years',
    '06_accounts',
    '07_categories',
    '08_products',
    '09_documents',
    '10_taxes',
    '11_bank_accounts',
    '12_checks',
    '13_warehouse_documents',
    '14_product_bom',
    '15_file_storage',
    '16_support',
    '17_email_config',
    '18_document_numbering',
]


def _load_module(module_name: str):
    """بارگذاری ماژول میگریشن از فولدر init_schema"""
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

