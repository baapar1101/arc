# خلاصه ادغام Migration های init_schema

**تاریخ**: 2026-01-02  
**وضعیت**: ✅ تکمیل شده

---

## ✅ کارهای انجام شده

### 1. ادغام Migration های Modular
تمام 44 migration فایل داخل پوشه `init_schema` به یک migration واحد ادغام شدند:
- `20250101_000000_init_schema.py` (4039 خط)

### 2. حذف پوشه init_schema
پوشه `init_schema` و تمام فایل‌های داخل آن حذف شدند.

### 3. ساختار جدید
- تمام migration ها اکنون در پوشه `versions` هستند
- ساختار modular حذف شد و به یک migration واحد تبدیل شد
- Import های `from migrations.versions.init_schema` حذف شدند

---

## 📊 آمار

- **Migration های ادغام شده**: 44 فایل
- **خطوط کد**: 4039 خط
- **فایل نهایی**: `20250101_000000_init_schema.py`

---

## 📋 Migration های ادغام شده

1. `01_users` - جدول users
2. `01a_auth_tables` - جداول احراز هویت
3. `02_currencies` - جداول ارزها
4. `03_businesses` - جداول کسب‌وکارها
5. `34_business_extras` - business_print_settings, business_permissions
6. `04_persons` - جداول اشخاص
7. `35_person_extras` - person_share_links
8. `05_fiscal_years` - جداول سال مالی
9. `06_accounts` - جداول حساب‌ها
10. `07_categories` - جداول دسته‌بندی‌ها
11. `08_products` - جداول محصولات
12. `36_product_extras` - product_instances, product_attributes, etc.
13. `09_documents` - جداول اسناد
14. `31_invoice_item_line` - invoice_item_lines
15. `10_taxes` - جداول مالیاتی
16. `11_bank_accounts` - جداول حساب‌های بانکی
17. `37_cash_management` - cash_registers, petty_cash
18. `12_checks` - جداول چک‌ها
19. `13_warehouse_documents` - جداول اسناد انبار
20. `14_product_bom` - جداول فرمول تولید
21. `15_file_storage` - جداول ذخیره‌سازی فایل
22. `16_support` - جداول پشتیبانی
23. `17_email_config` - جداول تنظیمات ایمیل
24. `18_document_numbering` - جداول شماره‌گذاری اسناد
25. `21_ai` - جداول AI
26. `22_activity_log` - activity_logs
27. `23_storage_plan` - storage_plans, subscriptions
28. `24_document_monetization` - document monetization tables
29. `25_wallet` - wallet_accounts, transactions, payouts
30. `42_zohal` - zohal_services, service_logs
31. `26_telegram` - telegram_link_tokens, ai_sessions
32. `27_system_settings` - system_settings
33. `41_monitoring` - monitoring_metrics, alerts
34. `28_notification` - notification_templates, settings
35. `29_marketplace` - marketplace_plugins, orders
36. `30_credit` - business_credit_settings
37. `32_report_template` - report_templates
38. `33_announcement` - announcements
39. `38_payment_gateway` - payment_gateways
40. `39_ping_pong` - ping_pong_scores
41. `40_quick_sales_settings` - quick_sales_settings
42. `19_seed_data` - اطلاعات پایه
43. `20_accounts_chart` - چارت حساب‌های حسابداری
44. `43_fix_zohal_account_code` - اصلاح کد حساب

---

## ✅ نتیجه

✅ تمام migration های `init_schema` به یک فایل واحد ادغام شدند  
✅ پوشه `init_schema` حذف شد  
✅ ساختار ساده‌تر و یکپارچه شد  
✅ تمام migration ها اکنون در پوشه `versions` هستند  

**همه چیز آماده است!**


