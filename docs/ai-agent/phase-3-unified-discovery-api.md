# Phase 3 — Unified Tool Discovery API

**وضعیت:** در کد پیاده شده است.  
**تاریخ:** ۱۹ اوت ۲۰۲۶  
**Source of Truth کد:** `hesabixAPI/app/services/ai/ai_tool_discovery.py`  
**مرتبط:** [`tool-discovery-architecture.md`](tool-discovery-architecture.md) · [`phase-2-security-first-discovery.md`](phase-2-security-first-discovery.md)

> Discovery می‌گوید کدام Tool مناسب است. Schema Loader می‌گوید JSON کامل آن چیست. این دو یکی نیستند.

---

## 1. Problem

پس از Phase 2 امنیت قبل از Ranking است، اما انتخاب Tool هنوز در چند مسیر پخش بود:

- `AIService.get_available_functions` شاخهٔ analyzer / catalog را خودش می‌ساخت
- Intent (`select_tool_names` / `select_catalog_tool_names`) هم Security داشت هم Ranking
- CRM، تیکت، Workflow، Subagent هر کدام `get_available_functions` یا Registry را جدا صدا می‌زدند
- MCP `tools/list` کاتالوگ permissionخوردهٔ کامل را بدون Intent می‌داد

بدون API واحد، Phase بعد (hybrid / Top-K تنگ) باید همهٔ Consumerها را دوباره عوض می‌کرد.

---

## 2. Existing Discovery Paths

استخراج از کد واقعی (قبل از این Phase):

| مسیر | Input | Toolهایی که می‌بیند | Permission | Security | Intent / Rank | Top-K |
|------|--------|---------------------|------------|----------|---------------|-------|
| Chat `get_available_functions` | query, mode, session, force, history | خروجی Registry برای همان user/tenant | Registry | `filter_security_candidates` | `select_tool_names` یا catalog | ۴۸ / ۱۲۸ |
| Subagent | goal، mode=analyzer | همان Chat سپس `filter_subagent_tools` | Registry از طریق Chat | Chat + write strip | Chat | ۴۸ سپس allowlist فرزند |
| CRM | query، analyzer | Chat سپس `CHANNEL_CRM_READ_TOOLS` | Registry | Chat + channel allowlist | Chat | allowlist کوچک |
| Ticket | عنوان تیکت، analyzer | Chat سپس ticket allowlist | Registry | همان | Chat | allowlist کوچک |
| Workflow agent | category / بدون query | همهٔ authorized (بدون rank) سپس denylist | Registry | Security بدون rank | هیچ | تا hard max |
| MCP `tools/list` | business_id | همهٔ permissioned | Registry | نه mutation | نه | بدون سقف Intent |
| MCP `tools/call` | name + args | یک Tool | Registry + write guard | اجرا | — | — |
| Gold / unit tests | catalog ساختگی | نام‌های داده‌شده | شبیه‌سازی‌شده | داخل select_* | keyword | ۴۸ / ۱۲۸ |

Permission در Discovery تکرار نمی‌شود. Tenant همان `business_id` نشست است.

---

## 3. Unified API

```python
discover_tools(
    query,
    permissioned_names=...,
    execution_mode=...,
    limit=...,
    history_messages=...,
    forced_names=...,
    prefer_names=...,
    protected_names=...,
    channel="chat",
    capability=None,
    rank=None,
) -> DiscoveryOffer
```

خروجی:

```text
DiscoveryOffer
├── candidates: ToolCandidate[]   # بدون Schema
│     name, score, match_reason, capability, namespace, domains, side_effect
├── strategy, channel, execution_mode, mutation
├── requested_limit, effective_limit
├── authorized_count, latency_ms, ranked
```

`get_available_functions` حالا:

```text
Registry.get_function_definitions
        ↓
discover_tools()          # names + lightweight metadata
        ↓
filter_function_definitions   # Schema loading (هنوز همین‌جا)
```

---

## 4. Security Boundary

```text
Registry (tenant / role / permission)
        ↓
discover_tools
        ↓
filter_security_candidates   # موجود؛ Duplicate نیست
        ↓
KeywordIntentStrategy
        ↓
Ranked authorized names
```

صدای مستقیم `discover_tools` هم Security را اجرا می‌کند. Permission را دوباره پیاده نمی‌کند؛ اگر caller نام غیرمجاز بدهد، آن نام‌ها permission-check نمی‌شوند — قرارداد این است که `permissioned_names` از Registry آمده باشد.

UNKNOWN همچنان fail-closed است (`unknown_policy=deny` در production).

---

## 5. Discovery Contract

**Input:** مجموعهٔ permissioned + query/mode/limit/channel — نه db و نه PII اضافه.

**Output:** فقط نام و metadata سبک. هیچ `parameters` / JSON Schema.

**Empty:** `permissioned_names=[]` یا هیچ Tool مجاز → `DiscoveryOffer` خالی، نه None و نه کاتالوگ کامل.

**Cache:** Interface برای کش بعدی آماده است (`DiscoveryEngine.discover`). در این Phase کش اضافه نشد.

---

## 6. Strategy Architecture

```text
DiscoveryEngine
 ├── KeywordIntentStrategy   ← فعال (Phase 3)
 ├── SemanticStrategy        ← NotImplemented
 └── HybridStrategy          ← NotImplemented
```

جایگزینی Phase بعد بدون تغییر Chat/Subagent: strategy دیگر به Engine داده می‌شود. Consumer همان `discover_tools` است.

Capability: پارامتر اختیاری؛ فعلاً prefer است نه hard filter. مقدارهای امروز درشت‌اند (`accounting`, `inventory`, …) نه `reports.sales`.

---

## 7. Chat Integration

`AIService.get_available_functions` → `discover_tools(..., channel="chat")`.

سقف پیش‌فرض همان ۴۸ analyzer / ۱۲۸ supervised-autonomous است. `force_tool_names` و مهارت/plan/subagent به‌صورت forced/prefer عبور می‌کنند.

Schema همچنان بعد از Discovery از Registry لود می‌شود تا حلقهٔ LLM نشکند.

---

## 8. Subagent Integration

Subagent Discovery مستقل ندارد.

```text
child.get_available_functions(..., channel="subagent")
        ↓
discover_tools()
        ↓
filter_subagent_tools (read-only + allowlist فرزند)
```

---

## 9. MCP Integration

در این Phase `tools/list` **عوض نشد**. قرارداد MCP: کلاینت خارجی کاتالوگ permissionخورده را می‌بیند و خودش انتخاب می‌کند. Execution Guard در `tools/call` باقی است.

Phase بعد (یا ۹ در roadmap):

```text
tools/list + query  → discover_tools(channel="mcp", limit=…)
tools/list بدون query → permissioned catalog با DISCOVERY_HARD_MAX
tools/call → بدون تغییر Guard
```

تا کلاینت MCP به listing کامل وابسته است، dynamize کردن list بدون هماهنگی پروتکل خطر سازگاری دارد.

---

## 10. Limit Handling

| مقدار | معنی |
|--------|------|
| `requested_limit` | آنچه Consumer خواست |
| `default` | ۴۸ analyzer / ۱۲۸ catalog / ۲۵۶ اگر rank خاموش |
| `DISCOVERY_HARD_MAX` | ۲۵۶ — بزرگ‌تر از کاتالوگ ۱۸۰؛ `limit=100000` به این سقف می‌رسد |
| `effective_limit` | `min(requested, hard_max)` پس از default |

۴۸ و ۱۲۸ به‌عنوان پیش‌فرض Chat حفظ شدند تا Accuracy عوض نشود.

---

## 11. Observability

`log_ai_event("tool_discovery")`:

- channel, mode, mutation, strategy, ranked
- candidate_count (authorized), selected_count, selected_tools (نام Tool)
- requested_limit, limit, discovery_latency_ms
- capability

**لاگ نمی‌شود:** متن query، نام مشتری، مبلغ، موجودی، ایمیل، شناسهٔ سند.

---

## 12. Tests

`tests/test_ai_tool_discovery.py`:

- Chat source → `discover_tools`
- Subagent source → `get_available_functions` + `channel=subagent`
- Unauthorized هرگز برنمی‌گردد
- `limit=100000` bounded
- Empty permissioned → offer خالی
- Gold recall از طریق `discover_tools` ≥ ۹۵٪
- Candidate بدون Schema
- Semantic/Hybrid هنوز NotImplemented

رگرسیون Phase 1–2 باید سبز بماند. تعداد Tool = ۱۸۰.

---

## 13. Migration

- هیچ Tool حذف یا rename نشد
- `select_tool_names` backend استراتژی است؛ Gold مستقیم هم هنوز آن را صدا می‌زند
- CRM/تیکت/Workflow از طریق `get_available_functions` به API واحد رسیدند؛ allowlist کانال سر جایش است
- MCP list عمداً مهاجرت نشد

---

## 14. Phase 4 Design

دو گزینه روی میز بود: Hybrid/Semantic فوری، یا پاکسازی Permission/Metadata.

**توصیهٔ این پروژه: ابتدا یک Phase مستقل برای کیفیت Metadata و بستن Permission Gap، سپس Hybrid.**

دلیل از وضعیت واقعی کد:

1. Phase 0 حدود ۲۲ Tool بدون `required_permissions` ثبت کرده؛ Registry برای permission خالی fail-open است. Semantic match این Toolها را بیشتر به مدل نزدیک می‌کند.
2. `upsert_memory_entry` هنوز `side_effect=none` است و در Discovery شبیه Read به‌نظر می‌رسد.
3. Capability امروز درشت است (`accounting`) نه `reports.sales`؛ Hybrid بدون متن جستجوی غنی (aliases/examples ناقص برای خیلی از Toolها) نویز دامنه می‌سازد.
4. سقف ۴۸/۱۲۸ هنوز برای بنچمارک ۵–۲۰ بسته نشده؛ Progressive Schema هم نیست.

پس Phase 4 پیشنهادی این مخزن: **Tool Metadata & Permission Hardening** (بستن gap، side_effect حافظه، aliases برای delete/export). Phase 5: Tight Top-K + Hybrid روی همان `discover_tools` / `HybridStrategy`.

**وضعیت اجرا:** Phase 4 طبق همین توصیه در کد فرود آمده است. جزئیات: [`phase-4-permission-metadata-hardening.md`](phase-4-permission-metadata-hardening.md). Retrieval هنوز عوض نشده.
