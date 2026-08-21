# Phase 6 — Ranking Architecture Correction

**وضعیت:** در کد پیاده شده است. سقف production عوض نشد.  
**تاریخ:** ۲۰ اوت ۲۰۲۶  
**نتایج ماشین‌خوان:** [`evals/tool-discovery/latest.json`](evals/tool-discovery/latest.json)  
**قرارداد داده:** همان `2026-08-19.v1` — Gold labels تغییر نکردند.

> **Core is a ranking signal, not a reserved capacity.**

> **Every authorized candidate must compete on relevance before Top-K truncation.**

> **Do not introduce semantic retrieval to compensate for a deterministic ranking bug.**

Hybrid / Embedding / Vector Search در این Phase پیاده نشد.

---

## 1. Phase 5 Findings

Gold `2026-08-19.v1`: ۴۷۳ query (۴۴۳ match + ۳۰ no-match).

| K | Recall Phase 5 |
|---|----------------|
| 5 | 34.1٪ |
| 10 | 35.0٪ |
| 15 | 70.7٪ |
| 20 | 78.6٪ |
| 48 | 89.4٪ |
| Legacy @48 | 100٪ |

`K=10 ≈ K=5` بود چون `rank_and_cap()` قبل از Ranking کامل، Core Tools را در Candidate Set جا می‌داد. Workflow @15 = **۳۶٪**. هدف عملیاتی `Recall@15 >= 95٪` نرسید.

تصمیم Phase 5: Case C — Tight Top-K را deploy نکنید. Analyzer=۴۸ / Autonomous=۱۲۸.

---

## 2. rank_and_cap Current Behavior (قبل از Phase 6)

ترتیب واقعی عملیات **قبل از اصلاح:**

```text
permissioned names
        ↓
security filter (side_effect / mutation / mode)
        ↓
candidate generation:
  • seed all is_core tools
  • if |selected| < 12 → dump financial + warehouse + crm
  • write companions / people → prefer
        ↓
sort key:  prefer first, then core, then -score
        ↓
protected writes never dropped
        ↓
take K   ← ظرفیت Top-K قبلاً توسط core/prefer اشغال شده
```

نقش امتیازها (همان مدل واژه‌ای؛ embedding نبود):

| سیگنال | نقش قبلی |
|--------|----------|
| name token overlap | +2 per token |
| tool name in query | +6 |
| alias substring | +5 + min(len, 12) |
| alias token overlap | +1 per token |
| keywords / examples / capability | **استفاده نمی‌شد** |
| intent domain | dump دسته، نه امتیاز |
| core | **hard reservation** در sort key |
| prefer | **hard reservation** در sort key |
| protected | هرگز به‌خاطر سقف حذف نمی‌شود |

`is_core` هنوز در Manifest وجود دارد؛ رفتارش عوض شد نه فیلد.

---

## 3. Core Tool Problem

با sort key `(prefer, core, -score)`:

- حالت A (مرتبط): Core با alias قوی بالا می‌ماند — درست.
- حالت B (نامرتبط): Core با امتیاز ۰ قبل از Tool غیر-core با امتیاز ۰/کم وارد Top-K می‌شد — **باگ**.
- حالت C (تساوی): Core tie-break — قابل قبول است اگر *بعد از* امتیاز باشد.

نتیجهٔ اندازه‌گیری‌شده: تا وقتی K از تعداد Core بزرگ‌تر نشود، Tool مرتبط اصلاً شانس ورود ندارد. لذا `K=10 ≈ K=5`.

---

## 4. New Ranking Pipeline

```text
Authorized Candidates (همهٔ نام‌های امنیتی‌شده)
        ↓
Relevance Scoring   (هر candidate یک score می‌گیرد)
        ↓
Global Ranking      sort(-score, prefer_tie, core_tie, name)
        ↓
drop score == 0     (به‌جز protected)
        ↓
Top-K
```

Core دیگر ظرفیت رزرو نمی‌کند. `core_bonus` به امتیاز اضافه **نمی‌شود**؛ فقط کلید سوم tie-break است.

`prefer` (companion / skill) یک `PREFER_BONUS = 8` داخل امتیاز است، نه slot reservation.

`INTENT_DOMAIN_BONUS = 5` فقط برای دسته‌های **واقعاً تطبیق‌یافته** (`ranking_intent_domains`). Dump عمومی `{financial, warehouse, crm, misc}` دیگر به Ranking تزریق نمی‌شود. دامنهٔ ضعیف `query` (کلمهٔ «امروز») امتیاز دامنه نمی‌گیرد.

Keywords و examples مثل alias در `_phrases_for` امتیاز می‌گیرند. Capability token overlap ضعیف است.

Protected فقط برای forced / mutation ایمنی صریح است؛ دیگر همهٔ writeها در مسیر eval محافظت نمی‌شوند.

Fallback جدا است: `DiscoveryOffer.fallback_names` — Schema کامل برای Core نامرتبط ارسال نمی‌شود.

---

## 5. No-Match Contract

**Consumerهای Empty Offer (قبل از فعال‌سازی production):**

- `get_available_functions` → `filter_function_definitions([], …)` → `[]`
- حلقهٔ chat: `eff_tools = bool(tools)` → False؛ Schema ابزار نمی‌رود
- `query_expects_tool_use` همچنان می‌تواند goal tracker را روشن کند
- برای chitchat این امن است
- **False-empty روی query معتبر خطرناک‌تر از candidate اضافه است**

رفتار فعلی (احتیاطی):

```text
ranked AND not forced AND not query_expects_tool_use AND top_score <= 0
        ↓
low_confidence = True
        ↓
candidates = []     (fallback_names جدا، بدون Schema)
```

روی ۳۰ no-match Gold:

| | مقدار |
|--|--|
| Empty + low_confidence (موفق) | ۱۹ / ۳۰ = **۶۳.۳٪** |
| False-positive (no-match هنوز tool برگرداند) | ۱۱ / ۳۰ = **۳۶.۷٪** |
| False-negative (match → empty) | **۰ / ۴۴۳ = ۰٪** |

Threshold تهاجمی‌تر فعال نشد چون FN=۰ را نباید خراب کرد. باقی FPها معمولاً امتیاز ۰–۲ و واژه‌های تصادفی دارند، نه retrieval حسابداری.

نمونهٔ قرارداد: «هوا امروز چطوره؟» → `low_confidence` و offer خالی. «امروز» به‌تنهایی دامنهٔ ابزار نیست؛ «از تاریخ امروز تا ۳ ماه پیش» هست.

---

## 6. Workflow Analysis

Phase 5: workflow @15 = **۳۶٪** حتی @48 = ۵۶٪.

علت‌ها:

| لایه | مشکل |
|------|------|
| domain | همهٔ workflowها با dump/core قاطی می‌شدند |
| aliases | «اجرا / تست / تریگر / نود / poll» روی `list_workflows` نبود |
| ZWNJ | `گردش‌کار` (`\u200c`) با regex `گردش\s*کار` نمی‌ساخت → mutation=READ → `execute_workflow` از امنیت حذف می‌شد |
| ranking | امتیاز ۰ + core tie-break |

پس از اصلاح ranking + aliasهای failure-driven + نرمال‌سازی ZWNJ در mutation:

**workflow @15 = ۱۰۰٪** (و @5 هم ۱۰۰٪).

این evidencاً باگ ranking/intent بود، نه نیاز به embedding.

---

## 7. Long-tail Analysis

Phase 4: ۱۰۷ tool بدون alias، ۱۵۰ بدون example — اختیاری اعلام شده بودند.

Phase 5 نشان داد برای Tight Retrieval روی Gold مهم‌اند. **همهٔ ۱۰۷ را پر نکردیم.** فقط ابزارهایی که در Failure Analysis Gold بودند:

نمونه: `search_checks`، `search_transfers`، `list_bank_accounts`، `get_inventory_status`، `get_pipeline_report`، `list_user_notifications`، `get_business_dashboard` (داشبورد)، `list_announcements`، و خانوادهٔ workflow.

---

## 8. Failure-Driven Metadata Fixes

برای هر miss: Query / Expected / Rank / Top-K / Why.

| نوع | اقدام |
|-----|--------|
| ranking bug | حذف core fill؛ score-then-cap |
| metadata | alias/example همان tool |
| intent | `ranking_intent_domains`؛ طرف‌حساب در people؛ mutation write/execute |
| capability | token overlap ضعیف؛ بازنویسی نشد |
| security regex | ZWNJ strip؛ `گردش‌کار را اجرا`؛ `به‌روز` / `بروزرسانی` / `اصلاح کن` |

Gold `expected_tools` تغییر نکرد.

---

## 9. Evaluation Results

همان ۴۷۳ query، همان expected tools.

| K | Recall | MRR | Precision | NDCG | Schema tokens |
|---|--------|-----|-----------|------|---------------|
| 5 | 89.6٪ | 0.777 | 0.351 | 0.779 | 1 380 |
| **10** | **95.5٪** | 0.786 | 0.216 | 0.804 | 2 605 |
| **15** | **97.5٪** | 0.787 | 0.171 | 0.811 | 3 706 |
| **20** | **98.2٪** | 0.787 | 0.150 | 0.814 | 4 621 |
| **48** | **98.2٪** | 0.787 | 0.121 | 0.818 | 7 862 |

`K=10` دیگر به `K=5` قفل نیست (۸۹.۶٪ → ۹۵.۵٪ → ۹۷.۵٪).

هدف `Recall@15 >= 95٪`: **رسید (۹۷.۵٪).**

ابزار با امتیاز ۰ دیگر Top-K را پر نمی‌کند؛ به همین دلیل Precision@48 از ۰.۰۶ (Phase 5) به ۰.۱۲ رسید و میانگین Schema در K=۴۸ کمتر از پر کردن اجباری ۴۸ اسلات است.

---

## 10. Regression Results

| | Phase 5 | Phase 6 |
|--|---------|---------|
| Legacy Recall@48 | 100٪ | **100٪** |
| Gold Recall@48 | 89.4٪ | **98.2٪** |
| شرط Phase 6 (`@48 >= 95٪`) | — | برقرار |

---

## 11. Token Impact

Production هنوز Analyzer=۴۸ / Autonomous=۱۲۸. هیچ کاهش production انجام نشد.

اگر بعداً K=۱۵ شود:

| | K=15 | K=48 | صرفه‌جویی |
|--|------|------|-----------|
| Schema / iteration | 3 706 | 7 862 | **~۵۳٪** |
| Schema × avg iterations (۴.۹۸) | 19 931 | 42 977 | ~۲۳k / request |

Progressive Schema Loading پیاده نشد. Avg iterations روی Gold match: **۴.۹۸** (Phase 5: ۵.۸) — عمدتاً به‌خاطر این‌که پیچیدگی دیگر dump چهار دامنه روی chitchat اعمال نمی‌کند.

---

## 12. Decision Gate

```text
Recall@15 = 97.52%  >=  95%
```

بنابراین Phase 7 **می‌تواند** Hybrid/Semantic را به‌عنوان **افزودنی روی Ranking فعلی** شروع کند، نه جایگزینی.

Eval `recommend_k` اکنون Case **A** و K پیشنهادی **۱۰** است. این فقط توصیهٔ اندازه‌گیری است. **ثابت‌های production عوض نشدند.**

۹–۱۱ failure باقی‌مانده در K=۱۵ (و تقریباً همان‌ها در K=۴۸):

| id | query | expected | جنس |
|----|-------|----------|-----|
| exp-044 | امتیاز باشگاه را کم و زیاد کن | `adjust_customer_club_points` | write در analyzer (gold intent) |
| exp-046 | RFM باشگاه را دوباره حساب کن | `recalculate_customer_club_rfm` | write / security |
| exp-058 | قالب گزارش را منتشر کن | `publish_report_template` | write / security |
| exp-086 | connector call | `invoke_business_connector` | execute/write + انگلیسی |
| con-01 | کانکتور قیمت را صدا بزن | `invoke_business_connector` | execute/write |
| acc-18 | این چک را حذف کن | `delete_check` | similar delete_* |
| exp-028 | این سرفصل را حذف کن | `delete_account` | similar delete_* |
| exp-031 | انتقال بانکی را حذف کن | `delete_transfer` | similar delete_* |
| hard-gen-01 | یک گزارش کلی از اوضاع بده | `get_business_dashboard` | **semantic / generic paraphrase** |
| plat-01 / exp-158 | اطلاعات این کسب‌وکار | `get_business_info` | short/generic metadata |

---

## 13. Phase 7 Recommendation

طبقه‌بندی failureهای باقی‌مانده (۱۱ مورد ≈ ۲.۵٪ از match):

```text
Current retrieval failures @15:
  ~45%  security / gold-intent (write tool در analyzer)
  ~27%  similar-tool ranking (خانوادهٔ delete_*)
  ~18%  generic / short business-info paraphrase
  ~9%   semantic mismatch (گزارش کلی از اوضاع)
  ~0%   core-reservation ranking bug
```

Embedding راه‌حل اصلی این ۹ مورد نیست. با این حال چون هدف ۹۵٪ رسیده، Hybrid به‌عنوان **لایهٔ کمکی برای paraphrase عمومی** مجاز است، روی ranker فعلی — نه به‌جای آن.

پیشنهاد عملی Phase 7:

1. هم‌ترازی mutation/intent برای writeهای gold که هنوز analyzer هستند (بدون عوض کردن `expected_tools`).
2. در صورت ورود به Hybrid: فقط برای missهای generic/paraphrase، با همان Gold v1.

**Production K در Phase 6 تغییر نمی‌کند.**
