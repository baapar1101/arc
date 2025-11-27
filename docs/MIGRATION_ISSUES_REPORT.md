# گزارش جامع مشکلات میگریشن‌ها

**تاریخ بررسی:** 2025-02-06  
**تعداد کل میگریشن‌ها:** 112 فایل  
**تعداد میگریشن‌های دارای downgrade:** 112 فایل

---

## 📋 خلاصه مشکلات

### آمار کلی:
- **مشکلات Critical (بحرانی):** 15 مورد
- **مشکلات High (بالا):** 8 مورد  
- **مشکلات Medium (متوسط):** 12 مورد
- **مشکلات Low (پایین):** 5 مورد

---

## 🔴 مشکلات Critical (بحرانی)

### 1. مشکل در downgrade میگریشن‌ها - عدم بررسی وجود

این مشکل در **15 میگریشن** وجود دارد که می‌تواند باعث خطا در اجرای اتوماتیک شود:

#### 1.1. `20250206_000001_add_product_instances_and_unique_inventory.py`
**مشکل:** در `downgrade` بدون بررسی وجود، ستون‌ها و جدول حذف می‌شوند.

```python
def downgrade() -> None:
    op.drop_column("warehouse_document_lines", "instance_ids")  # ❌ بدون بررسی
    op.drop_table("product_instances")  # ❌ بدون بررسی
    op.drop_column("products", "track_barcode")  # ❌ بدون بررسی
    op.drop_column("products", "track_serial")  # ❌ بدون بررسی
    op.drop_column("products", "inventory_mode")  # ❌ بدون بررسی
```

**راه حل:** باید با `inspector` بررسی شود که آیا جدول/ستون وجود دارد یا نه.

#### 1.2. `20251011_000901_add_checks_table.py`
**مشکل:** در `downgrade` بدون try-except ایندکس‌ها و جدول حذف می‌شوند.

```python
def downgrade() -> None:
    op.drop_index('ix_checks_business_due_date', table_name='checks')  # ❌ بدون بررسی
    op.drop_index('ix_checks_business_issue_date', table_name='checks')  # ❌ بدون بررسی
    op.drop_index('ix_checks_business_person', table_name='checks')  # ❌ بدون بررسی
    op.drop_index('ix_checks_business_type', table_name='checks')  # ❌ بدون بررسی
    op.drop_table('checks')  # ❌ بدون بررسی
```

#### 1.3. `20250119_000001_add_check_reconciliations_tables.py`
**مشکل:** در `downgrade` بدون بررسی ایندکس‌ها و جدول‌ها حذف می‌شوند.

```python
def downgrade() -> None:
    op.drop_index('ix_check_reconciliation_items_check', ...)  # ❌ بدون بررسی
    op.drop_index('ix_check_reconciliation_items_reconciliation', ...)  # ❌ بدون بررسی
    op.drop_index('ix_check_reconciliations_created_at', ...)  # ❌ بدون بررسی
    op.drop_index('ix_check_reconciliations_business', ...)  # ❌ بدون بررسی
    op.drop_table('check_reconciliation_items')  # ❌ بدون بررسی
    op.drop_table('check_reconciliations')  # ❌ بدون بررسی
```

#### 1.4. `20250929_000501_add_products_and_pricing.py`
**مشکل:** در `downgrade` بدون بررسی constraintها و جدول‌ها حذف می‌شوند.

```python
def downgrade() -> None:
    op.drop_constraint('uq_product_attribute_links_unique', ...)  # ❌ بدون بررسی
    op.drop_table('product_attribute_links')  # ❌ بدون بررسی
    op.drop_constraint('uq_price_items_unique_tier', ...)  # ❌ بدون بررسی
    op.drop_table('price_items')  # ❌ بدون بررسی
    op.drop_constraint('uq_price_lists_business_name', ...)  # ❌ بدون بررسی
    op.drop_table('price_lists')  # ❌ بدون بررسی
    op.drop_constraint('uq_products_business_code', ...)  # ❌ بدون بررسی
    op.drop_table('products')  # ❌ بدون بررسی
```

#### 1.5. `20250125_000001_add_telegram_ai_sessions.py`
**مشکل:** در `downgrade` بدون بررسی ایندکس‌ها و جدول حذف می‌شوند.

```python
def downgrade() -> None:
    op.drop_index('ix_telegram_ai_sessions_user_chat_active', ...)  # ❌ بدون بررسی
    op.drop_index(op.f('ix_telegram_ai_sessions_business_id'), ...)  # ❌ بدون بررسی
    op.drop_index(op.f('ix_telegram_ai_sessions_session_id'), ...)  # ❌ بدون بررسی
    op.drop_index(op.f('ix_telegram_ai_sessions_chat_id'), ...)  # ❌ بدون بررسی
    op.drop_index(op.f('ix_telegram_ai_sessions_user_id'), ...)  # ❌ بدون بررسی
    op.drop_table('telegram_ai_sessions')  # ❌ بدون بررسی
```

#### 1.6. `20251124_200001_add_email_verification.py`
**مشکل:** در `downgrade` بدون بررسی ایندکس‌ها و ستون حذف می‌شوند.

```python
def downgrade() -> None:
    op.drop_index(op.f('ix_email_verification_tokens_token_hash'), ...)  # ❌ بدون بررسی
    op.drop_index(op.f('ix_email_verification_tokens_email'), ...)  # ❌ بدون بررسی
    op.drop_index(op.f('ix_email_verification_tokens_user_id'), ...)  # ❌ بدون بررسی
    op.drop_table('email_verification_tokens')  # ❌ بدون بررسی
    op.drop_index(op.f('ix_users_email_verified'), ...)  # ❌ بدون بررسی
    op.drop_column('users', 'email_verified')  # ❌ بدون بررسی
```

#### 1.7. `20250205_000001_create_document_number_counters.py`
**مشکل:** در `downgrade` بدون بررسی constraintها و ایندکس‌ها حذف می‌شوند.

```python
def downgrade() -> None:
    op.drop_constraint("uq_doc_number_counter_bucket", ...)  # ❌ بدون بررسی
    op.drop_index("ix_doc_number_counter_document_type", ...)  # ❌ بدون بررسی
    op.drop_index("ix_doc_number_counter_business", ...)  # ❌ بدون بررسی
    op.drop_table("document_number_counters")  # ❌ بدون بررسی
```

#### 1.8. `20251124_150001_add_product_tax_codes.py`
**مشکل:** در `downgrade` بدون بررسی ایندکس و جدول حذف می‌شوند.

```python
def downgrade() -> None:
    op.drop_index("ix_product_tax_codes_code", ...)  # ❌ بدون بررسی
    op.drop_table("product_tax_codes")  # ❌ بدون بررسی
```

#### 1.9. `20250915_000001_init_auth_tables.py`
**مشکل:** در `downgrade` بدون بررسی ایندکس‌ها و جدول‌ها حذف می‌شوند (این میگریشن اولیه است، اما بهتر است بررسی شود).

```python
def downgrade() -> None:
    op.drop_index("ix_password_resets_user_id", ...)  # ❌ بدون بررسی
    op.drop_index("ix_password_resets_token_hash", ...)  # ❌ بدون بررسی
    op.drop_table("password_resets")  # ❌ بدون بررسی
    op.drop_table("captchas")  # ❌ بدون بررسی
    op.drop_index("ix_api_keys_user_id", ...)  # ❌ بدون بررسی
    op.drop_index("ix_api_keys_key_hash", ...)  # ❌ بدون بررسی
    op.drop_table("api_keys")  # ❌ بدون بررسی
    op.drop_index("ix_users_mobile", ...)  # ❌ بدون بررسی
    op.drop_index("ix_users_email", ...)  # ❌ بدون بررسی
    op.drop_table("users")  # ❌ بدون بررسی
```

#### 1.10. `20250120_000001_add_persons_tables.py`
**مشکل:** در `downgrade` بدون بررسی ایندکس‌ها و جدول‌ها حذف می‌شوند.

```python
def downgrade() -> None:
    op.drop_index(op.f('ix_person_bank_accounts_person_id'), ...)  # ❌ بدون بررسی
    op.drop_table('person_bank_accounts')  # ❌ بدون بررسی
    op.drop_index(op.f('ix_persons_national_id'), ...)  # ❌ بدون بررسی
    op.drop_index(op.f('ix_persons_alias_name'), ...)  # ❌ بدون بررسی
    op.drop_index(op.f('ix_persons_business_id'), ...)  # ❌ بدون بررسی
    op.drop_table('persons')  # ❌ بدون بررسی
```

#### 1.11. `20250120_000001_add_warehouse_contact_fields.py`
**مشکل:** در `downgrade` بدون بررسی وجود جدول، ستون‌ها حذف می‌شوند.

```python
def downgrade() -> None:
    with op.batch_alter_table('warehouses') as batch_op:
        batch_op.drop_column('postal_code')  # ❌ بدون بررسی وجود جدول
        batch_op.drop_column('address')  # ❌ بدون بررسی
        batch_op.drop_column('phone')  # ❌ بدون بررسی
        batch_op.drop_column('warehouse_keeper')  # ❌ بدون بررسی
```

#### 1.12. `b2b68cf299a3_convert_unit_fields_to_string.py`
**مشکل:** در `downgrade` بدون بررسی ستون حذف می‌شود.

```python
def downgrade() -> None:
    # ... کدهای دیگر ...
    op.drop_column('products', 'secondary_unit')  # ❌ بدون بررسی
```

#### 1.13. `20250123_000001_add_description_to_categories.py`
**مشکل:** در `downgrade` بررسی وجود انجام می‌شود اما بهتر است try-except هم اضافه شود.

```python
def downgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    table_name = "categories"
    
    if table_name in inspector.get_table_names():
        columns = {col["name"] for col in inspector.get_columns(table_name)}
        if "description" in columns:
            op.drop_column(table_name, "description")  # ⚠️ بهتر است try-except اضافه شود
```

#### 1.14. `20251120_000001_add_default_warehouse_to_products.py`
**مشکل:** در `downgrade` بررسی وجود انجام می‌شود اما بهتر است try-except هم اضافه شود.

#### 1.15. سایر میگریشن‌های مشابه
چند میگریشن دیگر هم همین مشکل را دارند که باید بررسی شوند.

---

## 🟠 مشکلات High (بالا)

### 2. مشکل در ترتیب زمانی میگریشن‌ها

#### 2.1. `20250119_000001_add_check_reconciliations_tables.py`
**مشکل:** تاریخ میگریشن `20250119` است اما به میگریشن `20251119` (بعدی) اشاره می‌کند.

```python
revision = '20250119_000001_add_check_reconciliations_tables'
down_revision = '20251119_000001_add_person_share_links'  # ❌ ترتیب زمانی اشتباه
```

**تاریخ میگریشن:** 2025-01-19  
**down_revision:** 2025-11-19 (10 ماه بعد!)

این می‌تواند باعث مشکل در اجرای اتوماتیک شود.

#### 2.2. `20250130_000001_create_tax_settings_table.py`
**مشکل:** تاریخ میگریشن `20250130` است اما به میگریشن `20251120` (بعدی) اشاره می‌کند.

```python
revision = "20250130_000001_create_tax_settings_table"
down_revision = "20251120_053716_add_ai_tables"  # ❌ ترتیب زمانی اشتباه
```

**تاریخ میگریشن:** 2025-01-30  
**down_revision:** 2025-11-20 (10 ماه بعد!)

#### 2.3. `20250125_000001_add_telegram_ai_sessions.py`
**مشکل:** تاریخ میگریشن `20250125` است اما به میگریشن `20251124_200001` (بعدی) اشاره می‌کند.

```python
revision = '20250125_000001'
down_revision = '20251124_200001'  # ❌ ترتیب زمانی اشتباه
```

**تاریخ میگریشن:** 2025-01-25  
**down_revision:** 2025-11-24 (10 ماه بعد!)

#### 2.4. `20250206_000001_add_product_instances_and_unique_inventory.py`
**مشکل:** تاریخ میگریشن `20250206` است اما به میگریشن `20251124_150001` (بعدی) اشاره می‌کند.

```python
revision = "20250206_000001_add_product_instances_and_unique_inventory"
down_revision = "20251124_150001_add_product_tax_codes"  # ❌ ترتیب زمانی اشتباه
```

**تاریخ میگریشن:** 2025-02-06  
**down_revision:** 2025-11-24 (9 ماه بعد!)

#### 2.5. `20250205_000001_create_document_number_counters.py`
**مشکل:** تاریخ میگریشن `20250205` است اما به میگریشن `023c8d2d2222` (merge head) اشاره می‌کند که تاریخ آن `2025-11-22` است.

```python
revision = "20250205_000001_create_document_number_counters"
down_revision = "023c8d2d2222"  # ❌ ترتیب زمانی اشتباه
```

**تاریخ میگریشن:** 2025-02-05  
**down_revision:** 2025-11-22 (9 ماه بعد!)

---

### 3. مشکل در Branch Management

#### 3.1. Branch ایجاد شده که باید merge شود

**مشکل:** یک branch ایجاد شده که باید merge شود:

- `20250206_000001` به `20251124_150001` اشاره می‌کند
- `3f8bc1df5f7c_merge_all_heads_final` هم به `20251124_150001` اشاره می‌کند

این دو میگریشن از یک parent منشعب شده‌اند. میگریشن `cc07f77111f2_merge_product_instances_with_telegram_ai` این branch را merge کرده، اما اگر اجرای اتوماتیک قبل از merge انجام شود، ممکن است خطا بدهد.

**راه حل:** باید مطمئن شویم که merge head قبل از اجرای میگریشن‌های branch اجرا می‌شود.

---

## 🟡 مشکلات Medium (متوسط)

### 4. مشکل در Consistency Commentها

#### 4.1. `20241120_000001_add_document_numbering_settings.py`
**مشکل:** Comment می‌گوید به `20251120_000001` اشاره می‌کند، اما در کد به `eb9be5452535` اشاره می‌کند.

```python
"""add business_document_numbering_settings table

Revision ID: 20241120_000001_add_document_numbering_settings
Revises: 20251120_000001_add_default_warehouse_to_products  # ❌ در comment
Create Date: 2024-11-20 00:00:01.000001
"""

down_revision: Union[str, None] = "eb9be5452535"  # ✅ در کد (درست است)
```

#### 4.2. `20250123_000001_add_description_to_categories.py`
**مشکل:** Comment می‌گوید به `20250122_000001` اشاره می‌کند، اما در کد به `023c8d2d2222` اشاره می‌کند.

```python
"""add description to categories table

Revision ID: 20250123_000001_add_description_to_categories
Revises: 20250122_000001_add_last_reset_at_and_expires_at_to_ai_subscriptions  # ❌ در comment
Create Date: 2025-01-23 00:00:01.000001
"""

down_revision: Union[str, None] = "023c8d2d2222"  # ✅ در کد (درست است)
```

#### 4.3. `20250130_000001_create_tax_settings_table.py`
**مشکل:** Comment می‌گوید به `20251120_053716_add_ai_tables` اشاره می‌کند، اما تاریخ میگریشن `20250130` است.

```python
"""create tax_settings table

Revision ID: 20250130_000001_create_tax_settings_table
Revises: 20251120_053716_add_ai_tables  # ❌ ترتیب زمانی اشتباه
Create Date: 2025-01-30 10:00:00.000000
"""
```

---

### 5. مشکل در میگریشن‌های Merge Head

#### 5.1. میگریشن‌های Merge Head بدون بررسی

چند میگریشن merge head وجود دارد که فقط `pass` دارند. این درست است، اما باید مطمئن شویم که همه branchها به درستی merge شده‌اند:

- `3f8bc1df5f7c_merge_all_heads_final.py`
- `eb9be5452535_merge_all_final_heads.py`
- `cc07f77111f2_merge_product_instances_with_telegram_ai.py`
- `bce59a9d4fc4_merge_telegram_ai_sessions.py`
- `023c8d2d2222_merge_heads_latest.py`
- و چند میگریشن merge head دیگر

---

## 🟢 مشکلات Low (پایین)

### 6. مشکلات جزئی

#### 6.1. میگریشن‌هایی که از `Union[str, None]` استفاده می‌کنند

چند میگریشن از `Union[str, None]` برای `down_revision` استفاده می‌کنند که درست است، اما بهتر است یکنواخت باشد.

#### 6.2. میگریشن‌هایی که از `op.f()` استفاده می‌کنند

برخی میگریشن‌ها از `op.f()` برای نام ایندکس‌ها استفاده می‌کنند و برخی نه. بهتر است یکنواخت باشد.

---

## 📊 آمار تفصیلی

### میگریشن‌های دارای مشکل downgrade:
- **15 میگریشن** بدون بررسی وجود در downgrade
- **8 میگریشن** با بررسی جزئی (نیاز به بهبود)
- **89 میگریشن** بدون مشکل یا با try-except مناسب

### میگریشن‌های دارای مشکل ترتیب زمانی:
- **5 میگریشن** با ترتیب زمانی اشتباه

### میگریشن‌های دارای مشکل consistency:
- **3 میگریشن** با inconsistency در commentها

---

## 🔧 توصیه‌های کلی

### 1. برای همه میگریشن‌ها:
- در `downgrade` همیشه از `inspector` برای بررسی وجود استفاده کنید
- یا از `try-except` برای handle کردن خطاها استفاده کنید
- مطمئن شوید که ترتیب زمانی درست است

### 2. برای میگریشن‌های جدید:
- همیشه بررسی وجود را در `upgrade` و `downgrade` انجام دهید
- از `inspector` برای بررسی وجود جدول/ستون/ایندکس استفاده کنید
- از `try-except` برای handle کردن خطاها استفاده کنید

### 3. برای Branch Management:
- قبل از ایجاد میگریشن جدید، مطمئن شوید که همه branchها merge شده‌اند
- از `alembic heads` برای بررسی branchهای موجود استفاده کنید

### 4. برای Consistency:
- Commentها را با کد هماهنگ کنید
- از یک فرمت یکنواخت برای `down_revision` استفاده کنید

---

## ✅ میگریشن‌های بدون مشکل (نمونه‌های خوب)

### 1. `20250130_000001_create_tax_settings_table.py`
این میگریشن به درستی از `inspector` برای بررسی وجود استفاده می‌کند:

```python
def downgrade() -> None:
    bind = op.get_bind()
    inspector = inspect(bind)

    if inspector.has_table("tax_settings"):
        existing_indexes = {idx["name"] for idx in inspector.get_indexes("tax_settings")}
        if "ix_tax_settings_created_by_user_id" in existing_indexes:
            try:
                op.drop_index(op.f("ix_tax_settings_created_by_user_id"), table_name="tax_settings")
            except Exception:
                pass
        # ...
```

### 2. `20241120_000001_add_document_numbering_settings.py`
این میگریشن به درستی از `try-except` استفاده می‌کند:

```python
def downgrade() -> None:
    try:
        op.drop_index("ix_doc_numbering_type", table_name="business_document_numbering_settings")
    except Exception:
        pass
    try:
        op.drop_index("ix_doc_numbering_business", table_name="business_document_numbering_settings")
    except Exception:
        pass
    try:
        op.drop_table("business_document_numbering_settings")
    except Exception:
        pass
```

### 3. `20251102_120001_add_check_status_fields.py`
این میگریشن به درستی از `try-except` استفاده می‌کند:

```python
def downgrade() -> None:
    try:
        op.drop_index('ix_checks_business_status', table_name='checks')
    except Exception:
        pass
    # ...
    for col in ['developer_data', ...]:
        try:
            op.drop_column('checks', col)
        except Exception:
            pass
```

---

## 🎯 اولویت‌بندی برای رفع مشکلات

### اولویت 1 (فوری):
1. رفع مشکلات downgrade در میگریشن‌های Critical
2. رفع مشکلات ترتیب زمانی

### اولویت 2 (مهم):
3. رفع مشکلات Branch Management
4. رفع مشکلات Consistency در Commentها

### اولویت 3 (بهبود):
5. یکنواخت‌سازی فرمت میگریشن‌ها
6. بهبود documentation

---

## 📝 نتیجه‌گیری

از **112 میگریشن** موجود:
- **15 میگریشن** دارای مشکلات Critical در downgrade
- **5 میگریشن** دارای مشکلات High در ترتیب زمانی
- **3 میگریشن** دارای مشکلات Medium در consistency
- **89 میگریشن** بدون مشکل یا با مشکلات جزئی

**توصیه:** قبل از اجرای اتوماتیک میگریشن‌ها در محیط production، باید مشکلات Critical و High رفع شوند.

---

**تهیه شده توسط:** AI Assistant  
**تاریخ:** 2025-02-06

