#!/usr/bin/env python3
"""
اسکریپت بازسازی migration ها برای ایجاد یک chain خطی

این اسکریپت:
1. تمام migration ها را به ترتیب زمانی مرتب می‌کند
2. migration های merge را حذف می‌کند
3. down_revision ها را اصلاح می‌کند
4. نام فایل‌ها را استاندارد می‌کند
"""

import os
import re
import shutil
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Tuple, Optional

MIGRATIONS_DIR = Path(__file__).parent / "versions"
BACKUP_DIR = MIGRATIONS_DIR / "backup_before_rebuild"

# Migration های merge که باید حذف شوند
MERGE_MIGRATIONS = {
    '4d60f85a6561',
    'b8c9286db6bd',
    'a23683863c8a',
    '010e36975a45',
    '8cb61ffb0637',
    '20260102_000002_merge_branches_after_4d60f85a6561',
}

# Migration های با نام غیراستاندارد که باید تغییر نام دهند
# Format: old_revision: (new_revision, new_filename)
RENAME_MIGRATIONS = {
    '9cc424e46c07': ('20250128_123300', '20250128_123300_add_quick_sales_settings'),
    '483a0bf37370': ('20250101_010000', '20250101_010000_add_mobile_verified_column'),
    '449131e7b816': ('20250116_010000', '20250116_010000_create_missing_monitoring_and_zohal'),
}


def parse_migration_file(file_path: Path) -> Dict:
    """خواندن اطلاعات یک migration file"""
    content = file_path.read_text(encoding='utf-8')
    
    # Extract revision - handle both formats
    revision = None
    for pattern in [
        r"^revision\s*:\s*str\s*=\s*['\"]([^'\"]+)['\"]",  # with type hint: revision: str = '...'
        r"^revision\s*=\s*['\"]([^'\"]+)['\"]",  # simple format: revision = '...'
    ]:
        revision_match = re.search(pattern, content, re.MULTILINE)
        if revision_match:
            revision = revision_match.group(1)
            break
    
    # Extract down_revision - handle both formats: down_revision = None and down_revision: Union[str, None] = None
    # Try multiple patterns
    down_revision_match = None
    for pattern in [
        r"^down_revision\s*[:\s]*[^=]*=\s*(.+?)(?:\s*#|$)",  # with type hint
        r"^down_revision\s*=\s*(.+?)(?:\s*#|$)",  # simple format
    ]:
        down_revision_match = re.search(pattern, content, re.MULTILINE)
        if down_revision_match:
            break
    
    down_revision_str = down_revision_match.group(1).strip() if down_revision_match else None
    
    # Parse down_revision (could be tuple, string, or None)
    down_revision = None
    if down_revision_str:
        # Remove type hints if present (Union[str, None], etc.)
        down_revision_str = re.sub(r'Union\[[^\]]+\]', '', down_revision_str).strip()
        down_revision_str = down_revision_str.strip()
        
        if down_revision_str in ('None', 'null', ''):
            down_revision = None
        elif '(' in down_revision_str and ',' in down_revision_str:
            # Tuple - extract first element
            tuple_match = re.search(r"\(['\"]([^'\"]+)['\"]", down_revision_str)
            if tuple_match:
                down_revision = tuple_match.group(1)
        else:
            # String value
            down_revision = down_revision_str.strip("'\"")
    
    # Extract create date
    date_match = re.search(r"Create Date:\s*(\d{4}-\d{2}-\d{2})", content)
    create_date = date_match.group(1) if date_match else None
    
    return {
        'file': file_path,
        'revision': revision,
        'down_revision': down_revision,
        'create_date': create_date,
        'content': content,
    }


def get_all_migrations() -> List[Dict]:
    """خواندن تمام migration files"""
    migrations = []
    
    for file_path in MIGRATIONS_DIR.glob("*.py"):
        if file_path.name == "__init__.py" or file_path.name.startswith("backup"):
            continue
        
        try:
            migration = parse_migration_file(file_path)
            if migration['revision']:
                migrations.append(migration)
        except Exception as e:
            print(f"⚠️ خطا در خواندن {file_path.name}: {e}")
    
    return migrations


def build_linear_chain(migrations: List[Dict]) -> List[Dict]:
    """ساخت یک chain خطی از migration ها به ترتیب زمانی"""
    # حذف migration های merge
    migrations = [m for m in migrations if m['revision'] not in MERGE_MIGRATIONS]
    
    # پیدا کردن base migration (init_schema)
    base_migration = next((m for m in migrations if m['revision'] == '20250101_000000'), None)
    if not base_migration:
        # اگر پیدا نشد، migration با down_revision None را پیدا کن
        base_migration = next((m for m in migrations if m['down_revision'] is None or m['down_revision'] == 'None'), None)
    
    if not base_migration:
        print("❌ Base migration پیدا نشد!")
        print(f"Available migrations: {[m['revision'] for m in migrations[:5]]}")
        return []
    
    # ساخت chain خطی - مرتب‌سازی بر اساس تاریخ
    remaining = [m for m in migrations if m['revision'] != base_migration['revision']]
    
    # استخراج تاریخ از revision یا create_date
    def get_sort_key(migration):
        revision = migration['revision']
        # اگر revision به فرمت YYYYMMDD_HHMMSS است، از آن استفاده کن
        match = re.match(r'^(\d{8})_?(\d{6})?', revision)
        if match:
            date_str = match.group(1)  # YYYYMMDD
            time_str = match.group(2) if match.group(2) else '000000'  # HHMMSS
            return (date_str, time_str)
        # در غیر این صورت از create_date استفاده کن
        create_date = migration.get('create_date') or '9999-99-99'
        # تبدیل YYYY-MM-DD به YYYYMMDD
        if '-' in create_date:
            create_date = create_date.replace('-', '')
        return (create_date, '000000')
    
    # مرتب‌سازی بر اساس تاریخ
    remaining.sort(key=get_sort_key)
    
    # ساخت chain: base + بقیه به ترتیب زمانی
    chain = [base_migration] + remaining
    
    return chain


def update_down_revisions(chain: List[Dict]) -> List[Dict]:
    """به‌روزرسانی down_revision ها برای chain خطی"""
    for i, migration in enumerate(chain):
        if i == 0:
            # Base migration
            migration['new_down_revision'] = None
        else:
            # هر migration به migration قبلی وابسته است
            migration['new_down_revision'] = chain[i-1]['revision']
    
    return chain


def rename_migration_file(old_file: Path, new_name: str) -> Path:
    """تغییر نام فایل migration"""
    new_file = old_file.parent / f"{new_name}.py"
    if old_file != new_file:
        shutil.move(str(old_file), str(new_file))
        print(f"✅ تغییر نام: {old_file.name} → {new_file.name}")
    return new_file


def update_migration_content(file_path: Path, new_revision: str, new_down_revision: Optional[str], new_filename: str) -> None:
    """به‌روزرسانی محتوای migration file"""
    content = file_path.read_text(encoding='utf-8')
    
    # Update revision
    content = re.sub(
        r"^revision\s*=\s*['\"][^'\"]+['\"]",
        f"revision = '{new_revision}'",
        content,
        flags=re.MULTILINE
    )
    
    # Update down_revision
    if new_down_revision:
        content = re.sub(
            r"^down_revision\s*=\s*.+",
            f"down_revision = '{new_down_revision}'",
            content,
            flags=re.MULTILINE
        )
    else:
        content = re.sub(
            r"^down_revision\s*=\s*.+",
            "down_revision = None",
            content,
            flags=re.MULTILINE
        )
    
    # Update Create Date comment if needed
    if 'Create Date:' in content:
        now = datetime.now().strftime('%Y-%m-%d %H:%M:%S.%f')[:-3]
        content = re.sub(
            r"Create Date:\s*\d{4}-\d{2}-\d{2}[^\n]*",
            f"Create Date: {now}",
            content
        )
    
    file_path.write_text(content, encoding='utf-8')


def main():
    """اجرای اصلی"""
    import sys
    
    # بررسی flag --apply
    auto_apply = '--apply' in sys.argv or os.getenv('AUTO_APPLY', 'false').lower() == 'true'
    
    print("🚀 شروع بازسازی migration ها...")
    print(f"📁 مسیر: {MIGRATIONS_DIR}")
    if auto_apply:
        print("⚠️ حالت اعمال خودکار فعال است")
    
    # پشتیبان‌گیری
    if BACKUP_DIR.exists():
        shutil.rmtree(BACKUP_DIR)
    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    
    print(f"\n📦 ایجاد پشتیبان در {BACKUP_DIR}...")
    for file_path in MIGRATIONS_DIR.glob("*.py"):
        if file_path.name != "__init__.py":
            shutil.copy2(file_path, BACKUP_DIR / file_path.name)
    print("✅ پشتیبان‌گیری انجام شد")
    
    # خواندن migration ها
    print("\n📖 خواندن migration ها...")
    migrations = get_all_migrations()
    print(f"✅ {len(migrations)} migration پیدا شد")
    
    # ساخت chain خطی
    print("\n🔗 ساخت chain خطی...")
    chain = build_linear_chain(migrations)
    print(f"✅ {len(chain)} migration در chain")
    
    # به‌روزرسانی down_revision ها
    print("\n🔄 به‌روزرسانی down_revision ها...")
    chain = update_down_revisions(chain)
    
    # نمایش chain
    print("\n📋 Chain نهایی:")
    for i, migration in enumerate(chain):
        prev_rev = chain[i-1]['revision'] if i > 0 else None
        print(f"  {i+1}. {migration['revision']} (down: {prev_rev}) - {migration['file'].name}")
    
    # بررسی flag --apply
    if not auto_apply:
        print("\n⚠️ برای اعمال تغییرات، از --apply استفاده کنید")
        print("❌ عملیات لغو شد (برای اعمال خودکار از --apply استفاده کنید)")
        return
    
    # اعمال تغییرات
    print("\n🔧 اعمال تغییرات...")
    
    for i, migration in enumerate(chain):
        file_path = migration['file']
        new_revision = migration['revision']
        new_down_revision = migration.get('new_down_revision')
        
        # تغییر نام اگر نیاز باشد
        if new_revision in RENAME_MIGRATIONS:
            new_rev_id, new_name = RENAME_MIGRATIONS[new_revision]
            file_path = rename_migration_file(file_path, new_name)
            new_revision = new_rev_id
        
        # به‌روزرسانی محتوا
        update_migration_content(file_path, new_revision, new_down_revision, file_path.stem)
        print(f"✅ {file_path.name} به‌روزرسانی شد")
    
    # حذف migration های merge
    print("\n🗑️ حذف migration های merge...")
    for file_path in MIGRATIONS_DIR.glob("*.py"):
        if file_path.name == "__init__.py":
            continue
        
        content = file_path.read_text(encoding='utf-8')
        revision_match = re.search(r"^revision\s*=\s*['\"]([^'\"]+)['\"]", content, re.MULTILINE)
        if revision_match:
            revision = revision_match.group(1)
            if revision in MERGE_MIGRATIONS:
                file_path.unlink()
                print(f"✅ حذف شد: {file_path.name}")
    
    print("\n✅ بازسازی کامل شد!")
    print(f"\n📦 پشتیبان در {BACKUP_DIR} ذخیره شد")


if __name__ == "__main__":
    main()

