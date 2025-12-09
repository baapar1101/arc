# تست Currency Selector در نودهای Workflow

## ✅ بررسی کدها

### 1. Backend Schema - ✅ صحیح

فایل: `hesabixAPI/app/services/workflow/triggers/document_triggers.py`

```python
"currency_id": {
    "type": "integer",
    "description": "فیلتر بر اساس ارز",
    "ui_type": "currency_selector",      # ✅ درست است
    "ui_config": {
        "business_scoped": True,
        "show_all_option": True
    },
    "required": False
},
```

### 2. Frontend Code - ✅ صحیح

فایل: `hesabixUI/hesabix_ui/lib/widgets/workflow/workflow_node_config_dialog.dart`

**بررسی ui_type:**
```dart
// خط 393
} else if (uiType == 'currency_selector') {
  return _buildCurrencySelector(key, schema, value, required, description);
}
```
✅ درست است

**متد _buildCurrencySelector:**
```dart
// خط 1029
Widget _buildCurrencySelector(
  String key,
  Map<String, dynamic> schema,
  dynamic currentValue,
  bool required,
  String? description,
) {
  // ... کد کامل موجود است
}
```
✅ موجود است

**متد _loadCurrenciesIfNeeded:**
```dart
Future<void> _loadCurrenciesIfNeeded() async {
  if (widget.businessId == null) return;
  
  bool needsCurrencies = false;
  if (_configSchema != null) {
    for (final entry in _configSchema!.entries) {
      final schema = entry.value;
      if (schema is Map<String, dynamic>) {
        final uiType = schema['ui_type'] as String?;
        if (uiType == 'currency_selector') {
          needsCurrencies = true;
          break;
        }
      }
    }
  }
  
  if (needsCurrencies) {
    // ... بارگذاری ارزها
  }
}
```
✅ موجود است

**State variables:**
```dart
List<Map<String, dynamic>> _currencies = [];
bool _loadingCurrencies = false;
```
✅ موجود است

### 3. Service Method - ✅ صحیح

فایل: `hesabixUI/hesabix_ui/lib/services/workflow_service.dart`

```dart
Future<List<Map<String, dynamic>>> getBusinessCurrencies({
  required int businessId,
}) async {
  final res = await _apiClient.get<Map<String, dynamic>>(
    '/api/v1/currencies/business/$businessId',
  );
  final data = res.data?['data'];
  if (data is List) {
    return data
        .map<Map<String, dynamic>>((c) => Map<String, dynamic>.from(c as Map))
        .toList();
  }
  return const <Map<String, dynamic>>[];
}
```
✅ موجود است

---

## 🔍 علت مشکل احتمالی

اگر فیلد هنوز به صورت TextField نمایش داده می‌شود، ممکن است:

### 1. **Cache مرورگر:**
```bash
# پاک کردن cache
cd /var/www/ark/hesabixUI/hesabix_ui
flutter clean
flutter pub get
flutter build web --release
```

### 2. **Hot Reload کافی نیست:**
- باید اپلیکیشن را کامل restart کنید
- یا build جدید بگیرید

### 3. **businessId موجود نیست:**
- اگر `widget.businessId` null باشه، ارزها لود نمی‌شوند
- بررسی کنید که در context مناسب استفاده می‌شود

### 4. **Schema به درستی parse نشده:**
- ممکنه metadata از API به درستی نیامده
- Debug کنید: `print(_configSchema);`

---

## 🧪 روش تست دقیق

### مرحله 1: بررسی Metadata

```dart
// در _WorkflowNodeConfigDialogState.initState()
print('=== DEBUG: Config Schema ===');
if (_configSchema != null) {
  _configSchema!.forEach((key, value) {
    if (key == 'currency_id') {
      print('Found currency_id:');
      print('  Type: ${value['type']}');
      print('  UI Type: ${value['ui_type']}');
      print('  Description: ${value['description']}');
    }
  });
}
```

### مرحله 2: بررسی Loading

```dart
// در _loadCurrenciesIfNeeded
print('=== Loading Currencies ===');
print('businessId: ${widget.businessId}');
print('needsCurrencies: $needsCurrencies');

// بعد از دریافت
print('Currencies loaded: ${_currencies.length}');
_currencies.forEach((c) {
  print('  - ${c['name']} (${c['code']})');
});
```

### مرحله 3: بررسی Render

```dart
// در _buildConfigFieldFromSchema
final uiType = schema['ui_type'] as String?;
print('=== Rendering field: $key ===');
print('  UI Type: $uiType');

if (uiType == 'currency_selector') {
  print('  ✅ Calling _buildCurrencySelector');
  return _buildCurrencySelector(key, schema, value, required, description);
}
```

---

## 🚀 راه حل سریع

اگر همه چیز درست است ولی هنوز کار نمی‌کند:

### گزینه 1: Hard Refresh مرورگر
```
Ctrl + Shift + R (Windows/Linux)
Cmd + Shift + R (Mac)
```

### گزینه 2: Build کامل جدید
```bash
cd /var/www/ark/hesabixUI/hesabix_ui
flutter clean
rm -rf build/
flutter pub get
flutter build web --release
```

### گزینه 3: بررسی Workflow Metadata از API

باز کردن DevTools و چک کردن:
```
Network Tab > Workflow API Calls > Response
```

بررسی کنید که metadata شامل این باشد:
```json
{
  "currency_id": {
    "type": "integer",
    "ui_type": "currency_selector",
    "description": "فیلتر بر اساس ارز",
    "ui_config": {
      "business_scoped": true
    }
  }
}
```

---

## 📝 چک لیست نهایی

- [x] Backend schema دارای `ui_type: "currency_selector"` است
- [x] Frontend شامل `_buildCurrencySelector` است
- [x] Service شامل `getBusinessCurrencies` است
- [x] State variables اضافه شده‌اند
- [x] `_loadCurrenciesIfNeeded` فراخوانی می‌شود
- [ ] Cache پاک شده است ✅ انجام شد
- [ ] Build جدید گرفته شده است
- [ ] مرورگر refresh شده است

---

## 💡 نکته مهم

اگر در حال توسعه هستید و از **Hot Reload** استفاده می‌کنید:

```dart
// Hot Reload کافی نیست برای تغییرات State
// باید Hot Restart انجام دهید:
```

کلیدهای میانبر:
- Hot Restart: `Ctrl + Shift + F5` (VS Code)
- یا در terminal: `r` (برای reload) و `R` (برای restart)

---

**نتیجه:**  
کد ✅ درست است  
Cache 🔄 پاک شد  
Build جدید 🚀 لازم است

