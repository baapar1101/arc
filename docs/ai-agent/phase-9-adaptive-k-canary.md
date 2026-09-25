# Phase 9 — Adaptive K Canary, Live Discovery Telemetry & Production Validation

**وضعیت:** زیرساخت Canary و Telemetry در کد است. Flagهای production خاموش‌اند. تصمیم از روی ترافیک زنده: **HOLD**.  
**تاریخ:** ۲۱ اوت ۲۰۲۶  
**نتایج:** [`evals/phase-9/latest.json`](evals/phase-9/latest.json) · [`evals/tool-scale/latest.json`](evals/tool-scale/latest.json)

> Do not promote Adaptive K because offline Recall is good. Promote it only when real task completion, discovery misses, schema tokens, latency, and security remain acceptable in production traffic.

> Hybrid فعلی از Keyword بهتر نیست و در این Phase Canary نمی‌شود.

---

## 1. Phase 8 Baseline (بدون تغییر)

| | مقدار |
|--|--|
| Tools | ۱۸۰ |
| Keyword Recall@10 | ۹۵.۴۹٪ |
| Keyword Recall@15 | ۹۷.۵۲٪ |
| Keyword Recall@20 / @48 | ۹۸.۱۹٪ |
| Adaptive tight (Gold) | Recall ۹۶.۶۱٪ · Avg K ≈ ۱۰.۱۹ |
| Hybrid @15 | ۹۶.۳۹٪ — **بدتر از Keyword** |
| Production K | Analyzer=۴۸ / Autonomous=۱۲۸ |

Gold ضروری است، کافی نیست. Offline Recall ≠ Production Tool Discovery Success.

---

## 2. Production defaults (امن)

قبل و بعد از این Phase، پیش‌فرض‌ها:

```text
PROGRESSIVE_SCHEMA_LOADING = False
ADAPTIVE_DISCOVERY_K = False
ADAPTIVE_K_ROLLOUT_PERCENT = 0
HYBRID_TOOL_DISCOVERY = False
```

هیچ Flagی Global روشن نشد. Hybrid Canary ندارد.

دو Flag جدا می‌مانند تا اثرشان قاطی نشود:

```text
ADAPTIVE_DISCOVERY_K          # سیاست K
PROGRESSIVE_SCHEMA_LOADING    # Schema کمتر از Discovery K
```

---

## 3. Canary architecture

```text
hash_sha256(salt + business_id + user_id) % 100  → bucket 0–99
bucket < ADAPTIVE_K_ROLLOUT_PERCENT              → experiment (Adaptive K)
else                                             → control (K=48/128)
```

- Assignment برای همان Tenant+User پایدار است. بین K=۴۸ و K=۱۰ تصادفی جابه‌جا نمی‌شود.
- شناسه‌ها فقط برای bucket مصرف می‌شوند؛ در Log نیستند (`adaptive_arm`, `adaptive_bucket`, `adaptive_percent`).
- مراحل مجاز: `0 → 5 → 10 → 25 → 50 → 100`. مقدار نامعتبر **به پایین** گرد می‌شود (۷→۵، ۳→۰).
- تفاوت بازوها فقط **سیاست K** است. Ranker، Security، Hybrid، Progressive بدون تغییر می‌مانند.
- `ADAPTIVE_DISCOVERY_K=True` کل ترافیک را experiment می‌کند — الان False است.
- حداقل نمونه زنده قبل از هر توصیهٔ promote: `ADAPTIVE_K_MIN_LIVE_SAMPLES = 500` در **هر بازو**.

کد: `ai_tool_canary.py` · `discover_tools(..., apply_adaptive=assignment.enabled)`.

---

## 4. Control vs Experiment

| | Control | Experiment |
|--|---------|------------|
| Retrieval | Keyword/intent فعلی | همان |
| Security | همان gate | همان |
| Hybrid | OFF | OFF |
| K | ۴۸ / ۱۲۸ | Adaptive tight (≈۱۰/۱۵/۲۰) |
| Schema | همان K | همان K آزمایش (Progressive جدا و خاموش) |

Agent نباید رفتار متفاوتی به‌خاطر assignment غیرمرتبط نشان دهد.

---

## 5. Telemetry (بدون دادهٔ مالی / متن Query)

هر Discovery زنده (`tool_discovery_live`):

```text
adaptive_enabled, recommended_k, effective_k,
top_score, second_score, score_gap,
candidate_count, schema_count, schema_tokens,
channel, mutation, capability, confidence_level,
strategy, query_hash, latency_ms
```

`effective_k` و `schema_tokens` از **مجموعهٔ واقعی روی سیم** می‌آیند، نه از cache hint ارائه‌دهنده.

رویدادهای typed جدا (یک Event واحد نیستند):

| Event | معنی |
|-------|------|
| `retrieval_miss` | Tool لازم در ranked candidate نبود |
| `schema_miss` | در ranked بود، Schema در context نبود |
| `authorization_failure` | Tool غیرمجاز / خارج از permission |
| `unknown_tool` | نام در Registry نیست |
| `tool_discovery_miss` | فقط umbrella برای retrieval+schema |
| `tool_rediscovery` | صف نوبت بعد (حداکثر ۱) |
| `rediscovery_recovered` / `rediscovery_failed` | نتیجهٔ همان miss |
| `tool_execution_success` / `execution_failure` | نتیجهٔ اجرای واقعی |

Privacy: بدون `user_id` / `business_id` / `session_id` / متن query / payload مالی. Tool names، scores، intent/capability، latency مجازند.

KPI اصلی Canary:

```text
Discovery Success WITHOUT Rediscovery
```

یعنی K کوچک + درست + بدون round-trip اضافه. Task Completion زنده مهم‌تر از Recall خام است.

---

## 6. Rediscovery و امنیت

```text
LLM asks for X
  ├─ not in registry → unknown_tool, no rediscovery
  ├─ unauthorized    → authorization_failure, no rediscovery
  ├─ authorized, not ranked → retrieval_miss → queue (max 1)
  └─ ranked, schema missing → schema_miss → queue (max 1)
```

- Tool مجاز ولی unoffered = **Discovery failure** نه Security failure.
- Tool غیرمجاز هرگز برای «موفق شدن Agent» وارد Discovery/Rediscovery نمی‌شود.
- `max_discovery_retries = 1`.
- `rediscovery_recovery_rate = recovered / queued`.

---

## 7. Segmentation

Live telemetry کانال را نگه می‌دارد: `chat` / `subagent` / `crm` / `ticket` / `workflow`.

High-risk: `mutation` در `{write, destructive, export, execute}`. کاهش K نباید Safety یا Approval coverage را کم کند.

طبقه‌بندی business (simple / power / large / high-tool-usage) در محصول تعریف نشده — Gold فقط `difficulty` و `category` را به‌عنوان proxy آفلاین دارد.

---

## 8. Gold proxy (نه ترافیک زنده)

Control = discover @۴۸. Experiment = همان لیست، truncate با tight.

این **Recall retrieval** است نه Task Completion مدل. Schema miss زنده در Gold صفر است چون Schema Loader در eval اجرا نمی‌شود.

جزئیات عددی: [`evals/phase-9/latest.json`](evals/phase-9/latest.json).

Live در این محیط: **۰ درخواست** → تصمیم خودکار **HOLD**. هیچ آستانهٔ کیفیت ساختگی hardcode نشد.

---

## 9. Index study (فقط Benchmark / معماری)

Semantic linear در ۱۰k ≈ ۲s (Phase 8). برای ۵k+ این‌ها گزینه‌اند، هیچ‌کدام Production نشد:

| گزینه | نقش |
|--------|------|
| A. Inverted keyword | Prototype در `ai_tool_scale_bench` — candidate gen واژه‌ای |
| B. PostgreSQL GIN / trigram | فازی روی metadata موجود؛ ANN نیست |
| C. pgvector ANN | فقط با embedding واقعی؛ n-gram فعلی کافی نیست |
| D. HNSW | لازم اگر semantic در ۵k+ بخواهیم |
| E. Hybrid inverted + vector | هدف Phase 10: inverted → ANN → ranker فعلی → Adaptive K → Progressive Schema → LLM |

Semantic روی ۱۰k Tool Production نرفت.

---

## 10. Rollout gate

ارتقای درصد فقط با نمونهٔ کافی **و** مقایسهٔ Control/Experiment روی:

Recall proxy · Miss rate · Rediscovery · Unknown tool · Task success · Execution success · Average K · Schema tokens/request · Latency · High-risk · Channel

بدون baseline زنده، درصد را بالا نبرید. Canary را با تعداد درخواست بسنجید نه فقط با روزهای تقویم.

---

## 11. تصمیم این Phase

**HOLD** — زیرساخت آماده است؛ ترافیک Canary صفر است. Gold tight هنوز Case A را *پیشنهاد* می‌کند (هزینه کمتر، Recall≥۹۵٪) ولی اصل Phase 9 ترافیک واقعی است.

Hybrid: **OFF**. Phase 10 اگر Adaptive در Production موفق شد: **Scalable Tool Index** نه tuning دوبارهٔ Hybrid.

---

## 12. Files

| فایل | نقش |
|------|------|
| `ai_tool_canary.py` | bucket پایدار، درصد، assignment |
| `ai_tool_discovery_telemetry.py` | نمونه‌ها، miss typed، snapshot |
| `ai_tool_rollout.py` | rediscovery typed؛ Progressive جدا |
| `ai_tool_discovery.py` | `apply_adaptive` بدون تغییر ranker |
| `ai_service.py` | resolve assignment → discover → live metrics |
| `ai_tool_phase9_eval.py` | Control vs Adaptive روی Gold |
| `ai_tool_scale_bench.py` | keyword / inverted / semantic تا ۱۰k |
