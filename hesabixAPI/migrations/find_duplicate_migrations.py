#!/usr/bin/env python3
"""
شناسایی migration های تکراری و اضافی
"""

import re
from pathlib import Path
from collections import defaultdict

VERSIONS_DIR = Path(__file__).parent / "versions"


def analyze_migrations():
    """تحلیل migration ها برای پیدا کردن تکراری‌ها"""
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
        
        # Extract description from docstring or filename
        desc_match = re.search(r'"""(.*?)"""', content, re.DOTALL)
        description = desc_match.group(1).strip().split('\n')[0] if desc_match else file_path.stem
        
        migrations.append({
            'file': file_path.name,
            'revision': revision,
            'description': description,
            'size': len(content),
        })
    
    # Group by description (similar migrations)
    by_description = defaultdict(list)
    for m in migrations:
        # Normalize description
        desc = m['description'].lower().replace('_', ' ').replace('-', ' ')
        by_description[desc].append(m)
    
    # Find duplicates
    duplicates = []
    for desc, migs in by_description.items():
        if len(migs) > 1:
            duplicates.append((desc, migs))
    
    return migrations, duplicates


def find_similar_migrations(migrations):
    """پیدا کردن migration های مشابه"""
    similar = []
    
    for i, m1 in enumerate(migrations):
        for m2 in migrations[i+1:]:
            # Check if descriptions are similar
            desc1 = m1['description'].lower()
            desc2 = m2['description'].lower()
            
            # Common words
            words1 = set(desc1.split())
            words2 = set(desc2.split())
            
            if len(words1 & words2) >= 3:  # At least 3 common words
                similar.append((m1, m2))
    
    return similar


def main():
    """اجرای اصلی"""
    print("🔍 بررسی migration های تکراری و اضافی...\n")
    
    migrations, duplicates = analyze_migrations()
    
    print(f"📊 تعداد کل migration ها: {len(migrations)}\n")
    
    if duplicates:
        print("⚠️ Migration های با description مشابه:")
        for desc, migs in duplicates:
            print(f"\n  {desc}:")
            for m in migs:
                print(f"    - {m['file']} (revision: {m['revision']})")
    
    # Find similar
    similar = find_similar_migrations(migrations)
    if similar:
        print("\n\n⚠️ Migration های مشابه:")
        for m1, m2 in similar[:10]:  # Show first 10
            print(f"  - {m1['file']} <-> {m2['file']}")
    
    # Check for empty migrations
    print("\n\n🔍 بررسی migration های خالی یا کوچک:")
    for m in migrations:
        if m['size'] < 500:  # Less than 500 bytes
            print(f"  ⚠️ {m['file']} ({m['size']} bytes) - ممکن است خالی باشد")
    
    print("\n✅ بررسی کامل شد")


if __name__ == "__main__":
    main()


