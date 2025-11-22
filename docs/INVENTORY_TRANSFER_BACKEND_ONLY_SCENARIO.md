# سناریوی حفظ `inventory_transfer` در Backend و حذف از Frontend

## سوال اصلی

آیا می‌توانیم `inventory_transfer` را در Backend حفظ کنیم (برای محاسبات) اما از Frontend حذف کنیم (عدم نمایش به کاربر)؟

## پاسخ: ✅ بله، کاملاً امکان‌پذیر است

## وضعیت فعلی

### Backend (باید حفظ شود):
1. ✅ `warehouse_service.py`: ایجاد سند حسابداری با `document_type='inventory_transfer'`
2. ✅ `kardex_service.py`: mapping برای نمایش نام در کاردکس
3. ✅ `document_repository.py`: mapping برای نمایش نام
4. ✅ `invoice_service.py`: استفاده در `_iter_product_movements` برای محاسبات موجودی

### Frontend (باید حذف شود):
1. ✅ `inventory_transfers_page.dart` - **حذف شده**
2. ✅ `inventory_transfer_form_dialog.dart` - **حذف شده**
3. ✅ `inventory_transfer_service.dart` - **حذف شده**
4. ✅ منوی "حواله‌ها" (shipments) - **حذف شده**
5. ✅ route `/business/:business_id/inventory-transfers` - **حذف شده**
6. ⚠️ `kardex_page.dart`: فیلتر `inventory_transfer` - **باید حذف شود**
7. ⚠️ `document_model.dart`: case برای `inventory_transfer` - **باید حذف شود**

## آیا کاربر نیاز به بخش inventory_transfers دارد؟

### ❌ خیر، کاربر نیازی به ایجاد مستقیم inventory_transfer ندارد:

1. **کاربر می‌تواند از طریق Warehouse Documents انتقال ایجاد کند:**
   - ایجاد Warehouse Document با `doc_type='transfer'`
   - پست کردن آن
   - خودکار یک سند حسابداری با `document_type='inventory_transfer'` ایجاد می‌شود

2. **کاربر نیازی به مشاهده لیست inventory_transfers ندارد:**
   - انتقال‌ها از طریق Warehouse Documents مدیریت می‌شوند
   - سند حسابداری در کاردکس نمایش داده می‌شود (که کافی است)

3. **کاربر نیازی به ویرایش/حذف مستقیم inventory_transfer ندارد:**
   - ویرایش/حذف از طریق Warehouse Documents انجام می‌شود
   - سند حسابداری به صورت خودکار به‌روزرسانی می‌شود

## مزایای این رویکرد

1. ✅ **حفظ محاسبات**: `inventory_transfer` در Backend حفظ می‌شود و در محاسبات استفاده می‌شود
2. ✅ **ساده‌سازی UI**: کاربر فقط با Warehouse Documents کار می‌کند
3. ✅ **تفکیک واضح**: انتقال موجودی = Warehouse Document، سند حسابداری = فقط برای محاسبات
4. ✅ **عدم نیاز به migration**: داده‌های موجود حفظ می‌شوند

## تغییرات لازم

### Frontend - حذف از UI (اما حفظ در کاردکس):

#### 1. `kardex_page.dart` - حذف فیلتر `inventory_transfer`:

**فعلی:**
```dart
FilterOption(value: 'inventory_transfer', label: t.warehouseTransfers),
```

**باید حذف شود** - چون کاربر نیازی به فیلتر کردن انتقال‌های موجودی ندارد. اما همچنان در کاردکس نمایش داده می‌شود (به عنوان یک سند حسابداری).

**یا می‌توانیم نگه داریم** - اگر کاربر بخواهد فقط انتقال‌های موجودی را در کاردکس ببیند.

#### 2. `document_model.dart` - حذف case برای `inventory_transfer`:

**فعلی:**
```dart
case 'inventory_transfer':
  return 'انتقال موجودی';
```

**باید حذف شود** - چون کاربر نباید مستقیماً با `inventory_transfer` کار کند. اما می‌توانیم از mapping در Backend استفاده کنیم.

**یا می‌توانیم نگه داریم** - برای نمایش نام در کاردکس.

## توصیه

### گزینه 1: حذف کامل از Frontend (پیشنهادی)

**حذف:**
- فیلتر `inventory_transfer` از `kardex_page.dart`
- case `inventory_transfer` از `document_model.dart`

**نتیجه:**
- کاربر نمی‌تواند فیلتر کند
- اما همچنان در کاردکس نمایش داده می‌شود (با نام از Backend)
- کاربر فقط با Warehouse Documents کار می‌کند

### گزینه 2: حفظ در کاردکس (برای گزارش‌گیری)

**نگه داشتن:**
- فیلتر `inventory_transfer` در `kardex_page.dart`
- case `inventory_transfer` در `document_model.dart`

**نتیجه:**
- کاربر می‌تواند فیلتر کند
- برای گزارش‌گیری مفید است
- اما همچنان نمی‌تواند مستقیماً ایجاد/ویرایش کند

## نتیجه‌گیری

**✅ بله، می‌توانیم `inventory_transfer` را در Backend حفظ کنیم و از Frontend حذف کنیم:**

1. **Backend**: حفظ `inventory_transfer` برای محاسبات و کاردکس
2. **Frontend**: حذف فیلتر و case (یا نگه داشتن برای گزارش‌گیری)
3. **کاربر**: فقط با Warehouse Documents کار می‌کند
4. **محاسبات**: همچنان از `inventory_transfer` استفاده می‌شود

این بهترین رویکرد است چون:
- ✅ محاسبات حفظ می‌شود
- ✅ UI ساده می‌شود
- ✅ کاربر فقط با یک سیستم کار می‌کند (Warehouse Documents)

