#!/usr/bin/env python3
"""
اسکریپت اصلاح chain migration ها
"""

import re
from pathlib import Path

MIGRATIONS_DIR = Path(__file__).parent / "versions"

# ترتیب صحیح migration ها (بر اساس تاریخ)
CORRECT_ORDER = [
    '20250101_000000',  # init_schema
    '20240101_120000',  # optimize_indexes
    '20250101_010000',  # add_mobile_verified_column (renamed from 483a0bf37370)
    '20250106_000001',  # create_business_notification_system
    '20250108_000001_optimize_ticket_indexes',  # optimize_ticket_indexes
    '20250112_000000',  # add_workflow_tables
    '20250115_000001',  # fix_zohal_account_code
    '20250116_000001',  # delete_account_codes
    '20250116_000002',  # create_activity_logs
    '20250116_010000',  # create_missing_monitoring_and_zohal (renamed from 449131e7b816)
    '20250117_000001',  # add_soft_delete_to_businesses
    '20250118_000001',  # add_product_warranty_plugin
    '20250119_000001',  # add_trial_support_to_marketplace
    '20250120_000001',  # create_warranty_tables
    '20250120_000002',  # rename_metadata_to_extra_metadata
    '20250121_000001_add_ai_expense_account',  # add_ai_expense_account
    '20250122_000001_add_last_reset_at_and_expires_at_to_ai_subscriptions',  # add_last_reset_at
    '20250128_123300',  # add_quick_sales_settings (renamed from 9cc424e46c07)
    '20250128_150000',  # add_default_price_list_to_quick_sales
    '20250129_120000',  # add_inventory_valuation_method
    '20250203_000001',  # change_warranty_code_unique_to_business_scope
    '20250205_000001_create_repair_shop_tables',  # create_repair_shop_tables
    '20250205_000002_seed_repair_shop_plugin',  # seed_repair_shop_plugin
    '20251202_000001',  # add_data_type_to_product_attributes
    '20251202_000002',  # create_document_monetization_expense_account
    '20251202_000003',  # backfill_document_monetization_accounting_documents
    '20251203_000001',  # add_warehouse_document_settings_to_quick_sales
    '20251204_000001',  # add_wallet_payout_admin_fields
    '20251204_000002',  # normalize_checks_enum_uppercase
    '20251205_000001',  # add_projects_table
    '20251206_000001_remove_phone_email_from_repair_orders',  # remove_phone_email_from_repair_orders
    '20251207_000001_change_activity_logs_entity_id_to_string',  # change_activity_logs_entity_id_to_string
    '20251223_001905',  # add_invoice_profit_calculation_settings
    '20251223_002500_create_ai_voice_interactions',  # create_ai_voice_interactions
    '20260101_000001',  # add_is_active_to_products
    '20260102_000001',  # protect_wallet_transactions
]


def fix_migration_file(file_path: Path, new_down_revision: str | None):
    """اصلاح down_revision یک فایل migration"""
    content = file_path.read_text(encoding='utf-8')
    
    # Replace down_revision
    if new_down_revision:
        content = re.sub(
            r"^down_revision\s*[:\s]*[^=]*=\s*.+",
            f"down_revision = '{new_down_revision}'",
            content,
            flags=re.MULTILINE
        )
    else:
        content = re.sub(
            r"^down_revision\s*[:\s]*[^=]*=\s*.+",
            "down_revision = None",
            content,
            flags=re.MULTILINE
        )
    
    file_path.write_text(content, encoding='utf-8')
    print(f"✅ {file_path.name} -> down_revision = {new_down_revision}")


def main():
    """اجرای اصلی"""
    print("🔧 اصلاح chain migration ها...\n")
    
    # Fix each migration
    for i, revision in enumerate(CORRECT_ORDER):
        # Find file with this revision
        for file_path in MIGRATIONS_DIR.glob("*.py"):
            if file_path.name == "__init__.py" or 'backup' in str(file_path):
                continue
            
            content = file_path.read_text(encoding='utf-8')
            # Try multiple patterns for revision
            rev_match = None
            for pattern in [
                r"^revision\s*:\s*str\s*=\s*['\"]([^'\"]+)['\"]",  # with type hint
                r"^revision\s*=\s*['\"]([^'\"]+)['\"]",  # simple format
            ]:
                rev_match = re.search(pattern, content, re.MULTILINE)
                if rev_match:
                    break
            
            if rev_match and rev_match.group(1) == revision:
                # Get previous revision
                prev_revision = CORRECT_ORDER[i-1] if i > 0 else None
                fix_migration_file(file_path, prev_revision)
                break
    
    print("\n✅ تمام migration ها اصلاح شدند!")


if __name__ == "__main__":
    main()

