# سناریوی اجرایی ایمپورت دیتابیس قدیمی (MySQL `.sql`)

## هدف

انتقال داده از دامپ phpMyAdmin نرم‌افزار قدیمی (مثل `oldsimpleDatabase.sql`) به Hesabix جدید (PostgreSQL) از طریق **پنل مدیر سیستم**، با ثبت مالی از مسیر **سرویس‌های استاندارد** (نه کپی مستقیم `hesabdari_row`).

## پیش‌نیاز

- دسترسی `superadmin`
- فایل `.sql` یا `.sql.gz` با اسکیمای شناخته‌شده (`user`, `business`, `year`, `person`, `commodity`, `hesabdari_doc`, …)
- ارزهای پایه (`IRR` و …) از قبل در جدول `currencies` موجود باشند

## API (پیاده‌سازی فاز ۱)

| متد | مسیر | توضیح |
|-----|------|--------|
| `POST` | `/api/v1/admin/legacy-import/analyze` | آپلود فایل؛ گزارش آماری بدون تغییر دیتابیس |
| `POST` | `/api/v1/admin/legacy-import/run` | اجرای ایمپورت در پس‌زمینه (Job) |

### پارامترهای `run`

| پارامتر | پیش‌فرض | توضیح |
|---------|---------|--------|
| `import_mode` | `new_business` | `new_business` \| `merge_into_business` |
| `target_business_id` | — | برای merge |
| `owner_user_id` | — | اختیاری؛ مالک هدف در حالت new |
| `dry_run` | `false` | فقط شبیه‌سازی |
| `import_users` | `true` | |
| `import_master_data` | `true` | اشخاص، کالا، بانک |
| `import_invoices` | `true` | buy/sell/rfbuy/rfsell |
| `import_receipts_payments` | `true` | buy_send, sell_receive, person_receive/send |
| `import_expense_income` | `true` | cost, income |
| `import_warehouses` | `true` | storeroom + storeroom_ticket/item (حواله انبار) |
| `import_transfers` | `true` | hesabdari_doc.type=transfer |
| `import_opening_balance` | `true` | open_balance |
| `import_checks` | `true` | جدول cheque (+ اسناد عملیات چک در صورت وجود) |
| `import_mode` | `new_business` | + `rewrite_business` با تأیید «بازنویسی» |
| `rewrite_confirmation` | — | الزامی برای rewrite |
| `conflict_policy` | `skip` | `skip` \| `link` (تطبیق موجود بدون به‌روزرسانی) |

## ترتیب اجرای Job

```
۱. validate     → جداول اجباری، charset
۲. analyze      → شمارش موجودیت‌ها (در analyze endpoint جداگانه)
۳. users        → تطبیق email/mobile؛ ایجاد در صورت نبود
۴. business     → new_business یا merge_into_business
۵. fiscal_years → از جدول year
۶. master       → person, commodity(+cat), bank_account
۷. invoices     → invoice_service.create_invoice (buy/sell/…)
۸. receipts     → receipt_payment_service
۹. expense/income
۱۰. warehouses  → create_warehouse + حواله (create_manual_warehouse_document + post)
۱۱. transfers   → transfer_service.create_transfer
۱۲. opening_balance → upsert_opening_balance
۱۳. checks      → check_service.create_check (از جدول cheque)
```

## قواعد نگاشت

- **کاربر:** `user.email` / `user.mobile` → `users`؛ رمز `$2y$` حفظ می‌شود
- **کسب‌وکار:** `business.name` + `owner_id` نگاشت‌شده
- **شخص:** `(bid_id, code)` → `persons`
- **کالا:** `(bid_id, code)` → `products`
- **سند:** `extra_info.old_document_id` برای idempotency

## تأیید پس از ایمپورت (چک‌لیست دستی)

- [ ] تعداد اسناد به تفکیک `type` با دامپ برابر است
- [ ] مانده یک شخص نمونه در گزارش اشخاص
- [ ] یک فاکتور خرید/فروش: جمع خطوط = مبلغ سند
- [ ] لاگ Job بدون خطای بحرانی

## UI

مسیر: **تنظیمات سیستم → ایمپورت دیتابیس قدیمی** (`/user/profile/system-settings/legacy-import`) — فقط superadmin.

## فرمت فایل

- `.sql` — دامپ phpMyAdmin
- `.sql.gz` / `.gz`
- `.zip` — بزرگ‌ترین فایل `.sql` داخل آرشیو استخراج می‌شود
- `.hs60` — همان موارد بالا (SQL خام، gzip، یا ZIP)

## فازهای بعدی

- هم‌ترازسازی وضعیت چک قدیمی (فارسی) با `CheckStatus` جدید پس از import
- ایمپورت `.hs60` از مسیر «کسب‌وکار جدید» (فعلاً فقط پنل legacy-import)

## نمونه اجرا (curl)

```bash
# تحلیل
curl -X POST "$BASE/api/v1/admin/legacy-import/analyze" \
  -H "Authorization: Bearer $TOKEN" \
  -F "file=@oldsimpleDatabase.sql"

# ایمپورت
curl -X POST "$BASE/api/v1/admin/legacy-import/run?import_mode=new_business&dry_run=true" \
  -H "Authorization: Bearer $TOKEN" \
  -F "file=@oldsimpleDatabase.sql"
```

پاسخ `run` شامل `job_id` است؛ وضعیت از `/api/v1/jobs/{job_id}`.
