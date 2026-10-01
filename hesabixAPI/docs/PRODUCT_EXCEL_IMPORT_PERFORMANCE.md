# معماری و عملیات ایمپورت Excel کالا و خدمت

## هدف

این سند رفتار فنی endpoint زیر را پس از بهینه‌سازی ثبت می‌کند:

```text
POST /api/v1/products/business/{business_id}/import/excel
```

هدف، حذف query و commit ردیف‌به‌ردیف، حفظ قرارداد فعلی API و جلوگیری از
بازسازی چندبارهٔ سند تراز افتتاحیه است. محدودیت فعلی فایل همچنان ۱۵ مگابایت و
۵۰۰۰ ردیف داده است.

## مشکل پیشین

در پیاده‌سازی قبلی، یک ردیف فایل رسمی ممکن بود همان کالا را تا پنج مرتبه از
دیتابیس پیدا کند. وجود ستون‌های «تعداد اولیه» در header نیز حتی با سلول خالی،
lookup اضافه ایجاد می‌کرد. اجرای واقعی هر کالا را جداگانه commit، serialize و
cache-invalidate می‌کرد.

در ردیف‌های دارای تعداد اولیه، سرویس تک‌کالا سند افتتاحیه را می‌خواند، کل خطوط
آن را پیمایش می‌کرد و تمام خطوط را دوباره می‌نوشت. برای `N` ردیف، حجم کار
تقریباً برابر `1 + 2 + ... + N` بود.

## جریان جدید

```text
خواندن workbook
      ↓
ساخت index مراجع و کالاهای منطبق
      ↓
اعتبارسنجی و تولید plan بدون write ردیف‌به‌ردیف
      ↓
flush کالاهای معتبر در یک Unit of Work
      ↓
ادغام همهٔ تغییرات تعداد اولیه در حافظه
      ↓
یک بازنویسی سند افتتاحیه
      ↓
یک commit و سپس یک cache invalidation
```

### lookup کالا

کلیدهای غیرخالی فایل ابتدا جمع‌آوری و با queryهای `IN` حداکثر ۵۰۰تایی
بارگذاری می‌شوند. نتیجه براساس کد یا نام normalize‌شده در حافظه نگهداری می‌شود.
dry-run، تصمیم insert/update و اجرای واقعی همگی از همین index استفاده می‌کنند.

تطبیق براساس کد همچنان گزینهٔ پیشنهادی است. در حالت تطبیق با نام، چند کالای
موجود با نام یکسان خطای ابهام تولید می‌کنند. تکرار کلید تطبیق داخل خود فایل نیز
پیش از write به‌عنوان خطای ردیف گزارش می‌شود.

### مراجع

دسته‌بندی‌ها، ویژگی‌ها، انبارها، انواع مالیات، واحدهای مالیاتی و ارزهای فعال
یک‌بار بارگذاری و index می‌شوند. ایجاد خودکار دسته یا ویژگی با `flush` انجام
می‌شود و commit آن به پایان Unit of Work موکول می‌گردد.

### تعداد اولیه

صرف وجود ستون‌های تعداد اولیه باعث پردازش نمی‌شود. فقط ردیفی که مقدار تعداد یا
بهای تمام‌شده دارد وارد plan افتتاحیه می‌شود.

در اجرای واقعی:

1. امکان ویرایش تراز افتتاحیه پیش از write بررسی می‌شود.
2. سند موجود با قفل ردیفی خوانده می‌شود.
3. خطوط کالا براساس `(product_id, warehouse_id)` در map قرار می‌گیرند.
4. همهٔ تغییرات فایل روی map اعمال می‌شوند.
5. خطوط اشخاص، بانک، صندوق، تنخواه و سایر حساب‌ها حفظ می‌شوند.
6. سند یک‌بار متوازن و یک‌بار نوشته می‌شود.

پیچیدگی ادغام خطوط `O(existing_lines + imported_changes)` است.

## رفتار تراکنشی

- dry-run هیچ write، commit یا cache invalidation ندارد.
- خطاهای validation پیش از apply به تفکیک ردیف در پاسخ گزارش می‌شوند.
- ردیف‌های معتبر در یک transaction اعمال می‌شوند.
- ایجاد کالا و ثبت تعداد اولیه در همان transaction هستند.
- خطای دیتابیس یا خطای غیرمنتظره در apply باعث rollback کل apply می‌شود؛ بنابراین
  کالای ساخته‌شده بدون تعداد اولیه باقی نمی‌ماند.
- conflict هم‌زمان یا نقض constraint با خطای `IMPORT_WRITE_CONFLICT` و HTTP 409
  برگردانده می‌شود.
- cache محصولات و کاتالوگ عمومی فقط پس از commit موفق و فقط یک‌بار پاک می‌شود.

این رفتار عمداً atomic‌تر از پیاده‌سازی قدیمی است که commitهای جزئی متعدد داشت.

## قرارداد API

فیلدهای موجود پاسخ حفظ شده‌اند:

- `summary`
- `errors`
- `reference_summary`
- `preview` در dry-run

فیلد افزوده‌شدهٔ `performance` شامل مقادیر زیر برحسب میلی‌ثانیه است:

- `parse_ms`
- `validation_ms`
- `apply_ms`
- `total_ms`

این داده‌ها secret، محتوای سلول‌ها یا اطلاعات اتصال را ثبت نمی‌کنند.

## تغییرات سرویس‌های مشترک

سرویس‌های ایجاد و ویرایش کالا گزینه‌های زیر را دارند و مقدار پیش‌فرض آن‌ها رفتار
endpointهای تک‌کالا را حفظ می‌کند:

- `auto_commit=True`
- `serialize_result=True`
- `defer_cache_invalidation=False`
- `prevalidated_code_uniqueness=False`
- `prevalidated_attribute_ids=False`

repositoryهای دسته، ویژگی و سند نیز `auto_commit=True` دارند. فقط importer این
گزینه‌ها را برای Unit of Work گروهی غیرفعال می‌کند.

## فایل‌های اصلی

- `adapters/api/v1/products.py`: orchestration، plan و پاسخ
- `app/services/product_excel_import_normalize.py`: index تطبیق و ارز
- `app/services/product_excel_import_opening_balance.py`: validation ردیف
- `app/services/product_opening_balance_service.py`: ادغام و apply گروهی
- `app/services/product_service.py`: write بدون commit/serialization اجباری
- `app/services/opening_balance_service.py`: upsert قابل استفاده در transaction بیرونی
- `adapters/db/repositories/document_repository.py`: write با commit اختیاری

## کلاینت

دیالوگ Flutter برای این درخواست timeout دریافت پنج‌دقیقه‌ای دارد. timeout بلندتر
راه‌حل کارایی نیست؛ فقط از قطع زودهنگام درخواست معتبر در شبکه‌های کند جلوگیری
می‌کند. UI همچنان باید از اجرای دوبارهٔ درخواست هنگام loading جلوگیری کند.

endpoint به‌صورت sync در threadpool اجرا می‌شود تا parse اکسل و SQLAlchemy
همگام، event loop درخواست‌های دیگر را مسدود نکنند. این رفتار فقط برای همین
endpoint با گزینهٔ `offload_sync` روی گارد دسترسی فعال شده است.

صفحهٔ تراز افتتاحیه خط سیستمی «بستن اختلاف تراز افتتاحیه» را از ردیف‌های قابل
ویرایش مخفی می‌کند. برای جلوگیری از نمایش اشتباه بستانکار صفر پس از ایمپورت،
محاسبهٔ جمع UI در صورت فعال‌بودن auto-balance و انتخاب حساب حقوق صاحبان سهام،
اثر همان خط مخفی را روی سمت مقابل بازسازی می‌کند. اگر auto-balance خاموش باشد یا
حساب مقابل انتخاب نشده باشد، اختلاف خام همچنان نمایش داده می‌شود.

## validation و تست

تست‌های لازم:

```text
tests/test_product_excel_import.py
tests/test_product_excel_import_opening_balance.py
tests/test_product_opening_balance.py
```

اجرای تست در محیط توسعه فقط از wrapper ایزوله مجاز است:

```bash
/home/mohammad/projects/hesabix/dev-env/toolkit/scripts/run-tests-isolated.sh -- \
  tests/test_product_excel_import.py \
  tests/test_product_excel_import_opening_balance.py \
  tests/test_product_opening_balance.py -q
```

wrapper روی worktree کثیف عمداً اجرا نمی‌شود. برای validation نهایی باید تغییرات
در یک branch/worktree تمیز و مطابق رویهٔ Git پروژه قرار گیرند؛ تست مستقیم با
`.env` متصل به `hesabix_dev` ممنوع است.

### نتیجهٔ اعتبارسنجی ۱۴۰۵/۰۷/۰۹ (۲۰۲۶-۱۰-۰۱)

- compilation فایل‌های Python تغییرکرده موفق بود.
- بررسی محدود Ruff برای `F821`، `F822`، `F823` و `E902` موفق بود.
- `git diff --check` برای فایل‌های این تغییر موفق بود.
- snapshot تمیز و مستقل برای اجرای wrapper ساخته شد و مرحله‌های `--check` و
  `--dry-run` آن موفق بودند.
- سه فایل تست هدف با wrapper ایزوله اجرا شدند: `28 passed` و `176 warnings` در
  `25.31s`. دیتابیس تصادفی `hesabix_test_*` پس از اجرا حذف شد و دیتابیس توسعه
  استفاده یا تغییر داده نشد.
- این سه فایل DB-free هستند. migration chain فعلی repository نمی‌تواند یک
  PostgreSQL کاملاً خالی را بسازد، زیرا revision
  `20250226_000002_add_bale_messenger_support` وجود جدول `users` را فرض می‌کند.
  بنابراین برای این اجرای unit-test فقط مرحلهٔ `alembic upgrade head` در
  snapshot تست bypass شد. این نتیجه پوشش integration دیتابیس یا endpoint HTTP
  محسوب نمی‌شود و مشکل baseline migration باید جداگانه اصلاح شود.

microbenchmark تابع ادغام گروهی روی همان محیط، با هفت تکرار و گزارش median:

| خطوط موجود | تغییرات ورودی | median | خطوط خروجی |
|---:|---:|---:|---:|
| ۱۰۰۰ | ۱۰۰۰ | ۱۵٫۰۸۲ ms | ۱۰۰۰ |
| ۵۰۰۰ | ۵۰۰۰ | ۸۶٫۵۶۱ ms | ۵۰۰۰ |
| ۱۰۰۰۰ | ۱۰۰۰۰ | ۱۸۸٫۹۳۱ ms | ۱۰۰۰۰ |

این اعداد فقط هزینهٔ `_merge_product_opening_balance_changes` را اندازه می‌گیرند
و benchmark انتها‌به‌انتهای HTTP/Excel/PostgreSQL نیستند. رشد مشاهده‌شده با
پیچیدگی خطی طراحی جدید سازگار است، اما معیار «پنج برابر سریع‌تر برای ۱۰۰۰ ردیف»
فقط پس از اجرای benchmark انتها‌به‌انتها در محیط staging قابل تأیید است.

### معیار پذیرش عملیاتی

- فایل بدون تعداد اولیه هیچ فراخوانی سرویس سند افتتاحیه نداشته باشد.
- lookup کالا متناسب با تعداد chunkها رشد کند، نه تعداد ردیف‌ها.
- اجرای واقعی یک commit نهایی داشته باشد.
- سند افتتاحیه برای کل فایل یک بار apply شود.
- cache invalidation برای کل import یک بار انجام شود.
- نتیجهٔ dry-run و real import برای insert/update/skip یکسان باشد.
- زمان ۱۰۰۰ ردیف روی یک محیط ثابت حداقل پنج برابر بهتر از baseline قدیمی باشد.

## پایش و عیب‌یابی

در log، summary و زمان مراحل را با `business_id` و تعداد ردیف ثبت کنید؛ نام فایل،
مقادیر سلول‌ها، token و اطلاعات اتصال نباید log شوند. برای تشخیص کندی، ابتدا
`performance` را بررسی کنید:

- `parse_ms` بالا: اندازه/پیچیدگی workbook یا openpyxl
- `validation_ms` بالا: تعداد مراجع، نام‌های مبهم یا validationهای دامنه
- `apply_ms` بالا: constraint، barcode، sync موجودی یا سند افتتاحیه

## rollback

این تغییر migration دیتابیس ندارد. rollback کد با بازگرداندن orchestration قدیمی
ممکن است، اما به‌دلیل خطر partial commit توصیه نمی‌شود. اگر rollback عملیاتی لازم
شد، endpoint ایمپورت موقتاً غیرفعال شود و سپس نسخهٔ قبلی deploy گردد؛ هیچ سند یا
کالایی برای rollback نباید به‌صورت دستی حذف شود. قبل از هر اصلاح داده، backup و
audit نتیجهٔ import بررسی شود.

## محدودیت‌های آگاهانه

- تولید کد خودکار همچنان برای هر کالای بدون کد نیازمند تخصیص یکتاست.
- validation بارکد عمومی و sync تغییر کنترل موجودی عمداً حذف نشده‌اند؛ این‌ها
  قواعد دامنه‌اند و در صورت نیاز باید در فاز جداگانه batch شوند.
- endpoint هنوز نتیجه را در همان درخواست HTTP برمی‌گرداند. اگر پس از benchmark فایل ۵۰۰۰ ردیفی
  طولانی بماند، مرحلهٔ بعد انتقال apply به job پس‌زمینه با progress و idempotency
  است؛ افزایش بیشتر timeout جایگزین آن نیست.
