#!/usr/bin/env python3
"""
حذف migration های تکراری و اضافی
"""

import re
from pathlib import Path
from collections import defaultdict

VERSIONS_DIR = Path(__file__).parent / "versions"


def analyze_migrations():
    """تحلیل migration ها"""
    migrations = []
    
    for file_path in VERSIONS_DIR.glob("*.py"):
        if file_path.name == "__init__.py" or 'backup' in str(file_path):
            continue
        
        content = file_path.read_text(encoding='utf-8')
        
        # Extract revision
        rev_match = re.search(r"^revision\s*[:\s]*=\s*['\"]([^'\"]+)['\"]", content, re.MULTILINE)
        if not rev_match:
            continue
        
        revision = rev_match.group(1)
        
        # Extract description
        desc_match = re.search(r'"""(.*?)"""', content, re.DOTALL)
        description = desc_match.group(1).strip().split('\n')[0] if desc_match else file_path.stem
        
        # Check content
        has_upgrade = 'def upgrade' in content
        upgrade_content = ''
        if has_upgrade:
            upgrade_match = re.search(r'def upgrade[^:]*:\s*(.*?)(?=def downgrade|$)', content, re.DOTALL)
            if upgrade_match:
                upgrade_content = upgrade_match.group(1).strip()
        
        is_empty = upgrade_content in ('', 'pass', '"""', "'''")
        
        migrations.append({
            'file': file_path.name,
            'revision': revision,
            'description': description,
            'size': len(content),
            'empty': is_empty,
            'content': upgrade_content[:100] if upgrade_content else ''
        })
    
    return migrations


def find_duplicates(migrations):
    """پیدا کردن migration های تکراری"""
    # Group by similar functionality
    groups = {
        'zohal_fix': [],
        'quick_sales': [],
        'optimize_indexes': [],
        'empty': []
    }
    
    for m in migrations:
        desc_lower = m['description'].lower()
        file_lower = m['file'].lower()
        
        if m['empty']:
            groups['empty'].append(m)
        elif 'zohal' in desc_lower or 'zohal' in file_lower:
            groups['zohal_fix'].append(m)
        elif 'quick' in desc_lower or 'price' in desc_lower:
            groups['quick_sales'].append(m)
        elif 'optimize' in desc_lower or 'index' in desc_lower:
            groups['optimize_indexes'].append(m)
    
    return groups


def main():
    """اجرای اصلی"""
    print("🔍 بررسی migration های تکراری...\n")
    
    migrations = analyze_migrations()
    groups = find_duplicates(migrations)
    
    print(f"📊 تعداد کل migration ها: {len(migrations)}\n")
    
    to_remove = []
    
    # Empty migrations
    if groups['empty']:
        print("⚠️ Migration های خالی:")
        for m in groups['empty']:
            print(f"  - {m['file']}")
            to_remove.append(m['file'])
    
    # Zohal fixes - keep the latest
    if len(groups['zohal_fix']) > 1:
        print("\n⚠️ Migration های zohal (حفظ جدیدترین):")
        sorted_zohal = sorted(groups['zohal_fix'], key=lambda x: x['file'])
        for m in sorted_zohal[:-1]:  # Keep last one
            print(f"  - {m['file']} (حذف)")
            to_remove.append(m['file'])
        print(f"  ✅ {sorted_zohal[-1]['file']} (نگه داشته می‌شود)")
    
    # Quick sales - might be duplicates
    if len(groups['quick_sales']) > 1:
        print("\n⚠️ Migration های quick_sales:")
        for m in groups['quick_sales']:
            print(f"  - {m['file']}")
        # Don't auto-remove, need manual review
    
    print(f"\n📋 Migration های برای حذف: {len(to_remove)}")
    for f in to_remove:
        print(f"  - {f}")
    
    if to_remove:
        print("\n⚠️ برای حذف، دستور زیر را اجرا کنید:")
        print(f"   cd {VERSIONS_DIR}")
        for f in to_remove:
            print(f"   rm {f}")


if __name__ == "__main__":
    main()


