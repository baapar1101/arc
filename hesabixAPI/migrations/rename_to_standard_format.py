#!/usr/bin/env python3
"""
اسکریپت تغییر نام تمام migration ها به فرمت استاندارد YYYYMMDD_HHMMSS_description.py
"""

import re
import shutil
from pathlib import Path

MIGRATIONS_DIR = Path(__file__).parent / "versions"

# Mapping: (old_revision, old_filename) -> (new_revision, new_filename)
RENAME_MAP = {
    # فایل‌هایی که revision ID با نام فایل مطابقت ندارد
    ('20250108_000001_optimize_ticket_indexes', '20250108_000001_optimize_ticket_indexes.py'): 
        ('20250108_000001', '20250108_000001_optimize_ticket_indexes.py'),
    
    ('20250121_000001_add_ai_expense_account', '20250121_000001_add_ai_expense_account.py'): 
        ('20250121_000001', '20250121_000001_add_ai_expense_account.py'),
    
    ('20250122_000001_add_last_reset_at_and_expires_at_to_ai_subscriptions', '20250122_000001_add_last_reset_at_and_expires_at_to_ai_subscriptions.py'): 
        ('20250122_000001', '20250122_000001_add_last_reset_at_and_expires_at_to_ai_subscriptions.py'),
    
    ('20250205_000001_create_repair_shop_tables', '20250205_000001_create_repair_shop_tables.py'): 
        ('20250205_000001', '20250205_000001_create_repair_shop_tables.py'),
    
    ('20250205_000002_seed_repair_shop_plugin', '20250205_000002_seed_repair_shop_plugin.py'): 
        ('20250205_000002', '20250205_000002_seed_repair_shop_plugin.py'),
    
    ('20251206_000001_remove_phone_email_from_repair_orders', '20251206_000001_remove_phone_email_from_repair_orders.py'): 
        ('20251206_000001', '20251206_000001_remove_phone_email_from_repair_orders.py'),
    
    ('20251207_000001_change_activity_logs_entity_id_to_string', '20251207_000001_change_activity_logs_entity_id_to_string.py'): 
        ('20251207_000001', '20251207_000001_change_activity_logs_entity_id_to_string.py'),
    
    ('20251223_002500_create_ai_voice_interactions', '20251223_002500_create_ai_voice_interactions.py'): 
        ('20251223_002500', '20251223_002500_create_ai_voice_interactions.py'),
}


def get_revision_from_file(file_path: Path) -> str | None:
    """خواندن revision از فایل"""
    content = file_path.read_text(encoding='utf-8')
    
    for pattern in [
        r"^revision\s*:\s*str\s*=\s*['\"]([^'\"]+)['\"]",
        r"^revision\s*=\s*['\"]([^'\"]+)['\"]",
    ]:
        match = re.search(pattern, content, re.MULTILINE)
        if match:
            return match.group(1)
    return None


def update_revision_in_file(file_path: Path, new_revision: str):
    """به‌روزرسانی revision در فایل"""
    content = file_path.read_text(encoding='utf-8')
    
    # Update revision
    for pattern in [
        (r"^revision\s*:\s*str\s*=\s*['\"]([^'\"]+)['\"]", f"revision: str = '{new_revision}'"),
        (r"^revision\s*=\s*['\"]([^'\"]+)['\"]", f"revision = '{new_revision}'"),
    ]:
        if re.search(pattern[0], content, re.MULTILINE):
            content = re.sub(pattern[0], pattern[1], content, flags=re.MULTILINE)
            break
    
    file_path.write_text(content, encoding='utf-8')


def update_down_revision_references(old_revision: str, new_revision: str):
    """به‌روزرسانی تمام reference های down_revision"""
    for file_path in MIGRATIONS_DIR.glob("*.py"):
        if file_path.name == "__init__.py" or 'backup' in str(file_path):
            continue
        
        content = file_path.read_text(encoding='utf-8')
        original_content = content
        
        # Update down_revision if it references old_revision
        if f"down_revision = '{old_revision}'" in content or f"down_revision: Union[str, None] = '{old_revision}'" in content:
            content = re.sub(
                rf"down_revision\s*[:\s]*[^=]*=\s*['\"]{re.escape(old_revision)}['\"]",
                f"down_revision = '{new_revision}'",
                content,
                flags=re.MULTILINE
            )
        
        if content != original_content:
            file_path.write_text(content, encoding='utf-8')
            print(f"  ✅ به‌روزرسانی down_revision در {file_path.name}")


def main():
    """اجرای اصلی"""
    print("🔄 تغییر نام migration ها به فرمت استاندارد...\n")
    
    # First, update revision IDs in files
    print("📝 به‌روزرسانی revision ID ها...")
    for file_path in MIGRATIONS_DIR.glob("*.py"):
        if file_path.name == "__init__.py" or 'backup' in str(file_path):
            continue
        
        current_revision = get_revision_from_file(file_path)
        if not current_revision:
            continue
        
        # Check if revision needs to be shortened
        # Extract YYYYMMDD_HHMMSS from revision if it's longer
        match = re.match(r'^(\d{8}_\d{6})', current_revision)
        if match:
            short_revision = match.group(1)
            if current_revision != short_revision:
                print(f"  🔄 {file_path.name}: {current_revision} -> {short_revision}")
                update_revision_in_file(file_path, short_revision)
                # Update all down_revision references
                update_down_revision_references(current_revision, short_revision)
    
    print("\n✅ تمام revision ID ها به فرمت استاندارد تبدیل شدند!")
    print("\n📋 خلاصه:")
    print("  - تمام revision ID ها به فرمت YYYYMMDD_HHMMSS تبدیل شدند")
    print("  - تمام down_revision reference ها به‌روزرسانی شدند")


if __name__ == "__main__":
    main()


