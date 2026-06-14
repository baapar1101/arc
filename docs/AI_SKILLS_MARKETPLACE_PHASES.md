# مارکت‌پلیس مهارت‌های AI — فازهای اجرایی و سناریوی مو‌به‌مو

این سند نقشهٔ اجرای کامل قابلیت Skills (سازگار با [agentskills.io](https://agentskills.io/specification) و Anthropic) در حسابیکس است.

---

## نمای کلی فازها

| فاز | عنوان | خروجی قابل تحویل | مدت تقریبی |
|-----|--------|------------------|------------|
| **۱** | زیرساخت و Portable Runtime | import ZIP، نصب محلی، فعال/غیرفعال، inject در چت | ۳–۴ هفته |
| **۲** | Native Anthropic Runtime | prebuilt skills، Skills API، hybrid | ۳–۴ هفته |
| **۳** | مارکت‌پلیس UGC | انتشار عمومی، moderation، reviews | ۳–۴ هفته |
| **۴** | اکوسیستم | Git import، monetization، مهارت‌های رسمی ERP | ۴+ هفته |

---

# فاز ۱ — زیرساخت و Portable Runtime

## هدف
کاربر بتواند مهارت استاندارد Agent Skills (ZIP با `SKILL.md`) را import کند، در کسب‌وکار نصب کند، به‌صورت داینامیک فعال/غیرفعال کند، و در چت AI با هر provider (OpenAI/Anthropic/Local) از حالت portable استفاده کند.

## خروجی‌های فاز ۱
- جداول: `ai_skill_packages`, `ai_skill_installs`
- سرویس‌ها: `ai_skill_parser`, `ai_skill_service`, `ai_skill_runtime`
- API: `/api/v1/ai/skills/*`
- یکپارچگی: `AIService.get_system_prompt` + `get_available_functions`
- UI (فاز بعدی Flutter): API آماده

---

## سناریوی مو‌به‌مو — فاز ۱

### گام ۱.۱ — import مهارت از ZIP

**بازیگر:** کاربر الکتروپارس  
**پیش‌شرط:** دسترسی `ai` به کسب‌وکار، فایل ZIP از مخزن `anthropics/skills`

| مرحله | عمل | سیستم | پاسخ |
|-------|-----|--------|------|
| 1 | `POST /businesses/{bid}/ai/skills/import` + multipart ZIP | استخراج فایل‌ها | — |
| 2 | — | یافتن `SKILL.md` (case-insensitive) | خطا اگر نباشد |
| 3 | — | `parse_skill_md()` → frontmatter + body | — |
| 4 | — | `validate_skill_spec()` → name, description | خطای validation |
| 5 | — | اسکن `scripts/`, `references/`, `assets/` | `has_scripts=true` |
| 6 | — | `build_compatibility_report()` | JSON گزارش |
| 7 | — | ذخیره bundle در JSON ستون `bundle_files` | `package_id` |
| 8 | — | `status=draft`, `source_type=portable` | — |

**بدنه پاسخ نمونه:**
```json
{
  "package_id": 42,
  "skill_slug": "mcp-builder",
  "compatibility": {
    "runtime_mode": "portable",
    "instruction_only": true,
    "has_scripts": true,
    "scripts_warning": "اسکریپت‌ها در فاز ۱ اجرا نمی‌شوند",
    "score": 75
  }
}
```

### گام ۱.۲ — ساخت مهارت در UI (بدون ZIP)

| مرحله | عمل | سیستم |
|-------|-----|--------|
| 1 | `POST /businesses/{bid}/ai/skills` | body: title, skill_slug, description, skill_body, allowed_tool_names |
| 2 | — | تولید `SKILL.md` synthetic از فیلدها |
| 3 | — | `source_type=hesabix_native` |
| 4 | — | `status=draft` |

### گام ۱.۳ — نصب مهارت در کسب‌وکار

| مرحله | عمل | سیستم |
|-------|-----|--------|
| 1 | `POST /businesses/{bid}/ai/skills/install` `{ "package_id": 42 }` | — |
| 2 | — | ایجاد `ai_skill_installs` |
| 3 | — | `is_enabled=true` پیش‌فرض |
| 4 | — | کپی `allowed_tool_names` از package |

### گام ۱.۴ — فعال/غیرفعال داینامیک

| مرحله | عمل | سیستم |
|-------|-----|--------|
| 1 | `PUT /businesses/{bid}/ai/skills/enabled` | `{ "install_ids": [1, 3], "disabled_ids": [2] }` |
| 2 | — | به‌روز `is_enabled` روی installs |
| 3 | پیام چت بعدی | فقط metadata مهارت‌های enabled |

**نکته:** تغییر بدون ری‌استارت session؛ در `get_system_prompt` هر بار خوانده می‌شود.

### گام ۱.۵ — چت با مهارت فعال

**درخواست:** `POST /ai/chat/sessions/{sid}/messages` — «لیست بدهکاران را تحلیل کن»

| مرحله | لایه | عمل |
|-------|------|-----|
| 1 | `ai_skill_runtime` | `list_enabled_metadata(business_id)` → ۳ مهارت |
| 2 | `ai_skill_runtime` | `select_skills_for_query(query, metadata)` → ۱ مهارت match |
| 3 | `get_system_prompt` | inject `[Skills metadata]` + `[Activated: debt-analysis]` body |
| 4 | `get_available_functions` | intersect با `allowed_tool_names` مهارت فعال‌شده |
| 5 | `AIService` | agent loop عادی |
| 6 | پاسخ | متن + tool calls محدود به مهارت |

**فرمت inject در prompt:**
```
## مهارت‌های فعال (metadata)
- debt-analysis: تحلیل بدهکاران. وقتی کاربر از بدهی، مطالبات صحبت کرد...
- sales-weekly: ...

## مهارت فعال‌شده: debt-analysis
[بدنه SKILL.md]
```

### گام ۱.۶ — انتشار محلی (فقط business، بدون marketplace)

| مرحله | عمل |
|-------|-----|
| 1 | `POST /businesses/{bid}/ai/skills/{package_id}/publish-local` |
| 2 | `visibility=business_only` — فقط همان کسب‌وکار |

---

## فایل‌های فاز ۱

| فایل | نقش |
|------|-----|
| `adapters/db/models/ai_skill.py` | مدل‌ها |
| `migrations/versions/20260702_000001_ai_skills.py` | migration |
| `app/services/ai/ai_skill_parser.py` | parse/validate SKILL.md |
| `app/services/ai/ai_skill_service.py` | CRUD, import, install |
| `app/services/ai/ai_skill_runtime.py` | prompt injection, tool filter |
| `adapters/api/v1/ai/skills.py` | REST API |
| `app/services/ai/ai_service.py` | hooks |
| `tests/test_ai_skill_parser.py` | unit tests |

---

# فاز ۲ — Native Anthropic Runtime

## هدف
مهارت‌های prebuilt Anthropic (`pdf`, `xlsx`, `docx`, `pptx`) و bundleهای دارای scripts از طریق Skills API اجرا شوند.

## سناریوی مو‌به‌مو

### گام ۲.۱ — فعال‌سازی provider Anthropic

| مرحله | شرط |
|-------|-----|
| 1 | `AIProviderCredential` برای `anthropic` فعال |
| 2 | مدل چت از خانواده Claude انتخاب شده |
| 3 | skill با `source_type=anthropic_prebuilt` یا `anthropic_skill_id` تنظیم شده |

### گام ۲.۲ — نصب مهارت prebuilt

| مرحله | عمل |
|-------|-----|
| 1 | `GET /ai/skills/catalog/anthropic` → لیست رسمی |
| 2 | کاربر «pdf» را install می‌کند |
| 3 | `anthropic_skill_id=pdf` ذخیره می‌شود (بدون ZIP) |

### گام ۲.۳ — اجرای hybrid

**سوال:** «گزارش فروش را بگیر و Excel بساز»

| مرحله | Runtime |
|-------|---------|
| 1 | Portable: مهارت `sales-report` → `get_sales_report` tool |
| 2 | Native: skill `xlsx` → `AnthropicProvider` با `container.skills` |
| 3 | ترکیب نتایج در پاسخ نهایی |

### گام ۲.۴ — گسترش AnthropicProvider

```python
# مفهومی
kwargs["container"] = {"skills": [{"skill_id": "xlsx", "type": "anthropic"}]}
# beta headers: code-execution-2025-08-25, skills-2025-10-02, files-api-2025-04-14
```

### گام ۲.۵ — hesabix.compat.yaml

هنگام import ZIP، اگر فایل وجود داشت parse شود؛ وگرنه auto-generate گزارش سازگاری.

---

# فاز ۳ — مارکت‌پلیس UGC

## هدف
انتشار عمومی، moderation، browse/install، reviews.

## سناریوی مو‌به‌مو

### گام ۳.۱ — انتشار عمومی

| مرحله | عمل |
|-------|-----|
| 1 | `POST /businesses/{bid}/ai/skills/{id}/publish` |
| 2 | `sanitize_skill_for_marketplace()` — حذف secrets |
| 3 | `ai_moderation_service.review_skill()` |
| 4 | `status=pending_review` → admin/auto → `published` |
| 5 | ظاهر در `GET /ai/skills/marketplace/packages` |

### گام ۳.۲ — browse و نصب توسط کاربر دیگر

| مرحله | عمل |
|-------|-----|
| 1 | کاربر B مارکت‌پلیس را باز می‌کند |
| 2 | فیلتر: `source_type`, tag, `compatibility_score` |
| 3 | جزئیات + گزارش سازگاری |
| 4 | Install → `install_count++` |

### گام ۳.۳ — review

| مرحله | عمل |
|-------|-----|
| 1 | `POST /ai/skills/marketplace/packages/{id}/reviews` |
| 2 | rating 1–5 + comment |
| 3 | نمایش میانگین در کارت مهارت |

### گام ۳.۴ — Flutter UI

| صفحه | الگو |
|------|------|
| `ai_skills_marketplace_page.dart` | `workflow_marketplace_page.dart` |
| `ai_chat_skills_sheet.dart` | `ai_chat_knowledge_sheet.dart` |

---

# فاز ۴ — اکوسیستم

## سناریوهای تکمیلی

### گام ۴.۱ — import از Git URL
`POST /ai/skills/import-git` → clone shallow → validate → package

### گام ۴.۲ — monetization
پلن پولی skill pack؛ `marketplace_orders`؛ سهم publisher

### گام ۴.۳ — مهارت‌های رسمی Hesabix
seed: `fiscal-year-close`, `sales-return`, `inventory-reorder`

### گام ۴.۴ — به‌روزرسانی نسخه
`parent_package_id` + notify installs + optional auto-migrate

### گام ۴.۵ — MCP export
مهارت‌های نصب‌شده در `/api/v1/ai/mcp` metadata

---

## Schema دیتابیس (خلاصه)

### ai_skill_packages
| ستون | نوع | توضیح |
|------|-----|--------|
| id | int PK | |
| skill_slug | varchar(64) | از frontmatter name |
| title | varchar(255) | نمایشی |
| description | text | از frontmatter |
| skill_body | text | markdown بدون frontmatter |
| source_type | varchar(32) | portable, anthropic_prebuilt, hesabix_native |
| anthropic_skill_id | varchar(64) nullable | pdf, xlsx, ... |
| bundle_files | json nullable | {path: content_base64 or text} |
| allowed_tool_names | json nullable | لیست ابزار حسابیکس |
| compatibility_report | json nullable | |
| has_scripts | bool | |
| publisher_user_id | int nullable | |
| publisher_business_id | int nullable | |
| visibility | varchar(32) | draft, business_only, pending_review, published, hidden |
| version_label | varchar(64) | |
| install_count | int | |
| tags | json | |

### ai_skill_installs
| ستون | نوع |
|------|-----|
| id | int PK |
| package_id | int FK |
| business_id | int FK |
| installed_by_user_id | int |
| is_enabled | bool |
| custom_title | varchar nullable |
| created_at | datetime |

---

## وابستگی بین فازها

```
فاز ۱ (پایه) ──► فاز ۲ (Anthropic native)
      │
      └──────────► فاز ۳ (Marketplace) ──► فاز ۴ (اکوسیستم)
```

فاز ۲ و ۳ می‌توانند موازی پس از فاز ۱ شروع شوند.

---

## معیار پذیرش (Acceptance Criteria)

### فاز ۱
- [x] ZIP معتبر agentskills.io import می‌شود
- [x] مهارت hesabix_native ساخته می‌شود
- [x] enable/disable بدون restart
- [x] prompt شامل metadata مهارت‌های فعال
- [x] tools فیلتر شده با allowed_tool_names
- [x] unit test parser

### فاز ۲
- [x] prebuilt pdf/xlsx با Claude — `AnthropicProvider` + `container.skills`
- [x] گزارش سازگاری برای skills دارای scripts + `hesabix.compat.yaml`
- [x] نصب prebuilt از API/UI

### فاز ۳
- [x] publish + moderation (spam) + admin approve/reject
- [x] public browse + install
- [x] reviews API
- [x] Flutter: skills sheet + marketplace page

### فاز ۴
- [x] Git import (GitHub URL → ZIP)
- [x] حداقل ۵ مهارت رسمی ERP seed شده
- [x] monetization (قیمت‌گذاری + خرید از کیف پول)
- [x] Flutter admin page برای moderation
- [x] تب «حسابیکس» در مارکت‌پلیس + نمایش قیمت
- [x] Import از GitHub در sheet مهارت‌ها

### فاز ۵ — ناشر و درآمد
- [x] UI انتشار با قیمت‌گذاری (`AISkillPublishDialog`)
- [x] سهم ناشر از فروش (پیش‌فرض ۷۰٪) + واریز به کیف پول
- [x] API گزارش درآمد ناشر (`GET .../publisher/revenue`)
- [x] صفحه داشبورد درآمد ناشر
- [x] تأیید خرید مهارت پولی قبل از نصب
- [x] لیست مهارت‌های owned + دکمه انتشار در sheet

### فاز ۵ — تکمیل
- [x] UI ادمین تنظیم درصد سهم ناشر (`/system-settings/ai-marketplace`)
- [x] API `GET/PUT /admin/system-settings/marketplace`
