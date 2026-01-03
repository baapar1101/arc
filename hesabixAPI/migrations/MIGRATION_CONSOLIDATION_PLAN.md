# برنامه تجمیع و بهینه‌سازی Migration ها برای PostgreSQL

**تاریخ**: 2026-01-02  
**هدف**: حذف کامل پشتیبانی MySQL و تجمیع migration های تکراری

---

## 📋 خلاصه مشکلات

### 1. Migration های Merge غیرضروری
- **6 migration merge** که فقط `pass` هستند و هیچ کاری انجام نمی‌دهند:
  - `4d60f85a6561_merge_all_current_heads.py`
  - `b8c9286db6bd_merge_all_heads_final.py`
  - `a23683863c8a_merge_multiple_heads.py`
  - `010e36975a45_merge_inventory_valuation_method_and_.py`
  - `8cb61ffb0637_merge_warranty_and_product_attributes_.py`
  - `20260102_000002_merge_branches_after_4d60f85a6561.py`

### 2. Migration های MySQL-Specific
- `20251204_000002_normalize_checks_enum_uppercase.py` - شامل کدهای MySQL-specific است

### 3. Migration های کوچک که می‌توانند تجمیع شوند
- چند migration کوچک که می‌توانند با هم ترکیب شوند

---

## 🎯 استراتژی تجمیع

### مرحله 1: حذف کدهای MySQL-Specific

#### 1.1. ساده‌سازی `normalize_checks_enum_uppercase`
```python
# قبل: پشتیبانی از MySQL و PostgreSQL
# بعد: فقط PostgreSQL
def upgrade():
    connection = op.get_bind()
    # فقط برای PostgreSQL
    connection.execute(text("UPDATE checks SET type='RECEIVED' WHERE type='received'"))
    connection.execute(text("UPDATE checks SET type='TRANSFERRED' WHERE type='transferred'"))
```

**اقدام**: حذف کامل بخش MySQL از این migration

---

### مرحله 2: حذف Migration های Merge غیرضروری

#### 2.1. شناسایی Migration های Merge
این migration ها فقط برای merge کردن branch ها استفاده می‌شوند و هیچ تغییری در schema ایجاد نمی‌کنند.

**اقدام**: 
- اگر migration های merge در یک chain هستند، می‌توانیم آن‌ها را حذف کنیم
- اما باید `down_revision` های migration های بعدی را اصلاح کنیم

#### 2.2. مثال: حذف `4d60f85a6561`
```
قبل:
20250106_000001 -> 4d60f85a6561 -> 20251207_000001

بعد:
20250106_000001 -> 20251207_000001 (down_revision را تغییر می‌دهیم)
```

---

### مرحله 3: تجمیع Migration های کوچک

#### 3.1. Migration های مرتبط که می‌توانند ترکیب شوند

**گروه 1: Quick Sales Settings**
- `9cc424e46c07_add_quick_sales_settings.py`
- `20250128_150000_add_default_price_list_to_quick_sales.py`
- `20251203_000001_add_warehouse_document_settings_to_quick_sales.py`

**گروه 2: Wallet**
- `20251204_000001_add_wallet_payout_admin_fields.py`
- (اگر migration های wallet دیگری وجود دارد)

**گروه 3: Document Monetization**
- `20251202_000001_add_data_type_to_product_attributes.py`
- `20251202_000002_create_document_monetization_expense_account.py`
- `20251202_000003_backfill_document_monetization_accounting_documents.py`

---

## 🔧 مراحل اجرا

### مرحله 1: پشتیبان‌گیری
```bash
# پشتیبان از دیتابیس
pg_dump -U hesabix -d hesabix > backup_before_consolidation.sql

# پشتیبان از migration ها
cp -r migrations/versions migrations/versions_backup
```

### مرحله 2: حذف کدهای MySQL
1. اصلاح `20251204_000002_normalize_checks_enum_uppercase.py`
2. حذف بخش MySQL

### مرحله 3: حذف Migration های Merge
برای هر migration merge:
1. پیدا کردن migration های بعدی که به آن وابسته‌اند
2. تغییر `down_revision` آن‌ها
3. حذف migration merge

### مرحله 4: تجمیع Migration های کوچک
برای هر گروه:
1. ایجاد یک migration جدید که تمام تغییرات را شامل شود
2. حذف migration های قدیمی
3. به‌روزرسانی `down_revision` ها

### مرحله 5: تست
```bash
# بررسی ساختار
alembic history

# بررسی heads
alembic heads

# تست upgrade
alembic upgrade head

# تست downgrade
alembic downgrade -1
```

---

## ⚠️ هشدارها

1. **هیچ‌گاه migration های موجود در production را حذف نکنید** بدون اینکه مطمئن شوید که:
   - دیتابیس production از آن‌ها استفاده نمی‌کند
   - یا migration جدیدی ایجاد کنید که همان کار را انجام دهد

2. **Migration های merge** را فقط در صورتی حذف کنید که:
   - هیچ migration دیگری به آن‌ها وابسته نباشد
   - یا `down_revision` های migration های بعدی را اصلاح کنید

3. **تست کامل** قبل از اعمال در production

---

## 📊 تخمین کاهش

- **Migration های Merge**: 6 فایل → 0 فایل (حذف)
- **Migration های MySQL-Specific**: 1 فایل → 1 فایل (ساده‌سازی)
- **Migration های کوچک**: ~10 فایل → ~5 فایل (تجمیع)

**کل کاهش**: از ~40 فایل به ~30 فایل (25% کاهش)

---

## ✅ چک‌لیست نهایی

- [ ] پشتیبان‌گیری از دیتابیس
- [ ] پشتیبان‌گیری از migration ها
- [ ] حذف کدهای MySQL از `normalize_checks_enum_uppercase`
- [ ] حذف migration های merge غیرضروری
- [ ] تجمیع migration های کوچک
- [ ] تست `alembic history`
- [ ] تست `alembic heads`
- [ ] تست `alembic upgrade head`
- [ ] تست `alembic downgrade -1`
- [ ] بررسی خطاهای linting
- [ ] مستندسازی تغییرات


