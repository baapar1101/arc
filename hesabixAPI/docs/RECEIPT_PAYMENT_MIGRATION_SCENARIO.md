# سناریوی انتقال اسناد دریافت و پرداخت از hesabixOld به hesabixpy

## خلاصه اجرایی

این سند سناریوی کامل انتقال اسناد دریافت و پرداخت از دیتابیس قدیمی (`hesabixOld`) به دیتابیس جدید (`hesabixpy`) را ارائه می‌دهد. تمرکز اصلی بر روی نحوه استفاده از سرویس `receipt_payment_service.create_receipt_payment()` برای ثبت صحیح اسناد است.

## نگاشت انواع اسناد

### جدول نگاشت

| نوع قدیمی (hesabdari_doc.type) | نوع جدید (documents.document_type) | سرویس مورد استفاده | توضیحات |
|--------------------------------|-------------------------------------|---------------------|---------|
| `person_receive` | `receipt` | `receipt_payment_service.create_receipt_payment()` | دریافت از اشخاص |
| `person_send` | `payment` | `receipt_payment_service.create_receipt_payment()` | پرداخت به اشخاص |
| `sell_receive` | `receipt` | `receipt_payment_service.create_receipt_payment()` | دریافت از فروش |
| `buy_send` | `payment` | `receipt_payment_service.create_receipt_payment()` | پرداخت برای خرید |

## ساختار داده‌ها در دیتابیس قدیمی

### جدول hesabdari_doc

برای اسناد دریافت/پرداخت، فیلدهای مهم:
- `id`: شناسه سند
- `bid_id`: شناسه کسب و کار
- `submitter_id`: شناسه کاربر ایجادکننده
- `year_id`: شناسه سال مالی
- `money_id`: شناسه ارز
- `date`: تاریخ سند (varchar - شمسی یا timestamp)
- `date_submit`: تاریخ ثبت (varchar - timestamp)
- `type`: نوع سند (`person_receive`, `person_send`, `sell_receive`, `buy_send`)
- `code`: کد سند
- `des`: توضیحات
- `amount`: مبلغ کل (varchar)
- `is_preview`: پیش‌نمایش (0 یا 1)
- `is_approved`: تایید شده (0 یا 1)
- `project_id`: شناسه پروژه (اختیاری)

### جدول hesabdari_row

سطرهای سند دریافت/پرداخت معمولاً شامل:
- `id`: شناسه سطر
- `doc_id`: شناسه سند
- `ref_id`: شناسه حساب (ارجاع به hesabdari_table)
- `person_id`: شناسه شخص (اختیاری)
- `bank_id`: شناسه حساب بانکی (اختیاری)
- `cashdesk_id`: شناسه صندوق (اختیاری)
- `salary_id`: شناسه تنخواه (اختیاری)
- `cheque_id`: شناسه چک (اختیاری)
- `bs`: مبلغ بدهکار (varchar)
- `bd`: مبلغ بستانکار (varchar)
- `des`: توضیحات سطر

## ساختار داده‌ها در سیستم جدید

### سرویس receipt_payment_service.create_receipt_payment()

```python
receipt_payment_service.create_receipt_payment(
    db=db,
    business_id=new_business_id,
    user_id=new_user_id,
    data={
        "document_type": "receipt",  # یا "payment"
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
                "transaction_type": "bank",  # "bank" | "cash_register" | "petty_cash" | "check"
                "bank_id": bank_account.id,  # اگر transaction_type = "bank"
                # "cash_register_id": ...  # اگر transaction_type = "cash_register"
                # "petty_cash_id": ...  # اگر transaction_type = "petty_cash"
                # "check_id": ...  # اگر transaction_type = "check"
            }
        ],
        "description": "دریافت وجه",
        "project_id": new_project_id,  # اختیاری
        "extra_info": {
            "source": "migration",
            "old_document_id": old_doc_id
        }
    }
)
```

### ثبت‌های حسابداری خودکار

سیستم جدید به صورت خودکار ثبت‌های حسابداری را ایجاد می‌کند:

#### برای دریافت (receipt):
- **بدهکار**: حساب بانک/صندوق/تنخواه/چک = مبلغ
- **بستانکار**: حساب شخص (10401 - حساب‌های دریافتنی) = مبلغ

#### برای پرداخت (payment):
- **بدهکار**: حساب شخص (20201 - حساب‌های پرداختنی) = مبلغ
- **بستانکار**: حساب بانک/صندوق/تنخواه/چک = مبلغ

## الگوریتم استخراج داده‌ها از دیتابیس قدیمی

### مرحله 1: شناسایی سطرهای شخص و حساب

برای هر سند دریافت/پرداخت، باید سطرها را به دو دسته تقسیم کنیم:

1. **سطرهای شخص (person_lines)**: سطرهایی که `person_id` دارند
2. **سطرهای حساب (account_lines)**: سطرهایی که `bank_id`, `cashdesk_id`, `salary_id`, یا `cheque_id` دارند

### مرحله 2: تشخیص نوع تراکنش حساب

برای هر سطر حساب، باید نوع تراکنش را تشخیص دهیم:

```python
def detect_account_transaction_type(row: Dict[str, Any]) -> str:
    """تشخیص نوع تراکنش حساب از سطر قدیمی"""
    if row.get("cheque_id"):
        return "check"
    elif row.get("bank_id"):
        return "bank"
    elif row.get("cashdesk_id"):
        return "cash_register"
    elif row.get("salary_id"):
        return "petty_cash"
    else:
        # اگر هیچکدام نبود، باید از ref_id استفاده کنیم
        # اما این حالت نباید در اسناد دریافت/پرداخت رخ دهد
        raise ValueError("نوع حساب نامشخص")
```

### مرحله 3: محاسبه مبالغ

برای هر سطر:
- اگر `bs` (بدهکار) > 0: مبلغ = `bs`
- اگر `bd` (بستانکار) > 0: مبلغ = `bd`

**نکته مهم**: مجموع مبالغ `person_lines` باید برابر مجموع مبالغ `account_lines` باشد.

## نگاشت شناسه‌ها

### 1. نگاشت business_id
```python
business_id_mapping: Dict[int, int]  # {old_business_id: new_business_id}
```

### 2. نگاشت user_id
```python
user_id_mapping: Dict[int, int]  # {old_user_id: new_user_id}
```

### 3. نگاشت fiscal_year_id
```python
fiscal_year_mapping: Dict[Tuple[int, int], int]  # {(old_business_id, old_year_id): new_year_id}
```

### 4. نگاشت currency_id
```python
currency_mapping: Dict[int, int]  # {old_money_id: new_currency_id}
```

### 5. نگاشت person_id
```python
person_mapping: Dict[Tuple[int, int], int]  # {(old_business_id, old_person_id): new_person_id}
```

### 6. نگاشت bank_account_id
```python
bank_account_mapping: Dict[Tuple[int, int], int]  # {(old_business_id, old_bank_id): new_bank_account_id}
```

### 7. نگاشت cash_register_id
```python
cash_register_mapping: Dict[Tuple[int, int], int]  # {(old_business_id, old_cashdesk_id): new_cash_register_id}
```

### 8. نگاشت petty_cash_id
```python
petty_cash_mapping: Dict[Tuple[int, int], int]  # {(old_business_id, old_salary_id): new_petty_cash_id}
```

### 9. نگاشت check_id
```python
check_mapping: Dict[Tuple[int, int], int]  # {(old_business_id, old_cheque_id): new_check_id}
```

## الگوریتم انتقال

### مرحله 1: آماده‌سازی

1. ایجاد mapping tables (همانند اسکریپت migrate_invoices_complete.py)
2. بررسی وجود حساب‌های ثابت مورد نیاز:
   - 10401: حساب‌های دریافتنی
   - 20201: حساب‌های پرداختنی
   - 10203: بانک
   - 10202: صندوق
   - 10201: تنخواه گردان
3. بارگذاری cache اسناد منتقل شده (برای جلوگیری از تکراری)

### مرحله 2: دریافت اسناد از دیتابیس قدیمی

```python
def get_old_receipts_payments(
    doc_types: List[str] = ["person_receive", "person_send", "sell_receive", "buy_send"],
    start_id: Optional[int] = None,
    limit: Optional[int] = None,
    business_ids: Optional[List[int]] = None
) -> List[Dict[str, Any]]:
    """دریافت اسناد دریافت/پرداخت از دیتابیس قدیمی"""
    query = text("""
        SELECT 
            d.id, d.bid_id, d.submitter_id, d.year_id, d.money_id,
            d.date_submit, d.date, d.type, d.code, d.des, d.amount,
            d.is_preview, d.is_approved, d.project_id
        FROM hesabdari_doc d
        WHERE d.type IN (:types)
        AND d.is_approved = 1
        AND d.is_preview = 0
        ORDER BY d.bid_id, d.id ASC
    """)
    # ... اجرای query
```

### مرحله 3: استخراج سطرها

```python
def extract_receipt_payment_lines(
    doc_id: int,
    old_business_id: int,
    business_id_mapping: Dict[int, int],
    person_mapping: Dict[Tuple[int, int], int],
    bank_account_mapping: Dict[Tuple[int, int], int],
    cash_register_mapping: Dict[Tuple[int, int], int],
    petty_cash_mapping: Dict[Tuple[int, int], int],
    check_mapping: Dict[Tuple[int, int], int]
) -> Tuple[List[Dict[str, Any]], List[Dict[str, Any]]]:
    """
    استخراج person_lines و account_lines از سطرهای قدیمی
    
    Returns:
        (person_lines, account_lines)
    """
    # دریافت سطرها
    query = text("""
        SELECT 
            r.id, r.ref_id, r.person_id, r.bank_id, r.cashdesk_id,
            r.salary_id, r.cheque_id, r.bs, r.bd, r.des
        FROM hesabdari_row r
        WHERE r.doc_id = :doc_id
        ORDER BY r.id ASC
    """)
    rows = old_db.execute(query, {"doc_id": doc_id}).fetchall()
    
    person_lines = []
    account_lines = []
    new_business_id = business_id_mapping.get(old_business_id)
    
    for row in rows:
        person_id = row[2]
        bank_id = row[3]
        cashdesk_id = row[4]
        salary_id = row[5]
        cheque_id = row[6]
        debit = convert_amount(row[7])
        credit = convert_amount(row[8])
        description = row[9]
        
        amount = debit if debit > 0 else credit
        
        # سطر شخص
        if person_id:
            new_person_id = person_mapping.get((old_business_id, person_id))
            if new_person_id:
                person_lines.append({
                    "person_id": new_person_id,
                    "amount": float(amount),
                    "description": description
                })
        
        # سطر حساب
        transaction_type = None
        account_line = {
            "amount": float(amount),
            "description": description
        }
        
        if cheque_id:
            new_check_id = check_mapping.get((old_business_id, cheque_id))
            if new_check_id:
                transaction_type = "check"
                account_line["check_id"] = new_check_id
        elif bank_id:
            new_bank_id = bank_account_mapping.get((old_business_id, bank_id))
            if new_bank_id:
                transaction_type = "bank"
                account_line["bank_id"] = new_bank_id
        elif cashdesk_id:
            new_cash_register_id = cash_register_mapping.get((old_business_id, cashdesk_id))
            if new_cash_register_id:
                transaction_type = "cash_register"
                account_line["cash_register_id"] = new_cash_register_id
        elif salary_id:
            new_petty_cash_id = petty_cash_mapping.get((old_business_id, salary_id))
            if new_petty_cash_id:
                transaction_type = "petty_cash"
                account_line["petty_cash_id"] = new_petty_cash_id
        
        if transaction_type:
            account_line["transaction_type"] = transaction_type
            # پیدا کردن account_id بر اساس نوع
            account_line["account_id"] = get_account_id_for_transaction_type(
                db, new_business_id, transaction_type, account_line
            )
            account_lines.append(account_line)
    
    return person_lines, account_lines
```

### مرحله 4: ایجاد سند با سرویس جدید

```python
def migrate_receipt_payment(
    old_doc: Dict[str, Any],
    business_id_mapping: Dict[int, int],
    user_id_mapping: Dict[int, int],
    fiscal_year_mapping: Dict[Tuple[int, int], int],
    currency_mapping: Dict[int, int],
    person_mapping: Dict[Tuple[int, int], int],
    bank_account_mapping: Dict[Tuple[int, int], int],
    cash_register_mapping: Dict[Tuple[int, int], int],
    petty_cash_mapping: Dict[Tuple[int, int], int],
    check_mapping: Dict[Tuple[int, int], int],
    dry_run: bool = False
) -> Optional[int]:
    """انتقال یک سند دریافت/پرداخت"""
    
    # نگاشت شناسه‌ها
    old_business_id = old_doc.get('business_id')
    new_business_id = business_id_mapping.get(old_business_id)
    if not new_business_id:
        return None
    
    old_user_id = old_doc.get('submitter_id')
    new_user_id = user_id_mapping.get(old_user_id)
    if not new_user_id:
        return None
    
    old_currency_id = old_doc.get('money_id')
    new_currency_id = currency_mapping.get(old_currency_id)
    if not new_currency_id:
        # استفاده از ارز پیش‌فرض کسب و کار
        new_currency_id = get_default_currency(db, new_business_id)
    
    # تشخیص نوع سند
    old_type = old_doc.get('type')
    type_mapping = {
        "person_receive": "receipt",
        "sell_receive": "receipt",
        "person_send": "payment",
        "buy_send": "payment"
    }
    new_doc_type = type_mapping.get(old_type)
    if not new_doc_type:
        return None
    
    # تبدیل تاریخ
    doc_date = convert_persian_date_to_date(old_doc.get('date'))
    if not doc_date:
        date_submit = convert_timestamp_to_datetime(old_doc.get('date_submit'))
        if date_submit:
            doc_date = date_submit.date()
        else:
            doc_date = date.today()
    
    # استخراج سطرها
    person_lines, account_lines = extract_receipt_payment_lines(
        doc_id=old_doc.get('id'),
        old_business_id=old_business_id,
        business_id_mapping=business_id_mapping,
        person_mapping=person_mapping,
        bank_account_mapping=bank_account_mapping,
        cash_register_mapping=cash_register_mapping,
        petty_cash_mapping=petty_cash_mapping,
        check_mapping=check_mapping
    )
    
    # بررسی وجود سطرها
    if not person_lines or not account_lines:
        return None
    
    # بررسی تعادل مبالغ
    person_total = sum(line.get("amount", 0) for line in person_lines)
    account_total = sum(line.get("amount", 0) for line in account_lines)
    if abs(person_total - account_total) > 0.01:
        # سند نامتعادل - skip می‌کنیم
        return None
    
    if dry_run:
        return None
    
    # ایجاد سند با سرویس جدید
    try:
        from app.services.receipt_payment_service import create_receipt_payment
        
        result = create_receipt_payment(
            db=db,
            business_id=new_business_id,
            user_id=new_user_id,
            data={
                "document_type": new_doc_type,
                "document_date": doc_date.isoformat(),
                "currency_id": new_currency_id,
                "person_lines": person_lines,
                "account_lines": account_lines,
                "description": old_doc.get('des'),
                "project_id": project_mapping.get((old_business_id, old_doc.get('project_id'))) if old_doc.get('project_id') else None,
                "extra_info": {
                    "source": "migration",
                    "old_document_id": old_doc.get('id'),
                    "old_code": old_doc.get('code')
                }
            }
        )
        
        return result.get("id")
        
    except Exception as e:
        # لاگ خطا
        logger.error(f"خطا در انتقال سند {old_doc.get('code')}: {str(e)}")
        return None
```

## چالش‌ها و راهکارها

### چالش 1: تشخیص صحیح سطرهای شخص و حساب

**مشکل**: در دیتابیس قدیمی ممکن است سطرها به درستی تفکیک نشده باشند.

**راهکار**:
1. سطرهایی که `person_id` دارند → `person_lines`
2. سطرهایی که `bank_id`, `cashdesk_id`, `salary_id`, یا `cheque_id` دارند → `account_lines`
3. اگر سطری هم `person_id` و هم `bank_id` (یا سایر) داشته باشد، باید به هر دو لیست اضافه شود (اما این حالت نادر است)

### چالش 2: تعادل مبالغ

**مشکل**: مجموع مبالغ `person_lines` باید برابر مجموع مبالغ `account_lines` باشد.

**راهکار**:
1. قبل از ایجاد سند، بررسی تعادل انجام شود
2. اگر نامتعادل بود، سند skip شود و در لاگ ثبت شود
3. می‌توانیم tolerance کوچک (مثلاً 0.01) در نظر بگیریم برای خطای ممیز شناور

### چالش 3: تشخیص نوع تراکنش حساب

**مشکل**: باید از `bank_id`, `cashdesk_id`, `salary_id`, یا `cheque_id` نوع تراکنش را تشخیص دهیم.

**راهکار**:
1. اولویت: `cheque_id` → `check`
2. سپس: `bank_id` → `bank`
3. سپس: `cashdesk_id` → `cash_register`
4. سپس: `salary_id` → `petty_cash`
5. اگر هیچکدام نبود، خطا

### چالش 4: پیدا کردن account_id برای account_lines

**مشکل**: در `account_lines` باید `account_id` را مشخص کنیم.

**راهکار**:
```python
def get_account_id_for_transaction_type(
    db: Session,
    business_id: int,
    transaction_type: str,
    account_line: Dict[str, Any]
) -> int:
    """پیدا کردن account_id بر اساس نوع تراکنش"""
    if transaction_type == "bank":
        bank_id = account_line.get("bank_id")
        bank_account = db.query(BankAccount).filter(
            BankAccount.id == bank_id,
            BankAccount.business_id == business_id
        ).first()
        if bank_account:
            return bank_account.account.id
        # اگر پیدا نشد، از حساب ثابت 10203 استفاده می‌کنیم
        return _get_fixed_account_by_code(db, "10203").id
    
    elif transaction_type == "cash_register":
        cash_register_id = account_line.get("cash_register_id")
        cash_register = db.query(CashRegister).filter(
            CashRegister.id == cash_register_id,
            CashRegister.business_id == business_id
        ).first()
        if cash_register:
            return cash_register.account.id
        # اگر پیدا نشد، از حساب ثابت 10202 استفاده می‌کنیم
        return _get_fixed_account_by_code(db, "10202").id
    
    elif transaction_type == "petty_cash":
        petty_cash_id = account_line.get("petty_cash_id")
        petty_cash = db.query(PettyCash).filter(
            PettyCash.id == petty_cash_id,
            PettyCash.business_id == business_id
        ).first()
        if petty_cash:
            return petty_cash.account.id
        # اگر پیدا نشد، از حساب ثابت 10201 استفاده می‌کنیم
        return _get_fixed_account_by_code(db, "10201").id
    
    elif transaction_type == "check":
        check_id = account_line.get("check_id")
        check = db.query(Check).filter(
            Check.id == check_id,
            Check.business_id == business_id
        ).first()
        if check:
            # برای چک دریافتی: 10403 (اسناد دریافتنی)
            # برای چک پرداختی: 20202 (اسناد پرداختنی)
            if check.type == CheckType.RECEIVED:
                return _get_fixed_account_by_code(db, "10403").id
            else:
                return _get_fixed_account_by_code(db, "20202").id
        # اگر پیدا نشد، خطا
        raise ValueError("چک پیدا نشد")
    
    else:
        raise ValueError(f"نوع تراکنش نامعتبر: {transaction_type}")
```

### چالش 5: اسناد با چند شخص یا چند حساب

**مشکل**: یک سند ممکن است چند شخص یا چند حساب داشته باشد.

**راهکار**:
1. سیستم جدید از لیست‌ها پشتیبانی می‌کند (`person_lines` و `account_lines`)
2. تمام سطرهای شخص را در `person_lines` جمع می‌کنیم
3. تمام سطرهای حساب را در `account_lines` جمع می‌کنیم
4. مجموع مبالغ باید برابر باشد

### چالش 6: اسناد با چک

**مشکل**: اگر سند شامل چک باشد، باید چک قبلاً منتقل شده باشد.

**راهکار**:
1. قبل از انتقال اسناد دریافت/پرداخت، باید چک‌ها منتقل شده باشند
2. اگر چک پیدا نشد، سند skip شود و در لاگ ثبت شود

### چالش 7: تبدیل تاریخ

**مشکل**: تاریخ در دیتابیس قدیمی به صورت varchar (شمسی یا timestamp) است.

**راهکار**:
1. ابتدا سعی می‌کنیم تاریخ شمسی را تبدیل کنیم
2. اگر ناموفق بود، از `date_submit` (timestamp) استفاده می‌کنیم
3. اگر هیچکدام کار نکرد، از تاریخ امروز استفاده می‌کنیم

## الگوریتم پیشنهادی برای اجرا

### مرحله 1: آماده‌سازی

1. ایجاد mapping tables (همانند migrate_invoices_complete.py)
2. بررسی وجود حساب‌های ثابت
3. بارگذاری cache اسناد منتقل شده

### مرحله 2: انتقال به صورت batch

```python
def run_migration(
    doc_types: List[str] = ["person_receive", "person_send", "sell_receive", "buy_send"],
    batch_size: int = 100,
    dry_run: bool = False
):
    """اجرای انتقال"""
    
    # ایجاد mapping ها
    business_id_mapping = create_business_id_mapping()
    user_id_mapping = create_user_id_mapping()
    fiscal_year_mapping = create_fiscal_year_mapping(business_id_mapping)
    currency_mapping = create_currency_mapping()
    person_mapping = create_person_id_mapping(business_id_mapping)
    bank_account_mapping = create_bank_account_mapping(business_id_mapping)
    cash_register_mapping = create_cash_register_mapping(business_id_mapping)
    petty_cash_mapping = create_petty_cash_mapping(business_id_mapping)
    check_mapping = create_check_mapping(business_id_mapping)
    
    # بارگذاری cache
    _load_migrated_documents_cache(business_id_mapping)
    
    offset = 0
    while True:
        # دریافت batch اسناد
        old_docs = get_old_receipts_payments(
            doc_types=doc_types,
            limit=batch_size,
            offset=offset,
            business_ids=list(business_id_mapping.keys())
        )
        
        if not old_docs:
            break
        
        # پردازش هر سند
        for old_doc in old_docs:
            result = migrate_receipt_payment(
                old_doc=old_doc,
                business_id_mapping=business_id_mapping,
                user_id_mapping=user_id_mapping,
                fiscal_year_mapping=fiscal_year_mapping,
                currency_mapping=currency_mapping,
                person_mapping=person_mapping,
                bank_account_mapping=bank_account_mapping,
                cash_register_mapping=cash_register_mapping,
                petty_cash_mapping=petty_cash_mapping,
                check_mapping=check_mapping,
                dry_run=dry_run
            )
        
        # Commit batch
        if not dry_run:
            db.commit()
        
        offset += batch_size
```

## نکات مهم

1. ✅ **استفاده از سرویس receipt_payment_service** - ثبت‌های حسابداری خودکار انجام می‌شود
2. ✅ **نیازی به نگاشت حساب‌های شخص نیست** - سیستم از حساب‌های ثابت (10401, 20201) استفاده می‌کند
3. ✅ **نیازی به نگاشت حساب‌های بانک/صندوق/تنخواه نیست** - سیستم از account مربوط به bank_account/cash_register/petty_cash استفاده می‌کند
4. ✅ **بررسی تعادل مبالغ** - قبل از انتقال، باید مطمئن شویم که سند متعادل است
5. ✅ **استفاده از transaction** - برای هر batch از transaction استفاده کنیم
6. ✅ **لاگ کامل** - تمام عملیات انتقال را لاگ کنیم
7. ✅ **Backup** - قبل از انتقال، backup کامل بگیریم
8. ⚠️ **چک‌ها باید قبلاً منتقل شده باشند** - قبل از انتقال اسناد دریافت/پرداخت، باید چک‌ها منتقل شده باشند

## وابستگی‌ها

قبل از انتقال اسناد دریافت/پرداخت، باید این جداول منتقل شده باشند:

1. ✅ users
2. ✅ businesses
3. ✅ fiscal_years
4. ✅ currencies
5. ✅ persons
6. ✅ bank_accounts (از bank_account)
7. ✅ cash_registers (از cashdesk)
8. ✅ petty_cash (از salary)
9. ✅ checks (از cheque) - **مهم**: چک‌ها باید قبل از اسناد دریافت/پرداخت منتقل شوند

## آمار پیش‌بینی شده

بر اساس ساختار دیتابیس قدیمی:
- `person_receive`: تعداد زیادی سند
- `person_send`: تعداد زیادی سند
- `sell_receive`: تعداد متوسط سند
- `buy_send`: تعداد متوسط سند

**نکته**: آمار دقیق باید از دیتابیس قدیمی استخراج شود.

## نتیجه‌گیری

با استفاده از سرویس `receipt_payment_service.create_receipt_payment()` و منطق صحیح استخراج داده‌ها از دیتابیس قدیمی، می‌توانیم اسناد دریافت و پرداخت را به درستی منتقل کنیم. مهم‌ترین نکات:

1. **استفاده از سرویس سیستم جدید** - ثبت‌های حسابداری خودکار و صحیح انجام می‌شود
2. **تشخیص صحیح سطرهای شخص و حساب** - باید از فیلدهای `person_id`, `bank_id`, `cashdesk_id`, `salary_id`, `cheque_id` استفاده کنیم
3. **بررسی تعادل مبالغ** - قبل از انتقال، باید مطمئن شویم که سند متعادل است
4. **وابستگی به چک‌ها** - چک‌ها باید قبل از اسناد دریافت/پرداخت منتقل شوند

