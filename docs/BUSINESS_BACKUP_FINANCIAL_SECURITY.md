# امنیت مالی بکاپ کسب‌وکار (`.hbx`)

## فازبندی پیاده‌سازی

| فاز | وضعیت | محتوا |
|-----|--------|--------|
| **P0** | انجام شد | حذف جداول کیف‌پول از export/import؛ صفر کردن مانده پس از restore |
| **P1** | انجام شد | حذف entitlementها؛ اعتبارسنجی مالک؛ ثبت checksum؛ قفل همزمانی |
| **P1+** | انجام شد | `ai_voice_interactions`؛ رد بکاپ بدون مالک؛ `BACKUP_LEGACY_NOT_ALLOWED` |
| **P2** | آینده | دفتر اعتبار متمرکز در سطح کاربر (ledger) |

## جداول مستثنی از بکاپ tenant

تعریف در `app/services/business_backup_financial_policy.py`:

- `wallet_*`
- `user_ai_subscriptions`, `ai_usage_logs`, `ai_invoices`, `ai_chat_sessions`, `ai_voice_interactions`
- `business_storage_subscriptions`, `storage_invoices`, `storage_usage_transactions`
- `business_plugins`, `marketplace_orders`, `marketplace_invoices`

## metadata بکاپ جدید (`schema_version: v1.2`)

- `financial_data_excluded: true`
- `owner_id`: مالک کسب‌وکار مبدأ (الزامی در export جدید)
- `excluded_tables`: لیست جداول حذف‌شده
- `table_schemas`: snapshot نام ستون‌های هر جدول در زمان export (سازگاری import بین نسخه‌ها)

## سازگاری اسکیمای دیتابیس (restore/import)

پیاده‌سازی در `app/services/business_backup_schema_compat.py` — **بدون لیست سخت‌کد per-table**:

| مکانیزم | توضیح |
|---------|--------|
| **introspection** | SQLAlchemy inspector + `information_schema.columns` (nullable، `column_default`) |
| **TableRestorePlan** | برای هر ستون: `from_backup` / `omit_use_db_default` / `fill_parsed_default` / `fill_type_inference` |
| **table_schemas** | union کلیدهای همهٔ ردیف‌ها در export؛ در import با اسکیمای فعلی diff می‌شود |
| **sanitize** | حذف ستون‌های حذف‌شده از DB از ردیف بکاپ |
| **validate** | هشدار NULL در ستون NOT NULL یا کلیدهای نامعتبر (لاگ) |

بکاپ‌های قدیمی: اسکن تا ۲۰۰ ردیف اول هر `jsonl` برای کشف union ستون‌ها.

## اتمی بودن restore/import

| مسیر | اتمی؟ | توضیح |
|------|--------|--------|
| `POST .../backups/restore` | بله | یک `get_db_session`؛ `create_business(defer_commit=True)`؛ بدون commit میانی؛ در خطا `rollback` |
| `POST /businesses/import-from-backup` | بله (پس از اصلاح) | همان الگو؛ قبلاً commit پس از هر جدول داشت و نیمه‌کاره می‌ماند |

خارج از تراکنش: وضعیت Job (`job_id`)، فایل آپلودشده. پس از rollback، ردیف کسب‌وکار و داده‌های tenant در DB باقی نمی‌مانند.

## پاک‌سازی کسب‌وکارهای یتیم (import نیمه‌کارهٔ قدیمی)

اسکریپت سیستمی: `cleanup_orphan_backup_businesses` در **مدیریت سیستم → اسکریپت‌ها** (`/api/v1/admin/scripts`).

| معیار | پیش‌فرض |
|--------|---------|
| ثبت‌نشده در `business_backup_import_logs` | بله |
| نام حاوی «بازیابی شده» | بله |
| داده tenant خالی (سند/شخص/کالا = ۰) | اختیاری (`include_empty_shell`) |
| حداقل سن | ۱ ساعت (`min_age_hours`) |

CLI: `hesabixAPI/scripts/cleanup_orphan_backup_businesses.py --dry-run` سپس `--execute`.

## اعتبارسنجی مالک

ترتیب استخراج `owner_id`:

1. `metadata.owner_id`
2. `tables/businesses.jsonl` → فیلد `owner_id`
3. ردیف زنده `businesses` در DB با `metadata.business_id`

اگر هیچ‌کدام نبود → `BACKUP_LEGACY_NOT_ALLOWED` (400).

اگر مالک ≠ کاربر importکننده → `BACKUP_OWNER_MISMATCH` (403).

## ضد تکرار import (`new_business`)

1. `pg_advisory_xact_lock` روی `(user_id, checksum)` در همان تراکنش
2. بررسی `business_backup_import_logs`
3. در ثبت نهایی: `IntegrityError` → `BACKUP_ALREADY_IMPORTED`

## migration

`20260621_000001_business_backup_import_security` — جدول `business_backup_import_logs`.

```bash
cd hesabixAPI && alembic upgrade head
```

## خطاهای API

| کد | معنی |
|----|------|
| `BACKUP_OWNER_MISMATCH` | فایل متعلق به کاربر دیگر |
| `BACKUP_ALREADY_IMPORTED` | همان فایل قبلاً برای new_business استفاده شده |
| `BACKUP_LEGACY_NOT_ALLOWED` | بکاپ قدیمی بدون مالک قابل تشخیص |

## بکاپ‌های قدیمی (v1)

- wallet و entitlementها restore نمی‌شوند و در پایان پاک/صفر می‌شوند.
- import فقط اگر `owner_id` از ردیف businesses بکاپ یا DB قابل استخراج باشد.
