# برنامه بازسازی کامل Migration ها

**هدف**: ایجاد یک chain خطی از migration ها با یک head واحد و نام‌گذاری استاندارد

---

## استراتژی

### مرحله 1: شناسایی ترتیب زمانی
تمام migration ها را به ترتیب زمانی مرتب می‌کنیم

### مرحله 2: حذف Migration های Merge
- حذف تمام migration های merge (که فقط `pass` هستند)
- اصلاح `down_revision` های migration های بعدی

### مرحله 3: استانداردسازی نام‌گذاری
- تمام فایل‌ها به فرمت `YYYYMMDD_HHMMSS_description.py`
- revision ID همان timestamp باشد

### مرحله 4: ایجاد Chain خطی
- هر migration فقط به یک migration قبلی وابسته باشد
- فقط یک head داشته باشیم

---

## ترتیب پیشنهادی Migration ها

1. `20250101_000000_init_schema.py` (base)
2. `20240101_120000_optimize_indexes_phase3.py`
3. `20250112_000000_add_workflow_tables.py`
4. `20250115_000001_fix_zohal_account_code.py`
5. `20250116_000001_delete_account_codes.py`
6. `20250116_000002_create_activity_logs.py`
7. `20250117_000001_add_soft_delete_to_businesses.py`
8. `20250118_000001_add_product_warranty_plugin.py`
9. `20250119_000001_add_trial_support_to_marketplace.py`
10. `20250120_000001_create_warranty_tables.py`
11. `20250120_000002_rename_metadata_to_extra_metadata.py`
12. `20250121_000001_add_ai_expense_account.py`
13. `20250122_000001_add_last_reset_at_and_expires_at_to_ai_subscriptions.py`
14. `20250128_150000_add_default_price_list_to_quick_sales.py`
15. `20250129_120000_add_inventory_valuation_method.py`
16. `20250203_000001_change_warranty_code_unique_to_business_scope.py`
17. `20250205_000001_create_repair_shop_tables.py`
18. `20250205_000002_seed_repair_shop_plugin.py`
19. `20250106_000001_create_business_notification_system.py`
20. `20251202_000001_add_data_type_to_product_attributes.py`
21. `20251202_000002_create_document_monetization_expense_account.py`
22. `20251202_000003_backfill_document_monetization_accounting_documents.py`
23. `20251203_000001_add_warehouse_document_settings_to_quick_sales.py`
24. `20251204_000001_add_wallet_payout_admin_fields.py`
25. `20251204_000002_normalize_checks_enum_uppercase.py`
26. `20251205_000001_add_projects_table.py`
27. `20251206_000001_remove_phone_email_from_repair_orders.py`
28. `20251207_000001_change_activity_logs_entity_id_to_string.py`
29. `20251223_001905_add_invoice_profit_calculation_settings.py`
30. `20251223_002500_create_ai_voice_interactions.py`
31. `20260101_000001_add_is_active_to_products.py`
32. `20260102_000001_protect_wallet_transactions.py`
33. `20250108_000001_optimize_ticket_indexes.py` (آخرین)

---

## Migration های Merge که حذف می‌شوند

1. `4d60f85a6561_merge_all_current_heads.py`
2. `b8c9286db6bd_merge_all_heads_final.py`
3. `a23683863c8a_merge_multiple_heads.py`
4. `010e36975a45_merge_inventory_valuation_method_and_.py`
5. `8cb61ffb0637_merge_warranty_and_product_attributes_.py`
6. `20260102_000002_merge_branches_after_4d60f85a6561.py`

---

## Migration های با نام‌گذاری غیراستاندارد که باید تغییر نام دهند

1. `9cc424e46c07_add_quick_sales_settings.py` → `20250112_010000_add_quick_sales_settings.py`
2. `483a0bf37370_add_mobile_verified_column.py` → `20250101_010000_add_mobile_verified_column.py`
3. `449131e7b816_create_missing_monitoring_and_zohal_.py` → `20250116_010000_create_missing_monitoring_and_zohal_.py`

---

## اقدامات

1. ✅ شناسایی ترتیب
2. ⏳ حذف migration های merge
3. ⏳ تغییر نام فایل‌های غیراستاندارد
4. ⏳ اصلاح down_revision ها
5. ⏳ تست


