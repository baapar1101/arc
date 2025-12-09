# رفع مشکل نمایش Currency_ID به صورت TextField در نودهای Workflow

## 🐛 مشکل

فیلد `currency_id` در فیلترهای نود InvoiceCreatedTrigger همچنان به صورت TextField عددی نمایش داده می‌شد به جای Dropdown انتخاب ارز.

---

## 🔍 علت ریشه‌ای

در کد Frontend، بررسی `ui_type` فقط برای فیلدهای از نوع `string` انجام می‌شد. اما `currency_id` از نوع `integer` است!

### کد قبلی (اشتباه):

```dart
switch (fieldType) {
  case 'string':
    // بررسی ui_type فقط اینجا بود ❌
    final uiType = schema['ui_type'] as String?;
    if (uiType == 'currency_selector') {
      return _buildCurrencySelector(...);
    }
    // ...
    
  case 'integer':
  case 'number':
    // هیچ بررسی ui_type نبود! ❌
    return TextFormField(...);  // همیشه TextField نشان می‌داد
```

---

## ✅ راه حل

اضافه کردن بررسی `ui_type` در case های `integer` و `number`:

```dart
case 'number':
case 'integer':
  // ✅ اول ui_type را چک می‌کنیم
  final uiType = schema['ui_type'] as String?;
  
  if (uiType == 'currency_selector') {
    return _buildCurrencySelector(key, schema, value, required, description);
  } else if (uiType == 'person_selector') {
    return _buildPersonSelector(key, schema, value, required, description);
  } else if (uiType == 'product_selector') {
    return _buildProductSelector(key, schema, value, required, description);
  } else if (uiType == 'warehouse_selector') {
    return _buildWarehouseSelector(key, schema, value, required, description);
  } else if (uiType == 'account_selector') {
    return _buildAccountSelector(key, schema, value, required, description);
  } else if (uiType == 'fiscal_year_selector') {
    return _buildFiscalYearSelector(key, schema, value, required, description);
  }
  
  // ✅ اگر ui_type خاصی نبود، TextField عددی معمولی
  return Padding(...);
```

---

## 🆕 متدهای Helper اضافه شده

### 1. **_buildNumberFieldWithReference**

یک TextField عددی که از Reference هم پشتیبانی می‌کند:

```dart
Widget _buildNumberFieldWithReference(
  String key,
  Map<String, dynamic> schema,
  dynamic currentValue,
  bool required,
  String? description,
  String fieldType,  // 'integer' or 'number'
) {
  final isReference = currentValue?.toString().startsWith('\$') ?? false;
  
  return TextFormField(
    initialValue: currentValue?.toString(),
    keyboardType: isReference ? TextInputType.text : TextInputType.number,
    decoration: InputDecoration(
      prefixIcon: isReference ? Icon(Icons.link) : null,
      suffixIcon: Row(
        children: [
          IconButton(
            icon: Icon(Icons.select_all),
            onPressed: () => _showReferenceSelector(key),
          ),
        ],
      ),
    ),
    onSaved: (newValue) {
      if (newValue?.startsWith('\$') ?? false) {
        _config[key] = newValue;  // ذخیره به صورت reference
      } else {
        _config[key] = fieldType == 'integer' 
            ? int.tryParse(newValue ?? '') ?? currentValue
            : double.tryParse(newValue ?? '') ?? currentValue;
      }
    },
  );
}
```

### 2. **Stub Methods** برای سلکتورهای آینده:

```dart
Widget _buildWarehouseSelector(...) {
  return _buildNumberFieldWithReference(...);
}

Widget _buildAccountSelector(...) {
  return _buildNumberFieldWithReference(...);
}

Widget _buildFiscalYearSelector(...) {
  return _buildNumberFieldWithReference(...);
}
```

این‌ها فعلاً مثل TextField عددی کار می‌کنند ولی آماده پیاده‌سازی کامل هستند.

---

## 📊 حالا چطور کار می‌کند؟

### روند Render فیلد currency_id:

```
1. Schema می‌گوید: type = "integer"
   ↓
2. Case 'integer' فراخوانی می‌شود
   ↓
3. بررسی ui_type:
   schema['ui_type'] = "currency_selector"
   ↓
4. شرط if (uiType == 'currency_selector') برقرار است
   ↓
5. ✅ _buildCurrencySelector() فراخوانی می‌شود
   ↓
6. Dropdown با لیست ارزها نمایش داده می‌شود!
```

---

## 🎨 نتیجه نهایی

### قبل (اشتباه):

```
┌────────────────────────────────────┐
│ Currency Id                  [⭐]  │  ← TextField عددی
├────────────────────────────────────┤
│ 1                                  │
└────────────────────────────────────┘
```

### بعد (صحیح):

```
┌────────────────────────────────────┐
│ 💰 ارز ▼                            │  ← Dropdown
├────────────────────────────────────┤
│ ﷼ ریال ایران (IRR)  [پیش‌فرض]  ✓ │
│ $ دلار آمریکا (USD)                │
│ € یورو (EUR)                       │
│ د.إ درهم امارات (AED)              │
└────────────────────────────────────┘

[🔗 استفاده از نود قبلی]
```

---

## 🔧 تغییرات نهایی

### فایل تغییر یافته:
- ✅ `hesabixUI/hesabix_ui/lib/widgets/workflow/workflow_node_config_dialog.dart`

### تغییرات:
1. ✅ بررسی `ui_type` در case `integer` و `number`
2. ✅ اضافه شدن 6 شرط برای ui_type های مختلف
3. ✅ متد `_buildNumberFieldWithReference` برای TextField های عددی
4. ✅ Stub methods برای سلکتورهای آینده

---

## ✅ نتیجه

اکنون **همه فیلدهای integer/number** که `ui_type` خاصی دارند، به درستی با Widget مناسب نمایش داده می‌شوند:

| ui_type | Widget |
|---------|--------|
| `currency_selector` | ✅ Dropdown ارزها |
| `person_selector` | ✅ Person Field با Reference |
| `product_selector` | ✅ Product Field با Reference |
| `warehouse_selector` | ⏳ TextField (آماده بهبود) |
| `account_selector` | ⏳ TextField (آماده بهبود) |
| `fiscal_year_selector` | ⏳ TextField (آماده بهبود) |
| بدون ui_type | TextField عددی معمولی |

---

**وضعیت**: ✅ رفع شد - آماده تست است!

