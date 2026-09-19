# Phase 13 — Production Evidence Gate for Indexed Retrieval

**وضعیت:** Canary ۵٪ مسلح است. ترافیک زنده این فرآیند **صفر** است → **HOLD**. Promotion به ۱۰٪ ممنوع است. Adaptive K / Hybrid / Progressive خاموش می‌مانند.  
**تاریخ:** ۲۱ اوت ۲۰۲۶  
**نتایج:** [`evals/phase-13/latest.json`](evals/phase-13/latest.json)

> No live evidence, no promotion.

> Gold proves the design is plausible; production evidence proves the feature is safe and useful.

> Candidate indexing must be independently measurable from ranking, Adaptive K, Hybrid Search, and Schema Loading.

```text
INDEXED_CANDIDATE_RETRIEVAL = False
INDEXED_CANDIDATE_ROLLOUT_PERCENT = 5
INDEXED_CANDIDATE_FALLBACK = True

ADAPTIVE_DISCOVERY_K = False
HYBRID_TOOL_DISCOVERY = False
PROGRESSIVE_SCHEMA_LOADING = False

Final K: Analyzer = 48 / Autonomous = 128
Candidate N = 100
```

این Phase معماری Retrieval جدید نمی‌سازد. Hybrid، embedding، Adaptive K، Progressive Schema و تغییر N ممنوع‌اند.

---

## 1. Production Evidence Model

دو منبع کاملاً جدا:

| منبع | برچسب | چه چیزی را ثابت می‌کند |
|------|--------|-------------------------|
| Offline Gold | `offline_gold` | طراحی قابل‌قبول است (Recall روی مجموعهٔ برچسب‌خورده) |
| Production Live | `production_live` | ویژگی روی ترافیک واقعی امن و مفید است |

```text
Gold Recall@100 = 100%     ← فقط Offline Gold
Production Recall@100      ← وجود ندارد مگر از ترافیک زنده اندازه‌گیری شود
```

هرگز Gold را به‌جای Production گزارش نکن. در این فرآیند Live Control = 0 و Live Experiment = 0؛ نرخ‌ها `null` هستند نه صفرِ ساختگی.

۱۰k bench (~۶ms indexed / ~۱۱۰ms full rank) فقط **Offline Performance Evidence** است.

Indexing ≠ کاهش توکن. K هنوز ۴۸/۱۲۸ است. Indexing باید latency retrieval، CPU و مقیاس را بهتر کند. توکن بعداً با Adaptive K + Progressive Schema.

---

## 2. Control / Experiment

Assignment پایدار است و بین درخواست‌ها عوض نمی‌شود:

```text
SHA256("indexed-retrieval-v1" + business_id + user_id) % 100 → bucket
bucket < INDEXED_CANDIDATE_ROLLOUT_PERCENT → experiment
```

Salt = `indexed-retrieval-v1`. مستقل از Adaptive (`adaptive-k-v1`). تغییر Salt = آزمایش جدید.

| Arm | رفتار |
|-----|--------|
| Control | Authorized set → Phase 6 Ranker → K=48/128 |
| Experiment | Authorized set → Indexed N=100 → همان Ranker → همان K |

شناسه‌ها لاگ نمی‌شوند. Kill switch بدون restart کد: `HESABIX_INDEXED_CANDIDATE_KILL=1` → همان tenant/user به Control برمی‌گردد.

---

## 3. Exposure

هر درخواست زنده یک رویداد:

```text
indexed_candidate_exposure
```

فیلدها: `arm`, `channel`, `mode`, `effective_candidate_retrieval`.

ذخیره نمی‌شود: `user_id`, `business_id`, متن کامل query، دادهٔ مالی.

`effective_candidate_retrieval`:

- `indexed` — ایندکس مجموعهٔ قابل‌استفاده داد
- `full_authorized` — Control، یا Experiment پس از Fallback

---

## 4. Telemetry

شمارنده‌های زنده:

```text
control_requests
experiment_requests
experiment_enabled_requests
experiment_fallback_requests
```

وضعیت ایندکس (جدا از Adaptive K `retrieval_miss`):

| Event | معنی |
|-------|------|
| `indexed_retrieval_hit` | مجموعهٔ کاندید قابل‌استفاده از ایندکس |
| `indexed_retrieval_miss` | ابزار لازم در candidate set نبود |
| `indexed_retrieval_empty` | ایندکس نتیجهٔ خالی داد |
| `indexed_retrieval_stale` | ایندکس کهنه / غیرقابل‌استفاده |

Fallback reasons (کاننیکال Phase 13):

```text
empty | low_candidate_quality | stale_index | index_error | index_inconsistency | unknown
```

`fallback_rate` و `fallback_reason` ثبت می‌شوند.

**Fallback Success ≠ Index Success**

```text
Index Miss / empty → Fallback → Task Success
task_success = TRUE
index_success = FALSE
```

هر دو همزمان مجازند. تکمیل Task را با موفقیت Retrieval یکی نکن.

Task completion مصنوعی ساخته نمی‌شود. فقط سیگنال‌های موجود:

- first-pass بدون rediscovery (`tool execution` مسیر)
- موفقیت اجرای ابزار
- در آینده: workflow completion / explicit agent success / user confirmation اگر واقعاً موجود باشند

اگر سیگنالی نباشد، `task_success = null`.

Latency جدا:

```text
discovery_latency | index_latency | rank_latency | total_ai_request_latency
p50 / p95 / p99 per arm
```

هدف اصلی end-to-end است، نه فقط lookup ایندکس.

`candidate_count` (معمولاً نزدیک N=100 یا کمتر) جدا از `final_tool_count` (K نهایی روی سیم).

کانال‌ها: `chat` / `subagent` / `crm` / `ticket` / `workflow`.

عملیات پرخطر per arm: `delete` / `write` / `export` / `execute` / `financial_mutation` × `success` / `failure` / `approval` / `unexpected_rejection`.

Health:

```text
tool_index_health:
  active_tool_count
  indexed_tool_count
  stale_tool_count
  disabled_tool_count
  last_refresh
  healthy
```

اگر ایندکس ناسالم باشد (مثلاً `last_refresh` صفر یا inconsistency) → fallback به full authorized rank.

قرارداد رویداد Production (privacy-safe):

```text
timestamp, arm, channel, mode, candidate_count, final_tool_count,
index_hit, index_miss, fallback, fallback_reason,
discovery_miss, schema_miss, tool_execution_success,
task_success, index_success, latency, effective_candidate_retrieval
```

---

## 5. Security Gate (Gate A)

```text
authorization bypass = 0
tenant leakage = 0
permission violation = 0
```

هر مقدار غیرصفر → **IMMEDIATE ROLLBACK** (Case D). Fallback هرگز Global Registry نیست.

---

## 6. Task Gate (Gate B)

Control و Experiment با دو نسبت (Wilson score interval، ۹۵٪) مقایسه می‌شوند.

آستانهٔ درصدی ساختگی («اگر ۵٪ افت کرد») استفاده نمی‌شود.

پس از `n ≥ 500` در هر بازو: اگر CI آزمایش کاملاً زیر CI کنترل باشد و نرخ آزمایش کمتر باشد → **ROLLBACK** (Case C).

قبل از ۵۰۰ نمونه: **HOLD**.

---

## 7. Retrieval Gate (Gate C)

`indexed_retrieval_miss_rate` جدا از `tool_discovery_miss` / Adaptive `retrieval_miss` گزارش می‌شود.

این Metric موفقیت ایندکس را می‌سنجد، نه موفقیت Ranker یا Schema.

---

## 8. Fallback Gate (Gate D)

اگر Fallback زیاد باشد، ایندکس سریع که اکثر درخواست‌ها را به full rank برمی‌گرداند موفقیت نیست.

پس از ۵۰۰ نمونه: اگر حد پایین CI نرخ Fallback آزمایش `> 0.5` باشد → **HOLD** و اصلاح ایندکس (Case B). آستانهٔ درصدی اختیاری دیگر ساخته نمی‌شود.

---

## 9. Latency Gate (Gate E)

مقایسه:

```text
Control p95 vs Experiment p95
Control p99 vs Experiment p99
```

اگر Experiment p95 از Control p99 بدتر باشد (پس از نمونهٔ کافی) → **HOLD**. ROLLBACK به‌خاطر latency تنها نیست.

هدف: end-to-end. ۱۰k bench آفلاین جایگزین Production latency نمی‌شود.

---

## 10. Kill Switch

```text
HESABIX_INDEXED_CANDIDATE_KILL=1
```

یا `HESABIX_INDEXED_CANDIDATE_RETRIEVAL=0`. Adaptive K / Hybrid / Schema را عوض نمی‌کند. بدون restart غیرضروری: assignment در هر درخواست خوانده می‌شود.

```text
canary active → kill switch → requests become control
```

---

## 11. Rollout

```text
5% → 10% → 25% → 50% → 100%
```

نردبان مستقل است. `propose_indexed_rollout` ثابت‌ها را نمی‌نویسد. **Auto-promotion ممنوع است.** Promotion فقط با تصمیم صریح اپراتور (`INDEXED_CANDIDATE_ROLLOUT_PERCENT`).

حداقل قبل از هر پله: **۵۰۰ live request در هر بازو**.

---

## 12. Statistical Method

- نسبت‌ها: Wilson score interval با `z=1.96` (۹۵٪).
- مقایسهٔ دو بازو: همپوشانی CI؛ regression معنادار = CI آزمایش کاملاً زیر کنترل و `delta < 0`.
- `enough_for_significance` فقط وقتی هر بازو `n ≥ 500`.
- بدون آستانهٔ درصدی اختراعی برای «چند درصد افت مجاز است».

---

## 13. Privacy

رویدادها و snapshot نباید شامل این‌ها باشند:

- `user_id` / `business_id` / `session_id`
- متن query
- مبلغ، شناسهٔ فاکتور/شخص، ایمیل، تلفن

Assignment از شناسه استفاده می‌کند ولی آن‌ها را لاگ نمی‌کند.

---

## 14. Current Status

این فرآیند / این محیط:

| Metric | Value |
|--------|--------|
| Live control | 0 |
| Live experiment | 0 |
| Exposure | 0 |
| Indexed hit/miss/fallback rates | null (no live samples) |
| Task completion | null (no live signal) |
| Tool execution success | null |
| Security | clean (0 bypass in this process) |
| p50 / p95 / p99 | null |
| Index health | manifest vs postings (offline-observable) |
| Kill switch | armed (`HESABIX_INDEXED_CANDIDATE_KILL=1` works) |
| Current rollout | **5%** |
| Promotion | **HOLD** |
| Adaptive K | **OFF** |
| Hybrid | **OFF** |
| Progressive Schema | **OFF** |

---

## 15. Promotion Criteria

قبل از ۵٪ → ۱۰٪:

```text
>= 500 control
>= 500 experiment
Security clean
Task no material regression (Wilson CI)
Fallback acceptable
Index miss acceptable (reported, not substituted)
p95 acceptable
Explicit operator decision
```

اگر همه برقرار باشند، helper حداکثر `REVIEW` + `allow_operator_promote` می‌دهد — **هرگز auto-promote نمی‌کند**.

---

## 16. Rollback Criteria

| Case | معنی | اقدام |
|------|------|--------|
| A | Healthy + ۵۰۰/بازو + Gateها | اجازهٔ Promotion به ۱۰٪ با تصمیم صریح |
| B | مشکل ایندکس / Fallback زیاد / latency بد | HOLD و اصلاح ایندکس |
| C | افت معنادار Task Success | ROLLBACK |
| D | Security / tenant leakage / permission | IMMEDIATE ROLLBACK |

---

## 17. Next Phase

Phase 14 فقط بعد از **شواهد زنده** معنا دارد: جمع‌آوری ترافیک واقعی روی Canary ۵٪، پر کردن Gateها، سپس تصمیم صریح برای ۱۰٪.

تا آن زمان:

- Adaptive K را روشن نکن (حتی اگر Indexed به ۱۰۰٪ برسد؛ آزمایش جدا است).
- Hybrid و Progressive را روشن نکن.
- N را عوض نکن.
- Gold را به‌جای Production مصرف نکن.

Recommended Phase 14: **Live traffic collection on the 5% canary** (observability + Gate fill). Not Adaptive K. Not Hybrid. Not 10% promotion.
