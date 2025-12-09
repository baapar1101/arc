# سناریوی انتقال اسناد حسابداری از hesabixOld به hesabixpy

## خلاصه اجرایی

این سند سناریوی کامل انتقال اسناد حسابداری از دیتابیس قدیمی (`hesabixOld`) به دیتابیس جدید (`hesabixpy`) را ارائه می‌دهد. تمرکز اصلی بر روی نحوه استفاده از منطق و سرویس‌های سیستم جدید برای ثبت صحیح اسناد است.

## نگاشت انواع اسناد

### جدول نگاشت کامل

| نوع قدیمی (hesabdari_doc.type) | نوع جدید (documents.document_type) | سرویس مورد استفاده | توضیحات |
|--------------------------------|-------------------------------------|---------------------|---------|
| `sell` | `invoice_sales` | `invoice_service.create_invoice()` | فاکتور فروش |
| `rfsell` | `invoice_sales_return` | `invoice_service.create_invoice()` | برگشت از فروش |
| `buy` | `invoice_purchase` | `invoice_service.create_invoice()` | فاکتور خرید |
| `rfbuy` | `invoice_purchase_return` | `invoice_service.create_invoice()` | برگشت از خرید |
| `person_receive` | `receipt` | `receipt_payment_service.create_receipt_payment()` | دریافت از اشخاص |
| `person_send` | `payment` | `receipt_payment_service.create_receipt_payment()` | پرداخت به اشخاص |
| `sell_receive` | `receipt` | `receipt_payment_service.create_receipt_payment()` | دریافت از فروش |
| `buy_send` | `payment` | `receipt_payment_service.create_receipt_payment()` | پرداخت برای خرید |
| `cost` | `expense` | `expense_income_service.create_expense_income()` | هزینه |
| `income` | `income` | `expense_income_service.create_expense_income()` | درآمد |
| `transfer` | `transfer` | `transfer_service.create_transfer()` | انتقال بین حساب‌ها |
| `modify_cheque` | `check` | `check_service.create_check()` | ثبت/تغییر وضعیت چک |
| `modify_cheque_output` | `check` | `check_service.create_check()` | ثبت/تغییر وضعیت چک پرداختی |
| `pass_cheque` | `check_clear` | `check_service.clear_check()` | وصول چک |
| `transfer_cheque` | `check_endorse` | `check_service.endorse_check()` | واگذاری/پاسخگویی چک |
| `open_balance` | `opening_balance` | `document_service.create_manual_document()` | تراز افتتاحیه |
| سایر | `manual` | `document_service.create_manual_document()` | سند دستی |

## مهم: استفاده از حساب‌های سیستم جدید

⚠️ **نکته بسیار مهم**: در سیستم جدید، **نیازی به نگاشت جدول حساب‌ها نیست**. سیستم جدید از **حساب‌های ثابت با کد** استفاده می‌کند که در چارت حساب پیش‌فرض قرار دارند. این حساب‌ها از طریق کد خودشان پیدا می‌شوند (مثل 10401, 20201, 50002 و...).

✅ **تنها برای اسناد دستی (manual)** نیاز به نگاشت `ref_id` قدیمی به `account_id` جدید است.

## سناریوی انتقال برای هر نوع سند

### 1. فاکتور فروش (sell → invoice_sales)

#### منطق سیستم جدید:
```python
invoice_service.create_invoice(
    db=db,
    business_id=new_business_id,
    user_id=new_user_id,
    data={
        "invoice_type": "invoice_sales",
        "document_date": "2025-01-15",
        "currency_id": new_currency_id,
        "person_id": new_person_id,
        "lines": [
            {
                "product_id": new_product_id,
                "quantity": 10,
                "unit_price": 100000,
                "discount": 0,
                "tax_percent": 9
            }
        ],
        "description": "توضیحات فاکتور",
        "extra_info": {
            "source": "migration",
            "old_document_id": old_doc_id
        }
    }
)
```

#### ثبت‌های حسابداری خودکار:
- **بدهکار**: حساب شخص (10401) = مبلغ کل با مالیات
- **بستانکار**: حساب درآمد (50001) = مبلغ ناخالص
- **بدهکار**: حساب مالیات خروجی (20101) = مبلغ مالیات
- **بستانکار**: حساب تخفیفات فروش (50003) = مبلغ تخفیف (اگر وجود داشته باشد)

#### نکات انتقال:
1. ✅ استفاده از سرویس `create_invoice()` - ثبت‌های حسابداری خودکار انجام می‌شود
2. ✅ نیاز به mapping: `person_id`, `product_id`, `currency_id`, `business_id`
3. ✅ محاسبه `gross`, `discount`, `tax`, `net` از سطرهای قدیمی
4. ✅ اگر `is_preview = 1` باشد، `is_proforma = True` تنظیم شود

---

### 2. برگشت از فروش (rfsell → invoice_sales_return)

#### منطق سیستم جدید:
```python
invoice_service.create_invoice(
    db=db,
    business_id=new_business_id,
    user_id=new_user_id,
    data={
        "invoice_type": "invoice_sales_return",
        "document_date": "2025-01-15",
        "currency_id": new_currency_id,
        "person_id": new_person_id,
        "lines": [...],
        "description": "برگشت از فروش"
    }
)
```

#### ثبت‌های حسابداری خودکار:
- **بستانکار**: حساب شخص (10401) = مبلغ کل با مالیات
- **بدهکار**: حساب برگشت از فروش (50002) = مبلغ ناخالص
- **بستانکار**: حساب تخفیفات فروش (50003) = مبلغ تخفیف (برگشت)
- **بدهکار**: حساب مالیات خروجی (20101) = مبلغ مالیات (تعدیل)

#### نکات انتقال:
1. ⚠️ **مهم**: در دیتابیس قدیمی ممکن است ساختار متفاوتی داشته باشد
2. ⚠️ **مهم**: ref_id=3 (حساب‌های دریافتی) باید به حساب دریافتنی (10401) نگاشت شود
3. ⚠️ **مهم**: ref_id=137 (موجودی کالا) در سیستم جدید در پست حواله انجام می‌شود
4. ✅ استفاده از سرویس `create_invoice()` - ثبت‌های حسابداری خودکار انجام می‌شود
5. ✅ **نباید** سطرهای قدیمی را مستقیماً کپی کنیم - باید از منطق جدید استفاده کنیم

---

### 3. فاکتور خرید (buy → invoice_purchase)

#### منطق سیستم جدید:
```python
invoice_service.create_invoice(
    db=db,
    business_id=new_business_id,
    user_id=new_user_id,
    data={
        "invoice_type": "invoice_purchase",
        "document_date": "2025-01-15",
        "currency_id": new_currency_id,
        "person_id": new_person_id,
        "lines": [...],
        "description": "فاکتور خرید"
    }
)
```

#### ثبت‌های حسابداری خودکار:
- **بدهکار**: حساب GRNI (30101) = مبلغ ناخالص
- **بستانکار**: حساب تخفیفات خرید (40003) = مبلغ تخفیف
- **بدهکار**: حساب مالیات ورودی (10104) = مبلغ مالیات
- **بستانکار**: حساب شخص (20201) = مبلغ کل با مالیات

---

### 4. برگشت از خرید (rfbuy → invoice_purchase_return)

#### منطق سیستم جدید:
```python
invoice_service.create_invoice(
    db=db,
    business_id=new_business_id,
    user_id=new_user_id,
    data={
        "invoice_type": "invoice_purchase_return",
        "document_date": "2025-01-15",
        "currency_id": new_currency_id,
        "person_id": new_person_id,
        "lines": [...],
        "description": "برگشت از خرید"
    }
)
```

#### ثبت‌های حسابداری خودکار:
- **بدهکار**: حساب شخص (20201) = مبلغ کل با مالیات
- **بستانکار**: حساب GRNI (30101) = مبلغ ناخالص
- **بدهکار**: حساب تخفیفات خرید (40003) = مبلغ تخفیف (برگشت)
- **بستانکار**: حساب مالیات ورودی (10104) = مبلغ مالیات (تعدیل)

#### نکات انتقال:
1. ⚠️ **مهم**: در دیتابیس قدیمی ref_id=3 (حساب‌های دریافتی) استفاده شده - باید به حساب پرداختنی (20201) نگاشت شود
2. ⚠️ **مهم**: ref_id=59 (فروش کالا) باید به GRNI (30101) نگاشت شود
3. ✅ استفاده از سرویس `create_invoice()` - ثبت‌های حسابداری خودکار انجام می‌شود

---

### 5. دریافت از اشخاص (person_receive → receipt)

#### منطق سیستم جدید:
```python
receipt_payment_service.create_receipt_payment(
    db=db,
    business_id=new_business_id,
    user_id=new_user_id,
    data={
        "document_type": "receipt",
        "document_date": "2025-01-15",
        "currency_id": new_currency_id,
        "person_lines": [
            {
                "person_id": new_person_id,
                "amount": 1000000,
                "description": "دریافت از مشتری"
            }
        ],
        "account_lines": [
            {
                "account_id": bank_account.account.id,  # حساب بانک
                "amount": 1000000,
                "transaction_type": "bank",
                "bank_id": bank_account.id
            }
        ],
        "description": "دریافت وجه"
    }
)
```

#### ثبت‌های حسابداری:
- **بدهکار**: حساب بانک/صندوق/تنخواه = مبلغ
- **بستانکار**: حساب شخص (10401) = مبلغ

#### نکات انتقال:
1. ✅ نیاز به تشخیص نوع حساب (bank_id, cashdesk_id, salary_id)
2. ✅ نگاشت به `bank_account_id`, `cash_register_id`, `petty_cash_id`
3. ✅ مجموع `person_lines` باید برابر `account_lines` باشد

---

### 6. پرداخت به اشخاص (person_send → payment)

#### منطق سیستم جدید:
```python
receipt_payment_service.create_receipt_payment(
    db=db,
    business_id=new_business_id,
    user_id=new_user_id,
    data={
        "document_type": "payment",
        "document_date": "2025-01-15",
        "currency_id": new_currency_id,
        "person_lines": [
            {
                "person_id": new_person_id,
                "amount": 1000000,
                "description": "پرداخت به تامین‌کننده"
            }
        ],
        "account_lines": [
            {
                "account_id": bank_account.account.id,
                "amount": 1000000,
                "transaction_type": "bank",
                "bank_id": bank_account.id
            }
        ],
        "description": "پرداخت وجه"
    }
)
```

#### ثبت‌های حسابداری:
- **بدهکار**: حساب شخص (20201) = مبلغ
- **بستانکار**: حساب بانک/صندوق/تنخواه = مبلغ

---

### 7. هزینه (cost → expense)

#### منطق سیستم جدید:
```python
expense_income_service.create_expense_income(
    db=db,
    business_id=new_business_id,
    user_id=new_user_id,
    data={
        "document_type": "expense",
        "document_date": "2025-01-15",
        "currency_id": new_currency_id,
        "item_lines": [
            {
                "account_id": expense_account.id,  # حساب هزینه
                "amount": 500000,
                "description": "هزینه حمل"
            }
        ],
        "counterparty_lines": [
            {
                "transaction_type": "bank",
                "amount": 500000,
                "bank_id": bank_account.id
            }
        ],
        "description": "هزینه حمل و نقل"
    }
)
```

#### ثبت‌های حسابداری:
- **بدهکار**: حساب هزینه = مبلغ
- **بستانکار**: حساب بانک/صندوق/تنخواه/شخص = مبلغ

#### نکات انتقال:
1. ✅ `item_lines`: سطرهای حساب‌های هزینه
2. ✅ `counterparty_lines`: سطرهای طرف‌حساب (بانک/صندوق/شخص/چک)
3. ✅ مجموع `item_lines` باید برابر `counterparty_lines` باشد

---

### 8. درآمد (income → income)

#### منطق سیستم جدید:
```python
expense_income_service.create_expense_income(
    db=db,
    business_id=new_business_id,
    user_id=new_user_id,
    data={
        "document_type": "income",
        "document_date": "2025-01-15",
        "currency_id": new_currency_id,
        "item_lines": [
            {
                "account_id": income_account.id,  # حساب درآمد
                "amount": 2000000,
                "description": "درآمد فروش"
            }
        ],
        "counterparty_lines": [
            {
                "transaction_type": "bank",
                "amount": 2000000,
                "bank_id": bank_account.id
            }
        ],
        "description": "دریافت درآمد"
    }
)
```

#### ثبت‌های حسابداری:
- **بدهکار**: حساب بانک/صندوق/تنخواه/شخص = مبلغ
- **بستانکار**: حساب درآمد = مبلغ

---

### 9. انتقال (transfer → transfer)

#### منطق سیستم جدید:
```python
transfer_service.create_transfer(
    db=db,
    business_id=new_business_id,
    user_id=new_user_id,
    data={
        "document_date": "2025-01-15",
        "currency_id": new_currency_id,
        "source": {
            "type": "bank",  # bank | cash_register | petty_cash
            "id": source_bank_account.id
        },
        "destination": {
            "type": "cash_register",
            "id": destination_cash_register.id
        },
        "amount": 5000000,
        "commission": 5000,  # اختیاری
        "description": "انتقال از بانک به صندوق"
    }
)
```

#### ثبت‌های حسابداری خودکار:
- **بدهکار**: حساب مقصد (بانک/صندوق/تنخواه) = مبلغ
- **بستانکار**: حساب مبدأ (بانک/صندوق/تنخواه) = مبلغ
- **بدهکار**: حساب کارمزد (70902) = کارمزد (اگر وجود داشته باشد)
- **بستانکار**: حساب مبدأ = کارمزد (اگر وجود داشته باشد)

#### نکات انتقال:
1. ✅ نیاز به تشخیص نوع source و destination از ref_id
2. ✅ نگاشت bank_id → bank_account_id
3. ✅ نگاشت cashdesk_id → cash_register_id
4. ✅ نگاشت salary_id → petty_cash_id

---

### 10. چک‌ها (modify_cheque, modify_cheque_output, pass_cheque, transfer_cheque)

#### آمار در دیتابیس قدیمی:
- `modify_cheque`: 1,250 سند (ثبت/تغییر چک)
- `modify_cheque_output`: 535 سند (ثبت چک پرداختی)
- `pass_cheque`: 306 سند (وصول چک)
- `transfer_cheque`: 299 سند (انتقال/واگذاری چک)

#### منطق سیستم جدید:

چک‌ها در سیستم جدید به صورت جداگانه در جدول `checks` مدیریت می‌شوند. هر عملیات روی چک یک سند حسابداری ایجاد می‌کند که به صورت خودکار ثبت می‌شود.

##### 10.1 ثبت چک دریافتی (modify_cheque → create_check)

```python
check_service.create_check(
    db=db,
    business_id=new_business_id,
    user_id=new_user_id,
    data={
        "type": "received",  # چک دریافتی
        "person_id": new_person_id,
        "issue_date": "2025-01-15",
        "due_date": "2025-02-15",
        "check_number": "123456",
        "amount": 10000000,
        "currency_id": new_currency_id,
        "bank_name": "بانک ملی",
        "branch_name": "شعبه مرکزی",
        "sayad_code": "1234567890123456",  # اختیاری
        "document_date": "2025-01-15",
        "document_description": "ثبت چک دریافتی"
    }
)
```

**ثبت‌های حسابداری خودکار**:
- **بدهکار**: حساب اسناد دریافتنی (10403) = مبلغ چک
- **بستانکار**: حساب شخص (10401) = مبلغ چک

##### 10.2 ثبت چک پرداختی (modify_cheque_output → create_check)

```python
check_service.create_check(
    db=db,
    business_id=new_business_id,
    user_id=new_user_id,
    data={
        "type": "transferred",  # چک پرداختی
        "person_id": new_person_id,
        "issue_date": "2025-01-15",
        "due_date": "2025-02-15",
        "check_number": "654321",
        "amount": 5000000,
        "currency_id": new_currency_id,
        "bank_name": "بانک ملت",
        "document_date": "2025-01-15",
        "document_description": "ثبت چک پرداختی"
    }
)
```

**ثبت‌های حسابداری خودکار**:
- **بدهکار**: حساب شخص (20201) = مبلغ چک
- **بستانکار**: حساب اسناد پرداختنی (20202) = مبلغ چک

##### 10.3 وصول چک (pass_cheque → clear_check)

```python
# ابتدا باید چک را پیدا کنیم یا ایجاد کنیم
check = find_or_create_check_from_old_document(old_doc)

# سپس وصول چک
check_service.clear_check(
    db=db,
    check_id=check.id,
    user_id=new_user_id,
    data={
        "document_date": "2025-02-15",
        "bank_account_id": bank_account.id,
        "description": "وصول چک"
    }
)
```

**ثبت‌های حسابداری خودکار**:
- **بدهکار**: حساب بانک (10203) = مبلغ چک
- **بستانکار**: حساب اسناد دریافتنی (10403) یا اسناد در جریان وصول (10404) = مبلغ چک

##### 10.4 واگذاری/پاسخگویی چک (transfer_cheque → endorse_check)

```python
# ابتدا باید چک را پیدا کنیم
check = find_or_create_check_from_old_document(old_doc)

# سپس واگذاری چک
check_service.endorse_check(
    db=db,
    check_id=check.id,
    user_id=new_user_id,
    data={
        "document_date": "2025-01-20",
        "to_person_id": new_person_id,
        "description": "واگذاری چک"
    }
)
```

**ثبت‌های حسابداری خودکار**:
- **بدهکار**: حساب شخص جدید (10401) = مبلغ چک
- **بستانکار**: حساب اسناد دریافتنی (10403) = مبلغ چک

#### نکات مهم انتقال چک‌ها:

1. ⚠️ **چک‌ها باید از جدول `cheque` در دیتابیس قدیمی منتقل شوند**
   - جدول `cheque` شامل اطلاعات کامل چک‌ها است
   - اسناد `hesabdari_doc` با نوع چک، فقط عملیات روی چک هستند

2. ⚠️ **ترتیب انتقال چک‌ها**:
   - ابتدا باید چک‌ها از جدول `cheque` منتقل شوند
   - سپس اسناد مربوط به چک‌ها (modify_cheque, pass_cheque و...) منتقل شوند

3. ✅ **استفاده از حساب‌های ثابت**:
   - سیستم جدید از حساب‌های ثابت با کد استفاده می‌کند:
     - 10403: اسناد دریافتنی
     - 10404: اسناد در جریان وصول
     - 20202: اسناد پرداختنی
     - 10401: حساب‌های دریافتنی
     - 20201: حساب‌های پرداختنی
     - 10203: بانک

4. ✅ **استفاده از سرویس‌های سیستم جدید**:
   - `create_check()`: برای ثبت چک
   - `clear_check()`: برای وصول چک
   - `deposit_check()`: برای سپرده چک
   - `endorse_check()`: برای واگذاری چک
   - `return_check()`: برای عودت چک
   - `bounce_check()`: برای برگشت خوردن چک

5. ⚠️ **تحلیل اسناد چک در دیتابیس قدیمی**:
   - `modify_cheque`: معمولاً ثبت چک جدید یا تغییر وضعیت
   - `pass_cheque`: وصول چک (معمولاً cheque_id در hesabdari_row وجود دارد)
   - `transfer_cheque`: واگذاری/پاسخگویی چک
   - باید بررسی کنیم که آیا cheque_id در hesabdari_row وجود دارد یا نه

---

### 11. سند دستی (calc, سایر → manual)

#### منطق سیستم جدید:
```python
document_service.create_manual_document(
    db=db,
    business_id=new_business_id,
    fiscal_year_id=new_fiscal_year_id,
    user_id=new_user_id,
    data={
        "code": "MAN-20250115-0001",
        "document_date": "2025-01-15",
        "currency_id": new_currency_id,
        "document_type": "manual",
        "description": "سند دستی",
        "lines": [
            {
                "account_id": account1.id,
                "debit": 1000000,
                "credit": 0,
                "description": "بدهکار"
            },
            {
                "account_id": account2.id,
                "debit": 0,
                "credit": 1000000,
                "description": "بستانکار"
            }
        ]
    }
)
```

#### نکات انتقال:
1. ✅ برای اسنادی که منطق خاصی ندارند (مثلاً calc)
2. ✅ باید تعادل بدهکار/بستانکار بررسی شود
3. ⚠️ **فقط برای اسناد دستی نیاز به نگاشت ref_id → account_id است**
4. ✅ برای نگاشت حساب‌ها در اسناد دستی:
   - باید mapping بین hesabdari_table و accounts ایجاد شود
   - بر اساس business_id (اگر مخصوص کسب و کار باشد) یا NULL (حساب عمومی)
   - بر اساس کد حساب (code)
   - بر اساس نوع حساب (type → account_type)

---

## چالش‌ها و راهکارها

### چالش 1: استفاده از حساب‌های ثابت سیستم جدید

**مهم**: در سیستم جدید، **نیازی به نگاشت جدول حساب‌ها نیست**. سیستم جدید از **حساب‌های ثابت با کد** استفاده می‌کند که در چارت حساب پیش‌فرض قرار دارند.

**حساب‌های ثابت سیستم جدید** (با کد):
- **10201**: تنخواه گردان
- **10202**: صندوق
- **10203**: بانک
- **10401**: حساب‌های دریافتنی
- **10403**: اسناد دریافتنی
- **10404**: اسناد در جریان وصول
- **20201**: حساب‌های پرداختنی
- **20202**: اسناد پرداختنی
- **30101**: GRNI
- **50001**: درآمد
- **50002**: برگشت از فروش
- **50003**: تخفیفات فروش
- **40003**: تخفیفات خرید
- **20101**: مالیات بر ارزش افزوده خروجی
- **10104**: مالیات بر ارزش افزوده ورودی
- و سایر حساب‌های ثابت...

**راهکار**:
1. ✅ **برای فاکتورها، دریافت/پرداخت، هزینه/درآمد، انتقال و چک**: از سرویس‌های سیستم جدید استفاده می‌کنیم که حساب‌ها را خودکار از کد پیدا می‌کنند
2. ✅ **فقط برای اسناد دستی (manual)**: نیاز به نگاشت `ref_id` به `account_id` است
3. ✅ **سیستم جدید حساب‌ها را از کد پیدا می‌کند**: `_get_fixed_account_by_code(db, "10401")`

### چالش 2: ساختار متفاوت ثبت‌های حسابداری

**مشکل**: در دیتابیس قدیمی ممکن است ساختار متفاوتی داشته باشد (مثلاً در rfbuy از ref_id=3 استفاده شده که باید حساب پرداختنی باشد).

**راهکار**:
1. ✅ **استفاده از سرویس‌های سیستم جدید** - ثبت‌های حسابداری خودکار و صحیح انجام می‌شود
2. ✅ **نباید سطرهای قدیمی را مستقیماً کپی کنیم** - باید از منطق جدید استفاده کنیم
3. ✅ **سیستم جدید حساب‌ها را از کد پیدا می‌کند** - نیازی به نگاشت ref_id نیست
4. ✅ باید از منطق جدید استفاده کنیم:
   - برای فاکتورها: `invoice_service.create_invoice()` - حساب‌ها خودکار
   - برای دریافت/پرداخت: `receipt_payment_service.create_receipt_payment()` - حساب‌ها خودکار
   - برای هزینه/درآمد: `expense_income_service.create_expense_income()` - حساب‌ها خودکار
   - برای انتقال: `transfer_service.create_transfer()` - حساب‌ها خودکار
   - برای چک: `check_service.*()` - حساب‌ها خودکار
   - فقط برای سند دستی: نیاز به نگاشت account_id داریم

### چالش 3: تبدیل تاریخ

**مشکل**: در دیتابیس قدیمی تاریخ به صورت varchar (timestamp یا جلالی) ذخیره شده.

**راهکار**:
1. تبدیل timestamp به datetime
2. تبدیل تاریخ جلالی به میلادی
3. استفاده از `CalendarConverter` برای تبدیل تاریخ

### چالش 4: حجم زیاد داده

**مشکل**: 126,447 سند نیاز به انتقال دارد.

**راهکار**:
1. انتقال به صورت batch (مثلاً 100 سند در هر batch)
2. استفاده از transaction برای هر batch
3. فقط اسناد تایید شده (`is_approved = 1`) و غیر پیش‌نمایش (`is_preview = 0`) را منتقل کنیم
4. لاگ کامل از عملیات انتقال

### چالش 5: وابستگی‌ها

**مشکل**: قبل از انتقال اسناد، باید این جداول منتقل شده باشند.

**راهکار**:
1. ترتیب انتقال:
   - ✅ users
   - ✅ businesses
   - ✅ fiscal_years
   - ✅ currencies
   - ✅ accounts (حساب‌های عمومی پیش‌فرض باید وجود داشته باشند - از migration)
   - ✅ persons
   - ✅ products (commodity → products)
   - ✅ bank_accounts
   - ✅ cash_registers
   - ✅ petty_cash
   - ✅ checks (از جدول cheque در دیتابیس قدیمی)
   - ✅ **documents** (آخرین مرحله)

**نکته مهم**: حساب‌های عمومی (با business_id = NULL) از طریق migration ایجاد می‌شوند و نیازی به انتقال ندارند. فقط باید مطمئن شویم که حساب‌های مورد نیاز وجود دارند.

---

## الگوریتم پیشنهادی برای انتقال

### مرحله 1: آماده‌سازی

1. ایجاد mapping tables:
   - `old_to_new_business_id`
   - `old_to_new_user_id`
   - `old_to_new_fiscal_year_id`
   - `old_to_new_currency_id`
   - `old_to_new_person_id`
   - `old_to_new_product_id`
   - `old_to_new_bank_account_id`
   - `old_to_new_cash_register_id`
   - `old_to_new_petty_cash_id`
   - `old_to_new_check_id`
   - `old_to_new_account_id` (فقط برای اسناد دستی - hesabdari_table → accounts)

2. بررسی وجود حساب‌های ثابت مورد نیاز:
   - حساب‌های عمومی باید از طریق migration ایجاد شده باشند
   - بررسی وجود حساب‌های با کد:
     - 10401 (حساب‌های دریافتنی)
     - 10403 (اسناد دریافتنی)
     - 20201 (حساب‌های پرداختنی)
     - 20202 (اسناد پرداختنی)
     - 10203 (بانک)
     - 10202 (صندوق)
     - 10201 (تنخواه گردان)
     - و سایر حساب‌های ثابت...

### مرحله 2: انتقال به ترتیب نوع

#### 2.1 فاکتورها (sell, rfsell, buy, rfbuy)

```python
for old_doc in old_invoices:
    # تشخیص نوع فاکتور
    invoice_type_map = {
        "sell": "invoice_sales",
        "rfsell": "invoice_sales_return",
        "buy": "invoice_purchase",
        "rfbuy": "invoice_purchase_return"
    }
    
    new_invoice_type = invoice_type_map[old_doc.type]
    
    # استخراج اطلاعات از سطرهای قدیمی
    lines = extract_lines_from_old_rows(old_doc.id)
    
    # محاسبه totals
    totals = calculate_totals(lines)
    
    # ایجاد فاکتور با سرویس جدید
    invoice_service.create_invoice(
        db=db,
        business_id=new_business_id,
        user_id=new_user_id,
        data={
            "invoice_type": new_invoice_type,
            "document_date": convert_date(old_doc.date),
            "currency_id": new_currency_id,
            "person_id": new_person_id,
            "lines": convert_lines_to_new_format(lines),
            "description": old_doc.des,
            "is_proforma": old_doc.is_preview == 1,
            "extra_info": {
                "source": "migration",
                "old_document_id": old_doc.id
            }
        }
    )
```

#### 2.2 دریافت/پرداخت (person_receive, person_send, sell_receive, buy_send)

```python
for old_doc in old_receipts_payments:
    # تشخیص نوع
    doc_type_map = {
        "person_receive": "receipt",
        "sell_receive": "receipt",
        "person_send": "payment",
        "buy_send": "payment"
    }
    
    new_doc_type = doc_type_map[old_doc.type]
    
    # استخراج person_lines و account_lines
    person_lines, account_lines = extract_receipt_payment_lines(old_doc.id)
    
    # ایجاد سند با سرویس جدید
    receipt_payment_service.create_receipt_payment(
        db=db,
        business_id=new_business_id,
        user_id=new_user_id,
        data={
            "document_type": new_doc_type,
            "document_date": convert_date(old_doc.date),
            "currency_id": new_currency_id,
            "person_lines": person_lines,
            "account_lines": account_lines,
            "description": old_doc.des
        }
    )
```

#### 2.3 هزینه/درآمد (cost, income)

```python
for old_doc in old_expenses_incomes:
    # تشخیص نوع
    doc_type_map = {
        "cost": "expense",
        "income": "income"
    }
    
    new_doc_type = doc_type_map[old_doc.type]
    
    # استخراج item_lines و counterparty_lines
    item_lines, counterparty_lines = extract_expense_income_lines(old_doc.id)
    
    # ایجاد سند با سرویس جدید
    expense_income_service.create_expense_income(
        db=db,
        business_id=new_business_id,
        user_id=new_user_id,
        data={
            "document_type": new_doc_type,
            "document_date": convert_date(old_doc.date),
            "currency_id": new_currency_id,
            "item_lines": item_lines,
            "counterparty_lines": counterparty_lines,
            "description": old_doc.des
        }
    )
```

#### 2.4 انتقال (transfer)

```python
for old_doc in old_transfers:
    # تشخیص source و destination از سطرها
    source, destination = extract_transfer_source_destination(old_doc.id)
    
    # ایجاد سند با سرویس جدید
    transfer_service.create_transfer(
        db=db,
        business_id=new_business_id,
        user_id=new_user_id,
        data={
            "document_date": convert_date(old_doc.date),
            "currency_id": new_currency_id,
            "source": source,
            "destination": destination,
            "amount": old_doc.amount,
            "commission": old_doc.commission or 0,
            "description": old_doc.des
        }
    )
```

#### 2.5 چک‌ها (modify_cheque, pass_cheque, transfer_cheque)

```python
# ابتدا چک‌ها از جدول cheque منتقل شده باشند
for old_doc in old_check_documents:
    # پیدا کردن چک مربوطه
    old_cheque = get_cheque_from_document(old_doc)
    
    if old_doc.type == "modify_cheque":
        # ثبت یا تغییر وضعیت چک
        check = find_or_create_check(old_cheque)
        
    elif old_doc.type == "pass_cheque":
        # وصول چک
        check = find_check_by_old_id(old_cheque.id)
        if check:
            check_service.clear_check(
                db=db,
                check_id=check.id,
                user_id=new_user_id,
                data={
                    "document_date": convert_date(old_doc.date),
                    "bank_account_id": get_bank_account_from_row(old_doc.id),
                    "description": old_doc.des
                }
            )
    
    elif old_doc.type == "transfer_cheque":
        # واگذاری چک
        check = find_check_by_old_id(old_cheque.id)
        if check:
            check_service.endorse_check(
                db=db,
                check_id=check.id,
                user_id=new_user_id,
                data={
                    "document_date": convert_date(old_doc.date),
                    "to_person_id": get_person_from_row(old_doc.id),
                    "description": old_doc.des
                }
            )
```

#### 2.6 سایر (manual)

```python
for old_doc in old_other_documents:
    # استخراج سطرها
    lines = extract_lines_from_old_rows(old_doc.id)
    
    # تبدیل به فرمت جدید - **فقط برای اسناد دستی نیاز به نگاشت account_id است**
    new_lines = []
    for line in lines:
        # نگاشت ref_id به account_id (فقط برای اسناد دستی)
        old_account_id = line.get("ref_id")
        new_account_id = account_mapping.get(old_account_id)  # از mapping استفاده می‌کنیم
        
        if not new_account_id:
            # اگر mapping پیدا نشد، لاگ می‌کنیم
            log_warning(f"حساب با ref_id {old_account_id} برای سند {old_doc.id} پیدا نشد")
            continue
        
        new_lines.append({
            "account_id": new_account_id,
            "debit": line.get("bs", 0),
            "credit": line.get("bd", 0),
            "description": line.get("des"),
            "person_id": person_mapping.get(line.get("person_id")),
            "product_id": product_mapping.get(line.get("commodity_id")),
            # سایر فیلدها...
        })
    
    # بررسی تعادل
    if not is_balanced(new_lines):
        log_warning(f"سند {old_doc.id} نامتعادل است")
        continue
    
    # ایجاد سند دستی
    document_service.create_manual_document(
        db=db,
        business_id=new_business_id,
        fiscal_year_id=new_fiscal_year_id,
        user_id=new_user_id,
        data={
            "code": generate_code(old_doc.code),
            "document_date": convert_date(old_doc.date),
            "currency_id": new_currency_id,
            "document_type": "manual",
            "description": old_doc.des,
            "lines": new_lines
        }
    )
```

### مرحله 3: Validation

1. بررسی تعادل همه اسناد منتقل شده
2. مقایسه مانده حساب‌ها قبل و بعد از انتقال
3. تست عملکرد اسناد در سیستم جدید

---

## نکات مهم

1. ✅ **همیشه از سرویس‌های سیستم جدید استفاده کنیم** - ثبت‌های حسابداری خودکار و صحیح انجام می‌شود
2. ✅ **نباید سطرهای قدیمی را مستقیماً کپی کنیم** - باید از منطق جدید استفاده کنیم
3. ✅ **استفاده از حساب‌های ثابت سیستم جدید** - نیازی به نگاشت حساب‌ها نیست، سیستم از کد حساب استفاده می‌کند (مثل 10401, 20201, 50002 و...)
4. ✅ **فقط برای اسناد دستی نیاز به نگاشت حساب** - باید ref_id را به account_id نگاشت کنیم
5. ✅ **چک‌ها ابتدا منتقل شوند** - قبل از انتقال اسناد مربوط به چک، باید چک‌ها از جدول cheque منتقل شده باشند
6. ✅ **بررسی تعادل** - قبل از انتقال، باید مطمئن شویم که سند متعادل است
7. ✅ **استفاده از transaction** - برای هر batch از transaction استفاده کنیم
8. ✅ **لاگ کامل** - تمام عملیات انتقال را لاگ کنیم
9. ✅ **Backup** - قبل از انتقال، backup کامل بگیریم

---

## نتیجه‌گیری

با استفاده از سرویس‌های سیستم جدید و منطق صحیح، می‌توانیم اسناد را به درستی منتقل کنیم. 

**مهم‌ترین نکات**:

1. **نباید سطرهای قدیمی را مستقیماً کپی کنیم** - باید از منطق جدید سیستم استفاده کنیم که ثبت‌های حسابداری را به صورت خودکار و صحیح انجام می‌دهد

2. **سیستم جدید از حساب‌های ثابت با کد استفاده می‌کند** - نیازی به نگاشت جدول حساب‌ها نیست. سیستم از طریق کد حساب (مثل 10401, 20201, 50002) حساب‌ها را پیدا می‌کند. فقط برای اسناد دستی نیاز به نگاشت ref_id به account_id داریم.

3. **چک‌ها باید ابتدا منتقل شوند** - قبل از انتقال اسناد مربوط به چک (modify_cheque, pass_cheque و...)، باید چک‌ها از جدول cheque در دیتابیس قدیمی منتقل شده باشند.

4. **هر نوع سند از سرویس مخصوص خودش استفاده می‌کند** - فاکتورها، دریافت/پرداخت، هزینه/درآمد، انتقال و چک هر کدام سرویس و منطق خاص خود را دارند که ثبت‌های حسابداری را به صورت خودکار انجام می‌دهد.

