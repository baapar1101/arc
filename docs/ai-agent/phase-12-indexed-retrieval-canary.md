# Phase 12 — Indexed Candidate Retrieval Production Canary

**وضعیت:** Canary ۵٪ در کد روشن است. ترافیک زنده این فرآیند صفر است → **HOLD** برای ۱۰٪. Adaptive K / Hybrid / Progressive بدون تغییر.  
**تاریخ:** ۲۱ اوت ۲۰۲۶  
**نتایج:** [`evals/phase-12/latest.json`](evals/phase-12/latest.json)

> Promote indexed retrieval only on live evidence; Gold proves correctness, production proves usefulness.

> Keep Candidate Retrieval, Ranking, Adaptive K, Hybrid, and Schema Loading independently deployable.

> A fast index is valuable only if it preserves the user’s ability to complete the task.

```text
INDEXED_CANDIDATE_RETRIEVAL = False
INDEXED_CANDIDATE_ROLLOUT_PERCENT = 5
INDEXED_CANDIDATE_FALLBACK = True
ADAPTIVE_DISCOVERY_K = False
HYBRID_TOOL_DISCOVERY = False
PROGRESSIVE_SCHEMA_LOADING = False
Analyzer = 48 / Autonomous = 128
```

---

## 1. Control

رفتار Production فعلی (۹۵٪ ترافیک در این مرحله):

```text
Authorized Tool Set
        ↓
Phase 6 Ranker
        ↓
K = 48 / 128
        ↓
Current Schema Loading
```

ایندکس صدا زده نمی‌شود. Security و Ranker همان Phase 6 هستند.

---

## 2. Experiment

۵٪ پایدار (bucket < 5):

```text
Authorized Tool Set
        ↓
Indexed Candidate Retrieval (N=100)
        ↓
Phase 6 Ranker
        ↓
K = 48 / 128
        ↓
Current Schema Loading
```

فقط Candidate Generation عوض می‌شود.

---

## 3. Stable Assignment

```text
SHA256("indexed-retrieval-v1" + business_id + user_id) % 100 → bucket
bucket < INDEXED_CANDIDATE_ROLLOUT_PERCENT → experiment
```

Salt جدا از Adaptive (`adaptive-k-v1`). شناسه‌ها فقط برای bucketاند. Log: `indexed_arm`, `indexed_bucket`, `indexed_percent` — بدون user/business id.

---

## 4. Fallback

`INDEXED_CANDIDATE_FALLBACK = True`. Empty / weak / inconsistent ایندکس هرگز Request را fail نمی‌کند:

```text
Indexed search → problem → Full authorized ranker
```

هرگز Global Registry. رویداد `indexed_candidate_fallback` با:

| field | allowed |
|-------|---------|
| channel, mode, reason, candidate_count, latency | yes |
| query text, user_id, business_id, permissions | **no** |

دلایل:

| reason | معنی |
|--------|------|
| `empty_index` | پستینگ خالی |
| `low_candidate_recall_signal` | expects_tools بدون keyword/capability hit |
| `disabled_tool` | ابزار مجاز در ایندکس disable است |
| `stale_index` | refresh شکست خورد |
| `normalization` | query پس از نرمال‌سازی توکن ندارد |
| `index_inconsistency` | Manifest ⊄ Index |
| `unknown` | سایر |

`index_consistency_failure` جدا ثبت می‌شود. Stale: `search_text_hash` عوض شود → upsert قبل از retrieve.

---

## 5. Metrics

حداقل:

```text
requests, indexed_requests, fallback_requests,
indexed_retrieval_miss, tool_discovery_miss, schema_miss,
unknown_tool, rediscovery,
tool_call_success, tool_call_failure,
task_completion (first-pass without rediscovery),
discovery latency, request latency
```

به‌علاوه: `candidate_index_hit` / `empty` / `indexed_candidate_fallback` / `unauthorized_candidate`.

Task completion زنده = first-pass success بدون rediscovery. از Recall آفلاین مهم‌تر است.

---

## 6. Security

```text
unauthorized candidate = 0
unauthorized rediscovery = 0
permission bypass = 0
```

هر bypass → **IMMEDIATE ROLLBACK**. Fallback هم فقط Authorized Set است. Kill switch Adaptive/Hybrid/Schema را عوض نمی‌کند.

---

## 7. Task Completion

سیگنال: `indexed_first_pass.{arm}.success / total`.

تا ۵۰۰ نمونه در هر بازو، مقایسهٔ آماری **HOLD** است. اگر Discovery خوب باشد ولی task completion افت معنادار داشته باشد → **ROLLBACK** (Case C).

---

## 8. Latency

Gold bench (۱۰k tools، همان Phase 11):

| | p50 | p95 |
|--|-----|-----|
| Control linear rank | 110.8ms | 112.5ms |
| Indexed + rank N=100 | 6.1ms | 6.6ms |

Live: `discovery_latency` و `request_latency` با p50 / p95 / p99 per arm. هدف: end-to-end بدون regression، نه فقط lookup سریع.

این فرآیند: live p50/p95/p99 = n/a (۰ درخواست).

---

## 9. Channel Analysis

Channelها جدا شمارش می‌شوند: `chat`, `subagent`, `crm`, `ticket`, `workflow`.

Live breakdown: خالی تا ترافیک واقعی برسد.

---

## 10. High-Risk Analysis

Mutation جدا: `read` / `write` / `destructive` (delete) / `export` / `execute`.

Write tools از `protected_names` وارد ranker می‌شوند حتی اگر ایندکس آن‌ها را ته لیست بگذارد. تست: `create_invoice` در Control و Experiment هست.

Live high-risk success: n/a.

---

## 11. Results

| | Value |
|--|-------|
| Canary | 5% stable SHA256 |
| Control live requests | 0 |
| Experiment live requests | 0 |
| Indexed retrieval miss | 0 |
| Fallback rate | n/a live (Gold empty→fallback, not fail) |
| Rediscovery | 0 |
| Task completion | n/a live |
| Tool execution | n/a live |
| Security regressions | 0 (tests) |
| Gold Candidate Recall@100 | 100% |
| Gold Final Recall indexed = full ranker | identical |

---

## 12. Statistical Analysis

Wilson 95% CI برای نرخ‌ها (`compare_rate`). قبل از n≥۵۰۰ در هر بازو: `enough_for_significance = false` → **HOLD**. میانگین تنها کافی نیست.

---

## 13. Promotion Gate

بعد از ۵۰۰ نمونه / بازو:

| Gate | Rule |
|------|------|
| A Security | no bypass |
| B Task | no meaningful regression |
| C Discovery | `indexed_retrieval_miss` acceptable |
| D Fallback | fallback_rate acceptable |
| E Latency | p95 does not regress |

الان: **HOLD** (`need_500_per_arm`).

Case A healthy → ۱۰٪. Case B miss بالا → HOLD/investigate. Case C task drop → ROLLBACK. Case D security → IMMEDIATE ROLLBACK.

مراحل: `0 → 5 → 10 → 25 → 50 → 100`. این Phase فقط ۰→۵ را باز کرد.

---

## 14. Rollback

بدون deploy کد:

```text
HESABIX_INDEXED_CANDIDATE_KILL=1
# or
HESABIX_INDEXED_CANDIDATE_RETRIEVAL=0
# or
HESABIX_INDEXED_CANDIDATE_ROLLOUT_PERCENT=0
```

ثابت `INDEXED_CANDIDATE_RETRIEVAL = False` یعنی **نه ۱۰۰٪**؛ canary از percent است. Kill مستقل Adaptive K / Hybrid / Progressive را لمس نمی‌کند.

---

## 15. Adaptive K Status

**HOLD.** `ADAPTIVE_DISCOVERY_K = False`, `ADAPTIVE_K_ROLLOUT_PERCENT = 0`. حتی اگر Indexed به ۱۰۰٪ برسد، Adaptive جدا می‌ماند.

---

## 16. Phase 13 Recommendation

1. جمع‌آوری ≥۵۰۰ discovery زنده در Control و Experiment.
2. Gate A–E + Wilson CI.
3. اگر سالم → ۱۰٪. اگر نه → HOLD یا ROLLBACK به ۰٪.
4. Adaptive K را در این داده قاطی نکن.
5. Hybrid و Progressive خاموش بمانند.
