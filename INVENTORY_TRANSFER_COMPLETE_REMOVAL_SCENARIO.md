# سناریوی حذف کامل `inventory_transfer`

## سوال اصلی

آیا می‌توان `inventory_transfer` را به عنوان `document_type` کاملاً حذف کرد؟

## وضعیت فعلی

### استفاده از `inventory_transfer`:

1. **در `warehouse_service.py`**:
   - وقتی یک Warehouse Document با `doc_type='transfer'` پست می‌شود
   - یک سند حسابداری با `document_type='inventory_transfer'` ایجاد می‌شود
   - این سند در کاردکس و محاسبات موجودی استفاده می‌شود

2. **در `kardex_service.py`**:
   - mapping برای نمایش نام: `"inventory_transfer": "انتقال موجودی"`

3. **در `document_repository.py`**:
   - mapping برای نمایش نام: `"inventory_transfer": "انتقال موجودی"`

4. **در `kardex_page.dart`**:
   - فیلتر برای نمایش در کاردکس: `FilterOption(value: 'inventory_transfer', label: t.warehouseTransfers)`

5. **در `document_model.dart`**:
   - case برای نمایش نام سند

## گزینه‌های حذف

### گزینه 1: استفاده از `document_type` دیگر

**استفاده از `manual` یا `warehouse_transfer`:**

**مزایا:**
- حذف کامل `inventory_transfer`
- استفاده از `document_type` موجود یا جدید

**معایب:**
- نیاز به تغییر در تمام mapping‌ها
- نیاز به migration داده‌های موجود
- ممکن است با سایر اسناد manual تداخل داشته باشد

**تغییرات لازم:**
1. تغییر `warehouse_service.py`: استفاده از `document_type='warehouse_transfer'` یا `'manual'`
2. تغییر mapping‌ها در `kardex_service.py` و `document_repository.py`
3. تغییر فیلتر در `kardex_page.dart`
4. تغییر `document_model.dart`
5. Migration داده‌های موجود از `inventory_transfer` به `warehouse_transfer`

### گزینه 2: عدم ایجاد سند حسابداری برای انتقال موجودی

**فلسفه:**
- انتقال موجودی بین انبارها یک عملیات فیزیکی است
- نیازی به ثبت در حسابداری ندارد (چون مبلغی ندارد)
- فقط در موجودی فیزیکی انبار ثبت می‌شود

**مزایا:**
- حذف کامل `inventory_transfer`
- ساده‌تر شدن سیستم
- تفکیک کامل بین حسابداری و انبارداری

**معایب:**
- انتقال موجودی در کاردکس نمایش داده نمی‌شود
- محاسبات موجودی حسابداری شامل انتقال‌ها نمی‌شود
- ممکن است برای گزارش‌گیری مشکل ایجاد کند

**تغییرات لازم:**
1. حذف ایجاد سند حسابداری از `post_warehouse_document`
2. حذف `inventory_transfer` از تمام mapping‌ها
3. حذف فیلتر از `kardex_page.dart`
4. حذف case از `document_model.dart`

### گزینه 3: استفاده از `document_type` جدید: `warehouse_transfer`

**مزایا:**
- نام واضح‌تر و متمایز
- حذف `inventory_transfer`
- عدم تداخل با سایر `document_type`ها

**معایب:**
- نیاز به تغییر در تمام mapping‌ها
- نیاز به migration داده‌های موجود

**تغییرات لازم:**
1. تغییر `warehouse_service.py`: استفاده از `document_type='warehouse_transfer'`
2. تغییر mapping‌ها در `kardex_service.py` و `document_repository.py`
3. تغییر فیلتر در `kardex_page.dart`
4. تغییر `document_model.dart`
5. Migration داده‌های موجود

## توصیه

**گزینه 3 (استفاده از `warehouse_transfer`) پیشنهاد می‌شود:**

1. **نام واضح‌تر**: `warehouse_transfer` بهتر از `inventory_transfer` است
2. **تفکیک بهتر**: نشان می‌دهد که این سند از Warehouse Document ایجاد شده
3. **عدم تداخل**: با سایر `document_type`ها تداخل ندارد
4. **سازگاری**: همچنان در کاردکس و محاسبات موجودی استفاده می‌شود

## فایل‌های نیاز به تغییر

### Backend

1. **`hesabixAPI/app/services/warehouse_service.py`**:
   - تغییر `document_type="inventory_transfer"` به `document_type="warehouse_transfer"`
   - تغییر prefix کد سند از `"ITR"` به `"WHT"` (اختیاری)

2. **`hesabixAPI/app/services/kardex_service.py`**:
   - حذف `"inventory_transfer": "انتقال موجودی"`
   - اضافه کردن `"warehouse_transfer": "انتقال موجودی"`

3. **`hesabixAPI/adapters/db/repositories/document_repository.py`**:
   - حذف `"inventory_transfer": "انتقال موجودی"`
   - اضافه کردن `"warehouse_transfer": "انتقال موجودی"`

### Frontend

4. **`hesabixUI/hesabix_ui/lib/pages/business/kardex_page.dart`**:
   - تغییر `FilterOption(value: 'inventory_transfer', ...)` به `FilterOption(value: 'warehouse_transfer', ...)`

5. **`hesabixUI/hesabix_ui/lib/models/document_model.dart`**:
   - تغییر `case 'inventory_transfer':` به `case 'warehouse_transfer':`

### Migration

6. **Migration Script**:
   - تبدیل تمام اسناد با `document_type='inventory_transfer'` به `document_type='warehouse_transfer'`

## سناریوی جایگزین: حذف کامل (گزینه 2)

اگر تصمیم بگیرید که انتقال موجودی نیازی به ثبت در حسابداری ندارد:

### تغییرات:

1. **`hesabixAPI/app/services/warehouse_service.py`**:
   - حذف کامل بخش ایجاد سند حسابداری از `post_warehouse_document`
   - فقط تغییر وضعیت Warehouse Document به `posted`

2. **حذف از mapping‌ها**:
   - `kardex_service.py`
   - `document_repository.py`

3. **حذف از Frontend**:
   - `kardex_page.dart` (فیلتر)
   - `document_model.dart` (case)

### نتیجه:

- انتقال موجودی فقط در `warehouse_documents` ثبت می‌شود
- در کاردکس و محاسبات موجودی حسابداری نمایش داده نمی‌شود
- تفکیک کامل بین حسابداری و انبارداری

## سوالات برای تصمیم‌گیری

1. **آیا انتقال موجودی باید در کاردکس نمایش داده شود؟**
   - اگر بله → گزینه 3 (استفاده از `warehouse_transfer`)
   - اگر خیر → گزینه 2 (عدم ایجاد سند حسابداری)

2. **آیا محاسبات موجودی حسابداری باید شامل انتقال‌ها باشد؟**
   - اگر بله → گزینه 3
   - اگر خیر → گزینه 2

3. **آیا داده‌های موجود از `inventory_transfer` دارید؟**
   - اگر بله → نیاز به migration
   - اگر خیر → می‌توانید مستقیماً تغییر دهید

