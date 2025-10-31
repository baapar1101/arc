# مشکلات و سناریوهای ثبت فاکتور

## 🔴 مشکلات شناسایی شده

### 1. **عدم تطابق نام فیلد نوع فاکتور**
- **مشکل**: در UI از `type` استفاده می‌شود اما API از `invoice_type` انتظار دارد
- **مکان**: `new_invoice_page.dart` خط 801
- **وضعیت فعلی**: `'type': _selectedInvoiceType!.value` (مثل `'sales'`, `'purchase'`)
- **وضعیت مورد انتظار**: `'invoice_type': 'invoice_sales'`, `'invoice_purchase'`, و غیره

### 2. **عدم تطابق فرمت نوع فاکتور**
- **مشکل**: UI مقادیر ساده ارسال می‌کند (`'sales'`) اما API فرمت کامل می‌خواهد (`'invoice_sales'`)
- **مکان**: تبدیل از `InvoiceType.value` به فرمت API
- **مثال**: `'sales'` باید به `'invoice_sales'` تبدیل شود

### 3. **عدم استخراج person_id از customer/seller**
- **مشکل**: API فقط `extra_info.person_id` را می‌خواند اما UI `customer_id` و `seller_id` را ارسال می‌کند
- **مکان**: `invoice_service.py` خط 393-399 (`_person_id_from_header`)
- **وضعیت فعلی**: `customer_id` و `seller_id` در payload هستند اما API آن‌ها را نمی‌خواند

### 4. **عدم تطابق نام فیلد تاریخ**
- **مشکل**: UI از `invoice_date` استفاده می‌کند اما API از `document_date` انتظار دارد
- **مکان**: `new_invoice_page.dart` خط 804

### 5. **عدم تطابق ساختار خطوط**
- **مشکل**: UI از `line_items` استفاده می‌کند اما API از `lines` انتظار دارد
- **مکان**: `new_invoice_page.dart` خط 823

### 6. **عدم وجود فیلد تامین‌کننده برای فاکتور خرید**
- **مشکل**: برای فاکتورهای خرید و برگشت از خرید، باید تامین‌کننده (supplier) انتخاب شود نه مشتری
- **مکان**: UI فقط `CustomerPickerWidget` دارد که برای خرید مناسب نیست

### 7. **عدم ارسال person_id در extra_info**
- **مشکل**: `person_id` باید در `extra_info` ارسال شود نه به صورت مستقیم
- **مکان**: `new_invoice_page.dart` - ساخت payload

---

## 📋 سناریوهای صحیح برای هر نوع فاکتور

### ✅ فاکتور فروش (Sales Invoice)
**فیلدهای مورد نیاز:**
- ✅ نوع فاکتور: `invoice_sales`
- ✅ مشتری (Customer): الزامی - باید به `person_id` تبدیل شود
- ✅ فروشنده/بازاریاب (Seller): اختیاری - فقط برای کارمزد
- ✅ تراکنش‌ها: دریافت (Receipt) - اختیاری
- ✅ تاریخ فاکتور: `document_date`
- ✅ تاریخ سررسید: `due_date` (اختیاری)

**ساختار payload صحیح:**
```json
{
  "invoice_type": "invoice_sales",
  "document_date": "2024-01-15",
  "due_date": "2024-02-15",
  "currency_id": 1,
  "is_proforma": false,
  "description": "فروش محصولات",
  "extra_info": {
    "person_id": 123,  // از customer_id استخراج شود
    "seller_id": 456,  // اختیاری
    "commission": {
      "type": "percentage",
      "value": 5.5
    },
    "totals": {
      "gross": 1000000,
      "discount": 50000,
      "tax": 95000,
      "net": 1045000
    }
  },
  "lines": [
    {
      "product_id": 1,
      "quantity": 10,
      "extra_info": {
        "unit_price": 100000,
        "line_discount": 5000,
        "tax_amount": 9500,
        "movement": "out"
      }
    }
  ],
  "payments": [
    {
      "transaction_type": "cash",
      "amount": 500000,
      "transaction_date": "2024-01-15"
    }
  ]
}
```

---

### ✅ فاکتور برگشت از فروش (Sales Return)
**فیلدهای مورد نیاز:**
- ✅ نوع فاکتور: `invoice_sales_return`
- ✅ مشتری (Customer): الزامی - همان مشتری فاکتور اصلی
- ✅ فروشنده/بازاریاب: اختیاری - همان فروشنده اصلی
- ✅ تراکنش‌ها: پرداخت (Payment) - اختیاری
- ✅ تاریخ فاکتور: `document_date`

**ساختار payload صحیح:**
```json
{
  "invoice_type": "invoice_sales_return",
  "document_date": "2024-01-20",
  "currency_id": 1,
  "is_proforma": false,
  "extra_info": {
    "person_id": 123,  // از customer_id استخراج شود
    "totals": {
      "gross": 500000,
      "discount": 0,
      "tax": 47500,
      "net": 547500
    }
  },
  "lines": [
    {
      "product_id": 1,
      "quantity": 5,
      "extra_info": {
        "unit_price": 100000,
        "movement": "in"
      }
    }
  ]
}
```

---

### ✅ فاکتور خرید (Purchase Invoice)
**فیلدهای مورد نیاز:**
- ✅ نوع فاکتور: `invoice_purchase`
- ✅ **تامین‌کننده (Supplier)**: الزامی - باید `PersonPickerWidget` با فیلتر `person_types: ['تامین‌کننده', 'فروشنده']` باشد
- ✅ تراکنش‌ها: پرداخت (Payment) - اختیاری
- ✅ تاریخ فاکتور: `document_date`

**مشکل فعلی:** UI فقط `CustomerPickerWidget` دارد که برای خرید مناسب نیست!

**ساختار payload صحیح:**
```json
{
  "invoice_type": "invoice_purchase",
  "document_date": "2024-01-15",
  "currency_id": 1,
  "is_proforma": false,
  "extra_info": {
    "person_id": 789,  // از supplier_id استخراج شود
    "totals": {
      "gross": 2000000,
      "discount": 100000,
      "tax": 190000,
      "net": 2090000
    }
  },
  "lines": [
    {
      "product_id": 2,
      "quantity": 20,
      "extra_info": {
        "unit_price": 100000,
        "movement": "in"
      }
    }
  ],
  "payments": [
    {
      "transaction_type": "cash",
      "amount": 1000000,
      "transaction_date": "2024-01-15"
    }
  ]
}
```

---

### ✅ فاکتور برگشت از خرید (Purchase Return)
**فیلدهای مورد نیاز:**
- ✅ نوع فاکتور: `invoice_purchase_return`
- ✅ **تامین‌کننده (Supplier)**: الزامی - همان تامین‌کننده فاکتور خرید اصلی
- ✅ تراکنش‌ها: دریافت (Receipt) - اختیاری
- ✅ تاریخ فاکتور: `document_date`

**ساختار payload صحیح:**
```json
{
  "invoice_type": "invoice_purchase_return",
  "document_date": "2024-01-20",
  "currency_id": 1,
  "is_proforma": false,
  "extra_info": {
    "person_id": 789,  // از supplier_id استخراج شود
    "totals": {
      "gross": 500000,
      "discount": 0,
      "tax": 47500,
      "net": 547500
    }
  },
  "lines": [
    {
      "product_id": 2,
      "quantity": 5,
      "extra_info": {
        "unit_price": 100000,
        "movement": "out"
      }
    }
  ]
}
```

---

### ✅ فاکتور مصرف مستقیم (Direct Consumption)
**فیلدهای مورد نیاز:**
- ✅ نوع فاکتور: `invoice_direct_consumption`
- ❌ مشتری/تامین‌کننده: نیاز ندارد
- ❌ تراکنش‌ها: نیاز ندارد
- ✅ تاریخ فاکتور: `document_date`

**ساختار payload صحیح:**
```json
{
  "invoice_type": "invoice_direct_consumption",
  "document_date": "2024-01-15",
  "currency_id": 1,
  "is_proforma": false,
  "extra_info": {
    "totals": {
      "gross": 0,
      "discount": 0,
      "tax": 0,
      "net": 0
    }
  },
  "lines": [
    {
      "product_id": 3,
      "quantity": 5,
      "extra_info": {
        "movement": "out"
      }
    }
  ]
}
```

---

### ✅ فاکتور ضایعات (Waste)
**فیلدهای مورد نیاز:**
- ✅ نوع فاکتور: `invoice_waste`
- ❌ مشتری/تامین‌کننده: نیاز ندارد
- ❌ تراکنش‌ها: نیاز ندارد
- ✅ تاریخ فاکتور: `document_date`

**ساختار payload صحیح:**
```json
{
  "invoice_type": "invoice_waste",
  "document_date": "2024-01-15",
  "currency_id": 1,
  "is_proforma": false,
  "extra_info": {
    "totals": {
      "gross": 0,
      "discount": 0,
      "tax": 0,
      "net": 0
    }
  },
  "lines": [
    {
      "product_id": 4,
      "quantity": 2,
      "extra_info": {
        "movement": "out"
      }
    }
  ]
}
```

---

### ✅ فاکتور تولید (Production)
**فیلدهای مورد نیاز:**
- ✅ نوع فاکتور: `invoice_production`
- ❌ مشتری/تامین‌کننده: نیاز ندارد
- ❌ تراکنش‌ها: نیاز ندارد
- ✅ تاریخ فاکتور: `document_date`
- ✅ خطوط خروجی (مواد اولیه): `movement: "out"`
- ✅ خطوط ورودی (کالای ساخته شده): `movement: "in"`

**ساختار payload صحیح:**
```json
{
  "invoice_type": "invoice_production",
  "document_date": "2024-01-15",
  "currency_id": 1,
  "is_proforma": false,
  "extra_info": {
    "totals": {
      "gross": 0,
      "discount": 0,
      "tax": 0,
      "net": 0
    }
  },
  "lines": [
    {
      "product_id": 5,  // مواد اولیه
      "quantity": 10,
      "extra_info": {
        "movement": "out"
      }
    },
    {
      "product_id": 6,  // کالای ساخته شده
      "quantity": 5,
      "extra_info": {
        "movement": "in"
      }
    }
  ]
}
```

---

## 🔧 راه‌حل‌های پیشنهادی

### 1. تبدیل صحیح نوع فاکتور
```dart
String _convertInvoiceTypeToApi(InvoiceType type) {
  return 'invoice_${type.value}';
}
```

### 2. استخراج person_id از customer/seller
```dart
// در ساخت payload:
if (_selectedInvoiceType == InvoiceType.sales || 
    _selectedInvoiceType == InvoiceType.salesReturn) {
  // برای فروش: person_id از customer
  if (_selectedCustomer != null) {
    extraInfo['person_id'] = _selectedCustomer!.id;
  }
}

if (_selectedInvoiceType == InvoiceType.purchase || 
    _selectedInvoiceType == InvoiceType.purchaseReturn) {
  // برای خرید: person_id از supplier
  if (_selectedSupplier != null) {
    extraInfo['person_id'] = _selectedSupplier!.id;
  }
}
```

### 3. افزودن PersonPickerWidget برای فاکتور خرید
```dart
// در _buildInvoiceInfoTab:
if (_selectedInvoiceType == InvoiceType.purchase || 
    _selectedInvoiceType == InvoiceType.purchaseReturn) {
  PersonPickerWidget(
    personTypes: ['تامین‌کننده', 'فروشنده'],
    selectedPerson: _selectedSupplier,
    onChanged: (person) {
      setState(() {
        _selectedSupplier = person;
      });
    },
  ),
}
```

### 4. تبدیل نام فیلدها
```dart
final payload = <String, dynamic>{
  'invoice_type': _convertInvoiceTypeToApi(_selectedInvoiceType!),
  'document_date': _invoiceDate!.toIso8601String().split('T')[0],
  // ...
  'lines': _lineItems.map((e) => _serializeLineItem(e)).toList(),
  'extra_info': {
    if (_selectedInvoiceType == InvoiceType.sales || 
        _selectedInvoiceType == InvoiceType.salesReturn)
      if (_selectedCustomer != null)
        'person_id': _selectedCustomer!.id,
    if (_selectedInvoiceType == InvoiceType.purchase || 
        _selectedInvoiceType == InvoiceType.purchaseReturn)
      if (_selectedSupplier != null)
        'person_id': _selectedSupplier!.id,
    'totals': {
      'gross': _sumSubtotal,
      'discount': _sumDiscount,
      'tax': _sumTax,
      'net': _sumTotal,
    },
  },
};
```

---

## 📝 خلاصه

### فاکتورهای نیازمند مشتری (Customer):
- ✅ فاکتور فروش
- ✅ فاکتور برگشت از فروش

### فاکتورهای نیازمند تامین‌کننده (Supplier):
- ✅ فاکتور خرید
- ✅ فاکتور برگشت از خرید

### فاکتورهای بدون person:
- ✅ فاکتور مصرف مستقیم
- ✅ فاکتور ضایعات
- ✅ فاکتور تولید

### فاکتورهای نیازمند تراکنش:
- ✅ فاکتور فروش (Receipt)
- ✅ فاکتور برگشت از فروش (Payment)
- ✅ فاکتور خرید (Payment)
- ✅ فاکتور برگشت از خرید (Receipt)

