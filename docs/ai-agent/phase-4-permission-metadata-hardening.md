# Phase 4 — Permission & Tool Metadata Hardening

**وضعیت:** در کد پیاده شده است.  
**تاریخ:** ۱۹ اوت ۲۰۲۶  
**ممیزی ماشین‌خوان:** [`tool-metadata-audit.md`](tool-metadata-audit.md)

> **Phase 4 improves the quality and trustworthiness of the catalog; it does not improve retrieval yet.**

پس از این Phase:

```text
Tool Catalog → Complete → Authorized → Correctly classified → Search-ready
```

Retrieval هنوز همان Keyword/Intent است. Vector / Hybrid / `search_tools` نیست.

---

## 1. Audit Before Changes

۱۸۰ Tool از سورس `AIFunction` + Manifest.parse شد (بدون instantiate زندهٔ Registry).

قبل از اصلاح:

- بدون `required_permissions` (حذف‌شده یا `[]`): **۲۲**
- `upsert_memory_entry`: `side_effect=none` و `is_readonly=True` در حالی که DB را می‌نوشت
- Capability درشت: `accounting` برای فاکتور و گزارش و سرفصل
- Fail-open: `if required_permissions:` خالی یعنی ALLOW

گزارش کامل ردیف‌ها: `tool-metadata-audit.md`.

---

## 2. Permission Gaps

۲۲ مورد یکی‌یکی طبق رفتار واقعی، نه یک permission ساختگی:

| دسته | تعداد | تصمیم |
|------|------|--------|
| Fan-in query (`query_business_data`, `batch_query_business_data`, `list_queryable_fields`) | ۳ | `permission_policy=handler` — چک per-entity در handler |
| حافظهٔ کاربر | ۳ | `self_scoped` — دادهٔ همان user+business |
| Agent session / subagent | ۶ | `agent_internal` |
| تقویم / عضویت / اعلان کاربر / پروفایل کسب‌وکار نشست | ۵ | `user_context` |
| کیف پول | ۳ | `wallet.view` (alias به wallet.view یا settings.business) |
| شرح پرتکرار اسناد | ۱ | `invoices.read` |
| کانکتور HTTP | ۱ | `settings.view` |

هیچ permission عمومی `ai.tools` اضافه نشد.

---

## 3. Side Effect Audit

Enum موجود حفظ شد: `none | write | delete | execute | export`.

`external_call` جدا نشد؛ `invoke_*` از قبل `execute` است.

اصلاح‌ها:

- `upsert_memory_entry` → **write** + `intent_write`
- `test_workflow` → **execute** (اجرای sandbox؛ چنداثر → خطرناک‌تر)
- `delete_memory_entry` از قبل delete (prefix)

اصل چندعملیاتی: کم‌خطرترین انتخاب نمی‌شود.

---

## 4. Memory Tool Analysis

`upsert_memory_entry` محتوای حافظه را در DB می‌نویسد (`upsert_memory` / `upsert_memory_item`). **WRITE است، READ_ONLY نیست.**

- Manifest: `intent_write=True` → `side_effect=write`
- Registry: `is_readonly=False`
- Approval: `requires_approval=False` — «به خاطر بسپار» نباید پشت تأیید مالی بماند
- Permission: self_scoped (نه invoices.write)
- Discovery: کلاس WRITE؛ کلیدواژهٔ `یادت باشه` / `به خاطر بسپار` به mutation نوشتن اضافه شد
- `فراموش کن` → destructive تا `delete_memory_entry` بتواند candidate شود

---

## 5. Capability Taxonomy

سه مفهوم جدا و هر کدام یک شغل دارند:

| مفهوم | شغل | مثال |
|--------|-----|------|
| **Domain** | سطل Intent کلیدواژه‌ای موجود | `financial` |
| **Capability** | کلید جستجوی نقطه‌ای آینده | `reports.sales` / `financial.invoice` |
| **Namespace** | بخش اول capability (ضد تصادم در ۱۲۰۰+) | `reports` / `financial` |

Capability از نام واقعی ۱۸۰ Tool استخراج شد (`ai_tool_capability.py`). `discover_tools(capability=)` مطابقت پیشوند دارد (`financial` → `financial.invoice`) اما Ranking عوض نشده است.

---

## 6. Search Metadata

`ToolManifestEntry.search_text` / `AIFunction.search_text`:

```text
name + description + capability + namespace + domains + aliases + keywords + examples
```

Embedding ساخته نمی‌شود. Phase بعد می‌تواند همین رشته را embed کند.

غنی‌سازی Alias/Example فقط برای Toolهای پرکاربرد/طلایی (`ai_tool_search_meta.py`). بقیه عمداً optional هستند.

---

## 7. Description Quality

Descriptionها بازنویسی کور نشدند. پارسر سطح `AIFunction` ثابت‌های `*_DESCRIPTION` را resolve می‌کند. چهار توضیح واقعاً کوتاه هدفمند اصلاح شدند. آستانهٔ ۱۶ کاراکتر اکنون برای هر ۱۸۰ Tool پاس می‌شود.

تمایز collision برای فاکتور/گزارش/شخص با capability + examples است نه بازنویسی همه.

---

## 8. Alias Quality

فقط عبارات واقعی کاربر (فاکتور فروش، گزارش بدهکاران، به خاطر بسپار، …). Alias انگلیسی بی‌معنی اضافه نشد.

---

## 9. Example Queries

برای خانوادهٔ فاکتور، فروش، شخص، کالا، موجودی، گزارش، export، workflow، حافظه، کیف پول، باسلام.

Discriminative: `get_invoice_details` اقلام/شماره؛ `search_invoices` لیست/ماه.

---

## 10. Tool Collisions

عمدی fan-in:

- `search_invoices` ≠ `query_business_data(entity=invoice)` ≠ `get_report`
- `get_sales_report` (`reports.sales`) ≠ `get_report` (`reports.overview`)

نام تکراری در Registry نیست.

---

## 11. Metadata Quality Score

`metadata_quality_score` (۰–۱۰۰) از description/domain/capability/aliases/keywords/examples/permission/side_effect.

**روی Ranking مدل اثر ندارد.** فقط audit و تست completeness.

---

## 12. Migration

```text
audit → classify 22 → assign real perm or explicit policy
     → fail-closed unspecified/required+empty
     → tests
```

`catalog_permission_allows` در `get_function_definitions` و `call_function`.

`has_any_ai_tool_permission([])` همچنان True است (برای چک entity داخل handler). مرز کاتالوگ جداست.

---

## 13. Security Decisions

- Permission ≠ side_effect
- خالی + سیاست نامعتبر → **NOT CANDIDATE / PermissionError**
- write/delete/export/execute بدون perm و بدون سیاست صریح → deny
- Memory write در Discovery کلاس WRITE است؛ Guard اجرا برای `requires_approval=False` تأیید مالی نمی‌خواهد
- Connector execute + settings.view + always_confirm

---

## 14. Tests

`tests/test_ai_tool_catalog_quality.py` + رگرسیون Phase 1–3.

---

## 15. Remaining Gaps

- Alias/example برای ~۱۰۷ / ~۱۵۰ Tool دم‌بلند هنوز optional است (عمدی)
- چند Tool با capability درشت `misc.general` (پروژه/تعمیر/گارانتی) — امنیتی نیست؛ جستجو ضعیف‌تر است
- Capability هنوز درخت کامل UI محصول نیست
- Hybrid search نیست

Description سطح کاتالوگ اکنون آستانهٔ ۱۶ کاراکتر را پاس می‌کند. این‌ها مانع Tight Top-K نیستند؛ مانع ۱۲۰۰+ Hybrid با کیفیت بالا اگر aliases دم‌بلند خالی بمانند می‌شوند.

---

## 16. Phase 5 Recommendation

Catalog برای **Tight Top-K + Evaluation** آماده است: هویت کامل، permission مشخص، side_effect درست، search_text موجود.

Phase 5 پیشنهادی: کاهش سقف analyzer به ۵–۲۰ با همان `discover_tools` + گسترش gold eval — **نه هنوز Hybrid**.

Hybrid وقتی ارزش دارد که Top-K تنگ eval شده باشد و aliases دم‌بلند در صورت افت recall پر شوند.
