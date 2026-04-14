# سناریو نهایی: فاکتور تولید با استفاده از فرمول تولید (BOM)

## 📋 خلاصه اجرایی

این سند شامل سناریو کامل، مشکلات شناسایی شده، و پیشنهادات نهایی برای پیاده‌سازی صحیح فاکتور تولید با استفاده از فرمول تولید (BOM) است.

---

## 🎯 اصل طراحی

**انفجار فرمول تولید صرفاً از طریق فاکتور تولید انجام می‌شود و این کار از نظر حسابداری اصولی‌تر است.**

### مزایای این رویکرد:

1. ✅ **یکپارچگی حسابداری**: تمام عملیات تولید در یک سند (فاکتور تولید) ثبت می‌شود
2. ✅ **ردیابی کامل**: هر فاکتور تولید به فرمول(های) استفاده شده لینک می‌شود
3. ✅ **کنترل بهتر**: جلوگیری از خطاهای انسانی در وارد کردن دستی مواد اولیه
4. ✅ **سازگاری با اصول حسابداری**: ثبت‌های حسابداری به درستی انجام می‌شود

---

## 🔍 مشکلات شناسایی شده

### 1. مشکلات فوری (Blocker)

#### مشکل 1.1: فایل `BomExplosionWidget` وجود ندارد
- **وضعیت**: فایل `lib/widgets/invoice/bom_explosion_widget.dart` وجود ندارد
- **تأثیر**: کامپایل انجام نمی‌شود
- **اولویت**: فوری
- **راه‌حل**: ایجاد فایل با عملکرد کامل

#### مشکل 1.2: خطای کامپایل
```
Error: Error when reading 'lib/widgets/invoice/bom_explosion_widget.dart': 
No such file or directory
```
- **محل**: خط 27 و 2440 در `new_invoice_page.dart`
- **اولویت**: فوری

---

### 2. مشکلات مهم (Critical)

#### مشکل 2.1: عدم وجود فیلد `production_operations_total` در UI
- **وضعیت**: بک‌اند از این فیلد استفاده می‌کند (خط 1694 و 2492)
- **مشکل**: در UI فیلدی برای وارد کردن هزینه عملیات/سربار تولید وجود ندارد
- **تأثیر حسابداری**: هزینه عملیات ثبت نمی‌شود
- **اولویت**: مهم
- **راه‌حل**: اضافه کردن فیلد در تب "تنظیمات" یا تب "کالاها"

#### مشکل 2.2: عدم تنظیم `cost_price` برای محصولات نهایی
- **وضعیت**: بک‌اند از `cost_price` در `extra_info` استفاده می‌کند (خط 2507)
- **مشکل**: در UI امکان تنظیم `cost_price` برای ردیف‌های `movement: "in"` وجود ندارد
- **تأثیر**: محاسبه هزینه محصول نهایی نادرست می‌شود
- **اولویت**: مهم
- **راه‌حل**: 
  - محاسبه خودکار: `cost_price = (مواد اولیه + هزینه عملیات) / تعداد محصول`
  - یا امکان ویرایش دستی در جدول ردیف‌ها

#### مشکل 2.3: API `explode_bom` اطلاعات کامل برنمی‌گرداند
- **مشکلات**:
  1. `movement` در پاسخ API نیست (باید در Frontend تنظیم شود)
  2. `bom_id` در پاسخ API نیست (باید در Frontend اضافه شود)
  3. `cost_price` در پاسخ API نیست (باید در Frontend محاسبه شود)
- **اولویت**: مهم

---

### 3. مشکلات متوسط (Medium)

#### مشکل 3.1: مدیریت ناقص `_bomIds`
- **مشکلات**:
  - اگر کاربر ردیف‌های مربوط به یک BOM را حذف کند، `_bomId` مربوطه از `_bomIds` حذف نمی‌شود
  - همگام‌سازی با حذف ردیف‌ها انجام نمی‌شود
- **اولویت**: متوسط

#### مشکل 3.2: عدم پشتیبانی کامل در صفحه ویرایش
- **مشکلات**:
  - `BomExplosionWidget` وجود ندارد
  - `bom_ids` از `extra_info` بارگذاری نمی‌شود
  - اعتبارسنجی `movement` انجام نمی‌شود
- **اولویت**: متوسط

#### مشکل 3.3: اعتبارسنجی ناقص
- **Frontend**: فقط خروجی‌های BOM بررسی می‌شود
- **Backend**: فقط `movement` بررسی می‌شود، `bom_ids` بررسی نمی‌شود
- **اولویت**: متوسط

---

## 📐 سناریو کامل پیاده‌سازی

### مرحله 1: تعریف فرمول تولید (بخش کالاها)

**مکان**: `product_bom_section.dart`

**عملکرد**:
1. ✅ کاربر فرمول‌های تولید را تعریف می‌کند
2. ✅ مواد اولیه (items) را اضافه می‌کند
3. ✅ خروجی‌ها (outputs) را اضافه می‌کند
4. ✅ عملیات (operations) را اضافه می‌کند
5. ✅ فرمول را ذخیره می‌کند
6. ✅ (اختیاری) فرمولی را به عنوان پیش‌فرض تنظیم می‌کند
7. ✅ **کارت راهنما**: "برای استفاده از این فرمول، به بخش فاکتور تولید بروید"

**نکته**: در این بخش **هیچ دکمه "انفجار فرمول" وجود ندارد** ✅

---

### مرحله 2: صدور فاکتور تولید

**مکان**: `new_invoice_page.dart`

#### 2.1: انتخاب نوع فاکتور
- کاربر نوع فاکتور را "تولید" انتخاب می‌کند
- سیستم بررسی می‌کند که آیا فرمولی منفجر شده است؟

#### 2.2: ویجت انفجار فرمول (`BomExplosionWidget`)

**عملکرد**:
1. **نمایش**: فقط برای `InvoiceType.production`
2. **انتخاب کالا**: کاربر کالای تولیدی را انتخاب می‌کند
3. **انتخاب فرمول**: 
   - اگر فرمول پیش‌فرض وجود دارد، به صورت پیش‌فرض انتخاب می‌شود
   - در غیر این صورت، کاربر فرمول را انتخاب می‌کند
4. **ورود مقدار**: کاربر مقدار تولید را وارد می‌کند
5. **انفجار**: فراخوانی API `explode_bom`
6. **تبدیل نتایج**:
   - `items` → ردیف‌های فاکتور با:
     - `movement: "out"` در `extra_info`
     - `bom_id` در `extra_info`
     - `cost_price` از COGS کالا
     - `warehouse_id` از `suggested_warehouse_id` (اگر وجود دارد)
   - `outputs` → ردیف‌های فاکتور با:
     - `movement: "in"` در `extra_info`
     - `bom_id` در `extra_info`
     - `cost_price` محاسبه شده (مواد اولیه + هزینه عملیات) / تعداد
     - `warehouse_id` (قابل ویرایش)
7. **افزودن به فاکتور**: ردیف‌ها به `_lineItems` اضافه می‌شوند
8. **ذخیره `bom_id`**: `bomId` به `_bomIds` اضافه می‌شود

#### 2.3: ویرایش ردیف‌ها (پس از انفجار)

**قابل ویرایش**:
- ✅ مقدار (quantity)
- ✅ قیمت (unit_price)
- ✅ انبار (warehouse_id)
- ✅ `cost_price` (برای محصولات نهایی)

**غیرقابل ویرایش**:
- ❌ `movement` (برای جلوگیری از خطا)
- ❌ `bom_id` (برای ردیابی)

#### 2.4: فیلد هزینه عملیات

**مکان**: تب "تنظیمات" یا تب "کالاها"

**نوع**: `TextField` با اعتبارسنجی عددی

**ذخیره**: در `extra_info` فاکتور به عنوان `production_operations_total`

**محاسبه هزینه محصول نهایی**:
```
cost_price = (مجموع هزینه مواد اولیه + هزینه عملیات) / تعداد محصول نهایی
```

#### 2.5: اعتبارسنجی قبل از ذخیره

**Frontend** (`_validateAndBuildPayload`):
1. ✅ بررسی وجود حداقل یک فرمول منفجر شده (`_bomIds.isEmpty`)
2. ✅ بررسی وجود `movement` در تمام ردیف‌ها
3. ✅ بررسی وجود حداقل یک ردیف با `movement: "out"` (مواد اولیه)
4. ✅ بررسی وجود حداقل یک ردیف با `movement: "in"` (محصول نهایی)
5. ✅ بررسی وجود خروجی‌های BOM در فاکتور (`_validateBomOutputs`)

**Backend** (`create_invoice`):
1. ✅ بررسی وجود `movement` در تمام ردیف‌ها
2. ✅ بررسی وجود حداقل یک ردیف با `movement: "out"`
3. ✅ بررسی وجود حداقل یک ردیف با `movement: "in"`
4. ✅ (پیشنهادی) بررسی وجود `bom_ids` در `extra_info` فاکتور

#### 2.6: ساخت Payload

**در `extra_info` فاکتور**:
```json
{
  "bom_ids": [1, 2],  // لیست ID فرمول‌های استفاده شده
  "production_operations_total": 50000,  // هزینه عملیات/سربار
  "post_inventory": true,
  "totals": {...}
}
```

**در `extra_info` هر ردیف**:
```json
{
  "movement": "out" | "in",
  "bom_id": 1,  // ID فرمول استفاده شده
  "cost_price": 1000,  // برای محصولات نهایی
  "warehouse_id": 5,
  "unit_price": 1000,
  ...
}
```

---

### مرحله 3: ثبت حسابداری (Backend)

**محاسبات**:
1. **مواد اولیه (movement: "out")**:
   - محاسبه COGS از `cogs_amount` یا `cost_price` یا `unit_price`
   - مجموع: `total_materials_cost`

2. **هزینه عملیات**:
   - از `production_operations_total` در `header_extra`
   - مجموع: `operations_total`

3. **محصولات نهایی (movement: "in")**:
   - اولویت: `cost_price` > `unit_price` > (مواد اولیه + عملیات) / تعداد
   - مجموع: `total_finished_cost`

**ثبت‌های حسابداری**:
```
بدهکار: WIP (مواد اولیه + هزینه عملیات)
  بستانکار: موجودی مواد اولیه

بدهکار: موجودی محصولات نهایی
  بستانکار: WIP
```

---

## 🛠️ پیشنهادات پیاده‌سازی

### پیشنهاد 1: ایجاد `BomExplosionWidget`

**فایل**: `hesabixUI/hesabix_ui/lib/widgets/invoice/bom_explosion_widget.dart`

**ساختار**:
```dart
class BomExplosionWidget extends StatefulWidget {
  final int businessId;
  final Function(List<InvoiceLineItem>, int bomId) onExploded;
  
  // ...
}

class _BomExplosionWidgetState extends State<BomExplosionWidget> {
  // State variables
  Product? _selectedProduct;
  ProductBOM? _selectedBom;
  double? _productionQuantity;
  bool _isLoading = false;
  
  // Methods
  Future<void> _loadBomsForProduct() async { ... }
  Future<void> _explodeAndAdd() async { ... }
  List<InvoiceLineItem> _convertToLineItems(BomExplosionResult result, int bomId) { ... }
}
```

**عملکرد**:
1. نمایش کارت برجسته در تب "کالاها"
2. دیالوگ انتخاب کالا و فرمول
3. ورود مقدار تولید
4. فراخوانی API `explode_bom`
5. تبدیل نتایج به `InvoiceLineItem` با تنظیم:
   - `movement: "out"` برای `items`
   - `movement: "in"` برای `outputs`
   - `bom_id` در `extra_info`
   - `cost_price` از COGS (برای مواد اولیه)
   - `cost_price` محاسبه شده (برای محصولات نهایی)
6. فراخوانی `onExploded` با لیست ردیف‌ها و `bomId`

---

### پیشنهاد 2: بهبود API `explode_bom` (اختیاری)

**پیشنهاد**: اضافه کردن `bom_id` به پاسخ API

```python
return {
    "items": explosion_items,
    "outputs": out_scaled,
    "bom_id": bom.id,  # اضافه شود
}
```

**نکته**: اگر این تغییر انجام نشود، باید در Frontend `bomId` را از انتخاب کاربر بگیریم.

---

### پیشنهاد 3: اضافه کردن فیلد `production_operations_total`

**مکان**: تب "تنظیمات" در `new_invoice_page.dart`

**کد**:
```dart
// در _buildSettingsTab()
if (_selectedInvoiceType == InvoiceType.production) ...[
  TextFormField(
    decoration: InputDecoration(
      labelText: 'هزینه عملیات/سربار تولید',
      helperText: 'هزینه عملیات و سربار تولید (ریال)',
    ),
    keyboardType: TextInputType.number,
    onChanged: (value) {
      setState(() {
        _productionOperationsTotal = double.tryParse(value);
      });
    },
  ),
],
```

**ذخیره در `_validateAndBuildPayload`**:
```dart
if (_selectedInvoiceType == InvoiceType.production) {
  if (_productionOperationsTotal != null && _productionOperationsTotal! > 0) {
    extraInfo['production_operations_total'] = _productionOperationsTotal;
  }
}
```

---

### پیشنهاد 4: محاسبه `cost_price` برای محصولات نهایی

**در `BomExplosionWidget` پس از انفجار**:

```dart
List<InvoiceLineItem> _convertToLineItems(
  BomExplosionResult result, 
  int bomId,
  double operationsTotal,
) {
  final lineItems = <InvoiceLineItem>[];
  
  // محاسبه مجموع هزینه مواد اولیه
  double totalMaterialsCost = 0;
  for (final item in result.items) {
    // دریافت COGS از محصول
    final cogs = _getProductCogs(item.componentProductId);
    totalMaterialsCost += item.requiredQty * cogs;
  }
  
  // محاسبه هزینه کل
  final totalCost = totalMaterialsCost + operationsTotal;
  
  // محاسبه تعداد کل محصولات نهایی
  double totalOutputQty = 0;
  for (final output in result.outputs) {
    totalOutputQty += output.ratio;
  }
  
  // محاسبه cost_price برای هر محصول نهایی
  final costPricePerUnit = totalOutputQty > 0 
    ? totalCost / totalOutputQty 
    : 0;
  
  // تبدیل items به ردیف‌ها (movement: "out")
  for (final item in result.items) {
    final cogs = _getProductCogs(item.componentProductId);
    lineItems.add(InvoiceLineItem(
      productId: item.componentProductId,
      quantity: item.requiredQty,
      unitPrice: cogs,
      extraInfo: {
        'movement': 'out',
        'bom_id': bomId,
        'cost_price': cogs,
        'warehouse_id': item.suggestedWarehouseId,
      },
    ));
  }
  
  // تبدیل outputs به ردیف‌ها (movement: "in")
  for (final output in result.outputs) {
    lineItems.add(InvoiceLineItem(
      productId: output.outputProductId,
      quantity: output.ratio,
      unitPrice: costPricePerUnit,
      extraInfo: {
        'movement': 'in',
        'bom_id': bomId,
        'cost_price': costPricePerUnit,
      },
    ));
  }
  
  return lineItems;
}
```

---

### پیشنهاد 5: بهبود مدیریت `_bomIds`

**در `new_invoice_page.dart`**:

```dart
// هنگام حذف ردیف
void _onLineItemRemoved(int index) {
  final removedItem = _lineItems[index];
  final bomId = removedItem.extraInfo?['bom_id'];
  
  setState(() {
    _lineItems.removeAt(index);
    
    // بررسی اینکه آیا ردیف دیگری با این bom_id وجود دارد
    if (bomId != null) {
      final hasOtherItems = _lineItems.any(
        (item) => item.extraInfo?['bom_id'] == bomId
      );
      
      if (!hasOtherItems) {
        _bomIds.remove(bomId);
      }
    }
    
    // محاسبه مجدد جمع‌ها
    _recalculateTotals();
  });
}
```

---

### پیشنهاد 6: پشتیبانی در صفحه ویرایش

**در `edit_invoice_page.dart`**:

1. **بارگذاری `bom_ids`**:
```dart
final bomIds = _originalExtraInfo['bom_ids'] as List<dynamic>?;
_bomIds = bomIds?.map((e) => e as int).toSet() ?? <int>{};
```

2. **افزودن `BomExplosionWidget`**:
```dart
if (_selectedInvoiceType == InvoiceType.production) ...[
  BomExplosionWidget(
    businessId: widget.businessId,
    onExploded: (newItems, bomId) {
      setState(() {
        _lineItems = [..._lineItems, ...newItems];
        _bomIds.add(bomId);
        _recalculateTotals();
      });
    },
  ),
],
```

3. **اعتبارسنجی مشابه صفحه ایجاد**

---

## 📊 اولویت‌بندی کارها

### فاز 1: رفع مشکلات فوری (اولویت بالا)

1. ✅ **ایجاد فایل `BomExplosionWidget`**
   - زمان تخمینی: 4-6 ساعت
   - وابستگی: ندارد

2. ✅ **اضافه کردن فیلد `production_operations_total`**
   - زمان تخمینی: 1-2 ساعت
   - وابستگی: ندارد

3. ✅ **تبدیل `BomExplosionResult` به `InvoiceLineItem`**
   - زمان تخمینی: 2-3 ساعت
   - وابستگی: نیاز به `BomExplosionWidget`

### فاز 2: بهبود عملکرد (اولویت متوسط)

4. ✅ **محاسبه `cost_price` برای محصولات نهایی**
   - زمان تخمینی: 2-3 ساعت
   - وابستگی: نیاز به فیلد `production_operations_total`

5. ✅ **بهبود مدیریت `_bomIds`**
   - زمان تخمینی: 1-2 ساعت
   - وابستگی: ندارد

6. ✅ **بهبود اعتبارسنجی**
   - زمان تخمینی: 2-3 ساعت
   - وابستگی: ندارد

### فاز 3: تکمیل (اولویت پایین)

7. ✅ **پشتیبانی در صفحه ویرایش**
   - زمان تخمینی: 3-4 ساعت
   - وابستگی: نیاز به `BomExplosionWidget`

8. ✅ **بهبود API `explode_bom` (اختیاری)**
   - زمان تخمینی: 1-2 ساعت
   - وابستگی: ندارد

---

## 📝 نکات حسابداری مهم

### 1. محاسبه هزینه تمام‌شده

**فرمول**:
```
هزینه تمام‌شده = هزینه مواد اولیه + هزینه عملیات/سربار
```

**برای هر واحد محصول**:
```
cost_price = هزینه تمام‌شده / تعداد محصولات نهایی
```

### 2. ثبت‌های حسابداری

**برای مواد اولیه (movement: "out")**:
- بدهکار: WIP (Work In Process)
- بستانکار: موجودی مواد اولیه
- مبلغ: مجموع COGS مواد اولیه

**برای هزینه عملیات**:
- بدهکار: WIP
- بستانکار: حساب هزینه عملیات/سربار
- مبلغ: `production_operations_total`

**برای محصولات نهایی (movement: "in")**:
- بدهکار: موجودی محصولات نهایی
- بستانکار: WIP
- مبلغ: `cost_price × quantity` برای هر محصول

### 3. اعتبارسنجی توازن

**باید بررسی شود**:
```
مجموع بدهکار WIP = مجموع بستانکار WIP
```

**یعنی**:
```
(مواد اولیه + هزینه عملیات) = مجموع هزینه محصولات نهایی
```

---

## ✅ چک‌لیست پیاده‌سازی

### Frontend

- [ ] ایجاد فایل `BomExplosionWidget`
- [ ] تبدیل `BomExplosionResult` به `InvoiceLineItem`
- [ ] تنظیم `movement: "out"` برای مواد اولیه
- [ ] تنظیم `movement: "in"` برای محصولات نهایی
- [ ] اضافه کردن `bom_id` به `extra_info` هر ردیف
- [ ] محاسبه `cost_price` برای محصولات نهایی
- [ ] اضافه کردن فیلد `production_operations_total`
- [ ] ذخیره `bom_ids` در `extra_info` فاکتور
- [ ] اعتبارسنجی قبل از ذخیره
- [ ] بهبود مدیریت `_bomIds`
- [ ] پشتیبانی در صفحه ویرایش

### Backend

- [ ] (اختیاری) اضافه کردن `bom_id` به پاسخ API `explode_bom`
- [ ] (اختیاری) بهبود اعتبارسنجی در `create_invoice`
- [ ] بررسی وجود `bom_ids` در `extra_info` فاکتور

---

## 🎯 نتیجه‌گیری

این سناریو یک راه‌حل کامل و اصولی برای پیاده‌سازی فاکتور تولید با استفاده از فرمول تولید ارائه می‌دهد. با رعایت این سناریو:

1. ✅ انفجار فرمول فقط از طریق فاکتور تولید انجام می‌شود
2. ✅ تمام عملیات تولید در یک سند ثبت می‌شود
3. ✅ ثبت‌های حسابداری به درستی انجام می‌شود
4. ✅ ردیابی کامل فرمول‌های استفاده شده امکان‌پذیر است
5. ✅ کنترل و اعتبارسنجی مناسب وجود دارد

---

**تاریخ ایجاد**: 2024
**نسخه**: 1.0
**وضعیت**: پیشنهاد نهایی

