# بهبود فیلترها و فیلدهای ورودی Workflow

## 📋 خلاصه تغییرات

این سند شامل تمام بهبودهایی است که برای فیلترها و فیلدهای ورودی در بخش Workflow انجام شده است.

---

## 🔧 تغییرات Backend (Python)

### 1. **Trigger Schemas - بهبود فیلدها**

#### `document_triggers.py` (InvoiceCreatedTrigger):

✅ فیلدهای بهبود یافته:
- `invoice_type`: تبدیل به enum با labels فارسی
- `status_filter`: تبدیل به multi-select با labels فارسی
- `person_type_filter`: تبدیل به enum با labels فارسی
- `currency_id`: اضافه شدن ui_type: "currency_selector"

```python
"invoice_type": {
    "type": "string",
    "description": "نوع فاکتور",
    "enum": ["invoice_sales", "invoice_purchase", "invoice_return_sales", "invoice_return_purchase"],
    "ui_config": {
        "labels": {
            "invoice_sales": "فاکتور فروش",
            "invoice_purchase": "فاکتور خرید",
            "invoice_return_sales": "برگشت از فروش",
            "invoice_return_purchase": "برگشت از خرید"
        }
    },
    "required": False
}
```

#### `person_triggers.py` (PersonCreatedTrigger):

✅ `person_type`: تبدیل به enum با labels فارسی

#### `scheduled_triggers.py` (ScheduledTrigger):

✅ `timezone`: تبدیل به enum با emoji و labels فارسی

```python
"timezone": {
    "type": "string",
    "description": "منطقه زمانی",
    "default": "Asia/Tehran",
    "enum": ["Asia/Tehran", "UTC", "Asia/Dubai", "Europe/London", "America/New_York"],
    "ui_config": {
        "labels": {
            "Asia/Tehran": "🇮🇷 تهران (ایران)",
            "UTC": "🌍 UTC (جهانی)",
            # ...
        }
    }
}
```

#### `webhook_triggers.py` (WebhookTrigger):

✅ `method`: تبدیل به enum با labels فارسی

---

### 2. **Action Schemas - بهبود فیلدها**

#### `communication_actions.py`:

**SendEmailAction:**
✅ `priority`: بهبود labels با emoji
```python
"priority": {
    "ui_config": {
        "labels": {
            "low": "🔽 کم - Low",
            "normal": "➖ عادی - Normal",
            "high": "🔼 بالا - High"
        }
    }
}
```

**SendTelegramAction:**
✅ `parse_mode`: بهبود labels فارسی

#### `document_actions.py` (CreateInvoiceAction):

✅ فیلدهای موجود با ui_type مناسب:
- `person_id`: ui_type: "person_selector"
- `currency_id`: ui_type: "currency_selector"
- `items[].product_id`: ui_type: "product_selector"
- `warehouse_settings.warehouse_id`: ui_type: "warehouse_selector"
- `payments[].payment_method`: enum با labels
- `discount.type`: enum (percent/fixed)

---

## 🎨 تغییرات Frontend (Flutter/Dart)

### 1. **workflow_node_config_dialog.dart - افزودن پشتیبانی از ui_type های جدید**

#### متدهای جدید اضافه شده:

1. **`_buildPersonSelector()`**: نمایش فیلد انتخاب طرف حساب
   - پشتیبانی از reference ($node_id.person_id)
   - نمایش helper text
   - دکمه "استفاده از نود قبلی"

2. **`_buildProductSelector()`**: نمایش فیلد انتخاب محصول
   - مشابه PersonSelector
   - پشتیبانی از reference

3. **`_buildCurrencySelector()`**: Dropdown برای انتخاب ارز
   - لیست ارزهای رایج (IRR, USD, EUR, AED)
   - نمایش نماد و نام ارز
   - پشتیبانی از reference

4. **`_buildMultiSelect()`**: Multi-select با FilterChips
   - برای فیلدهای array با ui_type: "multi_select"
   - نمایش labels فارسی از ui_config
   - انتخاب چند مورد همزمان

5. **`_buildReferenceTextField()`**: TextField برای مقادیر reference
   - شناسایی خودکار مقادیر با $ در ابتدا
   - آیکون Link
   - دکمه Reference Selector

#### منطق تشخیص ui_type:

```dart
final uiType = schema['ui_type'] as String?;
if (uiType == 'telegram_user_selector') {
  return _buildTelegramUserSelector(...);
} else if (uiType == 'person_selector') {
  return _buildPersonSelector(...);
} else if (uiType == 'product_selector') {
  return _buildProductSelector(...);
} else if (uiType == 'currency_selector') {
  return _buildCurrencySelector(...);
}
```

#### پشتیبانی از Multi-Select:

```dart
case 'array':
  final uiType = schema['ui_type'] as String?;
  if (uiType == 'multi_select') {
    return _buildMultiSelect(key, schema, value, required, description);
  }
  // Default array handling...
```

---

## 📊 مقایسه قبل و بعد

### قبل از تغییرات:

| فیلد | نوع UI | مشکل |
|------|--------|------|
| `invoice_type` | TextField | کاربر باید به صورت دستی تایپ کند |
| `status_filter` | TextField Array | انتخاب چند مورد دشوار |
| `person_id` | TextField Number | جستجو و انتخاب مشتری غیرممکن |
| `currency_id` | TextField Number | شناخت ارزها سخت |
| `priority` | Dropdown | بدون emoji و label فارسی |
| `timezone` | TextField | تایپ دستی timezone |

### بعد از تغییرات:

| فیلد | نوع UI | بهبود |
|------|--------|-------|
| `invoice_type` | Dropdown با emoji | انتخاب آسان با لیبل فارسی |
| `status_filter` | Multi-Select FilterChips | انتخاب چند مورد با یک کلیک |
| `person_id` | Person Selector (فعلاً TextField با hint) | راهنمایی برای استفاده از reference |
| `currency_id` | Dropdown ارزها | انتخاب از لیست با نماد و نام |
| `priority` | Dropdown با emoji | 🔽 کم / ➖ عادی / 🔼 بالا |
| `timezone` | Dropdown با پرچم | 🇮🇷 تهران / 🌍 UTC |

---

## 🎯 نحوه استفاده

### 1. در Backend - تعریف Schema:

```python
# برای enum ساده:
"field_name": {
    "type": "string",
    "enum": ["option1", "option2", "option3"],
    "ui_config": {
        "labels": {
            "option1": "🔵 گزینه اول",
            "option2": "🟢 گزینه دوم",
            "option3": "🔴 گزینه سوم"
        }
    }
}

# برای Person Selector:
"person_id": {
    "type": "integer",
    "ui_type": "person_selector",
    "ui_config": {
        "business_scoped": True,
        "show_reference_button": True
    }
}

# برای Multi-Select:
"status_filter": {
    "type": "array",
    "items": {
        "type": "string",
        "enum": ["draft", "confirmed", "cancelled"]
    },
    "ui_type": "multi_select",
    "ui_config": {
        "labels": {
            "draft": "پیش‌نویس",
            "confirmed": "تایید شده",
            "cancelled": "لغو شده"
        }
    }
}

# برای Currency Selector:
"currency_id": {
    "type": "integer",
    "ui_type": "currency_selector",
    "ui_config": {
        "business_scoped": True
    }
}
```

### 2. در Frontend - خودکار شناسایی می‌شود:

- کد موجود در `workflow_node_config_dialog.dart` به صورت خودکار ui_type را تشخیص می‌دهد
- اگر enum باشد، Dropdown نمایش می‌دهد
- اگر ui_type خاص باشد، کامپوننت مناسب را render می‌کند
- labels از ui_config خوانده و نمایش داده می‌شوند

---

## 🔄 بهبودهای آینده

### فاز 2 (پیشنهادی):

1. **PersonComboboxWidget Integration**:
   - استفاده از کامپوننت موجود `PersonComboboxWidget` برای انتخاب مستقیم مشتریان
   - نیاز به businessId از context workflow

2. **ProductComboboxWidget Integration**:
   - مشابه Person، استفاده از کامپوننت موجود
   - نمایش لیست محصولات با جستجو

3. **Warehouse Selector**:
   - ساخت Dropdown برای انبارها
   - دریافت لیست از API

4. **Account Selector**:
   - برای انتخاب حساب بانکی/صندوق
   - در قسمت payments

5. **Fiscal Year Selector**:
   - Dropdown سال‌های مالی
   - با نمایش سال جاری

6. **Date Range Picker**:
   - برای فیلترهای تاریخی
   - با پشتیبانی تقویم شمسی

---

## 📝 نکات مهم

1. **Reference Support**: تمام فیلدها از reference به نودهای قبلی پشتیبانی می‌کنند (`$node_id.field_name`)

2. **Validation**: فیلدهای required به صورت خودکار validate می‌شوند

3. **Labels**: همیشه از ui_config.labels استفاده کنید برای نمایش فارسی

4. **Icons & Emojis**: استفاده از emoji در labels تجربه کاربری را بهتر می‌کند

5. **Backward Compatibility**: تمام تغییرات backward compatible هستند

---

## ✅ تست

### سناریوهای تست:

1. ✅ ایجاد trigger جدید با فیلتر invoice_type
2. ✅ ایجاد action جدید با person_id
3. ✅ استفاده از multi-select برای status_filter
4. ✅ انتخاب currency از dropdown
5. ✅ استفاده از reference در فیلدها ($node_id.field)
6. ✅ نمایش صحیح labels فارسی و emoji

---

## 🐛 مشکلات شناخته شده

1. **Person/Product Selector**: فعلاً به صورت TextField ساده است و نیاز به integration کامل با PersonComboboxWidget دارد
2. **Dynamic Currency List**: لیست ارزها hardcoded است - باید از API لود شود
3. **Warehouse/Account Selectors**: هنوز پیاده‌سازی نشده‌اند

---

## 📞 پشتیبانی

برای مشکلات یا سوالات:
- مستندات: این فایل
- کد Backend: `hesabixAPI/app/services/workflow/`
- کد Frontend: `hesabixUI/hesabix_ui/lib/widgets/workflow/`

---

**تاریخ آخرین به‌روزرسانی**: دسامبر 2025
**نسخه**: 1.0.0


