# طرح محافظت از تراکنش‌های کیف پول

## مشکل شناسایی شده
کاربران می‌توانند تراکنش‌های مربوط به کیف پول را حذف کنند که منجر به خراب شدن داده‌ها می‌شود. این شامل:
- تراکنش‌های واریز و برداشت کیف پول
- صورت حساب‌های هوش مصنوعی
- پکیج‌ها و استفاده از نرم‌افزار بابت هوش مصنوعی
- صورتحساب‌های ذخیره‌سازی
- سرویس‌های زحل

## راه‌حل جامع

### 1. ایجاد تابع محافظتی مرکزی

#### 1.1. تابع بررسی ارتباط سند با تراکنش کیف پول
**فایل:** `app/services/wallet_service.py`

```python
def check_document_has_wallet_transactions(db: Session, document_id: int) -> Dict[str, Any]:
    """
    بررسی می‌کند که آیا یک سند به تراکنش‌های کیف پول مرتبط است یا نه
    
    Returns:
        {
            "has_wallet_transactions": bool,
            "transaction_count": int,
            "transaction_ids": List[int],
            "transaction_types": List[str],
            "message": str
        }
    """
    from adapters.db.models.wallet import WalletTransaction
    
    transactions = db.query(WalletTransaction).filter(
        WalletTransaction.document_id == document_id
    ).all()
    
    if not transactions:
        return {
            "has_wallet_transactions": False,
            "transaction_count": 0,
            "transaction_ids": [],
            "transaction_types": [],
            "message": None
        }
    
    transaction_ids = [tx.id for tx in transactions]
    transaction_types = list(set([tx.type for tx in transactions]))
    
    # انواع تراکنش‌های سیستمی که نباید حذف شوند
    protected_types = [
        "top_up",                    # واریز
        "payout_request",           # درخواست برداشت
        "payout_settlement",        # تسویه برداشت
        "internal_invoice_payment", # پرداخت صورتحساب داخلی
        "ai_subscription",           # اشتراک هوش مصنوعی
        "ai_usage",                 # استفاده از هوش مصنوعی
        "customer_payment",         # پرداخت مشتری (پکیج‌ها)
        "internal_service_charge",  # کسر سرویس داخلی
        "refund",                   # بازگشت وجه
        "fee",                      # کارمزد
        "chargeback",               # برگشت تراکنش
        "reversal"                  # معکوس کردن تراکنش
    ]
    
    has_protected = any(tx.type in protected_types for tx in transactions)
    
    if has_protected:
        protected_tx = [tx for tx in transactions if tx.type in protected_types]
        message = f"این سند به {len(protected_tx)} تراکنش کیف پول سیستمی مرتبط است و قابل حذف نمی‌باشد. انواع تراکنش‌ها: {', '.join(set([tx.type for tx in protected_tx]))}"
    else:
        message = f"این سند به {len(transactions)} تراکنش کیف پول مرتبط است"
    
    return {
        "has_wallet_transactions": True,
        "has_protected_transactions": has_protected,
        "transaction_count": len(transactions),
        "transaction_ids": transaction_ids,
        "transaction_types": transaction_types,
        "message": message
    }
```

#### 1.2. تابع بررسی تراکنش‌های مرتبط با موجودیت‌های دیگر
**فایل:** `app/services/wallet_service.py`

```python
def check_wallet_transaction_has_dependencies(db: Session, transaction_id: int) -> Dict[str, Any]:
    """
    بررسی می‌کند که آیا یک تراکنش کیف پول به موجودیت‌های دیگر لینک شده است یا نه
    
    Returns:
        {
            "has_dependencies": bool,
            "dependencies": {
                "ai_invoices": List[int],
                "storage_invoices": List[int],
                "marketplace_orders": List[int],
                "zohal_services": List[int],
                "ai_usage_logs": List[int]
            },
            "message": str
        }
    """
    dependencies = {
        "ai_invoices": [],
        "storage_invoices": [],
        "marketplace_orders": [],
        "zohal_services": [],
        "ai_usage_logs": []
    }
    
    # بررسی AI Invoices
    try:
        from adapters.db.models.ai_invoice import AIInvoice
        ai_invoices = db.query(AIInvoice).filter(
            AIInvoice.wallet_transaction_id == transaction_id
        ).all()
        dependencies["ai_invoices"] = [inv.id for inv in ai_invoices]
    except Exception:
        pass
    
    # بررسی Storage Invoices
    try:
        from adapters.db.models.storage_plan import StorageInvoice
        storage_invoices = db.query(StorageInvoice).filter(
            StorageInvoice.wallet_transaction_id == transaction_id
        ).all()
        dependencies["storage_invoices"] = [inv.id for inv in storage_invoices]
    except Exception:
        pass
    
    # بررسی Marketplace Orders
    try:
        from adapters.db.models.marketplace import MarketplaceOrder
        marketplace_orders = db.query(MarketplaceOrder).filter(
            MarketplaceOrder.wallet_transaction_id == transaction_id
        ).all()
        dependencies["marketplace_orders"] = [order.id for order in marketplace_orders]
    except Exception:
        pass
    
    # بررسی Zohal Services
    try:
        from adapters.db.models.zohal import ZohalServiceUsage
        zohal_services = db.query(ZohalServiceUsage).filter(
            ZohalServiceUsage.wallet_transaction_id == transaction_id
        ).all()
        dependencies["zohal_services"] = [svc.id for svc in zohal_services]
    except Exception:
        pass
    
    # بررسی AI Usage Logs
    try:
        from adapters.db.models.ai_usage_log import AIUsageLog
        ai_usage_logs = db.query(AIUsageLog).filter(
            AIUsageLog.wallet_transaction_id == transaction_id
        ).all()
        dependencies["ai_usage_logs"] = [log.id for log in ai_usage_logs]
    except Exception:
        pass
    
    total_dependencies = sum(len(v) for v in dependencies.values())
    has_dependencies = total_dependencies > 0
    
    if has_dependencies:
        dep_list = []
        if dependencies["ai_invoices"]:
            dep_list.append(f"{len(dependencies['ai_invoices'])} صورتحساب AI")
        if dependencies["storage_invoices"]:
            dep_list.append(f"{len(dependencies['storage_invoices'])} صورتحساب ذخیره‌سازی")
        if dependencies["marketplace_orders"]:
            dep_list.append(f"{len(dependencies['marketplace_orders'])} سفارش مارکت‌پلیس")
        if dependencies["zohal_services"]:
            dep_list.append(f"{len(dependencies['zohal_services'])} سرویس زحل")
        if dependencies["ai_usage_logs"]:
            dep_list.append(f"{len(dependencies['ai_usage_logs'])} لاگ استفاده AI")
        
        message = f"این تراکنش به {', '.join(dep_list)} مرتبط است و قابل حذف نمی‌باشد"
    else:
        message = None
    
    return {
        "has_dependencies": has_dependencies,
        "dependencies": dependencies,
        "message": message
    }
```

---

## 2. تغییرات در سرویس‌های حذف اسناد

### 2.1. تغییر در `delete_document` 
**فایل:** `app/services/document_service.py`

**قبل از حذف سند (بعد از خط 178):**
```python
# بررسی ارتباط با تراکنش‌های کیف پول
from app.services.wallet_service import check_document_has_wallet_transactions
wallet_check = check_document_has_wallet_transactions(db, document_id)
if wallet_check["has_wallet_transactions"] and wallet_check.get("has_protected_transactions", False):
    raise ApiError(
        "DOCUMENT_HAS_WALLET_TRANSACTIONS",
        wallet_check["message"],
        http_status=409
    )
```

### 2.2. تغییر در `delete_receipt_payment`
**فایل:** `app/services/receipt_payment_service.py`

**بعد از بررسی چک‌ها (بعد از خط 1429):**
```python
# 4) جلوگیری از حذف اگر سند به تراکنش‌های کیف پول مرتبط باشد
try:
    from app.services.wallet_service import check_document_has_wallet_transactions
    wallet_check = check_document_has_wallet_transactions(db, document_id)
    if wallet_check["has_wallet_transactions"] and wallet_check.get("has_protected_transactions", False):
        raise ApiError(
            "DOCUMENT_HAS_WALLET_TRANSACTIONS",
            wallet_check["message"],
            http_status=409,
        )
except ApiError:
    raise
except Exception:
    pass
```

### 2.3. تغییر در `delete_expense_income`
**فایل:** `app/services/expense_income_service.py`

**بعد از بررسی نوع سند (بعد از خط 1078):**
```python
# بررسی ارتباط با تراکنش‌های کیف پول
from app.services.wallet_service import check_document_has_wallet_transactions
wallet_check = check_document_has_wallet_transactions(db, document_id)
if wallet_check["has_wallet_transactions"] and wallet_check.get("has_protected_transactions", False):
    raise ApiError(
        "DOCUMENT_HAS_WALLET_TRANSACTIONS",
        wallet_check["message"],
        http_status=409
    )
```

### 2.4. تغییر در `delete_transfer`
**فایل:** `app/services/transfer_service.py`

**بعد از بررسی سال مالی (بعد از خط 443):**
```python
# بررسی ارتباط با تراکنش‌های کیف پول
from app.services.wallet_service import check_document_has_wallet_transactions
wallet_check = check_document_has_wallet_transactions(db, document_id)
if wallet_check["has_wallet_transactions"] and wallet_check.get("has_protected_transactions", False):
    raise ApiError(
        "DOCUMENT_HAS_WALLET_TRANSACTIONS",
        wallet_check["message"],
        http_status=409
    )
```

### 2.5. تغییر در `delete_invoice`
**فایل:** `app/services/invoice_service.py`

**بعد از بررسی کارپوشه مودیان (بعد از خط 3487):**
```python
# 3.5) جلوگیری از حذف اگر سند به تراکنش‌های کیف پول مرتبط باشد
try:
    from app.services.wallet_service import check_document_has_wallet_transactions
    wallet_check = check_document_has_wallet_transactions(db, document_id)
    if wallet_check["has_wallet_transactions"] and wallet_check.get("has_protected_transactions", False):
        logger.error(f"[DELETE_INVOICE] Invoice {document_id}: Cannot delete - has wallet transactions")
        raise ApiError(
            "DOCUMENT_HAS_WALLET_TRANSACTIONS",
            wallet_check["message"],
            http_status=409,
        )
except ApiError:
    raise
except Exception as ex:
    logger.warning(f"[DELETE_INVOICE] Invoice {document_id}: Error checking wallet transactions: {ex}")
    pass
```

---

## 3. تغییرات در Foreign Key Constraints

### 3.1. Migration برای تغییر `ondelete` از `SET NULL` به `RESTRICT`

**فایل جدید:** `migrations/versions/XXXXXX_protect_wallet_transactions.py`

```python
"""protect_wallet_transactions

Revision ID: XXXXXX
Revises: YYYYYY
Create Date: 2024-XX-XX XX:XX:XX.XXXXXX

"""
from alembic import op
import sqlalchemy as sa

# revision identifiers
revision = 'XXXXXX'
down_revision = 'YYYYYY'
branch_labels = None
depends_on = None

def upgrade():
    # تغییر constraint برای ai_invoices
    op.drop_constraint('ai_invoices_wallet_transaction_id_fkey', 'ai_invoices', type_='foreignkey')
    op.create_foreign_key(
        'ai_invoices_wallet_transaction_id_fkey',
        'ai_invoices', 'wallet_transactions',
        ['wallet_transaction_id'], ['id'],
        ondelete='RESTRICT'
    )
    
    # تغییر constraint برای storage_invoices
    op.drop_constraint('storage_invoices_wallet_transaction_id_fkey', 'storage_invoices', type_='foreignkey')
    op.create_foreign_key(
        'storage_invoices_wallet_transaction_id_fkey',
        'storage_invoices', 'wallet_transactions',
        ['wallet_transaction_id'], ['id'],
        ondelete='RESTRICT'
    )
    
    # تغییر constraint برای marketplace_orders
    op.drop_constraint('marketplace_orders_wallet_transaction_id_fkey', 'marketplace_orders', type_='foreignkey')
    op.create_foreign_key(
        'marketplace_orders_wallet_transaction_id_fkey',
        'marketplace_orders', 'wallet_transactions',
        ['wallet_transaction_id'], ['id'],
        ondelete='RESTRICT'
    )
    
    # تغییر constraint برای zohal_service_usage
    op.drop_constraint('zohal_service_usage_wallet_transaction_id_fkey', 'zohal_service_usage', type_='foreignkey')
    op.create_foreign_key(
        'zohal_service_usage_wallet_transaction_id_fkey',
        'zohal_service_usage', 'wallet_transactions',
        ['wallet_transaction_id'], ['id'],
        ondelete='RESTRICT'
    )
    
    # تغییر constraint برای ai_usage_logs
    op.drop_constraint('ai_usage_logs_wallet_transaction_id_fkey', 'ai_usage_logs', type_='foreignkey')
    op.create_foreign_key(
        'ai_usage_logs_wallet_transaction_id_fkey',
        'ai_usage_logs', 'wallet_transactions',
        ['wallet_transaction_id'], ['id'],
        ondelete='RESTRICT'
    )
    
    # تغییر constraint برای document_monetization
    op.drop_constraint('document_monetization_wallet_transaction_id_fkey', 'document_monetization', type_='foreignkey')
    op.create_foreign_key(
        'document_monetization_wallet_transaction_id_fkey',
        'document_monetization', 'wallet_transactions',
        ['wallet_transaction_id'], ['id'],
        ondelete='RESTRICT'
    )

def downgrade():
    # برگشت به SET NULL
    op.drop_constraint('ai_invoices_wallet_transaction_id_fkey', 'ai_invoices', type_='foreignkey')
    op.create_foreign_key(
        'ai_invoices_wallet_transaction_id_fkey',
        'ai_invoices', 'wallet_transactions',
        ['wallet_transaction_id'], ['id'],
        ondelete='SET NULL'
    )
    
    # ... (همین کار برای بقیه جداول)
```

### 3.2. تغییر در مدل‌ها
**تغییر `ondelete="SET NULL"` به `ondelete="RESTRICT"` در:**

- `adapters/db/models/ai_invoice.py` - خط 54
- `adapters/db/models/storage_plan.py` - خط 76
- `adapters/db/models/marketplace.py` - خط 72
- `adapters/db/models/zohal.py` - خط 68
- `adapters/db/models/ai_usage_log.py` - خط 41
- `adapters/db/models/document_monetization.py` - خط 97

---

## 4. تغییرات در Endpoint ها

### 4.1. Endpoint حذف سند
**فایل:** `adapters/api/v1/documents.py`

**تغییری لازم نیست** - بررسی در سرویس انجام می‌شود

### 4.2. Endpoint حذف دریافت/پرداخت
**فایل:** `adapters/api/v1/receipts_payments.py`

**تغییری لازم نیست** - بررسی در سرویس انجام می‌شود

### 4.3. Endpoint حذف هزینه/درآمد
**فایل:** `adapters/api/v1/expense_income.py`

**تغییری لازم نیست** - بررسی در سرویس انجام می‌شود

### 4.4. Endpoint حذف انتقال
**فایل:** `adapters/api/v1/transfers.py`

**تغییری لازم نیست** - بررسی در سرویس انجام می‌شود

### 4.5. Endpoint حذف فاکتور
**فایل:** `adapters/api/v1/invoices.py`

**تغییری لازم نیست** - بررسی در سرویس انجام می‌شود

---

## 5. جلوگیری از حذف مستقیم تراکنش‌های کیف پول

### 5.1. بررسی وجود Endpoint مستقیم برای حذف
**بررسی شده:** در `adapters/api/v1/wallet.py` هیچ endpoint برای حذف تراکنش وجود ندارد ✅

### 5.2. اگر در آینده endpoint اضافه شد
**قوانین:**
- فقط تراکنش‌های با `type` خاص (مثل "manual") قابل حذف باشند
- بررسی وابستگی‌ها قبل از حذف
- فقط کاربران admin بتوانند حذف کنند

---

## 6. تست‌ها و اعتبارسنجی

### 6.1. سناریوهای تست

#### تست 1: تلاش برای حذف سند مرتبط با واریز کیف پول
```
1. ایجاد یک سند دریافت/پرداخت
2. ایجاد تراکنش کیف پول از نوع "top_up" با document_id
3. تلاش برای حذف سند
4. انتظار: خطای DOCUMENT_HAS_WALLET_TRANSACTIONS
```

#### تست 2: تلاش برای حذف سند مرتبط با صورتحساب AI
```
1. پرداخت صورتحساب AI از کیف پول
2. تلاش برای حذف سند حسابداری مرتبط
3. انتظار: خطای DOCUMENT_HAS_WALLET_TRANSACTIONS
```

#### تست 3: حذف سند بدون تراکنش کیف پول
```
1. ایجاد یک سند دریافت/پرداخت بدون تراکنش کیف پول
2. حذف سند
3. انتظار: حذف موفق
```

#### تست 4: بررسی Foreign Key Constraint
```
1. تلاش برای حذف تراکنش کیف پول که به AI Invoice لینک شده
2. انتظار: خطای Foreign Key Constraint
```

---

## 7. مستندات و پیام‌های خطا

### 7.1. کدهای خطا
- `DOCUMENT_HAS_WALLET_TRANSACTIONS`: سند به تراکنش‌های کیف پول سیستمی مرتبط است

### 7.2. پیام‌های خطا
- فارسی: "این سند به {count} تراکنش کیف پول سیستمی مرتبط است و قابل حذف نمی‌باشد. انواع تراکنش‌ها: {types}"

---

## 8. چک‌لیست پیاده‌سازی

- [ ] اضافه کردن توابع محافظتی در `wallet_service.py`
- [ ] تغییر `delete_document` در `document_service.py`
- [ ] تغییر `delete_receipt_payment` در `receipt_payment_service.py`
- [ ] تغییر `delete_expense_income` در `expense_income_service.py`
- [ ] تغییر `delete_transfer` در `transfer_service.py`
- [ ] تغییر `delete_invoice` در `invoice_service.py`
- [ ] ایجاد migration برای تغییر Foreign Key Constraints
- [ ] تغییر مدل‌ها (ondelete="RESTRICT")
- [ ] تست سناریوهای مختلف
- [ ] به‌روزرسانی مستندات API

---

## 9. نکات مهم

1. **تغییر Foreign Key Constraints:** این تغییر ممکن است روی داده‌های موجود تأثیر بگذارد. قبل از اجرا، باید داده‌های موجود را بررسی کرد.

2. **Backward Compatibility:** اگر در آینده نیاز به حذف تراکنش‌های کیف پول بود، باید از "reversal" استفاده شود نه حذف مستقیم.

3. **Performance:** بررسی‌های اضافه شده ممکن است کمی تأخیر ایجاد کنند، اما برای حفظ یکپارچگی داده‌ها ضروری است.

4. **لاگ‌گذاری:** تمام تلاش‌های حذف ناموفق باید در لاگ ثبت شوند.

---

## 10. خلاصه تغییرات

| فایل | نوع تغییر | توضیحات |
|------|-----------|---------|
| `app/services/wallet_service.py` | اضافه | توابع محافظتی |
| `app/services/document_service.py` | تغییر | بررسی قبل از حذف |
| `app/services/receipt_payment_service.py` | تغییر | بررسی قبل از حذف |
| `app/services/expense_income_service.py` | تغییر | بررسی قبل از حذف |
| `app/services/transfer_service.py` | تغییر | بررسی قبل از حذف |
| `app/services/invoice_service.py` | تغییر | بررسی قبل از حذف |
| `adapters/db/models/*.py` | تغییر | ondelete="RESTRICT" |
| `migrations/versions/*.py` | اضافه | Migration برای FK |

---

**تاریخ ایجاد:** 2024
**وضعیت:** آماده برای پیاده‌سازی

