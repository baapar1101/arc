#!/usr/bin/env python3
"""
اسکریپت ادغام صحیح migration های init_schema با indentation درست
"""

import re
from pathlib import Path

VERSIONS_DIR = Path(__file__).parent / "versions"
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
    """استخراج body یک function"""
    # Pattern for function definition
    pattern = rf'def\s+{func_name}\s*\([^)]*\)\s*:\s*(.*?)(?=\ndef\s+\w+|$)'
    match = re.search(pattern, content, re.DOTALL)
    if match:
        body = match.group(1).strip()
        # Remove docstring if present
        if body.startswith('"""') or body.startswith("'''"):
            # Find end of docstring
            quote = '"""' if body.startswith('"""') else "'''"
            end_quote = body.find(quote, 3)
            if end_quote != -1:
                body = body[end_quote + 3:].strip()
        return body
    return ""


def fix_indentation(code: str, base_indent: int = 4) -> str:
    """اصلاح indentation کد"""
    lines = code.split('\n')
    fixed_lines = []
    
    for line in lines:
        if not line.strip():
            fixed_lines.append('')
            continue
        
        # Calculate current indentation
        current_indent = len(line) - len(line.lstrip())
        stripped = line.lstrip()
        
        # Skip comments and empty lines
        if stripped.startswith('#'):
            fixed_lines.append(' ' * base_indent + stripped)
        elif stripped:
            # Ensure proper indentation
            fixed_lines.append(' ' * base_indent + stripped)
        else:
            fixed_lines.append('')
    
    return '\n'.join(fixed_lines)


def merge_from_git_history():
    """ادغام migration ها از git history"""
    import subprocess
    
    print("📖 خواندن migration ها از git history...\n")
    
    upgrade_parts = []
    downgrade_parts = []
    
    for module_name in MIGRATION_ORDER:
        file_path = f"migrations/versions/init_schema/{module_name}.py"
        
        try:
            # Try to get file from git
            result = subprocess.run(
                ['git', 'show', f'HEAD:{file_path}'],
                capture_output=True,
                text=True,
                cwd=VERSIONS_DIR.parent.parent
            )
            
            if result.returncode == 0:
                content = result.stdout
                print(f"  ✅ {module_name}.py")
                
                # Extract upgrade
                upgrade_body = extract_function_body(content, 'upgrade')
                if upgrade_body:
                    upgrade_parts.append(f"    # === {module_name} ===")
                    upgrade_parts.append(fix_indentation(upgrade_body, 4))
                    upgrade_parts.append("")
                
                # Extract downgrade
                downgrade_body = extract_function_body(content, 'downgrade')
                if downgrade_body:
                    downgrade_parts.append(f"    # === {module_name} ===")
                    downgrade_parts.append(fix_indentation(downgrade_body, 4))
                    downgrade_parts.append("")
            else:
                print(f"  ⚠️ {module_name}.py (not found in git)")
        except Exception as e:
            print(f"  ❌ {module_name}.py: {e}")
    
    return upgrade_parts, downgrade_parts


def create_merged_migration(upgrade_parts: list, downgrade_parts: list):
    """ایجاد migration ادغام شده"""
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


def main():
    """اجرای اصلی"""
    print("🔄 ادغام migration های init_schema از git history...\n")
    
    upgrade_parts, downgrade_parts = merge_from_git_history()
    
    if not upgrade_parts:
        print("\n❌ هیچ migration پیدا نشد!")
        print("💡 راه حل: فایل‌های init_schema را از git checkout کنید:")
        print("   git checkout HEAD -- migrations/versions/init_schema/")
        return
    
    create_merged_migration(upgrade_parts, downgrade_parts)
    print(f"\n✅ {len(MIGRATION_ORDER)} migration فایل ادغام شدند")


if __name__ == "__main__":
    main()


