#!/usr/bin/env python3
"""
اسکریپت ادغام صحیح migration های init_schema با indentation درست
"""

import re
from pathlib import Path

VERSIONS_DIR = Path(__file__).parent / "versions"
INIT_SCHEMA_DIR = VERSIONS_DIR / "init_schema"
TARGET_FILE = VERSIONS_DIR / "20250101_000000_init_schema.py"

# ترتیب migration ها (از __init__.py)
MIGRATION_ORDER = [
    '01_users',
    '01a_auth_tables',
    '02_currencies',
    '03_businesses',
    '34_business_extras',
    '04_persons',
    '35_person_extras',
    '05_fiscal_years',
    '06_accounts',
    '07_categories',
    '08_products',
    '36_product_extras',
    '09_documents',
    '31_invoice_item_line',
    '10_taxes',
    '11_bank_accounts',
    '37_cash_management',
    '12_checks',
    '13_warehouse_documents',
    '14_product_bom',
    '15_file_storage',
    '16_support',
    '17_email_config',
    '18_document_numbering',
    '21_ai',
    '22_activity_log',
    '23_storage_plan',
    '24_document_monetization',
    '25_wallet',
    '42_zohal',
    '26_telegram',
    '27_system_settings',
    '41_monitoring',
    '28_notification',
    '29_marketplace',
    '30_credit',
    '32_report_template',
    '33_announcement',
    '38_payment_gateway',
    '39_ping_pong',
    '40_quick_sales_settings',
    '19_seed_data',
    '20_accounts_chart',
    '43_fix_zohal_account_code',
]


def extract_function_body(content: str, func_name: str) -> str:
    """استخراج body یک function با حفظ indentation"""
    # Pattern for function definition
    pattern = rf'def\s+{func_name}\s*\([^)]*\)\s*:\s*(.*?)(?=\ndef\s+\w+|$)'
    match = re.search(pattern, content, re.DOTALL)
    if match:
        body = match.group(1).strip()
        # Remove docstring if present
        if body.startswith('"""') or body.startswith("'''"):
            quote = '"""' if body.startswith('"""') else "'''"
            end_quote = body.find(quote, 3)
            if end_quote != -1:
                body = body[end_quote + 3:].strip()
        return body
    return ""


def normalize_indentation(code: str, target_indent: int = 4) -> str:
    """نرمال‌سازی indentation کد"""
    if not code.strip():
        return ""
    
    lines = code.split('\n')
    if not lines:
        return ""
    
    # Find minimum indentation (excluding empty lines)
    min_indent = float('inf')
    for line in lines:
        if line.strip():
            indent = len(line) - len(line.lstrip())
            min_indent = min(min_indent, indent)
    
    if min_indent == float('inf'):
        min_indent = 0
    
    # Normalize to target_indent
    fixed_lines = []
    for line in lines:
        if not line.strip():
            fixed_lines.append('')
        else:
            current_indent = len(line) - len(line.lstrip())
            # Calculate relative indent
            relative_indent = current_indent - min_indent
            new_indent = target_indent + relative_indent
            fixed_lines.append(' ' * new_indent + line.lstrip())
    
    return '\n'.join(fixed_lines)


def merge_migrations():
    """ادغام migration ها"""
    print("🔄 ادغام migration های init_schema...\n")
    
    if not INIT_SCHEMA_DIR.exists():
        print(f"❌ پوشه {INIT_SCHEMA_DIR} پیدا نشد!")
        return
    
    upgrade_parts = []
    downgrade_parts = []
    
    for module_name in MIGRATION_ORDER:
        file_path = INIT_SCHEMA_DIR / f"{module_name}.py"
        
        if not file_path.exists():
            print(f"  ⚠️ {module_name}.py (not found)")
            continue
        
        print(f"  📖 {module_name}.py")
        content = file_path.read_text(encoding='utf-8')
        
        # Extract upgrade
        upgrade_body = extract_function_body(content, 'upgrade')
        if upgrade_body:
            upgrade_parts.append(f"    # === {module_name} ===")
            normalized = normalize_indentation(upgrade_body, 4)
            upgrade_parts.append(normalized)
            upgrade_parts.append("")
        
        # Extract downgrade
        downgrade_body = extract_function_body(content, 'downgrade')
        if downgrade_body:
            downgrade_parts.append(f"    # === {module_name} ===")
            normalized = normalize_indentation(downgrade_body, 4)
            downgrade_parts.append(normalized)
            downgrade_parts.append("")
    
    # Create merged migration
    upgrade_code = '\n'.join(upgrade_parts)
    downgrade_code = '\n'.join(downgrade_parts)
    
    content = f'''"""init schema

Revision ID: 20250101_000000
Revises: 
Create Date: 2025-01-01 00:00:00.000000

این migration تمام جداول پایگاه داده را ایجاد می‌کند.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = '20250101_000000'
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """ایجاد تمام جداول پایگاه داده"""
{upgrade_code}


def downgrade() -> None:
    """حذف تمام جداول پایگاه داده"""
{downgrade_code}
'''
    
    TARGET_FILE.write_text(content, encoding='utf-8')
    print(f"\n✅ Migration ادغام شده در {TARGET_FILE.name} ذخیره شد")
    print(f"   - Upgrade: {len(upgrade_parts)} بخش")
    print(f"   - Downgrade: {len(downgrade_parts)} بخش")


def main():
    """اجرای اصلی"""
    merge_migrations()
    
    # Test syntax
    print("\n🔍 بررسی syntax...")
    import py_compile
    try:
        py_compile.compile(str(TARGET_FILE), doraise=True)
        print("✅ Syntax صحیح است!")
    except py_compile.PyCompileError as e:
        print(f"❌ خطای syntax: {e}")
        print("⚠️ نیاز به بررسی دستی indentation")


if __name__ == "__main__":
    main()


