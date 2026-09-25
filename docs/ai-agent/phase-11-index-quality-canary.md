# Phase 11 — Candidate Index Quality Hardening & Independent Canary

**وضعیت:** Metadata پنج miss پوشش داده شد. Candidate Recall@100 = ۱۰۰٪. Canary ایندکس در کد آماده است و Production روی ۰٪ مانده. Adaptive K همچنان HOLD. Hybrid OFF.  
**تاریخ:** ۲۱ اوت ۲۰۲۶  
**نتایج:** [`evals/phase-11/latest.json`](evals/phase-11/latest.json)  
**Dataset:** `2026-08-19.v1` (بدون تغییر Gold)

> Do not compensate for metadata gaps by making the candidate pool larger. Fix coverage, then keep the index small and fast.

> Candidate retrieval may reduce the search universe, but the existing ranker remains the authority for relevance.

> Candidate indexing, Adaptive K, Hybrid Search, and Schema Loading are independent control planes.

Production flags بعد از این Phase:

```text
PROGRESSIVE_SCHEMA_LOADING = False
ADAPTIVE_DISCOVERY_K = False
ADAPTIVE_K_ROLLOUT_PERCENT = 0
HYBRID_TOOL_DISCOVERY = False
INDEXED_CANDIDATE_RETRIEVAL = False
INDEXED_CANDIDATE_ROLLOUT_PERCENT = 0
VECTOR_CANDIDATE_RETRIEVAL = False
Analyzer = 48 / Autonomous = 128
```

---

## 1. Five Metadata Misses

Phase 10 روی N=۲۰/۵۰/۱۰۰/۲۰۰ اشباع شد (۹۸.۸۷٪). پنج miss باقی‌مانده **Metadata Gap** بودند نه کمبود ظرفیت ایندکس. Gold عوض نشد.

| Gold | Query | Tool | Classification | Why the index missed |
|------|-------|------|----------------|----------------------|
| `ppl-05` | مانده حساب علی چقدر است | `get_person_balance` | missing alias / keyword | توکن `مانده` در search text نبود. دامنه `people` بود؛ intent اغلب `financial` است پس domain expansion هم کمکی نمی‌کرد. |
| `acc-21` | لیست ارزها | `list_currencies` | missing alias + query parsing | Alias فقط `ارز` بود؛ stemming نداریم پس `ارزها` جدا است. UI label همان «لیست ارزها» است. `expects_tools` برای query کوتاه False بود. Tokenizer بازنویسی نشد. |
| `hard-gen-01` | یک گزارش کلی از اوضاع بده | `get_business_dashboard` | wrong domain + missing keyword | دامنه فقط `financial` بود در حالی که capability `reports.overview` است. Alias فقط داشبورد؛ `گزارش کلی` / `اوضاع` نبود. |
| `plat-01` | اطلاعات این کسب‌وکار | `get_business_info` | missing alias | UI «اطلاعات کسب‌وکار». ZWNJ، `کسب‌وکار` را به `کسب` + `وکار` می‌شکند و `اطلاعات` در search text نبود. |
| `exp-158` | اطلاعات کسب‌وکار نشست | `get_business_info` | missing alias | همان شکاف `plat-01`. |

جزئیات هر Tool قبل از Fix:

| Tool | capability | domain | namespace | ranking |
|------|------------|--------|-----------|---------|
| `get_person_balance` | `people.person` | `people` | `people` | Phase 6 lexical؛ بدون همپوشانی توکن با query |
| `list_currencies` | `financial.currency` | `financial`, `products_write` | `financial` | بدون توکن `ارزها` |
| `get_business_dashboard` | `reports.overview` | `financial` | `reports` | `گزارش` به ابزارهای گزارش فروش می‌رسید نه داشبورد |
| `get_business_info` | `platform.settings` | `misc` | `platform` | بدون `اطلاعات` |

Gold این پنج query درست است. Dataset version افزایش نیافت.

---

## 2. Metadata Fixes

فقط پوشش زبان واقعی اضافه شد. Alias/example ساختگی انباشته نشد. `گزارش` برهنه به داشبورد اضافه نشد تا با `get_sales_report` و تست گردش‌کار تداخل نکند.

| Tool | Change |
|------|--------|
| `get_person_balance` | alias: `مانده حساب`, `مانده شخص` · keyword: `مانده` · example: query طلایی |
| `list_currencies` | alias: `ارزها`, `لیست ارزها` در کنار `ارز` / `currency` / `واحد پول` |
| `get_business_dashboard` | domain: `financial` + `reports_meta` · keyword: `گزارش کلی`, `اوضاع`, `خلاصه وضعیت`, `نمای کلی` · examples شامل query طلایی |
| `get_business_info` | alias: `اطلاعات کسب‌وکار`, `مشخصات کسب‌وکار` · keyword: `اطلاعات` · example: `اطلاعات این کسب‌وکار` |

Pipeline بعد از Fix:

```text
Registry / Manifest  →  Search Meta merge  →  search_text  →  inverted postings
```

Rebuild کامل و incremental upsert برای کاتالوگ آزمایشی معادل شدند.

---

## 3. Candidate Recall

پس از Fix، روی ۴۴۳ query دارای gold label (بدون no-match):

| N | Phase 10 | Phase 11 |
|---|----------|----------|
| 20 | 94.58% | **95.49%** |
| 50 | 98.65% | **99.55%** |
| 100 | 98.87% | **100.00%** |
| 200 | 98.87% | **100.00%** |

هدف `Candidate Recall@100 >= 99%` رسید. Miss@100 = ۰. N بزرگ‌تر نشد (`CANDIDATE_RETRIEVAL_N = 100`).

پنج miss قبلی همگی در مجموعهٔ کاندیدا@۱۰۰ هستند و rank ایندکس آن‌ها ۱ است.

---

## 4. Index Consistency

سه مسیر برای کاتالوگ شش‌تایی (`search_invoices`, `list_accounts`, `get_person_balance`, `list_currencies`, `get_business_dashboard`, `get_business_info`):

| Path | Result |
|------|--------|
| Full rebuild (`load_many`) | مرجع |
| Incremental upsert | معادل |
| Incremental disable + re-enable | معادل |

Property tests: Unicode ی/ي ک/ك ZWNJ، alias تکراری، metadata خالی، disable/deprecate، collision هم‌نام، `is_stale` روی version.

---

## 5. Candidate vs Ranker Contract

```text
Candidate Index
    ↓  must maximize candidate recall
Final Ranker (Phase 6)
    ↓  must maximize relevance
Adaptive K
    ↓  controls final tool surface   (HOLD / off)
Schema Loader
    ↓  controls LLM context          (off)
Security
    ↓  authorizes everything         (before index)
```

ایندکس فقط Candidate Generator است. `discover_tools(apply_indexed=True)` کاندیدا را تنگ می‌کند؛ Top-K نهایی همچنان `score_tool_for_query` / `rank_and_cap` است. Adaptive K و Hybrid از این مسیر روشن نمی‌شوند.

---

## 6. Canary Architecture

Canary فقط `INDEXED_CANDIDATE_RETRIEVAL` را عوض می‌کند (از طریق percent مستقل، نه flag سراسری).

```text
SHA256("indexed-retrieval-v1" + business_id + user_id) % 100
        ↓
   bucket < INDEXED_CANDIDATE_ROLLOUT_PERCENT
```

Salt جدا از Adaptive (`adaptive-k-v1`) است. شناسه‌ها فقط برای assignmentاند و لاگ نمی‌شوند.

`AIService.get_available_functions` هر دو assignment را جدا resolve می‌کند:

```text
apply_adaptive=assignment.enabled
apply_indexed=indexed.enabled
```

---

## 7. Control / Experiment

```text
Control
  Authorized Set → Phase 6 Ranker over full authorized set → K=48/128

Experiment
  Authorized Set → Indexed Candidate Retrieval (N=100)
                 → Phase 6 Ranker → K=48/128
```

فقط Candidate Generation فرق می‌کند. Ranker، Adaptive K، Hybrid، Schema Loader دست‌نخورده‌اند.

---

## 8. Fallback

فقط برای Canary (`INDEXED_CANDIDATE_FALLBACK = True`):

```text
Indexed Candidate Search
       ↓
No / low candidate
       ↓
Fallback to existing full authorized ranker
```

Silent failure نیست. Fallback هرگز Global Registry را به Ranker نمی‌دهد؛ همان Authorized Set است.

رویدادها:

- `candidate_index_hit`
- `candidate_index_empty`
- `candidate_index_fallback`

---

## 9. Security

```text
Global Index  →  Authorized Set  →  Candidate Retrieval
```

ایندکس permission نگه نمی‌دارد. Tool غیرمجاز وارد candidate set نمی‌شود. Disable از postings حذف می‌کند؛ Deprecate از active candidates؛ Re-enable postings را برمی‌گرداند.

`indexed_retrieval_miss` جدا از `retrieval_miss` (قطع Top-K / Adaptive K) است: ابزار مجاز در stage-1 ایندکس نبود و fallback هم رخ نداد.

---

## 10. Latency

Control = rank خطی روی کل کاتالوگ. Experiment = lookup ایندکس + rank روی N=۱۰۰.

| Size | Control p50 | Control p95 | Indexed p50 | Indexed p95 |
|------|-------------|-------------|-------------|-------------|
| 180 | 7.8ms | 8.1ms | 3.4ms | 3.5ms |
| 1,200 | 18.6ms | 18.8ms | 3.9ms | 3.9ms |
| 5,000 | 58.8ms | 61.1ms | 4.6ms | 4.8ms |
| 10,000 | 110.8ms | 112.5ms | 6.1ms | 6.6ms |

هدف سریع‌تر کردن Ranker نبود. هدف این است Ranker روی کل کاتالوگ اجرا نشود. در ۱۰k ایندکس ≈ O(lookup) می‌ماند؛ کنترل ≈ O(N).

---

## 11. Live Metrics

نمونه زنده هنوز صفر است. آستانهٔ تصمیم: `INDEXED_CANDIDATE_MIN_LIVE_SAMPLES = 500` در هر بازو.

متریک‌های آماده:

- `retrieval_latency`, `candidate_count`, `final_tool_count`
- `tool_discovery_miss`, `schema_miss`, `unknown_tool`, `rediscovery`
- `tool_execution_success` / `tool_execution_failure`
- `candidate_index_hit` / `empty` / `fallback`
- `indexed_retrieval_miss` (جدا از Adaptive K miss)

---

## 12. Results

| Gate | Value |
|------|-------|
| Five metadata misses | resolved (all hit@100, index rank 1) |
| Candidate Recall@100 | **100%** (>= 99%) |
| Final Recall@10/15/20/48 indexed | 96.16 / 98.19 / 98.87 / 98.87 |
| Same-metadata full ranker | identical — no index/ranker-boundary regression |
| vs Phase 6 baseline | improved (metadata), not degraded |
| Incremental consistency | PASS |
| Security tests | PASS |
| Gold dataset | unchanged `2026-08-19.v1` |

Final Recall نسبت به Phase 6 بالا رفته چون پوشش متادیتا بهتر شده، نه چون N بزرگ شده. Indexed و Control روی همان متادیتا برابرند.

---

## 13. Rollout Decision

**Gold: Case A.** Candidate Recall ≥ ۹۹٪ و Final Recall پایدار.

**Live: HOLD at 0%.** متریک زنده نیست؛ مثل Phase 9 بدون ترافیک promote نمی‌شود.

پیشنهاد stage بعد از مشاهدهٔ زنده:

```text
0%  →  5%  →  10%  →  25%  →  50%  →  100%
```

هر stage فقط بعد از بررسی stage قبلی. Flag سراسری `INDEXED_CANDIDATE_RETRIEVAL` خاموش می‌ماند تا percent عمداً بالا برود.

---

## 14. Adaptive K Status

**HOLD.** `ADAPTIVE_K_ROLLOUT_PERCENT = 0`. این Phase دربارهٔ Adaptive K تصمیم نمی‌گیرد.

---

## 15. Hybrid Status

**OFF.** `HYBRID_TOOL_DISCOVERY = False`. وجود زیرساخت vector/ANN به معنی روشن بودن Hybrid نیست.

---

## 16. Phase 12 Recommendation

1. Canary زندهٔ Indexed Retrieval از ۵٪ با fallback و `indexed_retrieval_miss` جدا.
2. اگر fallback و discovery miss در ۵٪ سالم بود، ۱۰٪ سپس ۲۵٪.
3. Adaptive K را فقط بعد از دادهٔ زندهٔ Phase 9 جدا بررسی کن.
4. برای ۱۰۰k: فشرده‌سازی posting / shard، نه بزرگ کردن N.
5. Hybrid را canary نکن مگر lexical miss باقی‌مانده پس از metadata ثابت شود.
