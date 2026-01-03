#!/usr/bin/env python3
"""
استخراج بخش seed data از migration های مختلف
"""

from pathlib import Path
import re

VERSIONS_DIR = Path(__file__).parent / "versions"

# Migration های seed data
SEED_MIGRATIONS = [
    "20250205_000002_seed_repair_shop_plugin.py",
    "20250118_000001_add_product_warranty_plugin.py",
    "20250121_000001_add_ai_expense_account.py",
    "20250115_000001_fix_zohal_account_code.py",
    "20251202_000002_create_document_monetization_expense_account.py",
    "20251202_000003_backfill_document_monetization_accounting_documents.py",
]

def extract_seed_from_init_schema():
    """استخراج بخش seed data از init_schema"""
    file_path = VERSIONS_DIR / "20250101_000000_init_schema.py"
    if not file_path.exists():
        return None
    
    content = file_path.read_text(encoding='utf-8')
    
    # پیدا کردن بخش seed data
    seed_start = content.find("# === 19_seed_data ===")
    if seed_start == -1:
        return None
    
    # پیدا کردن پایان بخش seed (قبل از downgrade)
    downgrade_start = content.find("def downgrade()", seed_start)
    if downgrade_start == -1:
        downgrade_start = len(content)
    
    seed_section = content[seed_start:downgrade_start]
    
    return seed_section

def extract_seed_from_migration(filename):
    """استخراج بخش upgrade از یک migration"""
    file_path = VERSIONS_DIR / filename
    if not file_path.exists():
        return None
    
    content = file_path.read_text(encoding='utf-8')
    
    # پیدا کردن بخش upgrade
    upgrade_start = content.find("def upgrade()")
    if upgrade_start == -1:
        return None
    
    # پیدا کردن پایان upgrade (قبل از downgrade)
    downgrade_start = content.find("def downgrade()", upgrade_start)
    if downgrade_start == -1:
        downgrade_start = len(content)
    
    upgrade_section = content[upgrade_start:downgrade_start]
    
    return upgrade_section

def main():
    """استخراج همه seed data"""
    print("🔍 استخراج seed data از migration ها...\n")
    
    seed_data = []
    
    # استخراج از init_schema
    print("📦 استخراج از init_schema...")
    init_seed = extract_seed_from_init_schema()
    if init_seed:
        seed_data.append({
            'file': '20250101_000000_init_schema.py',
            'content': init_seed,
            'type': 'init_schema_seed'
        })
        print("   ✅ بخش seed data استخراج شد")
    else:
        print("   ⚠️ بخش seed data یافت نشد")
    
    # استخراج از سایر migration ها
    for filename in SEED_MIGRATIONS:
        print(f"📦 استخراج از {filename}...")
        seed_content = extract_seed_from_migration(filename)
        if seed_content:
            seed_data.append({
                'file': filename,
                'content': seed_content,
                'type': 'full_migration'
            })
            print("   ✅ استخراج شد")
        else:
            print("   ⚠️ محتوا یافت نشد")
    
    # ذخیره در فایل
    output_file = Path(__file__).parent / "extracted_seed_data.py"
    with open(output_file, 'w', encoding='utf-8') as f:
        f.write("# Seed Data Extracted from Migrations\n")
        f.write("# این فایل شامل تمام seed data استخراج شده از migration ها است\n\n")
        f.write("from alembic import op\n")
        f.write("import sqlalchemy as sa\n")
        f.write("from datetime import datetime\n\n\n")
        f.write("def apply_seed_data():\n")
        f.write("    \"\"\"اعمال تمام seed data\"\"\"\n")
        f.write("    conn = op.get_bind()\n\n")
        
        for i, seed in enumerate(seed_data):
            f.write(f"    # === Seed from {seed['file']} ===\n")
            # تبدیل def upgrade() به تابع داخلی
            content = seed['content']
            # حذف def upgrade() و indent کردن
            if content.startswith("def upgrade()"):
                content = content.replace("def upgrade():", "", 1)
                # حذف docstring اول
                content = re.sub(r'""".*?"""', '', content, flags=re.DOTALL, count=1)
                # اضافه کردن indent
                lines = content.split('\n')
                indented = '\n'.join('    ' + line if line.strip() else line for line in lines)
                f.write(indented)
            else:
                f.write(content)
            f.write("\n\n")
    
    print(f"\n✅ Seed data در {output_file} ذخیره شد")
    print(f"📊 تعداد migration های seed: {len(seed_data)}")

if __name__ == "__main__":
    main()

