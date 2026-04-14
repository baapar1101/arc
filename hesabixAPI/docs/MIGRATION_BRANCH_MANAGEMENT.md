# مدیریت Branchهای میگریشن

## مشکل چند شاخه بودن میگریشن‌ها

وقتی چند developer به صورت همزمان روی پروژه کار می‌کنند و میگریشن‌های جدید ایجاد می‌کنند، ممکن است چند branch در میگریشن‌ها ایجاد شود. این مشکل می‌تواند باعث خطا در اجرای میگریشن‌ها شود.

## راه حل اصولی

### 1. بررسی قبل از ایجاد میگریشن جدید

قبل از ایجاد میگریشن جدید، همیشه بررسی کنید که آیا branchهای merge نشده وجود دارند:

```bash
alembic heads
```

اگر چند head نمایش داده شد، باید ابتدا آن‌ها را merge کنید.

### 2. استفاده از اسکریپت بررسی

یک اسکریپت برای بررسی و حل خودکار مشکل branchها ایجاد شده است:

```bash
python3 scripts/check_migration_branches.py
```

این اسکریپت:
- تعداد headهای موجود را بررسی می‌کند
- اگر چند head وجود داشته باشد، یک merge head ایجاد می‌کند
- وضعیت را گزارش می‌دهد

### 3. اجرای میگریشن‌ها

بعد از merge کردن branchها، میگریشن‌ها را اجرا کنید:

```bash
alembic upgrade head
```

## مراحل کار

### مرحله 1: بررسی وضعیت

```bash
# بررسی headهای موجود
alembic heads

# بررسی branchها
alembic branches

# بررسی وضعیت فعلی دیتابیس
alembic current
```

### مرحله 2: حل مشکل branchها

اگر چند head وجود دارد:

```bash
# استفاده از اسکریپت خودکار
python3 scripts/check_migration_branches.py

# یا به صورت دستی
alembic merge -m "merge_all_heads" head1 head2
```

### مرحله 3: اجرای میگریشن‌ها

```bash
alembic upgrade head
```

## بهترین روش‌ها

### 1. همیشه قبل از ایجاد میگریشن جدید بررسی کنید

```bash
# بررسی headها
alembic heads

# اگر چند head وجود دارد، ابتدا merge کنید
```

### 2. از Git برای هماهنگی استفاده کنید

- قبل از ایجاد میگریشن جدید، آخرین تغییرات را pull کنید
- بعد از ایجاد میگریشن، فوراً commit و push کنید
- اگر conflict در میگریشن‌ها پیش آمد، ابتدا آن را حل کنید

### 3. بررسی منظم

در محیط production، قبل از deploy، همیشه بررسی کنید:

```bash
python3 scripts/check_migration_branches.py
```

## مثال‌ها

### مثال 1: بررسی و حل خودکار

```bash
$ python3 scripts/check_migration_branches.py
بررسی وضعیت میگریشن‌ها...
تعداد headهای موجود: 2
⚠️  2 head یافت شد:
  - 48f89768a316
  - add_default_price_list_to_quick_sales

⚠️  Branchهای merge نشده یافت شد!
در حال ایجاد merge head...
Merge head با موفقیت ایجاد شد: b8c9286db6bd_merge_all_heads_final.py
✓ Merge head با موفقیت ایجاد شد.
```

### مثال 2: وضعیت سالم

```bash
$ python3 scripts/check_migration_branches.py
بررسی وضعیت میگریشن‌ها...
تعداد headهای موجود: 1
✓ فقط یک head وجود دارد. همه چیز درست است.
```

## مشکلات رایج

### مشکل 1: "Can't locate revision identified by 'XXXXX'"

این مشکل زمانی پیش می‌آید که یک revision در دیتابیس ثبت شده اما فایل میگریشن وجود ندارد.

**راه حل:**
```python
# حذف revision گمشده از دیتابیس
DELETE FROM alembic_version WHERE version_num = 'XXXXX';
```

### مشکل 2: "Multiple heads detected"

این مشکل زمانی پیش می‌آید که چند head وجود دارد.

**راه حل:**
```bash
# استفاده از اسکریپت
python3 scripts/check_migration_branches.py

# یا به صورت دستی
alembic merge -m "merge_heads" head1 head2
alembic upgrade head
```

### مشکل 3: "Table already exists" در میگریشن init_schema

این مشکل زمانی پیش می‌آید که میگریشن init_schema سعی می‌کند جداول را ایجاد کند اما جداول قبلاً وجود دارند.

**راه حل:**
وضعیت میگریشن را به آخرین revision تنظیم کنید:

```python
# تنظیم وضعیت به آخرین merge head
UPDATE alembic_version SET version_num = 'b8c9286db6bd';
```

## نکات مهم

1. **همیشه قبل از deploy بررسی کنید**: در محیط production، همیشه قبل از deploy، وضعیت میگریشن‌ها را بررسی کنید.

2. **از اسکریپت استفاده کنید**: اسکریپت `check_migration_branches.py` به صورت خودکار مشکل branchها را حل می‌کند.

3. **مستندات را به‌روز نگه دارید**: اگر میگریشن جدیدی ایجاد می‌کنید، مطمئن شوید که مستندات به‌روز است.

4. **تست کنید**: قبل از deploy در production، میگریشن‌ها را در محیط test تست کنید.

## خلاصه

- همیشه قبل از ایجاد میگریشن جدید، `alembic heads` را اجرا کنید
- اگر چند head وجود دارد، از `check_migration_branches.py` استفاده کنید
- بعد از merge، `alembic upgrade head` را اجرا کنید
- در محیط production، همیشه قبل از deploy بررسی کنید

