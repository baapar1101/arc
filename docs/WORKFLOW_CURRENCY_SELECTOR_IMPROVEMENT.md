# بهبود Currency Selector در فیلترهای نودهای Workflow

## 🎯 هدف

تبدیل فیلد `currency_id` از TextField معمولی به یک **Dropdown هوشمند** که ارزهای کسب‌وکار را به صورت dynamic از API می‌خواند.

---

## ✅ تغییرات انجام شده

### 1. **Backend - Schema آماده بود** ✅

در `document_triggers.py` (InvoiceCreatedTrigger):

```python
"currency_id": {
    "type": "integer",
    "description": "فیلتر بر اساس ارز",
    "ui_type": "currency_selector",  # ✅
    "ui_config": {
        "business_scoped": True,
        "show_all_option": True
    },
    "required": False
}
```

---

### 2. **Frontend - Widget بهبود یافت** ✅

#### A. اضافه کردن State برای ارزها:

در `workflow_node_config_dialog.dart`:

```dart
class _WorkflowNodeConfigDialogState extends State<WorkflowNodeConfigDialog> {
  // ...
  List<Map<String, dynamic>> _currencies = [];      // ✅ لیست ارزها
  bool _loadingCurrencies = false;                   // ✅ وضعیت لود
```

#### B. متد بارگذاری ارزها:

```dart
Future<void> _loadCurrenciesIfNeeded() async {
  if (widget.businessId == null) return;
  
  // بررسی نیاز به لود ارزها
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
    setState(() => _loadingCurrencies = true);
    try {
      final response = await _workflowService.getBusinessCurrencies(
        businessId: widget.businessId!,
      );
      setState(() {
        _currencies = response;
        _loadingCurrencies = false;
      });
    } catch (e) {
      // در صورت خطا، از لیست پیش‌فرض استفاده می‌شود
      setState(() {
        _currencies = [
          {'id': 1, 'code': 'IRR', 'name': 'ریال', 'symbol': '﷼'},
          // ...
        ];
        _loadingCurrencies = false;
      });
    }
  }
}
```

#### C. Widget بهبود یافته `_buildCurrencySelector`:

```dart
Widget _buildCurrencySelector(...) {
  // چک reference
  if (currentValue?.toString().startsWith('\$') ?? false) {
    return _buildReferenceTextField(...);
  }
  
  return Column(
    children: [
      // Loading state
      if (_loadingCurrencies)
        Container(
          child: Row(
            children: [
              CircularProgressIndicator(),
              Text('در حال بارگذاری ارزها...'),
            ],
          ),
        )
      // Empty state
      else if (_currencies.isEmpty)
        Container(
          child: Text('ارزی یافت نشد'),
        )
      // Dropdown با ارزها
      else
        DropdownButtonFormField<int>(
          value: currentValue is int ? currentValue : null,
          decoration: InputDecoration(
            labelText: _formatKey(key),
            prefixIcon: Icon(Icons.monetization_on),
          ),
          items: _currencies.map((currency) {
            final id = currency['id'] as int;
            final symbol = currency['symbol'] as String? ?? '';
            final name = currency['title'] ?? currency['name'] ?? '';
            final code = currency['code'] ?? '';
            final isDefault = currency['is_default'] == true;
            
            return DropdownMenuItem<int>(
              value: id,
              child: Row(
                children: [
                  Text(symbol, style: TextStyle(fontWeight: FontWeight.bold)),
                  SizedBox(width: 8),
                  Expanded(child: Text('$name ($code)')),
                  if (isDefault)
                    Container(
                      child: Text('پیش‌فرض'),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                      ),
                    ),
                ],
              ),
            );
          }).toList(),
          onChanged: (newValue) {
            // ...
          },
        ),
      // دکمه Reference
      if (!_loadingCurrencies)
        OutlinedButton.icon(
          icon: Icon(Icons.link),
          label: Text('استفاده از نود قبلی'),
          onPressed: () => _showReferenceSelector(key),
        ),
    ],
  );
}
```

---

### 3. **Service - متد جدید** ✅

در `workflow_service.dart`:

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

---

## 🎨 نمایش در UI

### حالت Loading:

```
┌─────────────────────────────────────────┐
│ ⏳ در حال بارگذاری ارزها...             │
└─────────────────────────────────────────┘
```

### حالت Empty:

```
┌─────────────────────────────────────────┐
│ ⚠️ ارزی یافت نشد. لطفاً شناسه ارز را   │
│    وارد کنید.                            │
└─────────────────────────────────────────┘
```

### حالت عادی (Dropdown):

```
┌─────────────────────────────────────────┐
│ 💰 ارز ▼                                 │
├─────────────────────────────────────────┤
│ ﷼  ریال ایران (IRR)     [پیش‌فرض]  ✓  │
│ $  دلار آمریکا (USD)                    │
│ €  یورو (EUR)                           │
│ د.إ درهم امارات (AED)                   │
└─────────────────────────────────────────┘

[🔗 استفاده از نود قبلی]
```

### حالت Reference:

```
┌─────────────────────────────────────────┐
│ ارز                                      │
├─────────────────────────────────────────┤
│ 🔗 $trigger-1.currency_id      [🔗] [⭐] │
└─────────────────────────────────────────┘
ℹ️ این مقدار از یک نود قبلی استفاده می‌کند

[🔗 استفاده از نود قبلی]
```

---

## 🔄 روند کار

### 1. هنگام باز شدن دیالوگ:

```
initState()
  ↓
تشخیص schema های موجود
  ↓
آیا ui_type = "currency_selector" وجود دارد؟
  ↓ (بله)
_loadCurrenciesIfNeeded()
  ↓
API Call: GET /api/v1/currencies/business/{businessId}
  ↓
setState: _currencies = response
  ↓
Rebuild Widget با لیست ارزها
```

### 2. هنگام انتخاب:

```
کاربر روی Dropdown کلیک می‌کند
  ↓
لیست ارزها نمایش داده می‌شود
  ↓
کاربر یک ارز را انتخاب می‌کند
  ↓
onChanged() فراخوانی می‌شود
  ↓
_config[key] = selectedCurrencyId
  ↓
setState() برای به‌روزرسانی UI
```

---

## 🎁 ویژگی‌های اضافه شده

### 1. **نمایش ارز پیش‌فرض**:
- ارزی که `is_default = true` است، با badge "پیش‌فرض" نمایش داده می‌شود

### 2. **نمایش نماد ارز**:
- هر ارز با نماد خودش نمایش داده می‌شود (﷼, $, €, د.إ)

### 3. **Fallback**:
- در صورت خطا در API، از لیست hardcoded استفاده می‌شود

### 4. **Reference Support**:
- پشتیبانی کامل از مقادیر reference (`$node_id.currency_id`)

### 5. **Loading State**:
- نمایش وضعیت بارگذاری با CircularProgressIndicator

### 6. **Empty State**:
- پیام مناسب برای حالتی که ارزی موجود نیست

---

## 📊 مقایسه قبل و بعد

| ویژگی | قبل ❌ | بعد ✅ |
|-------|--------|-------|
| نوع ورودی | TextField (number) | Dropdown با لیست |
| منبع داده | - | API (Dynamic) |
| نمایش نام ارز | خیر (فقط ID) | بله (نام + نماد + کد) |
| نمایش ارز پیش‌فرض | خیر | بله (با badge) |
| Loading State | خیر | بله |
| Empty State | خیر | بله |
| Reference Support | خیر | بله |
| UX | ضعیف (تایپ ID) | عالی (انتخاب بصری) |

---

## 🧪 نحوه تست

### 1. تست عادی:
```
1. وارد صفحه ویرایش workflow شوید
2. یک نود trigger از نوع "InvoiceCreatedTrigger" اضافه کنید
3. روی ویرایش نود کلیک کنید
4. به فیلتر currency_id بروید
5. باید Dropdown با لیست ارزهای کسب‌وکار نمایش داده شود
6. ارزی را انتخاب کنید و ذخیره کنید
```

### 2. تست Reference:
```
1. دو نود اضافه کنید (یک trigger و یک action)
2. در action، روی دکمه "استفاده از نود قبلی" کلیک کنید
3. نود trigger را انتخاب کنید
4. فیلد currency_id را انتخاب کنید
5. باید $trigger-1.currency_id در TextField نمایش داده شود
```

### 3. تست خطا:
```
1. اتصال به API را قطع کنید
2. دیالوگ تنظیمات نود را باز کنید
3. باید لیست fallback با 4 ارز رایج نمایش داده شود
```

---

## 📁 فایل‌های تغییر یافته

### Backend:
- ✅ `hesabixAPI/app/services/workflow/triggers/document_triggers.py` (قبلاً آماده بود)

### Frontend:
- ✅ `hesabixUI/hesabix_ui/lib/widgets/workflow/workflow_node_config_dialog.dart`
- ✅ `hesabixUI/hesabix_ui/lib/services/workflow_service.dart`

---

## 🚀 بهبودهای آینده (اختیاری)

1. **Cache کردن ارزها**: برای جلوگیری از API call های مکرر
2. **Multi-Currency Support**: انتخاب چند ارز همزمان
3. **Currency Conversion**: نمایش نرخ تبدیل
4. **Search در Dropdown**: برای لیست‌های بلند
5. **Custom Currency**: امکان افزودن ارز دلخواه

---

**تاریخ**: دسامبر 2025  
**وضعیت**: ✅ کامل و آماده استفاده


