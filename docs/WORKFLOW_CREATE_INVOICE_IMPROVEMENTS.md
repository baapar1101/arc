# 📋 تحلیل و پیشنهادات بهبود نود "ایجاد فاکتور"

## 🔍 وضعیت فعلی

### فیلدهای موجود:
```python
{
    "invoice_type": {
        "type": "string",
        "description": "نوع فاکتور (invoice_sales/invoice_purchase)",
        "required": True
    },
    "person_id": {
        "type": "integer",
        "description": "شناسه شخص",
        "required": True
    },
    "items": {
        "type": "array",
        "description": "آیتم‌های فاکتور",
        "required": True
    }
}
```

### محدودیت‌های کنونی:

1. **تاریخ ثابت**: 
   - `document_date` همیشه `datetime.now()` است
   - کاربر نمی‌تواند تاریخ دلخواه تنظیم کند

2. **فیلدهای مهم ناقص**:
   - ❌ توضیحات (description)
   - ❌ تخفیف کلی (global_discount)
   - ❌ اطلاعات پرداخت (payments)
   - ❌ انتخاب انبار (warehouse)
   - ❌ سال مالی (fiscal_year)
   - ❌ تنظیمات مالیاتی (tax settings)

3. **UI ضعیف برای items**:
   - آیتم‌ها به صورت array ساده است
   - هیچ UI builder برای افزودن محصولات وجود ندارد

4. **عدم پشتیبانی از سناریوهای پیشرفته**:
   - ❌ فروش اقساطی
   - ❌ پیش‌فاکتور (proforma)
   - ❌ فاکتور برگشتی
   - ❌ تخفیفات چند سطحی

---

## 💡 پیشنهادات بهبود

### 1️⃣ فیلدهای پایه (High Priority)

#### 1.1. تاریخ فاکتور (document_date)
```python
"document_date": {
    "type": "string",
    "format": "date",
    "description": "تاریخ فاکتور (ISO format: YYYY-MM-DD)",
    "required": False,
    "default": "today",  # استفاده از امروز به صورت پیش‌فرض
    "ui_type": "date_picker",
    "ui_config": {
        "allow_future": True,
        "allow_past": True,
        "max_days_past": 365,
        "max_days_future": 30
    }
}
```

**مزایا:**
- کاربر می‌تواند فاکتورهای گذشته یا آینده ایجاد کند
- می‌تواند از reference به نودهای قبلی استفاده کند: `$trigger.event_date`

#### 1.2. توضیحات (description)
```python
"description": {
    "type": "string",
    "description": "توضیحات فاکتور",
    "required": False,
    "maxLength": 500,
    "ui_type": "textarea",
    "ui_config": {
        "rows": 3,
        "placeholder": "توضیحات فاکتور را وارد کنید..."
    }
}
```

**مزایا:**
- امکان افزودن توضیحات دینامیک: `"فاکتور برای $trigger.customer_name"`
- بهبود قابلیت جستجو و فیلتر

#### 1.3. ارز (currency_id) - بهبود
```python
"currency_id": {
    "type": "integer",
    "description": "شناسه ارز (پیش‌فرض: ارز کسب‌وکار)",
    "required": False,
    "ui_type": "currency_selector",
    "ui_config": {
        "business_scoped": True,
        "show_default": True
    }
}
```

**تغییر:**
- فعلاً به صورت اختیاری است اما UI مناسبی ندارد
- باید selector زیبا با پیش‌نمایش ارز افزوده شود

#### 1.4. نوع فاکتور (invoice_type) - بهبود
```python
"invoice_type": {
    "type": "string",
    "description": "نوع فاکتور",
    "required": True,
    "enum": [
        "invoice_sales",
        "invoice_purchase",
        "invoice_return_sales",
        "invoice_return_purchase"
    ],
    "ui_type": "select",
    "ui_config": {
        "labels": {
            "invoice_sales": "🛒 فاکتور فروش",
            "invoice_purchase": "🛍️ فاکتور خرید",
            "invoice_return_sales": "↩️ برگشت از فروش",
            "invoice_return_purchase": "↪️ برگشت از خرید"
        }
    }
}
```

**بهبود:**
- پشتیبانی از فاکتورهای برگشتی
- UI بهتر با آیکون‌ها

---

### 2️⃣ مدیریت آیتم‌ها (Items) - Critical

#### مشکل فعلی:
```python
"items": {
    "type": "array",
    "description": "آیتم‌های فاکتور",
    "required": True
}
```

#### پیشنهاد:

**الف) استفاده از Reference به نود قبلی:**
```python
"items_source": {
    "type": "string",
    "description": "منبع آیتم‌ها",
    "required": False,
    "enum": ["manual", "from_node"],
    "default": "manual",
    "ui_type": "radio"
}
```

**ب) برای حالت manual - Item Builder:**
```python
"items": {
    "type": "array",
    "description": "آیتم‌های فاکتور",
    "required": True,
    "ui_type": "invoice_items_builder",
    "ui_config": {
        "min_items": 1,
        "max_items": 100,
        "fields": {
            "product_id": {
                "type": "product_selector",
                "required": True,
                "business_scoped": True
            },
            "quantity": {
                "type": "number",
                "required": True,
                "min": 0.001,
                "default": 1
            },
            "unit_price": {
                "type": "number",
                "required": False,
                "description": "پیش‌فرض: قیمت محصول"
            },
            "discount_percent": {
                "type": "number",
                "required": False,
                "min": 0,
                "max": 100,
                "default": 0
            },
            "tax_percent": {
                "type": "number",
                "required": False,
                "min": 0,
                "max": 100,
                "default": 9
            },
            "description": {
                "type": "string",
                "required": False,
                "maxLength": 200
            }
        }
    }
}
```

**ج) برای حالت from_node:**
```python
"items_reference": {
    "type": "string",
    "description": "Reference به نود قبلی برای آیتم‌ها",
    "required": False,
    "ui_type": "node_reference",
    "ui_config": {
        "expected_output": "array"
    },
    "example": "$previous_node.items"
}
```

**مزایا:**
- UI بسیار بهتر برای افزودن آیتم‌ها
- Validation بهتر
- پشتیبانی از هر دو حالت manual و dynamic

---

### 3️⃣ طرف حساب (person_id) - بهبود

#### پیشنهاد:
```python
"person_id": {
    "type": "integer",
    "description": "شناسه طرف حساب (مشتری/تأمین‌کننده)",
    "required": True,
    "ui_type": "person_selector",
    "ui_config": {
        "business_scoped": True,
        "filter_by_invoice_type": True,  # فیلتر بر اساس نوع فاکتور
        "allow_create": False,
        "person_types": ["customer", "supplier"]  # بسته به invoice_type
    }
}
```

**بهبودها:**
- Selector زیبا با جستجو
- فیلتر خودکار بر اساس نوع فاکتور (فروش→مشتری، خرید→تأمین‌کننده)
- نمایش اطلاعات طرف حساب

---

### 4️⃣ تخفیفات و مالیات (Medium Priority)

```python
"discount": {
    "type": "object",
    "description": "تخفیف کلی فاکتور",
    "required": False,
    "properties": {
        "type": {
            "type": "string",
            "enum": ["percent", "fixed"],
            "default": "percent"
        },
        "value": {
            "type": "number",
            "min": 0
        }
    },
    "ui_type": "discount_config"
}

"tax_config": {
    "type": "object",
    "description": "تنظیمات مالیاتی",
    "required": False,
    "properties": {
        "apply_tax": {
            "type": "boolean",
            "default": True
        },
        "tax_rate": {
            "type": "number",
            "min": 0,
            "max": 100,
            "default": 9,
            "description": "نرخ مالیات (درصد)"
        },
        "tax_included": {
            "type": "boolean",
            "default": False,
            "description": "مالیات جزو قیمت است"
        }
    }
}
```

---

### 5️⃣ پرداخت (Payments) - High Priority

```python
"auto_create_payment": {
    "type": "boolean",
    "description": "ایجاد خودکار سند پرداخت",
    "default": False,
    "required": False
}

"payments": {
    "type": "array",
    "description": "پرداخت‌های همزمان با فاکتور",
    "required": False,
    "depends_on": {
        "auto_create_payment": True
    },
    "ui_type": "payments_builder",
    "ui_config": {
        "max_payments": 5,
        "fields": {
            "amount": {
                "type": "number",
                "required": True,
                "min": 0
            },
            "payment_method": {
                "type": "string",
                "enum": ["cash", "bank", "check", "card"],
                "required": True
            },
            "account_id": {
                "type": "integer",
                "description": "حساب بانکی/صندوق",
                "ui_type": "account_selector"
            },
            "description": {
                "type": "string",
                "maxLength": 200
            }
        }
    }
}
```

---

### 6️⃣ انبار (Warehouse) - Medium Priority

```python
"warehouse_settings": {
    "type": "object",
    "description": "تنظیمات انبار و حواله",
    "required": False,
    "properties": {
        "create_warehouse_document": {
            "type": "boolean",
            "default": True,
            "description": "ایجاد خودکار حواله انبار"
        },
        "warehouse_id": {
            "type": "integer",
            "description": "انبار مبدأ/مقصد",
            "ui_type": "warehouse_selector",
            "ui_config": {
                "business_scoped": True
            }
        },
        "auto_post": {
            "type": "boolean",
            "default": False,
            "description": "ثبت خودکار حواله"
        }
    }
}
```

---

### 7️⃣ تنظیمات پیشرفته (Low Priority)

```python
"advanced_settings": {
    "type": "object",
    "description": "تنظیمات پیشرفته",
    "required": False,
    "ui_group": "پیشرفته",
    "properties": {
        "is_proforma": {
            "type": "boolean",
            "default": False,
            "description": "پیش‌فاکتور (بدون تأثیر حسابداری)"
        },
        "fiscal_year_id": {
            "type": "integer",
            "description": "سال مالی (پیش‌فرض: سال جاری)",
            "ui_type": "fiscal_year_selector"
        },
        "reference_code": {
            "type": "string",
            "description": "کد/شماره مرجع",
            "maxLength": 50
        },
        "installment_plan": {
            "type": "object",
            "description": "طرح اقساط",
            "properties": {
                "enabled": {"type": "boolean", "default": False},
                "down_payment_percent": {"type": "number", "min": 0, "max": 100},
                "installment_count": {"type": "integer", "min": 2, "max": 60},
                "interest_rate": {"type": "number", "min": 0, "max": 100}
            }
        },
        "extra_info": {
            "type": "object",
            "description": "اطلاعات اضافی (JSON)",
            "ui_type": "json_editor"
        }
    }
}
```

---

## 🎨 بهبودهای UI

### 1. گروه‌بندی فیلدها:

```
📋 اطلاعات پایه
  ├─ نوع فاکتور
  ├─ طرف حساب
  ├─ تاریخ
  └─ توضیحات

🛍️ آیتم‌های فاکتور
  ├─ منبع آیتم‌ها (Manual/Reference)
  └─ لیست آیتم‌ها (با UI builder)

💰 مالی
  ├─ ارز
  ├─ تخفیف کلی
  └─ تنظیمات مالیات

💳 پرداخت
  ├─ ایجاد خودکار پرداخت
  └─ لیست پرداخت‌ها

📦 انبار
  ├─ ایجاد حواله
  ├─ انتخاب انبار
  └─ ثبت خودکار

⚙️ پیشرفته (Collapsible)
  ├─ پیش‌فاکتور
  ├─ سال مالی
  ├─ طرح اقساط
  └─ اطلاعات اضافی
```

### 2. Validation و Help Text:

```python
"validation_rules": {
    "items": {
        "min_items": 1,
        "max_items": 100,
        "error_messages": {
            "min": "حداقل یک آیتم باید وارد شود",
            "max": "حداکثر 100 آیتم مجاز است"
        }
    },
    "person_id": {
        "business_member": True,
        "error_message": "طرف حساب باید در لیست مشتریان/تأمین‌کنندگان باشد"
    },
    "document_date": {
        "within_fiscal_year": True,
        "error_message": "تاریخ باید در محدوده سال مالی فعال باشد"
    }
}

"help_texts": {
    "items": "محصولات فاکتور را اضافه کنید. می‌توانید از reference به نودهای قبلی استفاده کنید.",
    "warehouse_settings": "در صورت فعال بودن، حواله انبار به صورت خودکار ایجاد می‌شود.",
    "installment_plan": "برای فروش اقساطی، تنظیمات طرح اقساط را وارد کنید."
}
```

### 3. Preview و Summary:

```python
"ui_features": {
    "show_preview": True,  # پیش‌نمایش فاکتور قبل از ایجاد
    "show_summary": True,  # خلاصه مبالغ (جمع، تخفیف، مالیات، نهایی)
    "show_validation_errors": True,  # نمایش خطاها قبل از save
    "auto_calculate": True  # محاسبه خودکار مبالغ
}
```

---

## 📊 پیشنهاد Schema کامل (نسخه بهبود یافته)

### Schema پیشنهادی:

```python
def get_metadata(self) -> Dict[str, Any]:
    return {
        "name": "ایجاد فاکتور",
        "description": "ایجاد فاکتور فروش، خرید یا برگشتی با امکانات پیشرفته",
        "icon": "receipt_long",
        "category": "مالی و حسابداری",
        "config_schema": {
            # گروه 1: اطلاعات پایه
            "invoice_type": { ... },  # با پشتیبانی از فاکتور برگشتی
            "person_id": { ... },     # با selector بهتر
            "document_date": { ... }, # با date picker
            "description": { ... },   # با textarea
            "currency_id": { ... },   # با currency selector
            
            # گروه 2: آیتم‌ها
            "items_source": { ... },      # manual یا from_node
            "items": { ... },             # با UI builder
            "items_reference": { ... },   # برای حالت from_node
            
            # گروه 3: مالی
            "discount": { ... },       # تخفیف کلی
            "tax_config": { ... },     # تنظیمات مالیات
            
            # گروه 4: پرداخت
            "auto_create_payment": { ... },
            "payments": { ... },       # با payment builder
            
            # گروه 5: انبار
            "warehouse_settings": {
                "create_warehouse_document": { ... },
                "warehouse_id": { ... },
                "auto_post": { ... }
            },
            
            # گروه 6: پیشرفته
            "advanced_settings": {
                "is_proforma": { ... },
                "fiscal_year_id": { ... },
                "reference_code": { ... },
                "installment_plan": { ... },
                "extra_info": { ... }
            }
        },
        
        # UI Configuration
        "ui_config": {
            "groups": [...],           # گروه‌بندی فیلدها
            "validation_rules": {...}, # قوانین validation
            "help_texts": {...},       # راهنماها
            "features": {...}          # فیچرهای UI
        }
    }
```

---

## 🚀 اولویت‌بندی پیاده‌سازی

### Phase 1 - Critical (باید حتماً پیاده شود):
1. ✅ تاریخ قابل تنظیم (document_date)
2. ✅ توضیحات (description)
3. ✅ بهبود UI برای items (Item Builder)
4. ✅ بهبود person selector

### Phase 2 - High Priority (بسیار مهم):
1. ✅ پشتیبانی از پرداخت (payments)
2. ✅ تنظیمات انبار (warehouse_settings)
3. ✅ تخفیف و مالیات (discount, tax_config)
4. ✅ گروه‌بندی فیلدها در UI

### Phase 3 - Medium Priority (مفید):
1. ✅ پیش‌فاکتور (is_proforma)
2. ✅ فاکتورهای برگشتی
3. ✅ Preview و Summary
4. ✅ Validation بهتر

### Phase 4 - Low Priority (Nice to have):
1. ✅ طرح اقساط (installment_plan)
2. ✅ JSON Editor برای extra_info
3. ✅ Advanced settings
4. ✅ Custom validations

---

## 📝 نکات پیاده‌سازی

### 1. Backward Compatibility:
- همه فیلدهای جدید باید **optional** باشند
- ورک‌فلوهای موجود نباید break شوند
- مقادیر پیش‌فرض معقول تعریف شوند

### 2. Performance:
- Item Builder نباید برای تعداد زیاد آیتم کند شود
- Validation سمت client انجام شود (قبل از ارسال به server)
- Cache کردن لیست محصولات/مشتریان

### 3. Error Handling:
- پیام‌های خطای واضح و کاربرپسند
- Validation قبل از ارسال
- Rollback در صورت خطا

### 4. Testing:
- Unit tests برای هر فیلد جدید
- Integration tests برای سناریوهای مختلف
- UI tests برای Item Builder

---

## 🎯 مثال‌های کاربردی

### مثال 1: فاکتور ساده با یک آیتم
```json
{
    "invoice_type": "invoice_sales",
    "person_id": 123,
    "document_date": "2025-12-05",
    "items": [
        {
            "product_id": 456,
            "quantity": 2,
            "unit_price": 100000
        }
    ]
}
```

### مثال 2: فاکتور با تخفیف و پرداخت
```json
{
    "invoice_type": "invoice_sales",
    "person_id": 123,
    "items": [...],
    "discount": {
        "type": "percent",
        "value": 10
    },
    "auto_create_payment": true,
    "payments": [
        {
            "amount": 180000,
            "payment_method": "bank",
            "account_id": 789
        }
    ]
}
```

### مثال 3: استفاده از Reference
```json
{
    "invoice_type": "invoice_sales",
    "person_id": "$trigger.customer_id",
    "document_date": "$trigger.order_date",
    "description": "فاکتور برای سفارش $trigger.order_number",
    "items_source": "from_node",
    "items_reference": "$previous_node.order_items"
}
```

---

## ✅ خلاصه

| موضوع | وضعیت فعلی | پیشنهاد | اولویت |
|-------|------------|---------|--------|
| تاریخ فاکتور | ثابت (امروز) | Date Picker | 🔴 Critical |
| توضیحات | ندارد | Textarea | 🔴 Critical |
| UI آیتم‌ها | Array ساده | Item Builder | 🔴 Critical |
| Person Selector | ساده | Advanced Selector | 🔴 Critical |
| پرداخت | ندارد | Payment Builder | 🟡 High |
| انبار | ندارد | Warehouse Config | 🟡 High |
| تخفیف/مالیات | ندارد | Tax & Discount Config | 🟡 High |
| پیش‌فاکتور | ندارد | Boolean Flag | 🟢 Medium |
| طرح اقساط | ندارد | Installment Config | ⚪ Low |

---

**نتیجه‌گیری:**

نود "ایجاد فاکتور" پتانسیل بسیار زیادی برای بهبود دارد. با پیاده‌سازی پیشنهادات Phase 1 و 2، این نود می‌تواند یکی از قدرتمندترین نودهای سیستم ورک‌فلو شود و کاربردهای بسیار متنوعی پیدا کند.


