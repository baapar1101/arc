# 🌍 سیستم ترجمه (i18n) برای نودهای ورک‌فلو

## 📋 خلاصه اجرایی

این مستند یک سیستم جامع برای چند زبانه کردن نودهای ورک‌فلو ارائه می‌دهد. این سیستم امکان ترجمه تمام رشته‌های استفاده شده در:
- نام و توضیحات نودها
- نام فیلدها و توضیحات آن‌ها
- گزینه‌های enum
- پیام‌های کمکی (help texts)
- پیام‌های خطا (validation errors)

را فراهم می‌کند.

---

## 🏗️ معماری سیستم

### کامپوننت‌ها:

```
┌─────────────────────────────────────────────────────────────┐
│                        Backend (Python)                      │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  workflow_translations.py                                    │
│  ├─ COMMON_TRANSLATIONS                                      │
│  ├─ CREATE_INVOICE_TRANSLATIONS                             │
│  ├─ SEND_TELEGRAM_TRANSLATIONS                              │
│  ├─ SEND_EMAIL_TRANSLATIONS                                 │
│  └─ OTHER_ACTIONS_TRANSLATIONS                              │
│                                                              │
│  API Endpoints:                                              │
│  ├─ GET /workflows/metadata/actions?lang=fa                 │
│  ├─ GET /workflows/metadata/triggers?lang=fa                │
│  ├─ GET /workflows/translations?lang=fa                     │
│  └─ GET /workflows/translations/export?lang=fa              │
│                                                              │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                      Frontend (Flutter)                      │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  WorkflowTranslationService                                  │
│  ├─ getTranslations(lang)                                    │
│  ├─ getActionsMetadata(lang)                                 │
│  ├─ getTriggersMetadata(lang)                                │
│  └─ getFieldTranslation(action, field, type)                │
│                                                              │
│  WorkflowLocalizations Extension                             │
│  ├─ workflowCreateInvoiceActionName                         │
│  ├─ workflowSendTelegramFieldMessage                        │
│  └─ ... (تمام ترجمه‌ها)                                     │
│                                                              │
│  UI Components:                                              │
│  └─ WorkflowNodeConfigDialog                                │
│     ├─ استفاده از ترجمه‌ها در labels                       │
│     ├─ استفاده از ترجمه‌ها در descriptions                 │
│     ├─ استفاده از ترجمه‌ها در placeholders                 │
│     └─ استفاده از ترجمه‌ها در enum labels                  │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 🔧 نحوه کار

### 1. Backend (Python)

#### ساختار ترجمه‌ها:

```python
CREATE_INVOICE_TRANSLATIONS = {
    "fa": {
        "action_name": "ایجاد فاکتور",
        "action_description": "ایجاد فاکتور فروش، خرید یا...",
        
        "group_basic_info": "اطلاعات پایه",
        "group_items": "آیتم‌های فاکتور",
        
        "field_invoice_type": "نوع فاکتور",
        "field_invoice_type_desc": "نوع فاکتور",
        
        "invoice_sales": "🛒 فاکتور فروش",
        "invoice_purchase": "🛍️ فاکتور خرید",
        
        "error_min_items": "حداقل یک آیتم باید وارد شود",
    },
    "en": {
        "action_name": "Create Invoice",
        "action_description": "Create sales, purchase or...",
        
        "group_basic_info": "Basic Information",
        "group_items": "Invoice Items",
        
        "field_invoice_type": "Invoice Type",
        "field_invoice_type_desc": "Invoice Type",
        
        "invoice_sales": "🛒 Sales Invoice",
        "invoice_purchase": "🛍️ Purchase Invoice",
        
        "error_min_items": "At least one item is required",
    }
}
```

#### API Endpoints:

**1. دریافت ترجمه‌ها:**
```http
GET /api/v1/workflows/translations?lang=fa

Response:
{
  "language": "fa",
  "translations": {
    "settings": "تنظیمات",
    "create_invoice": {
      "action_name": "ایجاد فاکتور",
      "field_invoice_type": "نوع فاکتور"
    }
  }
}
```

**2. دریافت metadata با ترجمه:**
```http
GET /api/v1/workflows/metadata/actions?lang=en

Response:
{
  "data": [
    {
      "key": "create_invoice",
      "name": "Create Invoice",  // ترجمه شده
      "description": "Create sales invoice...",  // ترجمه شده
      "config_schema": {
        "invoice_type": {
          "description": "Invoice Type",  // ترجمه شده
          "enum": ["invoice_sales", "invoice_purchase"],
          "ui_config": {
            "labels": {
              "invoice_sales": "Sales Invoice",  // ترجمه شده
              "invoice_purchase": "Purchase Invoice"  // ترجمه شده
            }
          }
        }
      }
    }
  ]
}
```

**3. صادرات به فرمت arb:**
```http
GET /api/v1/workflows/translations/export?lang=fa

Response:
{
  "format": "arb",
  "translations": {
    "workflowSettings": "تنظیمات",
    "workflowCreateInvoiceActionName": "ایجاد فاکتور",
    "workflowCreateInvoiceFieldInvoiceType": "نوع فاکتور"
  }
}
```

---

### 2. Frontend (Flutter)

#### استفاده در UI:

```dart
import '../../services/workflow_translation_service.dart';
import '../../extensions/workflow_localizations_extension.dart';

class _WorkflowNodeConfigDialogState extends State<WorkflowNodeConfigDialog> {
  final WorkflowTranslationService _translationService = WorkflowTranslationService();
  Map<String, dynamic>? _translations;
  
  @override
  void initState() {
    super.initState();
    _loadTranslations();
  }
  
  Future<void> _loadTranslations() async {
    final locale = Localizations.localeOf(context);
    final translations = await _translationService.getTranslations(lang: locale.languageCode);
    setState(() {
      _translations = translations;
    });
  }
  
  Widget build(BuildContext context) {
    // استفاده از extension
    final t = AppLocalizations.of(context);
    final label = t.workflowCreateInvoiceFieldInvoiceType;
    
    // یا استفاده از service
    final description = _translationService.getFieldTranslation(
      'create_invoice',
      'invoice_type',
      type: 'desc',
    );
    
    return TextFormField(
      decoration: InputDecoration(
        labelText: label,
        helperText: description,
      ),
    );
  }
}
```

---

## 📝 نحوه افزودن ترجمه برای نود جدید

### مرحله 1: افزودن ترجمه‌ها در Python

**فایل:** `app/services/workflow/i18n/workflow_translations.py`

```python
# ترجمه‌های نود جدید
MY_NEW_ACTION_TRANSLATIONS = {
    "fa": {
        "action_name": "نام فارسی اکشن",
        "action_description": "توضیحات فارسی اکشن",
        
        "field_my_field": "نام فیلد",
        "field_my_field_desc": "توضیحات فیلد",
        "field_my_field_placeholder": "متن placeholder",
        "field_my_field_help": "متن کمکی",
        
        "my_enum_value": "لیبل فارسی",
        
        "error_my_error": "پیام خطا",
    },
    "en": {
        "action_name": "English Action Name",
        "action_description": "English action description",
        
        "field_my_field": "Field Name",
        "field_my_field_desc": "Field description",
        "field_my_field_placeholder": "Placeholder text",
        "field_my_field_help": "Help text",
        
        "my_enum_value": "English Label",
        
        "error_my_error": "Error message",
    }
}
```

### مرحله 2: اضافه کردن به exports

```python
# در همان فایل
__all__ = [
    ...,
    "MY_NEW_ACTION_TRANSLATIONS",
]

# در تابع get_translation
translations_map = {
    ...,
    "my_new_action": MY_NEW_ACTION_TRANSLATIONS,
}
```

### مرحله 3: استخراج و صادرات

```bash
cd /var/www/ark/hesabixAPI
source venv/bin/activate
python scripts/extract_workflow_translations.py
```

### مرحله 4: بازسازی Flutter

```bash
cd /var/www/ark/hesabixUI/hesabix_ui
flutter pub run build_runner build --delete-conflicting-outputs
```

---

## 🎨 الگوهای نام‌گذاری

### Backend (Python):

| نوع | الگو | مثال |
|-----|------|------|
| نام action | `action_name` | `"ایجاد فاکتور"` |
| توضیحات action | `action_description` | `"ایجاد فاکتور..."` |
| نام گروه | `group_{group_key}` | `group_basic_info` |
| نام فیلد | `field_{field_key}` | `field_invoice_type` |
| توضیحات فیلد | `field_{field_key}_desc` | `field_invoice_type_desc` |
| Placeholder فیلد | `field_{field_key}_placeholder` | `field_message_placeholder` |
| راهنمای فیلد | `field_{field_key}_help` | `field_items_help` |
| Enum value | `{enum_value}` | `invoice_sales` |
| پیام خطا | `error_{error_key}` | `error_min_items` |

### Frontend (Dart):

| نوع | الگو | مثال |
|-----|------|------|
| نام action | `workflow{Action}ActionName` | `workflowCreateInvoiceActionName` |
| توضیحات action | `workflow{Action}ActionDescription` | `workflowCreateInvoiceActionDescription` |
| نام فیلد | `workflow{Action}Field{Field}` | `workflowCreateInvoiceFieldInvoiceType` |
| Enum value | `workflow{Action}{EnumValue}` | `workflowCreateInvoiceInvoiceSales` |

---

## 📊 ساختار فایل‌ها

### Backend:

```
hesabixAPI/
├── app/
│   └── services/
│       └── workflow/
│           ├── i18n/
│           │   ├── __init__.py
│           │   └── workflow_translations.py  ← ترجمه‌ها
│           └── actions/
│               ├── communication_actions.py  ← استفاده از ترجمه
│               ├── document_actions.py       ← استفاده از ترجمه
│               └── utility_actions.py        ← استفاده از ترجمه
├── adapters/
│   └── api/
│       └── v1/
│           └── workflows.py  ← API endpoints برای ترجمه
└── scripts/
    └── extract_workflow_translations.py  ← اسکریپت استخراج
```

### Frontend:

```
hesabixUI/hesabix_ui/
├── lib/
│   ├── services/
│   │   └── workflow_translation_service.dart  ← سرویس ترجمه
│   ├── extensions/
│   │   └── workflow_localizations_extension.dart  ← Extension
│   ├── widgets/
│   │   └── workflow/
│   │       └── workflow_node_config_dialog.dart  ← استفاده از ترجمه
│   └── l10n/
│       ├── workflow_fa.arb  ← ترجمه‌های فارسی (auto-generated)
│       └── workflow_en.arb  ← ترجمه‌های انگلیسی (auto-generated)
```

---

## 🚀 نحوه استفاده

### 1. در Backend:

#### افزودن ترجمه به metadata:

```python
from app.services.workflow.i18n import translate_metadata

class MyAction(ActionHandler):
    def get_metadata(self) -> Dict[str, Any]:
        return {
            "name": "نام پیش‌فرض",  # این جایگزین می‌شود
            "description": "توضیحات پیش‌فرض",  # این جایگزین می‌شود
            "config_schema": {
                "my_field": {
                    "type": "string",
                    "description": "توضیحات فیلد",  # این جایگزین می‌شود
                    "enum": ["value1", "value2"],
                    "ui_config": {
                        # labels جایگزین می‌شوند
                    }
                }
            }
        }
```

#### استفاده در API endpoint:

```python
@router.get("/workflows/metadata/actions")
async def get_actions_metadata(lang: str = "fa"):
    action_registry = ActionRegistry()
    all_actions = action_registry.get_all_metadata()
    
    translated_actions = []
    for action in all_actions:
        translated = translate_metadata(action, lang, action.get("key"))
        translated_actions.append(translated)
    
    return success_response(data=translated_actions)
```

### 2. در Frontend:

#### استفاده از Extension:

```dart
import '../../extensions/workflow_localizations_extension.dart';

@override
Widget build(BuildContext context) {
  final t = AppLocalizations.of(context);
  
  return Column(
    children: [
      Text(t.workflowCreateInvoiceActionName),
      Text(t.workflowCreateInvoiceFieldInvoiceType),
      Text(t.workflowSendTelegramFieldMessage),
    ],
  );
}
```

#### استفاده از Service:

```dart
final translationService = WorkflowTranslationService();

// بارگذاری ترجمه‌ها
final translations = await translationService.getTranslations(lang: 'fa');

// دریافت metadata با ترجمه
final actionsMetadata = await translationService.getActionsMetadata(lang: 'fa');

// دریافت ترجمه یک فیلد خاص
final fieldLabel = translationService.getFieldTranslation(
  'create_invoice',
  'invoice_type',
  type: 'name',
);
```

#### در Dialog تنظیمات نود:

```dart
class _WorkflowNodeConfigDialogState extends State<WorkflowNodeConfigDialog> {
  Map<String, dynamic>? _translations;
  
  @override
  void initState() {
    super.initState();
    _loadTranslations();
  }
  
  Future<void> _loadTranslations() async {
    final locale = Localizations.localeOf(context);
    final translations = await _translationService.getTranslations(
      lang: locale.languageCode
    );
    setState(() {
      _translations = translations;
    });
  }
  
  String _formatKey(String key) {
    // استفاده از ترجمه (اگر موجود باشد)
    if (_translations != null && widget.node.key != null) {
      final actionKey = widget.node.key;
      final fieldKey = 'field_$key';
      
      if (_translations![actionKey]?[fieldKey] != null) {
        return _translations![actionKey][fieldKey];
      }
    }
    
    // Fallback
    return _formatFieldName(key);
  }
}
```

---

## 📚 مثال کامل: نود "ایجاد فاکتور"

### Backend:

```python
# در workflow_translations.py
CREATE_INVOICE_TRANSLATIONS = {
    "fa": {
        "action_name": "ایجاد فاکتور",
        "field_invoice_type": "نوع فاکتور",
        "invoice_sales": "🛒 فاکتور فروش",
        "invoice_purchase": "🛍️ فاکتور خرید",
    },
    "en": {
        "action_name": "Create Invoice",
        "field_invoice_type": "Invoice Type",
        "invoice_sales": "🛒 Sales Invoice",
        "invoice_purchase": "🛍️ Purchase Invoice",
    }
}

# در document_actions.py
class CreateInvoiceAction(ActionHandler):
    def get_metadata(self) -> Dict[str, Any]:
        return {
            "name": "ایجاد فاکتور",  # جایگزین می‌شود با ترجمه
            "config_schema": {
                "invoice_type": {
                    "enum": ["invoice_sales", "invoice_purchase"],
                    "ui_config": {
                        "labels": {
                            # این labels از ترجمه می‌آید
                            "invoice_sales": "فاکتور فروش",
                            "invoice_purchase": "فاکتور خرید"
                        }
                    }
                }
            }
        }
```

### Frontend:

```dart
// استفاده از extension
final t = AppLocalizations.of(context);

DropdownButtonFormField<String>(
  decoration: InputDecoration(
    labelText: t.workflowCreateInvoiceFieldInvoiceType,
  ),
  items: [
    DropdownMenuItem(
      value: 'invoice_sales',
      child: Text(t.workflowCreateInvoiceInvoiceSales),
    ),
    DropdownMenuItem(
      value: 'invoice_purchase',
      child: Text(t.workflowCreateInvoiceInvoicePurchase),
    ),
  ],
)
```

---

## 🔄 فرآیند توسعه

### هنگام افزودن نود جدید:

```
1. ایجاد Action Handler
   ↓
2. افزودن ترجمه‌ها در workflow_translations.py
   ↓
3. اجرای extract_workflow_translations.py
   ↓
4. ری‌استارت API
   ↓
5. بازسازی Flutter (build_runner)
   ↓
6. استفاده در UI
```

### هنگام تغییر ترجمه:

```
1. ویرایش workflow_translations.py
   ↓
2. اجرای extract_workflow_translations.py
   ↓
3. بازسازی Flutter (اگر لازم باشد)
   ↓
4. ری‌استارت API
```

---

## 🧪 تست

### تست ترجمه‌ها در Backend:

```python
from app.services.workflow.i18n import get_translation, translate_metadata

# تست دریافت ترجمه
assert get_translation("action_name", "fa", "create_invoice") == "ایجاد فاکتور"
assert get_translation("action_name", "en", "create_invoice") == "Create Invoice"

# تست ترجمه metadata
metadata = {
    "name": "default name",
    "config_schema": {...}
}

translated_fa = translate_metadata(metadata, "fa", "create_invoice")
assert translated_fa["name"] == "ایجاد فاکتور"

translated_en = translate_metadata(metadata, "en", "create_invoice")
assert translated_en["name"] == "Create Invoice"
```

### تست در Frontend:

```dart
// تست extension
test('WorkflowLocalizations extension', () {
  final t = AppLocalizations.delegate.load(Locale('fa'));
  expect(t.workflowCreateInvoiceActionName, equals('ایجاد فاکتور'));
});

// تست service
test('WorkflowTranslationService', () async {
  final service = WorkflowTranslationService();
  final translations = await service.getTranslations(lang: 'fa');
  expect(translations['create_invoice']['action_name'], equals('ایجاد فاکتور'));
});
```

---

## 📋 لیست کامل کلیدهای ترجمه

### نودهای فعلی:

#### 1. Create Invoice (17 فیلد + 20 ترجمه)
- ✅ action_name, action_description
- ✅ 6 group (basic_info, items, financial, payment, warehouse, advanced)
- ✅ 17 field (invoice_type, person_id, document_date, ...)
- ✅ 4 enum label (invoice_sales, invoice_purchase, ...)
- ✅ 4 help_text
- ✅ 3 error_message

**جمع کل: ~54 کلید ترجمه**

#### 2. Send Telegram (7 فیلد + 10 ترجمه)
- ✅ action_name, action_description
- ✅ 7 field (user_id, message, parse_mode, ...)
- ✅ 3 enum label (HTML, Markdown, None)
- ✅ 2 help_text

**جمع کل: ~22 کلید ترجمه**

#### 3. Send Email (8 فیلد + 10 ترجمه)
- ✅ action_name, action_description
- ✅ 8 field (to, cc, bcc, subject, body, ...)
- ✅ 2 help_text

**جمع کل: ~20 کلید ترجمه**

#### 4. سایر نودها (6 نود)
- Create Notification
- Set Variable
- Log
- HTTP Request
- Create Document
- Update Inventory

**جمع کل هر نود: ~10-15 کلید**

---

## 📊 آمار کلی

| زبان | تعداد کلیدهای مشترک | تعداد کلیدها per نود | جمع کل (تخمینی) |
|------|---------------------|---------------------|------------------|
| فارسی | 15 | ~20-50 | 200+ |
| انگلیسی | 15 | ~20-50 | 200+ |

---

## 💡 بهترین شیوه‌ها (Best Practices)

### 1. نام‌گذاری:
- ✅ از snake_case استفاده کنید
- ✅ نام‌های توصیفی و واضح
- ✅ پیشوند مناسب (`field_`, `group_`, `error_`)

### 2. سازماندهی:
- ✅ هر action یک dictionary جداگانه
- ✅ گروه‌بندی منطقی (basic, advanced, ...)
- ✅ ترتیب منطقی کلیدها

### 3. محتوا:
- ✅ متن‌های کوتاه و واضح
- ✅ از آیکون‌های Emoji در جای مناسب
- ✅ راهنماها و مثال‌ها

### 4. مدیریت:
- ✅ همیشه هر دو زبان را به‌روز نگه دارید
- ✅ از اسکریپت extract برای صادرات استفاده کنید
- ✅ Cache کردن در frontend

### 5. Testing:
- ✅ تست ترجمه‌ها در هر دو زبان
- ✅ بررسی کلیدهای گمشده
- ✅ مقایسه با UI واقعی

---

## 🔍 Debugging

### مشکل: ترجمه نمایش داده نمی‌شود

**چک‌لیست:**
1. ✅ آیا ترجمه در `workflow_translations.py` وجود دارد؟
2. ✅ آیا API ری‌استارت شده؟
3. ✅ آیا cache در frontend پاک شده؟
4. ✅ آیا زبان صحیح انتخاب شده؟
5. ✅ آیا کلید ترجمه صحیح است؟

### مشکل: ترجمه انگلیسی نمایش داده نمی‌شود

```dart
// بررسی locale
final locale = Localizations.localeOf(context);
print('Current locale: ${locale.languageCode}');

// بررسی ترجمه‌های دریافت شده
final translations = await _translationService.getTranslations(lang: 'en');
print('Translations: $translations');
```

### مشکل: کلید ترجمه یافت نمی‌شود

```python
# در Python
from app.services.workflow.i18n import get_all_translation_keys

keys = get_all_translation_keys("create_invoice")
print("Available keys (fa):", keys["fa"])
print("Available keys (en):", keys["en"])
```

---

## 🎯 مزایای این سیستم

### 1. مدیریت متمرکز:
- ✅ تمام ترجمه‌ها در یک مکان
- ✅ راحتی به‌روزرسانی
- ✅ کاهش تکرار

### 2. Type-Safe:
- ✅ Extension با type-safety کامل
- ✅ Autocomplete در IDE
- ✅ Compile-time checking

### 3. Performance:
- ✅ Cache در سمت client
- ✅ دریافت یک‌باره ترجمه‌ها
- ✅ Lazy loading

### 4. Scalability:
- ✅ افزودن زبان جدید آسان است
- ✅ افزودن نود جدید ساده است
- ✅ صادرات به فرمت‌های مختلف

### 5. Developer Experience:
- ✅ API ساده و واضح
- ✅ مستندات کامل
- ✅ اسکریپت‌های کمکی
- ✅ Fallback برای ترجمه‌های گمشده

---

## 📦 فایل‌های ایجاد شده

| فایل | نوع | توضیحات |
|------|-----|---------|
| `workflow_translations.py` | Backend | ترجمه‌های پایه |
| `workflows.py` (updated) | Backend | API endpoints |
| `extract_workflow_translations.py` | Script | استخراج و صادرات |
| `workflow_translation_service.dart` | Frontend | سرویس دریافت ترجمه |
| `workflow_localizations_extension.dart` | Frontend | Extension برای راحتی |
| `workflow_node_config_dialog.dart` (updated) | Frontend | استفاده از ترجمه در UI |

---

## ✅ نتیجه‌گیری

سیستم i18n کامل و حرفه‌ای برای نودهای ورک‌فلو پیاده‌سازی شد که:

✅ **200+ رشته** را پشتیبانی می‌کند  
✅ **2 زبان** (فارسی و انگلیسی)  
✅ **قابل توسعه** برای زبان‌های بیشتر  
✅ **مدیریت آسان** با اسکریپت‌های کمکی  
✅ **Type-Safe** در Flutter  
✅ **Cache** برای performance بهتر  
✅ **Fallback** برای ترجمه‌های گمشده  

این سیستم امکان ایجاد یک تجربه کاربری یکپارچه و چند زبانه را فراهم می‌کند! 🌍🎉


