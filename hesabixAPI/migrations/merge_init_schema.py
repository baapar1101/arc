#!/usr/bin/env python3
"""
اسکریپت تبدیل migration های modular init_schema به یک migration واحد
"""

import re
from pathlib import Path

INIT_SCHEMA_DIR = Path(__file__).parent / "versions" / "init_schema"
VERSIONS_DIR = Path(__file__).parent / "versions"
TARGET_FILE = VERSIONS_DIR / "20250101_000000_init_schema.py"


def read_migration_file(file_path: Path) -> str:
    """خواندن محتوای یک فایل migration"""
    content = file_path.read_text(encoding='utf-8')
    
    # Extract upgrade function
    upgrade_match = re.search(r'def upgrade\([^)]*\):\s*(.*?)(?=def downgrade|$)', content, re.DOTALL)
    if upgrade_match:
        return upgrade_match.group(1).strip()
    return ""


def read_downgrade_file(file_path: Path) -> str:
    """خواندن محتوای downgrade یک فایل migration"""
    content = file_path.read_text(encoding='utf-8')
    
    # Extract downgrade function
    downgrade_match = re.search(r'def downgrade\([^)]*\):\s*(.*?)$', content, re.DOTALL)
    if downgrade_match:
        return downgrade_match.group(1).strip()
    return ""


def get_migration_order():
    """خواندن ترتیب migration ها از __init__.py"""
    init_file = INIT_SCHEMA_DIR / "__init__.py"
    content = init_file.read_text(encoding='utf-8')
    
    # Extract MIGRATION_FILES list
    match = re.search(r'MIGRATION_FILES\s*=\s*\[(.*?)\]', content, re.DOTALL)
    if not match:
        return []
    
    files_str = match.group(1)
    # Extract file names
    files = re.findall(r"'([^']+)'", files_str)
    return files


def merge_migrations():
    """ادغام تمام migration های init_schema"""
    print("🔄 ادغام migration های init_schema...\n")
    
    # Get migration order
    migration_files = get_migration_order()
    print(f"📋 پیدا شد {len(migration_files)} migration فایل\n")
    
    # Collect upgrade and downgrade code
    upgrade_code_parts = []
    downgrade_code_parts = []
    
    for module_name in migration_files:
        file_path = INIT_SCHEMA_DIR / f"{module_name}.py"
        if not file_path.exists():
            print(f"⚠️ فایل {module_name}.py پیدا نشد")
            continue
        
        print(f"  📖 خواندن {module_name}.py...")
        upgrade_code = read_migration_file(file_path)
        downgrade_code = read_downgrade_file(file_path)
        
        if upgrade_code:
            upgrade_code_parts.append(f"    # === {module_name} ===")
            # Indent the code
            indented = '\n'.join('    ' + line if line.strip() else line for line in upgrade_code.split('\n'))
            upgrade_code_parts.append(indented)
            upgrade_code_parts.append("")
        
        if downgrade_code:
            downgrade_code_parts.append(f"    # === {module_name} ===")
            # Indent the code
            indented = '\n'.join('    ' + line if line.strip() else line for line in downgrade_code.split('\n'))
            downgrade_code_parts.append(indented)
            downgrade_code_parts.append("")
    
    # Create new migration file
    new_content = f'''"""init schema

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
{chr(10).join(upgrade_code_parts)}


def downgrade() -> None:
    """حذف تمام جداول پایگاه داده"""
{chr(10).join(downgrade_code_parts)}
'''
    
    # Write new file
    TARGET_FILE.write_text(new_content, encoding='utf-8')
    print(f"\n✅ Migration ادغام شده در {TARGET_FILE.name} ذخیره شد")
    
    return len(migration_files)


def main():
    """اجرای اصلی"""
    if not INIT_SCHEMA_DIR.exists():
        print(f"❌ پوشه {INIT_SCHEMA_DIR} پیدا نشد!")
        return
    
    count = merge_migrations()
    print(f"\n✅ {count} migration فایل ادغام شدند")
    print("\n⚠️ برای حذف پوشه init_schema، دستور زیر را اجرا کنید:")
    print(f"   rm -rf {INIT_SCHEMA_DIR}")


if __name__ == "__main__":
    main()


