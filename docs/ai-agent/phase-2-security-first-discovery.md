# Phase 2 — Security-First Tool Discovery

**وضعیت:** در کد پیاده شده است.  
**تاریخ:** ۱۹ اوت ۲۰۲۶  
**Source of Truth کد:** `hesabixAPI/app/services/ai/`  
**مرتبط:** [`tool-discovery-architecture.md`](tool-discovery-architecture.md) · [`dynamic-tool-discovery.md`](dynamic-tool-discovery.md)

## اصل معماری

> **Security is a hard boundary, not a ranking signal.**

> **A tool must be authorized before it can become a discovery candidate.**

> **Discovery reduces context; it must never weaken authorization.**

---

## 1. Current Security Flow

پس از Phase 1، هویت Tool در Manifest/Index است. مسیر زندهٔ چت:

```text
All tools (registry)
        │
        ▼
Tenant / session business_id     ← function_registry.get_function_definitions
        │                           (business_context_required)
        ▼
Role filter                      ← allowed_roles
        │
        ▼
User permission                  ← required_permissions + ai_permission_map
        │
        ▼
Security / side-effect filter    ← ai_tool_security.filter_security_candidates
        │                           (execution_mode + query mutation)
        ▼
Intent / domain filter           ← select_tool_names / select_catalog_tool_names
        │
        ▼
Ranking / Top-K                  ← rank_and_cap_tool_names (۴۸ / ۱۲۸)
        │
        ▼
LLM
        │
        ▼
Tool call
        │
        ▼
Execution guard                  ← ai_write_guard + ai_execution_policy
        │                           (analyzer block, approval, high-risk)
        ▼
Handler (session business_id injected)
```

| لایه | کجا | چه زمانی |
|------|-----|----------|
| Tool identity | `ai_tool_manifest` / `AIFunction` | ثبت Tool |
| Tool security class | `side_effect` + `intent_write` + `always_confirm` | قبل از Ranking |
| User permission | `required_permissions` + `ai_permission_map` | قبل از Security filter |
| UI permission alias | `ai_permission_map.PERMISSION_ALIASES` | فقط ترجمهٔ رشته به سکشن UI |
| Tenant / company | `business_id` نشست + `business_context_required` | Registry؛ تکرار نمی‌شود |
| Execution mode | `ai_execution_policy` | Discovery (analyzer=read-only) و Execution |
| Approval | `ai_write_guard` / `should_require_write_approval` | بعد از tool_call، قبل از handler |
| MCP list | `get_function_definitions` | Permission/tenant فقط |
| MCP call | `is_write_function` + `approve_writes` | Guard اجرا؛ listing مجوز اجرا نیست |

Intent selection (`select_tool_names`) دیگر روی کل کاتالوگ permissionخورده کار نمی‌کند؛ ورودی‌اش مجموعهٔ امنیتی‌شده است. `force_tool_names` (تأیید در جریان) از فیلتر mutation معاف است تا پیام «تأیید» Tool نوشتنی را حذف نکند.

---

## 2. Problems

Phase 0/1 این شکاف‌ها را باقی گذاشته بود:

1. **Permission قبل از Intent بود، اما side-effect بعد از Intent نبود.** `delete_invoice` در دامنهٔ `financial` است؛ گزارش وضعیت مالی آن را وارد ۴۸/۱۲۸ می‌کرد.
2. **کاتالوگ Autonomous همهٔ writeها را بعد از Ranking دوباره union می‌کرد.** سقف ۱۲۸ امنیت را override می‌کرد.
3. **`filter_function_definitions` روی مجموعهٔ خالی fail-open بود** و همهٔ تعاریف را برمی‌گرداند.
4. **Intent نوشتن با Destructive یکی بود** (`حذف` داخل `_WRITE_KEYWORDS`).
5. **Export شبیه Read به‌نظر می‌رسید** درحالی‌که `side_effect=export` و `always_confirm` است.
6. **امتیاز keyword می‌توانست Tool غیرمجاز را در Top-K نگه دارد** چون فیلتر سخت قبل از rank نبود.

---

## 3. Security Model

طبقه‌بندی Tool از Manifest است، نه از prefix نام. Prefix فقط داخل `infer_side_effect` به‌عنوان signal ذخیره می‌شود.

| کلاس Discovery | شرط Manifest | مثال |
|----------------|--------------|------|
| `READ_ONLY` | `side_effect=none` | `search_invoices` |
| `WRITE` | `side_effect=write` یا `intent_write` (و delete/export/execute نباشد) | `create_invoice` |
| `DESTRUCTIVE` | `side_effect=delete` | `delete_invoice` |
| `HIGH_RISK` | `side_effect=export` یا `execute` | `export_business_data`, `execute_workflow` |
| `UNKNOWN` | خارج از Manifest یا `enabled=false` | — |

`always_confirm` و `risk_level` **سیاست اجرا/تأیید** هستند، نه امتیاز Discovery. اگر `always_confirm` را در Discovery معادل HIGH_RISK می‌گرفتیم، `create_workflow` از intent نوشتن اتوماسیون حذف می‌شد. تأیید همچنان در Execution Guard است.

کلاس mutation کوئری (جدا از دامنهٔ مالی/انبار):

| Query | Mutation |
|-------|----------|
| فاکتور علی را نشان بده | `READ` |
| فاکتور جدید ایجاد کن | `WRITE` |
| این فاکتور را حذف کن | `DESTRUCTIVE` |
| خروجی اکسل / export | `EXPORT` |
| اجرای workflow | `EXECUTE` |
| خالی / نامشخص | `UNKNOWN` → فقط read |

اولویت: Destructive > Execute > Export > Write > Read.

ماتریس مجاز (supervised/autonomous):

| Mutation \ Tool | READ_ONLY | WRITE | DESTRUCTIVE | HIGH_RISK |
|-----------------|-----------|-------|-------------|-----------|
| READ / UNKNOWN | بله | خیر | خیر | خیر |
| WRITE | بله | بله | خیر | خیر |
| DESTRUCTIVE | بله | خیر | بله | خیر |
| EXPORT | بله | خیر | خیر | فقط `export` |
| EXECUTE | بله | خیر | خیر | فقط `execute` |

Analyzer: فقط `READ_ONLY`، حتی اگر کوئری نوشتنی باشد.

---

## 4. Candidate Filtering

قرارداد Discovery:

```text
Input:
  permissioned tool names   (بعد از tenant/role/permission)
  user context / tenant     (در Registry مصرف شده؛ اینجا تکرار نمی‌شود)
  execution_mode
  intent / query / history
  forced_names              (تأیید در جریان، plan/subagent در صورت expose)

Output:
  authorized candidates only
```

API:

```python
filter_security_candidates(
    names,
    user_query,
    execution_mode=mode,
    forced_names=...,
    history_messages=...,
    unknown_policy="deny",  # production
)
```

سپس `select_tool_names` / `select_catalog_tool_names` فقط روی همین مجموعه rank می‌کنند. `prefer_names` و امتیاز semantic/keyword **نمی‌توانند** نام حذف‌شده را برگردانند.

`unknown_policy="allow"` فقط برای fillerهای تست ranking است (`zzz_filler_*`) که در Manifest نیستند.

---

## 5. Permission Architecture

لایه‌ها جدا می‌مانند. Registry محل سیاست User نیست.

```text
Tool Identity     Manifest name + AIFunction.name
Tool Security     side_effect / intent_write / always_confirm / risk_level
User Permission   AIFunction.required_permissions  (رشته‌های محصول)
UI Permission     ai_permission_map aliases → people.view / invoices.add / …
Tenant Policy     session business_id + can_access_business در handler
```

`ai_permission_map` همچنان alias UI/Product است. Tool Identity محسوب نمی‌شود.

---

## 6. Tenant Isolation

Toolها رکورد per-tenant نیستند؛ کاتالوگ سراسری است. جداسازی داده:

1. `get_function_definitions`: بدون `business_id` هیچ Tool با `business_context_required` candidate نمی‌شود.
2. Handler: `business_id` از نشست inject می‌شود؛ `business_id` جعلی در arguments اگر به کسب‌وکار دیگر اشاره کند رد می‌شود.
3. Discovery فیلتر tenant جداگانه **تکرار نمی‌کند** تا cache/logic دوتایی ساخته نشود.

«Tool متعلق به tenant دیگر» در این مدل یعنی نام در ورودی permissioned/session نیست → candidate نمی‌شود.

---

## 7. Risk Classification

Export عمداً `READ_ONLY` نیست. فیلد جدید (`SENSITIVE_READ`) اضافه نشد؛ `side_effect=export` + `always_confirm` همان مفهوم exfiltration را می‌پوشاند و در Discovery کلاس `HIGH_RISK` است.

Destructive از `side_effect=delete` می‌آید (نه فقط `delete_*` در Intent). Write از metadata است. Execute از `side_effect=execute`.

---

## 8. Approval Flow

Discovery فیلتر می‌کند؛ جای Guard اجرا را نمی‌گیرد.

```text
User Request → Intent → Security Filter → Candidate → LLM
    → Tool Call → Approval / Risk Guard → Execution
```

- analyzer: write در candidate نیست **و** `should_block_write_in_analyzer` همچنان فعال است.
- supervised: write فقط با mutation نوشتن candidate می‌شود؛ اجرا بدون `approve_writes` نمی‌شود.
- autonomous: high-risk (`always_confirm`) همچنان تأیید می‌خواهد.
- `force_tool_names` برای ادامهٔ نوبت تأیید لازم است تا Tool از لیست حذف نشود.

---

## 9. MCP Security

MCP سرور خروجی است (`POST /api/v1/ai/mcp`)، نه موتور Discovery داخلی.

| مسیر | فیلتر |
|------|--------|
| `tools/list` | همان permission/tenant Registry — کلاینت MCP انتخاب خودش را دارد |
| `tools/call` | `prepare_mcp_tool_arguments` در پشتی `_approve_writes` را حذف می‌کند؛ write فقط با `params.approve_writes is True` |

Listing یک write tool اجازهٔ اجرا نیست. Agent داخلی و MCP هر دو به Execution Guard ختم می‌شوند.

---

## 10. Failure Modes

| حالت | رفتار |
|------|--------|
| UNKNOWN classification | NOT CANDIDATE (`unknown_policy=deny`) |
| Permission نامشخص / رد | نام به فیلتر نمی‌رسد |
| بدون business_id | Toolهای کسب‌وکار حذف می‌شوند |
| کوئری عمومی مالی | delete/export/execute/write نیستند |
| مجموعهٔ allowed خالی | هیچ Schemaای به مدل نمی‌رود (fail-closed) |
| Rank بالا روی Tool غیرمجاز | بی‌اثر؛ نام در ورودی rank نیست |
| LLM tool_call خارج از لیست | Registry + write guard |
| MCP call بدون approve | `build_approval_required_result` |

---

## 11. Tests

`tests/test_ai_tool_security.py` به‌علاوهٔ رگرسیون:

- Unauthorized / authorized read / write روی read query
- Generic financial query → نه delete/export/execute
- Explicit delete → `delete_invoice` ممکن است candidate شود؛ `is_write_function` همچنان True (approval)
- Unknown → fail-closed
- Ranking `prefer_names` امنیت را override نمی‌کند
- MCP write/export/execute/delete همچنان gated
- Tenant = عدم ورود نام خارج از ورودی نشست
- Gold recall، catalog، execution policy، write guard، channel، MCP write، subagent، memory

---

## 12. Performance

فیلتر روی حدود ۱۸۰ نام در حافظه است (Index از قبل ساخته شده). در این Phase cache جدید اضافه نشد:

- Permission همان مسیر Registry است (بدون query اضافه per tool فراتر از قبل)
- Metadata از `ToolIndex` / Manifest
- Authorized set هر نوبت از روی نام‌های permissionخورده محاسبه می‌شود

Cache مجموعهٔ مجاز وقتی کاتالوگ به ۱۲۰۰+ برسد و هزینهٔ permission غالب شود در Phaseهای بعد بررسی شود.

---

## 13. Migration Notes

- تعداد Tool: ۱۸۰ → ۱۸۰
- سقف ۴۸/۱۲۸ عوض نشده
- Vector / hybrid / `search_tools` / progressive schema **پیاده نشده**
- تست `test_autonomous_catalog_keeps_907_write_tools` به `test_autonomous_catalog_keeps_mutation_allowed_writes` تغییر کرد: محافظت از همهٔ deleteها روی کوئری ایجاد شخص همان باگ Phase 0 بود
- `filter_function_definitions([])` دیگر همه را برنمی‌گرداند

---

## 14. Phase 3 Recommendation

موتور واحد `discover_tools(ctx, query, mode, channel) -> ToolOffer` برای چت، MCP، CRM، subagent — هنوز بدون vector search. ورودی همان Authorized set این Phase است. سقف و Schema کامل را یکی کند تا `get_available_functions` شاخهٔ تکراری نداشته باشد.
