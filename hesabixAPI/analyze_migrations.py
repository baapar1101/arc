#!/usr/bin/env python3
"""
اسکریپت تحلیل migration ها برای یافتن مشکلات چند head و down_revision های اشتباه
"""
import re
from pathlib import Path
from collections import defaultdict

MIGRATIONS_DIR = Path(__file__).parent / "migrations" / "versions"

def parse_migration_file(filepath):
    """پارس کردن یک فایل migration و استخراج revision و down_revision"""
    content = filepath.read_text(encoding='utf-8')
    
    # استخراج revision
    revision_match = re.search(r"^revision\s*=\s*['\"]([^'\"]+)['\"]", content, re.MULTILINE)
    revision = revision_match.group(1) if revision_match else None
    
    # استخراج down_revision (می‌تواند string یا tuple باشد)
    down_revision = None
    # حالت 1: down_revision = 'string'
    down_match = re.search(r"^down_revision\s*=\s*['\"]([^'\"]+)['\"]", content, re.MULTILINE)
    if down_match:
        down_revision = down_match.group(1)
    else:
        # حالت 2: down_revision = ('rev1', 'rev2', ...)
        tuple_match = re.search(r"^down_revision\s*=\s*\(([^)]+)\)", content, re.MULTILINE)
        if tuple_match:
            # استخراج revision های داخل tuple
            tuple_content = tuple_match.group(1)
            revisions = re.findall(r"['\"]([^'\"]+)['\"]", tuple_content)
            down_revision = tuple(revisions) if revisions else None
    
    return {
        'revision': revision,
        'down_revision': down_revision,
        'file': filepath.name
    }

def analyze_migrations():
    """تحلیل تمام migration ها"""
    migrations = {}
    children = defaultdict(list)
    
    # خواندن تمام فایل‌های Python (به جز __init__.py و __pycache__)
    for filepath in MIGRATIONS_DIR.rglob("*.py"):
        if filepath.name.startswith("__"):
            continue
        
        try:
            info = parse_migration_file(filepath)
            if info['revision']:
                migrations[info['revision']] = info
                
                # ثبت children
                if info['down_revision']:
                    if isinstance(info['down_revision'], tuple):
                        for parent in info['down_revision']:
                            children[parent].append(info['revision'])
                    else:
                        children[info['down_revision']].append(info['revision'])
        except Exception as e:
            print(f"⚠️ خطا در خواندن {filepath.name}: {e}")
    
    # یافتن headها (migration هایی که هیچ کس از آن‌ها استفاده نمی‌کند)
    heads = []
    for revision, info in migrations.items():
        if revision not in children:
            heads.append(revision)
    
    # یافتن migration هایی با down_revision اشتباه
    missing_parents = []
    for revision, info in migrations.items():
        if info['down_revision']:
            if isinstance(info['down_revision'], tuple):
                for parent in info['down_revision']:
                    if parent not in migrations:
                        missing_parents.append((revision, parent))
            else:
                if info['down_revision'] not in migrations:
                    missing_parents.append((revision, info['down_revision']))
    
    return migrations, children, heads, missing_parents

def main():
    print("🔍 در حال تحلیل migration ها...\n")
    
    migrations, children, heads, missing_parents = analyze_migrations()
    
    print(f"📊 تعداد migration ها: {len(migrations)}\n")
    
    # نمایش headها
    print(f"📌 Headهای موجود ({len(heads)}):")
    for head in sorted(heads):
        info = migrations[head]
        print(f"  - {head} ({info['file']})")
    
    if len(heads) > 1:
        print(f"\n⚠️ مشکل: {len(heads)} head وجود دارد! باید merge شوند.")
    
    # نمایش missing parents
    if missing_parents:
        print(f"\n❌ Migration هایی با down_revision نامعتبر ({len(missing_parents)}):")
        for child, parent in missing_parents:
            info = migrations[child]
            print(f"  - {child} ({info['file']})")
            print(f"    down_revision = {parent} (وجود ندارد!)")
    
    # بررسی مشکلات خاص
    print("\n🔎 بررسی مشکلات خاص:\n")
    
    # بررسی 20250106_000001
    if '20250106_000001' in migrations:
        info = migrations['20250106_000001']
        print(f"📄 {info['file']}:")
        print(f"   revision = {info['revision']}")
        print(f"   down_revision = {info['down_revision']}")
        if info['down_revision'] == '20250205_000002_seed_repair_shop_plugin':
            print("   ⚠️ مشکل: down_revision به یک migration با تاریخ بعدی اشاره می‌کند!")
            print("   پیشنهاد: باید down_revision را به 'a23683863c8a' تغییر داد")
    
    return len(heads), missing_parents

if __name__ == '__main__':
    main()

