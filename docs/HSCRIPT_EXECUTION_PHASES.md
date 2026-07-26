# فازبندی اجرایی HScript — گزارش‌نویسی سفارشی حسابیکس

> وضعیت فعلی: **فاز ۱ (MVP Backend) پیاده‌سازی شده** — Runtime امن، Gateway، API، Docs، ابزارهای AI پایه.

---

## نقشه فازها

| فاز | نام | وضعیت | خروجی کلیدی |
|-----|-----|--------|-------------|
| ۰ | قفل طراحی | ✅ | مدل تهدید، Spec، قرارداد Gateway |
| ۱ | Runtime + API | ✅ | HScript interpreter، CRUD گزارش، run/validate |
| ۲ | Studio UI + Charts render | ✅ | فهرست + استودیو Flutter + رندر Spec |
| ۳ | PDF/Print از Spec | ✅ | WeasyPrint از Spec امن + دکمه PDF در Studio |
| ۴ | AI عمیق + RAG | ✅ | دکمه از AI بساز، retrieve docs، tools جدید |
| ۵ | Isolation سخت + Queue | ✅ | QUEUE_REPORTS، polling، rate limit، worker limits |
| ۶ | Excel + Dashboard composer | ✅ | Excel از Spec + span/row_break داشبورد |
| ۷ | Marketplace + پلن محدودیت | ✅ | پلاگین + سقف پلن + audit ادمین + cross-tenant |
| ۸ | Studio UX + Semantic Gateway | ✅ | فرم پارامتر، نسخه‌ها، recipes، HTable، debtors/banks/… |
| ۹ | Schedule + Permissions + Dual-mode | ✅ | زمان‌بندی تحویل، hscript.*، صفحه فقط‌اجرا |

---

## فاز ۰ — طراحی (انجام‌شده در تحلیل)

- زبان: شبه‌پایتون + Interpreter AST سفید (نه Python کامل)
- داده: Data Gateway روی سرویس‌های موجود
- خروجی: Report Spec JSON
- امنیت: Context قفل `business_id` + caps منابع

---

## فاز ۱ — MVP Backend (همین commit کاری)

### تحویل‌شده

**Runtime**
- `app/services/hscript/` — lexer, parser, interpreter, values, limits, report_builder
- ممنوعیت‌ها: import/class/eval/فایل/ویژگی `_`
- سقف: زمان، گام، حلقه، gateway calls، حجم خروجی

**Gateway v1**
- `invoices`, `customers`, `products`, `payments`
- همیشه با `business_id` سروری

**Persistence**
- جداول `hscript_reports`, `hscript_report_versions`, `hscript_report_runs`
- Migration: `20260720_000003_hscript_custom_reports`

**API** (`/api/v1/businesses/{id}/hscript/...`)
- validate / run (adhoc)
- CRUD reports + publish/archive
- versions
- docs manifest

**AI**
- tools: `hscript_search_docs`, `hscript_read_doc`, `hscript_validate_script`, `hscript_language_guide`

**Docs RAG-ready**
- `docs/hscript/**` با `doc_id` و frontmatter

### تست پذیرش فاز ۱

```bash
cd hesabixAPI && pytest tests/test_hscript_runtime.py tests/test_hscript_pdf_renderer.py -q
alembic upgrade head   # اعمال migration
```

---

## فاز ۲ — Studio Flutter (انجام‌شده)

### تحویل‌شده
- سرویس: `hesabix_ui/lib/services/hscript_report_service.dart`
- رندر Spec: `lib/widgets/hscript/hscript_spec_renderer.dart` (KPI، جدول، bar/line/area/pie، gauge)
- فهرست: `lib/pages/business/hscript/hscript_reports_page.dart`
- استودیو: `lib/pages/business/hscript/hscript_studio_page.dart` (کد + params + validate/run/save/publish/PDF)
- مسیرها: `hscript`, `hscript/studio/new`, `hscript/studio/:report_id`
- لینک در هاب گزارش‌ها (سکشن عمومی)

### معیار اتمام
کاربر از منوی گزارش‌ها → گزارش‌ساز اسکریپتی وارد می‌شود، اسکریپت می‌نویسد، پیش‌نمایش می‌بیند و ذخیره می‌کند.

---

## فاز ۳ — PDF (انجام‌شده)

### تحویل‌شده
- `app/services/hscript/pdf_renderer.py` — Spec → HTML escape‌شده → WeasyPrint
- API: `POST .../hscript/pdf` و `POST .../hscript/reports/{id}/pdf` (نیازمند `reports.export`)
- دکمه PDF در استودیو

### نکته امنیتی PDF
متن کاربر تماماً HTML-escape می‌شود؛ تصویر با URL خارجی رندر نمی‌شود.

---

## فاز ۴ — AI عمیق

### تحویل‌شده
- دکمه «از AI بساز» در استودیو + بازیابی context مستندات
- `AIChatDialog.initialPrompt` برای ارسال خودکار درخواست ساخت گزارش
- «اعمال از کلیپ‌بورد» برای استخراج بلوک ```hscript
- API: `POST .../hscript/assist/context`
- RAG سبک: جستجو روی محتوای فایل‌ها + `retrieve_docs_for_rag`
- Tools جدید: `hscript_retrieve_docs`, `hscript_run_preview`, `hscript_fix_script`

---

## فاز ۵ — Queue و سخت‌سازی

### تحویل‌شده
- Job: `app/services/jobs/hscript_job.py` روی `QUEUE_REPORTS`
- `async_mode` در run API → `{async:true, job_id}` یا fallback sync
- Studio: polling با `JobService`
- Rate limit: حداکثر ۸ اجرا / دقیقه / کسب‌وکار
- Worker limits + sanitize خطاهای عمومی
- اجرای worker در process جدا از API (RQ worker)

### معیار اتمام
با Redis/RQ فعال، اجرای سنگین از API جدا می‌شود و UI وضعیت را نشان می‌دهد.

---

## فاز ۶ — Excel + Dashboard composer

### تحویل‌شده
- `excel_renderer.py` → workbook چندشیتی (خلاصه / جداول / داده نمودار)
- API: `POST .../hscript/excel` و `.../reports/{id}/excel` (`reports.export`)
- دکمه Excel در استودیو
- Dashboard composer: `report.dashboard(columns=12)`, `span=`, `row_break()`
- رندر UI با شبکه span-aware
- مستندات: `tutorials/dashboard.md`, `tutorials/excel-export.md`

---

## فاز ۷ — Marketplace و پلن

### تحویل‌شده
- Seed افزونه `hscript_custom_reports` در بازار (trial + monthly/yearly/lifetime)
- `plan_limits.py`: بدون لایسنس = free؛ با لایسنس = سقف بالاتر بر اساس period
- سقف تعداد گزارش ذخیره‌شده و `runs_per_minute` از entitlement
- ResourceLimits اجرا بر اساس پلن
- API: `GET …/hscript/plan`
- Admin audit: `GET /admin/hscript/runs`
- Flutter: بنر ارتقا + «اعمال به استودیو HScript» از چت AI
- تست‌های cross-tenant و سقف ذخیره

---

## فاز ۸ — Studio UX و گسترش معنایی (انجام‌شده)

### تحویل‌شده
- **HTable 1.1:** `where` / `field__op`، `join`، `distinct`، `pivot`، `rename`
- **Gateway جدید:** `persons`, `banks`, `warehouses`, `debtors`, `creditors`
- **dates:** `today`, `month_bounds`, `last_month_bounds`, `days_ago`
- **Param schema:** پارس `# @param` + استنتاج از `params.get` / default_params
- **API:** `/catalog`, `/recipes`, `/param-schema`, version detail/restore، `/runs`
- **Studio Flutter:** فرم پارامتر (با حالت JSON)، گالری دستورپخت، تاریخچه نسخه+بازگردانی، ساختار خروجی، بایگانی، سابقه اجرا
- زبان: `1.1.0`

### تست
```bash
cd hesabixAPI && pytest tests/test_hscript_phase8.py tests/test_hscript_runtime.py -q
```

---

## فاز ۹ — زمان‌بندی، مجوز ریز، Dual-mode (انجام‌شده)

### تحویل‌شده
- جدول `hscript_report_schedules` + migration
- سرویس زمان‌بندی با cron ساده/پیشرفته + لوپ پس‌زمینه ۶۰ثانیه
- تحویل: اعلان in-app + ایمیل پیوست PDF/Excel
- مجوزهای `hscript.view|write|publish|export|schedule` با fallback به `reports.*`
- Dual-mode lite: بدون write فقط اجرای گزارش منتشرشده (`/hscript/run/:id`)
- UI زمان‌بندی در فهرست و استودیو + صفحه مجوزها

### تست
```bash
cd hesabixAPI && pytest tests/test_hscript_phase9.py -q
alembic upgrade head
```

---

## ترتیب کار توصیه‌شده از این نقطه

1. همگام‌سازی seed بازار (`ensure_default_marketplace_plugins`) تا افزونه در UI دیده شود
2. تست دستی: سقف free → فعال‌سازی افزونه → سقف بالاتر
3. (اختیاری) صفحه ادمین UI روی `/admin/hscript/runs`
4. (اختیاری) embedding کامل docs

---

## وابستگی‌ها

| وابستگی | استفاده |
|---------|---------|
| FastAPI AuthContext / permissions | قفل tenant و دسترسی |
| document_service / person_service | Gateway |
| WeasyPrint + Jinja sandbox | PDF فاز ۳ |
| RQ QueueService | فاز ۵ |
| AI function_registry | ابزارها |
| Flutter fl_chart / pdf | Studio و خروجی کلاینت |

---

## ریسک‌های باز

- Gateway باید با رشد دامنه گسترش catalog داشته باشد
- Isolation در سطح RQ worker است؛ gVisor/container هنوز پیاده نشده
- صفحه UI ادمین برای `/admin/hscript/runs` هنوز نیست (API آماده است)
- بدون Redis، اجرا sync می‌ماند (fallback عمدی)
