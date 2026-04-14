# لیست Endpoint های سطح کسب و کار که نیاز به تغییر دارند

این فایل شامل لیست کامل endpoint هایی است که از `require_business_management_dep` استفاده می‌کنند و باید به `require_business_permission_dep` تغییر کنند.

## دسته‌بندی Endpoint ها

### 1. Endpoint هایی که `business_id` در path دارند (قابل استفاده از `require_business_permission_dep`)

#### اشخاص (Persons)
| فایل | Endpoint | Section | Action | توضیحات |
|------|----------|---------|--------|---------|
| `persons.py` | `POST /businesses/{business_id}/persons/create` | `people` | `add` | ✅ **تغییر یافته** |
| `persons.py` | `POST /businesses/{business_id}/persons/bulk-delete` | `people` | `delete` | ✅ **تغییر یافته** |
| `persons.py` | `GET /businesses/{business_id}/persons/summary` | `people` | `view` | نیاز به تغییر |

#### حساب‌های بانکی (Bank Accounts)
| فایل | Endpoint | Section | Action | توضیحات |
|------|----------|---------|--------|---------|
| `bank_accounts.py` | `POST /businesses/{business_id}/bank-accounts` | `bank_accounts` | `add` | نیاز به تغییر |
| `bank_accounts.py` | `POST /businesses/{business_id}/bank-accounts/bulk-delete` | `bank_accounts` | `delete` | نیاز به تغییر |

#### صندوق‌ها (Cash Registers)
| فایل | Endpoint | Section | Action | توضیحات |
|------|----------|---------|--------|---------|
| `cash_registers.py` | `POST /businesses/{business_id}/cash-registers` | `cash` | `add` | نیاز به تغییر |
| `cash_registers.py` | `POST /businesses/{business_id}/cash-registers/bulk-delete` | `cash` | `delete` | نیاز به تغییر |

#### چک‌ها (Checks)
| فایل | Endpoint | Section | Action | توضیحات |
|------|----------|---------|--------|---------|
| `checks.py` | `POST /businesses/{business_id}/checks` | `checks` | `add` | نیاز به تغییر |

#### انتقال‌ها (Transfers)
| فایل | Endpoint | Section | Action | توضیحات |
|------|----------|---------|--------|---------|
| `transfers.py` | `POST /businesses/{business_id}/transfers` | `transfers` | `add` | نیاز به تغییر |

#### هزینه/درآمد (Expense/Income)
| فایل | Endpoint | Section | Action | توضیحات |
|------|----------|---------|--------|---------|
| `expense_income.py` | `POST /businesses/{business_id}/expense-income/create` | `expenses_income` | `add` | نیاز به تغییر |

#### دریافت/پرداخت (Receipts/Payments)
| فایل | Endpoint | Section | Action | توضیحات |
|------|----------|---------|--------|---------|
| `receipts_payments.py` | `POST /businesses/{business_id}/receipts-payments` | `people_receipts` یا `people_payments` | `add` | نیاز به تغییر |

#### تنخواه گردان (Petty Cash)
| فایل | Endpoint | Section | Action | توضیحات |
|------|----------|---------|--------|---------|
| `petty_cash.py` | `POST /businesses/{business_id}/petty-cash` | `petty_cash` | `add` | نیاز به تغییر |
| `petty_cash.py` | `POST /businesses/{business_id}/petty-cash/bulk-delete` | `petty_cash` | `delete` | نیاز به تغییر |

#### تراز افتتاحیه (Opening Balance)
| فایل | Endpoint | Section | Action | توضیحات |
|------|----------|---------|--------|---------|
| `opening_balance.py` | `POST /businesses/{business_id}/opening-balance` | `opening_balance` | `edit` | نیاز به تغییر |
| `opening_balance.py` | `POST /businesses/{business_id}/opening-balance/post` | `opening_balance` | `edit` | نیاز به تغییر |

#### اسناد (Documents)
| فایل | Endpoint | Section | Action | توضیحات |
|------|----------|---------|--------|---------|
| `documents.py` | `POST /businesses/{business_id}/documents/manual` | `accounting_documents` | `add` | نیاز به تغییر |

#### فاکتورها (Invoices)
| فایل | Endpoint | Section | Action | توضیحات |
|------|----------|---------|--------|---------|
| `invoices.py` | `DELETE /businesses/{business_id}/invoices/{invoice_id}` | `invoices` | `delete` | نیاز به تغییر |

---

### 2. Endpoint هایی که ID دیگری در path دارند (نیاز به dependency جدید یا روش متفاوت)

این endpoint ها `business_id` در path ندارند، بلکه ID دیگری دارند (مثل `person_id`, `document_id`, ...). 
باید ابتدا business_id را از دیتابیس بگیریم و سپس permission را چک کنیم.

#### اشخاص (Persons)
| فایل | Endpoint | Section | Action | توضیحات |
|------|----------|---------|--------|---------|
| `persons.py` | `GET /persons/{person_id}` | `people` | `view` | نیاز به dependency جدید |
| `persons.py` | `PUT /persons/{person_id}` | `people` | `edit` | نیاز به dependency جدید |
| `persons.py` | `DELETE /persons/{person_id}` | `people` | `delete` | نیاز به dependency جدید |
| `persons.py` | `GET /persons/{person_id}/share-link` | `people` | `view` | نیاز به dependency جدید |
| `persons.py` | `POST /persons/{person_id}/share-link` | `people` | `edit` | نیاز به dependency جدید |
| `persons.py` | `DELETE /persons/{person_id}/share-link` | `people` | `edit` | نیاز به dependency جدید |

#### حساب‌های بانکی (Bank Accounts)
| فایل | Endpoint | Section | Action | توضیحات |
|------|----------|---------|--------|---------|
| `bank_accounts.py` | `GET /bank-accounts/{account_id}` | `bank_accounts` | `view` | نیاز به dependency جدید |
| `bank_accounts.py` | `PUT /bank-accounts/{account_id}` | `bank_accounts` | `edit` | نیاز به dependency جدید |
| `bank_accounts.py` | `DELETE /bank-accounts/{account_id}` | `bank_accounts` | `delete` | نیاز به dependency جدید |

#### صندوق‌ها (Cash Registers)
| فایل | Endpoint | Section | Action | توضیحات |
|------|----------|---------|--------|---------|
| `cash_registers.py` | `GET /cash-registers/{cash_id}` | `cash` | `view` | نیاز به dependency جدید |
| `cash_registers.py` | `PUT /cash-registers/{cash_id}` | `cash` | `edit` | نیاز به dependency جدید |
| `cash_registers.py` | `DELETE /cash-registers/{cash_id}` | `cash` | `delete` | نیاز به dependency جدید |

#### چک‌ها (Checks)
| فایل | Endpoint | Section | Action | توضیحات |
|------|----------|---------|--------|---------|
| `checks.py` | `PUT /checks/{check_id}` | `checks` | `edit` | نیاز به dependency جدید |
| `checks.py` | `DELETE /checks/{check_id}` | `checks` | `delete` | نیاز به dependency جدید |
| `checks.py` | `DELETE /businesses/{business_id}/checks/bulk-delete` | `checks` | `delete` | نیاز به تغییر |

#### انتقال‌ها (Transfers)
| فایل | Endpoint | Section | Action | توضیحات |
|------|----------|---------|--------|---------|
| `transfers.py` | `PUT /transfers/{document_id}` | `transfers` | `edit` | نیاز به dependency جدید |
| `transfers.py` | `DELETE /transfers/{document_id}` | `transfers` | `delete` | نیاز به dependency جدید |

#### هزینه/درآمد (Expense/Income)
| فایل | Endpoint | Section | Action | توضیحات |
|------|----------|---------|--------|---------|
| `expense_income.py` | `PUT /expense-income/{document_id}` | `expenses_income` | `edit` | نیاز به dependency جدید |
| `expense_income.py` | `DELETE /expense-income/{document_id}` | `expenses_income` | `delete` | نیاز به dependency جدید |
| `expense_income.py` | `POST /expense-income/bulk-delete` | `expenses_income` | `delete` | نیاز به dependency جدید |

#### دریافت/پرداخت (Receipts/Payments)
| فایل | Endpoint | Section | Action | توضیحات |
|------|----------|---------|--------|---------|
| `receipts_payments.py` | `PUT /receipts-payments/{document_id}` | `people_receipts` یا `people_payments` | `edit` | نیاز به dependency جدید |
| `receipts_payments.py` | `DELETE /receipts-payments/{document_id}` | `people_receipts` یا `people_payments` | `delete` | نیاز به dependency جدید |

#### تنخواه گردان (Petty Cash)
| فایل | Endpoint | Section | Action | توضیحات |
|------|----------|---------|--------|---------|
| `petty_cash.py` | `GET /petty-cash/{petty_cash_id}` | `petty_cash` | `view` | نیاز به dependency جدید |
| `petty_cash.py` | `PUT /petty-cash/{petty_cash_id}` | `petty_cash` | `edit` | نیاز به dependency جدید |
| `petty_cash.py` | `DELETE /petty-cash/{petty_cash_id}` | `petty_cash` | `delete` | نیاز به dependency جدید |

#### اسناد (Documents)
| فایل | Endpoint | Section | Action | توضیحات |
|------|----------|---------|--------|---------|
| `documents.py` | `DELETE /documents/{document_id}` | `accounting_documents` | `delete` | نیاز به dependency جدید |
| `documents.py` | `POST /documents/bulk-delete` | `accounting_documents` | `delete` | نیاز به dependency جدید |
| `documents.py` | `PUT /documents/{document_id}` | `accounting_documents` | `edit` | نیاز به dependency جدید |

---

## خلاصه

### تعداد Endpoint های با `business_id` در path: **18 endpoint**
- می‌توانند از `require_business_permission_dep` استفاده کنند
- **2 مورد** قبلاً تغییر یافته (persons/create و persons/bulk-delete)
- **16 مورد** باقی مانده

### تعداد Endpoint های با ID دیگری در path: **27 endpoint**
- نیاز به dependency جدید دارند که business_id را از دیتابیس بگیرد
- باید `require_business_permission_by_entity_dep` یا مشابه آن ایجاد شود

---

## پیشنهاد

برای endpoint هایی که ID دیگری دارند، باید یک dependency جدید بسازیم:

```python
def require_business_permission_by_entity_dep(
    section: str, 
    action: str,
    entity_type: str,  # "person", "document", "bank_account", ...
    entity_id_param: str = "{entity_type}_id"  # "person_id", "document_id", ...
):
    """
    Dependency برای endpoint هایی که business_id در path ندارند
    ابتدا business_id را از entity می‌گیرد و سپس permission را چک می‌کند
    """
    ...
```

این dependency:
1. entity را از دیتابیس می‌گیرد
2. `business_id` را از entity استخراج می‌کند
3. دسترسی به کسب و کار را چک می‌کند
4. permission را چک می‌کند

