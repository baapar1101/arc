# اسکریپت تجمیع Migration ها

این فایل شامل دستورالعمل‌های گام به گام برای تجمیع migration ها است.

## ⚠️ هشدار مهم

**قبل از اجرای هر تغییری:**
1. پشتیبان کامل از دیتابیس بگیرید
2. پشتیبان از فولدر migrations بگیرید
3. در یک محیط test تست کنید

---

## مرحله 1: حذف کدهای MySQL-Specific ✅

**انجام شده**: فایل `20251204_000002_normalize_checks_enum_uppercase.py` اصلاح شد

---

## مرحله 2: شناسایی Migration های Merge

### Migration های Merge که فقط `pass` هستند:

1. `4d60f85a6561_merge_all_current_heads.py`
   - Merge می‌کند: `20250106_000001`, `20251204_000001`, `20251205_000001`, `20251206_000001_remove_phone_email_from_repair_orders`
   - Migration بعدی: `20251207_000001_change_activity_logs_entity_id_to_string.py`

2. `b8c9286db6bd_merge_all_heads_final.py`
   - Merge می‌کند: `20250112_000000`, `9cc424e46c07`, `20250128_150000`, `483a0bf37370`
   - Migration بعدی: `20250115_000001_fix_zohal_account_code.py` و `20250129_120000_add_inventory_valuation_method.py`

3. `a23683863c8a_merge_multiple_heads.py`
   - Merge می‌کند: `20250203_000001`, `20250115_000001`, `20250129_120000`
   - Migration بعدی: `20250205_000001_create_repair_shop_tables.py`

4. `010e36975a45_merge_inventory_valuation_method_and_.py`
   - Merge می‌کند: `20240101_120000`, `483a0bf37370`
   - Migration بعدی: `b8c9286db6bd` (که خودش merge است)

5. `8cb61ffb0637_merge_warranty_and_product_attributes_.py`
   - Merge می‌کند: `20250120_000002`, `20251202_000001`
   - Migration بعدی: `20250203_000001_change_warranty_code_unique_to_business_scope.py`

6. `20260102_000002_merge_branches_after_4d60f85a6561.py`
   - Merge می‌کند: `20250108_000001_optimize_ticket_indexes`, `20260102_000001`
   - Migration بعدی: (head)

---

## مرحله 3: استراتژی حذف Migration های Merge

### ⚠️ نکته مهم:
حذف migration های merge **خطرناک** است اگر:
- دیتابیس production از آن‌ها استفاده کرده باشد
- migration های بعدی به آن‌ها وابسته باشند

### راه حل امن:
به جای حذف، می‌توانیم migration های merge را **ساده** کنیم و فقط برای PostgreSQL نگه داریم.

---

## مرحله 4: تجمیع Migration های کوچک

### گروه 1: Quick Sales Settings
این migration ها می‌توانند در یک migration تجمیع شوند:

1. `9cc424e46c07_add_quick_sales_settings.py` - ایجاد جدول
2. `20250128_150000_add_default_price_list_to_quick_sales.py` - اضافه کردن فیلد
3. `20251203_000001_add_warehouse_document_settings_to_quick_sales.py` - اضافه کردن فیلد

**اقدام**: می‌توانیم یک migration جدید ایجاد کنیم که تمام این تغییرات را شامل شود.

### گروه 2: Document Monetization
1. `20251202_000001_add_data_type_to_product_attributes.py`
2. `20251202_000002_create_document_monetization_expense_account.py`
3. `20251202_000003_backfill_document_monetization_accounting_documents.py`

**اقدام**: می‌توانیم این‌ها را در یک migration تجمیع کنیم.

---

## مرحله 5: پیشنهاد نهایی

### گزینه 1: حذف Migration های Merge (خطرناک)
- نیاز به تغییر `down_revision` های زیادی
- خطرناک برای production

### گزینه 2: نگه داشتن Migration های Merge (پیشنهادی)
- امن‌تر است
- فقط کدهای MySQL را حذف می‌کنیم
- migration های merge را نگه می‌داریم (آن‌ها فقط `pass` هستند و مشکلی ایجاد نمی‌کنند)

### گزینه 3: تجمیع Migration های کوچک (پیشنهادی)
- migration های مرتبط را در یک migration تجمیع می‌کنیم
- این کار امن‌تر است و ساختار را تمیزتر می‌کند

---

## ✅ اقدامات انجام شده

1. ✅ حذف کدهای MySQL از `normalize_checks_enum_uppercase.py`
2. ✅ ایجاد مستندات برای تجمیع

---

## 📋 اقدامات پیشنهادی بعدی

1. **تجمیع Quick Sales Settings** (3 migration → 1 migration)
2. **تجمیع Document Monetization** (3 migration → 1 migration)
3. **بررسی migration های دیگر** برای تجمیع بیشتر

---

## 🔍 بررسی Migration های دیگر

برای پیدا کردن migration های دیگر که می‌توانند تجمیع شوند:

```bash
# لیست migration ها با تعداد خطوط
find migrations/versions -name "*.py" -type f ! -name "__init__.py" -exec wc -l {} \; | sort -n

# Migration های کوچک (کمتر از 50 خط)
find migrations/versions -name "*.py" -type f ! -name "__init__.py" -exec sh -c 'lines=$(wc -l < "$1"); if [ "$lines" -lt 50 ]; then echo "$lines $1"; fi' _ {} \;
```


