# بررسی امکان استفاده از انواع اسناد موجود به جای `inventory_transfer`

## سوال اصلی

آیا می‌توانیم از انواع اسناد موجود (فروش، خرید، تولید و ...) استفاده کنیم و همان نتیجه `inventory_transfer` را بگیریم؟

## نحوه کار سیستم فعلی

### 1. `_iter_product_movements` چگونه movement را تعیین می‌کند:

```python
movement = (info.get("movement") or None)  # اول از extra_info.movement استفاده می‌کند
if movement is None:
    # fallback از نوع سند اگر صراحتاً مشخص نشده باشد
    inv_move, _ = _movement_from_type(doc.document_type)
    movement = inv_move
```

**نکته مهم**: اول از `extra_info.movement` استفاده می‌کند، سپس از `document_type` به عنوان fallback.

### 2. `_movement_from_type` چه می‌کند:

```python
def _movement_from_type(invoice_type: str) -> Tuple[Optional[str], Optional[str]]:
    if invoice_type == INVOICE_SALES:
        return ("out", None)  # فقط خروج
    if invoice_type == INVOICE_SALES_RETURN:
        return ("in", None)  # فقط ورود
    if invoice_type == INVOICE_PURCHASE:
        return ("in", None)  # فقط ورود
    if invoice_type == INVOICE_PURCHASE_RETURN:
        return ("out", None)  # فقط خروج
    if invoice_type in (INVOICE_DIRECT_CONSUMPTION, INVOICE_WASTE):
        return ("out", None)  # فقط خروج
    if invoice_type == INVOICE_PRODUCTION:
        return (None, None)  # هم ورود و هم خروج (برای محصولات مختلف)
    return (None, None)
```

## تحلیل انواع اسناد موجود

### ❌ نمی‌توانیم از `invoice_sales` استفاده کنیم:
- فقط "out" است
- انتقال موجودی نیاز به هم "in" و هم "out" دارد (برای همان محصول، اما انبارهای مختلف)

### ❌ نمی‌توانیم از `invoice_purchase` استفاده کنیم:
- فقط "in" است
- انتقال موجودی نیاز به هم "in" و هم "out" دارد

### ❌ نمی‌توانیم از `invoice_production` استفاده کنیم:
- هم "in" و هم "out" دارد
- اما برای محصولات مختلف (مواد اولیه = out، کالای ساخته شده = in)
- انتقال موجودی برای همان محصول است (فقط انبار متفاوت)

### ✅ می‌توانیم از `manual` استفاده کنیم:
- `_movement_from_type` برای `manual` مقدار `None` برمی‌گرداند
- اما چون `extra_info.movement` را صراحتاً تنظیم می‌کنیم، مشکلی نیست
- در حال حاضر برای `inventory_transfer` هم همین کار را می‌کنیم

## راه‌حل: استفاده از `document_type='manual'`

### مزایا:
1. ✅ **استفاده از `document_type` موجود**: نیازی به `inventory_transfer` نیست
2. ✅ **همان عملکرد**: چون `extra_info.movement` را صراحتاً تنظیم می‌کنیم
3. ✅ **عدم نیاز به mapping جدید**: `manual` از قبل وجود دارد
4. ✅ **عدم نیاز به migration**: می‌توانیم مستقیماً تغییر دهیم

### معایب:
1. ⚠️ **عدم تمایز**: نمی‌توانیم بین سند manual عادی و انتقال موجودی تفاوت قائل شویم
2. ⚠️ **فیلتر در کاردکس**: نمی‌توانیم فقط انتقال‌های موجودی را فیلتر کنیم
3. ⚠️ **گزارش‌گیری**: ممکن است در گزارش‌ها مشکل ایجاد کند

### راه‌حل بهتر: استفاده از `extra_info.source`

می‌توانیم از `document_type='manual'` استفاده کنیم اما در `extra_info.source` مشخص کنیم که از Warehouse Document آمده:

```python
accounting_doc = Document(
    document_type="manual",
    extra_info={
        "source": "warehouse_document",
        "warehouse_document_id": wh.id,
        "warehouse_transfer": True,  # برای تشخیص
    },
)
```

سپس در کاردکس می‌توانیم فیلتر کنیم:
```python
# فیلتر برای انتقال‌های موجودی
if doc.document_type == "manual" and doc.extra_info.get("warehouse_transfer"):
    # این یک انتقال موجودی است
```

## مقایسه گزینه‌ها

### گزینه 1: استفاده از `manual` با `extra_info.warehouse_transfer`
- ✅ حذف `inventory_transfer`
- ✅ استفاده از `document_type` موجود
- ⚠️ نیاز به تغییر فیلتر در کاردکس (بر اساس `extra_info`)
- ⚠️ نیاز به تغییر mapping برای نمایش نام

### گزینه 2: نگه داشتن `inventory_transfer`
- ✅ نام واضح و متمایز
- ✅ فیلتر ساده در کاردکس
- ❌ نیاز به نگه داشتن یک `document_type` اضافی

### گزینه 3: استفاده از `warehouse_transfer` (جدید)
- ✅ نام واضح و متمایز
- ✅ فیلتر ساده در کاردکس
- ❌ نیاز به اضافه کردن `document_type` جدید
- ❌ نیاز به migration

## توصیه

**گزینه 1 (استفاده از `manual` با `extra_info.warehouse_transfer`) پیشنهاد می‌شود:**

1. **حذف کامل `inventory_transfer`**: دیگر نیازی به آن نیست
2. **استفاده از `document_type` موجود**: از `manual` استفاده می‌کنیم
3. **تمایز از طریق `extra_info`**: با `warehouse_transfer: True` مشخص می‌کنیم
4. **فیلتر در کاردکس**: می‌توانیم بر اساس `extra_info.warehouse_transfer` فیلتر کنیم

## تغییرات لازم

### Backend

1. **`hesabixAPI/app/services/warehouse_service.py`**:
   ```python
   accounting_doc = Document(
       document_type="manual",  # به جای "inventory_transfer"
       extra_info={
           "source": "warehouse_document",
           "warehouse_document_id": wh.id,
           "warehouse_transfer": True,  # برای تشخیص
       },
   )
   ```

2. **`hesabixAPI/app/services/kardex_service.py`**:
   - حذف `"inventory_transfer": "انتقال موجودی"` از mapping
   - تغییر `_get_document_type_name` برای بررسی `extra_info.warehouse_transfer`:
   ```python
   def _get_document_type_name(doc_type: str | None, extra_info: dict | None = None) -> str:
       if doc_type == "manual" and extra_info and extra_info.get("warehouse_transfer"):
           return "انتقال موجودی"
       # ... سایر mapping‌ها
   ```

3. **`hesabixAPI/adapters/db/repositories/document_repository.py`**:
   - همان تغییرات `kardex_service.py`

### Frontend

4. **`hesabixUI/hesabix_ui/lib/pages/business/kardex_page.dart`**:
   - تغییر فیلتر برای استفاده از `extra_info.warehouse_transfer`:
   ```dart
   // به جای فیلتر بر اساس document_type
   // باید فیلتر را بر اساس extra_info.warehouse_transfer انجام دهیم
   ```

5. **`hesabixUI/hesabix_ui/lib/models/document_model.dart`**:
   - حذف `case 'inventory_transfer':`
   - اضافه کردن بررسی `extra_info.warehouse_transfer` برای `manual`

## نتیجه‌گیری

**بله، می‌توانیم از `document_type='manual'` استفاده کنیم** و با تنظیم `extra_info.movement` و `extra_info.warehouse_transfer` همان نتیجه را بگیریم. این روش:
- ✅ `inventory_transfer` را کاملاً حذف می‌کند
- ✅ از `document_type` موجود استفاده می‌کند
- ✅ نیاز به migration ندارد (اگر داده‌های موجود را تبدیل کنیم)
- ⚠️ نیاز به تغییر فیلتر در کاردکس دارد

