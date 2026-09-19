# Phase 7 — Progressive Tool Schema Loading

**وضعیت:** در کد پیاده شده است. سقف production عوض نشد.  
**تاریخ:** ۲۰ اوت ۲۰۲۶  
**نتایج ماشین‌خوان:** [`evals/tool-schema-loading/latest.json`](evals/tool-schema-loading/latest.json)  
**قرارداد داده:** همان Gold `2026-08-19.v1` — Retrieval و `expected_tools` تغییر نکردند.

> **Discover only what is relevant. Load only what is needed. Never confuse schema caching with authorization.**

Embedding / Hybrid / `search_tools` / LLM discovery در این Phase پیاده نشد.

---

## 1. Current Schema Loading

قبل از این Phase مسیر چنین بود:

```text
discover_tools()
      ↓
tool names
      ↓
registry.get_function_definitions()   ← JSON برای همهٔ authorized
      ↓
filter_function_definitions()
      ↓
full schemas → هر iteration همان لیست روی سیم
```

Call siteهای auditشده:

| مسیر | انتخاب نام | بارگذاری Schema |
|------|------------|-----------------|
| Chat | `discover_tools` داخل `get_available_functions` | همان متد → `load_tool_schemas` |
| Subagent | `get_available_functions(..., channel="subagent")` | همان loader؛ سپس `filter_subagent_tools` |
| CRM / Ticket | `get_available_functions` سپس allowlist کانال | keep-path در loop |
| Workflow | `get_available_functions(..., channel="workflow")` | همان loader |
| MCP `tools/list` | permissioned catalog کامل | `registry.get_function_definitions` — عمداً جدا ماند |

مشاهدات:

* Schema در زمان `get_available_functions` ساخته می‌شد (یک‌بار قبل از loop).
* همان object لیست در **هر HTTP request** iteration دوباره serialize می‌شد.
* Tool implementation (handler) از JSON Schema جدا است؛ Schema از `parameters_schema` + description است.
* Schema در عمل immutable است مگر کد/manifest عوض شود.

میانگین iteration زندهٔ قبلی ≈ ۵.۸؛ روی Gold از `QUERY_COMPLEXITY_ITERATIONS` میانگین **۴.۹۸** است.

---

## 2. New Architecture

```text
                 User Query
                     │
                     ▼
              discover_tools()          ← بدون JSON Schema
                     │
                     ▼
              ToolCandidate[]
                     │
                     ▼
            load_tool_schemas()
                     │
                     ▼
              Selected Schemas
                     │
                     ▼
                    LLM
                     │
              ┌──────┴──────┐
              │             │
           Tool Call      No Tool
              │
              ▼
        Execute Tool  (authorization جدا)
              │
              ▼
       Continue Agent Loop
```

دو abstraction مستقل:

| لایه | خروجی | شامل Schema؟ |
|------|--------|----------------|
| Discovery | `DiscoveryOffer` / `ToolCandidate` | خیر |
| Schema Loading | OpenAI tool JSON | بله، فقط برای نام‌های درخواستیِ مجاز |

سقف production Discovery همان **۴۸ / ۱۲۸** است. Schema Loading می‌تواند `max_total` جدا داشته باشد تا Evaluation روی K=5…48 بدون عوض کردن معماری انجام شود.

---

## 3. Schema Loader API

`hesabixAPI/app/services/ai/ai_tool_schema.py`

```python
load_tool_schemas(
    requested_names,
    *,
    authorized_names,   # هر call؛ cache جایگزین این نیست
    source,             # SchemaSource protocol
    state=None,         # ToolContextState per agent-run
    max_total=None,
    iteration=0,
) -> SchemaLoadResult
```

`SchemaSource` پروتکل است تا تست‌ها Registry زنده را import نکنند.

`get_available_functions` بعد از `discover_tools` فقط نام‌ها را به loader می‌دهد.

---

## 4. Schema Cache

`ToolSchemaCache` در سطح process، کلید `(tool_name, schema_version)`، deepcopy هنگام get/put، thread-safe.

این کش **هزینهٔ ساخت JSON در Python** را کم می‌کند، نه لزوماً توکن روی سیم.

کش نتیجهٔ tool (`ai_tool_cache.py`) جدا است. Tool Result باعث reload Schema نمی‌شود.

---

## 5. Schema Versioning

`AIFunction.schema_version` از Manifest کپی می‌شود.

`registry.schema_version_for(name)`:

```text
{declared}.{sha256(description + parameters_schema)[:12]}
```

اگر JSON عوض شود بدون bump دستی، cache invalid می‌شود. اگر declared هم بالا برود، کلید عوض می‌شود.

---

## 6. Tool Context State

Per agent-run، نه per-process authorization:

```text
ToolContextState
├── loaded_tools / order
├── loaded_versions
├── payloads
├── available_authorized   # snapshot همین round
└── rounds[]               # instrumentation
```

با `loaded_schema_versions` یکی است. Authorization از `authorized_names` هر call می‌آید، نه از این state.

مسیر `"keep"` (Subagent / CRM که از قبل tools دارند) با `hydrate_state_from_definitions` پر می‌شود.

---

## 7. Progressive Loading

Prototype در Agent Loop:

1. Iteration 1: schemaهای Discovery (اگر flag روشن باشد، سقف اولیه `PROGRESSIVE_SCHEMA_INITIAL_K=15`).
2. Iteration 2+: اگر `PROGRESSIVE_SCHEMA_LOADING`، Discovery دوباره و **فقط schemaهای جدید** ساخته می‌شوند؛ union روی سیم می‌رود.
3. اگر flag خاموش باشد (production): همان مجموعه دوباره `record_wire_repeat` می‌شود — صادقانه: توکن سیم تکرار می‌شود.

```text
Already loaded: A B C D E
New discovery:  C D F G
Construct:      F G only
Wire (if provider requires tools each call): A B C D E F G
```

Production:

```text
PROGRESSIVE_SCHEMA_LOADING = False
Analyzer K = 48
Autonomous K = 128
```

---

## 8. Security Boundary

**Schema cache is not an authorization cache.**

* نام غیرمجاز حتی با cache hit به payload اضافه نمی‌شود.
* Execution guard: اگر `_offered_tool_names` ست شده باشد و مدل نامی خارج از schemaهای loadشده بدهد → `UNKNOWN_TOOL`.
* Write approval / side_effect / tenant permission مسیر قبلی‌اند.
* خالی بودن Discovery → صفر schema.

---

## 9. Provider Constraints

هر iteration Agent یک HTTP request مستقل است.

| Provider | Prompt cache موجود؟ | Tool schema cache؟ |
|----------|---------------------|---------------------|
| OpenAI رسمی | `prompt_cache_key` روی prefix سیستم | tools در body هر request؛ وابسته به prefix cache نیست |
| OpenAI-compatible / آروان | `prompt_cache_key` فرستاده نمی‌شود | resend |
| Anthropic | `cache_control` روی system / conversation | tools هر بار `_openai_tools_to_anthropic` |
| Local | ندارد | tools در Ollama path عملاً استفاده نمی‌شود |

Architecture به هیچ Provider قفل نشد. بهینه‌سازی cache مخصوص tools موضوع Phase بعد است.

```text
Application-side duplication:  solved
LLM wire/context duplication:  reduced only if fewer schemas are put in the request
```

نگه داشتن نام‌ها در یک Python `set` به‌تنهایی توکن LLM را کم نمی‌کند.

---

## 10. Token Measurements

Instrumentation هر round (`log_ai_event("tool_schema_round")`):

```text
initial_schema_count / initial_schema_tokens
new_schema_count / new_schema_tokens
repeated_schema_count / repeated_schema_tokens
wire_schema_count / wire_schema_tokens
construction_hits / construction_misses
```

Eval بدون LLM، با `estimate_tools_schema_tokens` (همان تخمین Phase 5/6):

| حالت | Recall | Initial tokens | Additional | Wire tokens / request | Avg tools built |
|------|--------|----------------|------------|------------------------|-----------------|
| Current K=48 | 98.19٪ | 7,862 | 0 | **42,977** | 30.56 |
| Current K=20 | 98.19٪ | 4,621 | 0 | 24,837 | 17.05 |
| Progressive K=15 | 97.52٪ | 3,706 | 6 | **19,955** | 13.54 |
| Progressive K=10 | 95.49٪ | 2,605 | 13 | 14,028 | 9.48 |

میانگین iteration روی Gold = ۴.۹۸.

عدد قدیمی «≈۶۵k» فرض ۴۸ schema کامل × ~۵.۸ iteration بود. روی Gold معمولاً کمتر از ۴۸ نام score>0 دارند (میانگین ساخت ~۳۱)، بنابراین baseline اندازه‌گیری‌شده **۴۳k** است نه ۶۵k.

Progressive K=15 در برابر Current K=48: **۵۳.۶٪** کاهش توکن schema روی سیم — **اگر** مجموعهٔ ۱۵تایی واقعاً در request باشد.

Additional tokens نزدیک صفر است چون Recall@15 از قبل ۹۷.۵٪ است؛ تقریباً همهٔ gold toolها در Top-15 هستند. سود اصلی **K کوچک‌تر** است، نه افزودن تدریجی.

Production با flag خاموش هنوز Current K=48 را روی سیم می‌فرستد. Dedup پایتونی ساخت JSON را کم می‌کند، توکن LLM را نه.

---

## 11. Chat

`AIService.get_available_functions` → `discover_tools` → `load_tool_schemas`.

Loop: `_progressive_schema_round` + `_observe_schema_round`.

---

## 12. Subagent

همان `get_available_functions(..., channel="subagent")`. Loader دوم وجود ندارد. مسیر `"keep"` state را hydrate می‌کند.

---

## 13. MCP

`tools/list` همچنان catalog کامل permissioned است. می‌تواند بعداً `load_tool_schemas` را برای ساخت JSON تک‌به‌تک استفاده کند؛ قرارداد listing عوض نشد.

---

## 14. Tests

حداقل:

* Schema A دوباره → یک‌بار build
* A B C سپس B C D → فقط D جدید؛ union چهار نام
* version bump → rebuild
* cache hit ≠ authorized
* discovery خالی → صفر schema
* unoffered tool call → reject
* wire repeat → بدون rebuild
* CRM / Ticket / Workflow / Subagent از `get_available_functions`
* production K=48/128 و flag خاموش

Regression AI (Phases 1–7، بدون فایل‌هایی که Registry را در import حلقه می‌کنند): **۲۴۳ passed**.

---

## 15. Results

```text
Schema Discovery separated: YES
Schema Loader:              YES
Schema deduplication:       YES
Schema versioning:          YES
Security independent:       YES
Progressive loading:        YES (opt-in)
Chat / Subagent:            YES
MCP:                        audited, unchanged
Recall regression:          none (@10/@15/@20/@48 = Phase 6)
Production wire tokens:     unchanged (flag off, K=48)
Eval wire tokens K=15:      19,955 vs 42,977  (−53.6%)
```

---

## 16. Remaining Limitations

1. هر request هنوز باید tools را در body بگذارد مگر Provider cache مخصوص tools داشته باشد.
2. Flag production خاموش است؛ کاهش توکن LLM در production فعال نیست.
3. تخمین توکن از طول متن schema است، نه tokenizer مدل زنده.
4. شبیه‌سازی Progressive، tool ازقلم‌افتاده را به‌عنوان «کشف بعدی» اضافه می‌کند؛ loop واقعی LLM نیست.
5. MCP listing هنوز full catalog است.

---

## 17. Phase 8 Recommendation

ترتیب پیشنهادی:

1. **Enable progressive initial K=15 in production** — Retrieval@15 = ۹۷.۵٪؛ این تنها راه قطعی کاهش توکن سیم بدون وابستگی به Provider است.
2. **Provider tool-prefix caching** — Anthropic `cache_control` روی tools اگر API اجازه دهد؛ OpenAI official prompt cache روی بلوک پایدار شامل tools. Architecture را به یک vendor قفل نکنید.
3. **Hybrid / embeddings فقط به‌عنوان add-on روی ranker Phase 6** — برای ۲.۵٪ miss باقی‌مانده؛ جایگزین Schema Loader نیست.

پیشنهاد عملی: ابتدا (1)، بعد اندازه‌گیری توکن واقعی usage API، سپس (2).
