# Phase 14 — Live Indexed Retrieval Canary Validation

**وضعیت:** Canary ۵٪ مسلح است. ترافیک زنده این فرآیند **صفر** است → **HOLD**. Promotion به ۱۰٪ ممنوع. Adaptive K / Hybrid / Progressive خاموش.  
**تاریخ:** ۲۱ اوت ۲۰۲۶  
**نتایج:** [`evals/phase-14/latest.json`](evals/phase-14/latest.json)

> No live evidence, no promotion.

> Do not interpret fallback-assisted success as index success.

> Do not mix Indexed Retrieval validation with Adaptive K validation.

```text
INDEXED_CANDIDATE_RETRIEVAL = False
INDEXED_CANDIDATE_ROLLOUT_PERCENT = 5
INDEXED_CANDIDATE_FALLBACK = True
ADAPTIVE_DISCOVERY_K = False
HYBRID_TOOL_DISCOVERY = False
PROGRESSIVE_SCHEMA_LOADING = False
Analyzer = 48 / Autonomous = 128
Candidate N = 100
```

این Phase موتور Retrieval، Ranker، Hybrid، Embedding، Adaptive K یا Progressive Schema اضافه نمی‌کند.

---

## 1. Live Experiment Contract

سه منبع جدا:

| منبع | برچسب |
|------|--------|
| Offline Gold | `offline_gold` |
| Production Control | `production_control` |
| Production Experiment | `production_experiment` |

Gold Recall هرگز Production Recall نیست.

هر درخواست زنده: `indexed_candidate_exposure` با `arm`, `channel`, `mode`, `candidate_retrieval_enabled`. بدون user_id / business_id / query / مالی / permission payload.

Assignment پایدار: SHA256(`indexed-retrieval-v1` + ids). Salt ثابت. تغییر Salt = آزمایش جدید. شناسه لاگ نمی‌شود.

---

## 2. Metrics

```text
live_control_requests
live_experiment_requests
indexed_retrieval_hit | miss | empty | stale | error
fallback_total | fallback_empty | fallback_low_candidate_quality
fallback_stale_index | fallback_index_error | fallback_index_inconsistency
fallback_rate
tool_discovery_miss   ≠  indexed_retrieval_miss
index_success         ≠  task_success
tool_execution_success / failure  per arm × read|write|delete|export|execute
no_match_requests / no_match_false_tool_selection
```

Task completion فقط از سیگنال صریح (`workflow_completion` / `explicit_agent_success` / `user_confirmation`). از `tool_execution_success` یا first-pass استنتاج نمی‌شود؛ در غیر این صورت `null`.

---

## 3. Control / Experiment

Control: Authorized → Phase 6 Ranker → K=48/128.  
Experiment: Authorized → Indexed N=100 → همان Ranker → همان K.

اگر Index unhealthy باشد، Experiment به Fallback (full authorized rank) می‌رود.

---

## 4. Security Gate

```text
authorization_bypass = 0
tenant_leakage = 0
permission_violation = 0
```

هر Bypass → IMMEDIATE ROLLBACK.

High-risk (`delete` / `write` / `export` / `execute` / `financial_mutation`): approval success, execution success, unexpected rejection, authorization failure.

---

## 5. Task Gate

Wilson CI روی دو نسبت، فقط وقتی سیگنال Task صریح وجود دارد.

اگر Confidence کافی نیست یا Task قابل اندازه‌گیری نیست → **HOLD**. نتیجه‌گیری نکن.

---

## 6. Retrieval Gate

`indexed_retrieval_hit_rate` و `indexed_retrieval_miss_rate` روی ترافیک Experiment.

اگر Miss نسبت به Gold آفلاین غیرمنتظره بالا باشد، علت را جدا بررسی کن — Gold را به‌جای Production گزارش نکن.

---

## 7. Fallback Gate

Fallback ≠ Miss. نرخ Fallback را جدا حساب کن. Fallback زیاد یعنی ایندکس ممکن است ارزش Production نداشته باشد، حتی اگر Task موفق باشد.

---

## 8. Latency Gate

Per arm: p50 / p95 / p99 برای:

- retrieval latency
- end-to-end AI request latency

بهبود p50 به‌تنهایی کافی نیست. Experiment نباید p95 را به‌شکل قابل‌توجه بدتر کند.

---

## 9. Sample Size

قبل از هر Promotion: Control ≥ 500 و Experiment ≥ 500. اگر نتیجه borderline بود، نمونهٔ بیشتر جمع کن. Auto-promotion ممنوع.

---

## 10. Channel Analysis

`chat` / `subagent` / `crm` / `ticket` / `workflow`.

اگر یک کانال مشکل دارد، **channel-specific HOLD** بهتر از Rollback کامل است:

```text
HESABIX_INDEXED_CANDIDATE_CHANNEL_HOLD=ticket,crm
```

بدون kill کل Canary و بدون restart.

---

## 11. Kill Switch

بدون restart:

```text
HESABIX_INDEXED_CANDIDATE_KILL=1
HESABIX_INDEXED_CANDIDATE_RETRIEVAL=0
```

هر دو Experiment را به Control تبدیل می‌کنند. Adaptive K / Hybrid / Schema دست نخورده می‌مانند.

---

## 12. Rollout

```text
5% → 10% → 25% → 50% → 100%
```

فقط با تصمیم صریح. `propose_indexed_rollout` ثابت را نمی‌نویسد.

---

## 13. Results

این فرآیند:

| Metric | Value |
|--------|--------|
| Live control | 0 |
| Live experiment | 0 |
| Exposure | 0 |
| Indexed hit / miss / fallback | null |
| Task completion | null |
| Tool execution | null |
| Security | clean |
| p50 / p95 / p99 | null |
| Index health | healthy (180/180, stale=0) |
| Kill switch | PASS |
| Current rollout | 5% |

---

## 14. Promotion Decision

**HOLD**

Zero live traffic is a valid outcome. Promotion به ۱۰٪ ممنوع است تا ۵۰۰ نمونه در هر بازو و Gateهای A–E پر شوند.

---

## 15. Limitations

- این محیط ترافیک Production ندارد؛ نرخ‌ها ساختگی نیستند (`null`).
- Task completion سراسری هنوز به سیگنال صریح وصل نشده؛ first-pass و tool execution جدا می‌مانند.
- Indexing توکن را کم نمی‌کند (K=48/128).
- ۱۰k bench آفلاین است، نه latency Production.

---

## 16. Next Phase

جمع‌آوری ترافیک واقعی روی Canary ۵٪. Adaptive K / Hybrid / Progressive / افزایش N را روشن نکن. تا Gateها با دادهٔ زنده پر نشده‌اند به ۱۰٪ نرو.
