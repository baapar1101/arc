# Phase 5 — Tight Top-K Retrieval & Evaluation

**وضعیت:** در کد پیاده شده است. سقف production عوض نشد.  
**تاریخ:** ۱۹ اوت ۲۰۲۶  
**نتایج ماشین‌خوان:** [`evals/tool-discovery/latest.json`](evals/tool-discovery/latest.json)  
**قرارداد داده:** [`evals/tool-discovery/gold_queries.v1.json`](evals/tool-discovery/gold_queries.v1.json)

> **Do not optimize tool count by intuition. Measure retrieval recall first.**

> Phase 5 measures Keyword/Intent retrieval and selects K from data. It does **not** add embeddings, hybrid search, `search_tools`, or progressive schema loading.

**تصمیم:** Case C — Tight Top-K را deploy نکنید. `MAX_TOOLS_PER_REQUEST` همان **۴۸** می‌ماند. `MAX_TOOLS_AUTONOMOUS` همان **۱۲۸**.

---

## 1. Dataset

نسخه: `2026-08-19.v1` روی کاتالوگ `180.phase4`.

ارزیابی فقط `discover_tools()` را صدا می‌زند (بدون LLM Provider).

| | |
|--|--|
| Queries | **۴۷۳** |
| Match | ۴۴۳ |
| No-match / chitchat | ۳۰ |
| Tools covered | ۱۷۵ / ۱۸۰ |
| Capabilities | ۴۸ |
| Write | ۶۹ |
| Destructive | ۲۰ |
| Report-family | ۶۰ |
| Memory | ۱۳ |
| Hard / ambiguous | ۱۱۲ |
| Legacy gold (Phase 1–3) | ۲۲ |

Queryها نام Tool نیستند. شامل فارسی حسابداری، انگلیسی، غلط املایی، کوتاه، بلند، چندمنظوره، و follow-up مکالمه‌ای.

منبع: `hesabixAPI/app/services/ai/ai_tool_discovery_gold.py`

---

## 2. Baseline

بدون تغییر سقف:

| Mode | K |
|------|---|
| Analyzer | ۴۸ |
| Supervised / Autonomous | ۱۲۸ |

روی ۴۴۳ query تطبیقی:

| | Recall | MRR | Precision | NDCG | Retrieval Success |
|--|--------|-----|-----------|------|-------------------|
| **K=48** | **۸۹.۴٪** | ۰.۵۲ | ۰.۰۶ | ۰.۶۱ | ۸۹.۴٪ |

مجموعهٔ طلایی قدیمی (۲۲ query) در K=۴۸: **Recall = ۱۰۰٪** (رگرسیون ندارد).

---

## 3. Metrics

تعاریف استفاده‌شده (همه روی خروجی ranked `discover_tools`):

- **Recall@K:** حداقل یک `primary_expected_tool` در Top-K
- **Multi-tool Recall@K:** همهٔ primaryها وقتی `require_all_primary`
- **Retrieval Success:** اگر چند Tool لازم باشد همه؛ وگرنه همان Recall (قابل‌قبول بودن `acceptable_tools` جدا در NDCG است)
- **MRR:** معکوس رتبهٔ اولین primary
- **Precision@K:** سهم Toolهای primary∪acceptable در K
- **NDCG@K:** relevance ۲ برای primary، ۱ برای acceptable

Provider-independent: Query → `discover_tools()` → Candidates.

---

## 4. K Sweep

| K | Recall | Multi-tool | MRR | Precision | NDCG | Schema tokens | Share of 28k |
|---|--------|------------|-----|-----------|------|---------------|--------------|
| 3 | 33.6٪ | 10٪ | 0.26 | 0.10 | 0.24 | 3 034 | 11٪ |
| 5 | 34.1٪ | 10٪ | 0.26 | 0.10 | 0.24 | 3 407 | 12٪ |
| 8 | 34.5٪ | 10٪ | 0.26 | 0.06 | 0.26 | 3 952 | 14٪ |
| **10** | **35.0٪** | 10٪ | 0.26 | 0.06 | 0.26 | 4 331 | 15٪ |
| 12 | 35.2٪ | 10٪ | 0.26 | 0.06 | 0.26 | 4 734 | 17٪ |
| **15** | **70.7٪** | 60٪ | 0.54 | 0.09 | 0.56 | 5 315 | 19٪ |
| **20** | **78.6٪** | 60٪ | 0.54 | 0.08 | 0.58 | 6 201 | 22٪ |
| 30 | 84.4٪ | 60٪ | 0.53 | 0.07 | 0.60 | 7 685 | 27٪ |
| **48** | **89.4٪** | 80٪ | 0.52 | 0.06 | 0.61 | 10 364 | 37٪ |
| 64 | 91.9٪ | — | — | — | — | 11 694 | 42٪ |
| 128 | 92.6٪ | — | — | — | — | 15 491 | 55٪ |

پرتگاه بین K=۱۲ و K=۱۵ ساختگی نیست: `rank_and_cap` اول `prefer` و **core tools** را نگه می‌دارد، بعد امتیاز query. تا وقتی K از اندازهٔ core بزرگ‌تر نشود، Tool درست اصلاً وارد مجموعه نمی‌شود.

---

## 5. Overall Recall

نمی‌توان به‌جای ۴۸ Tool فقط ۱۰–۲۰ Tool به LLM داد.

```text
K=10  Recall@10 = 35.0%
K=15  Recall@15 = 70.7%
K=20  Recall@20 = 78.6%
K=48  Recall@48 = 89.4%
```

هدف عملیاتی (≥۹۵٪ در ۱۰–۲۰) برآورده نشد.

---

## 6. Per-Capability / Category Recall

K=۱۵ در برابر K=۴۸:

| دسته | K=15 | K=20 | K=48 |
|------|------|------|------|
| invoice | 94٪ | 94٪ | 96٪ |
| sales | 93٪ | 93٪ | 100٪ |
| purchase | 100٪ | 100٪ | 100٪ |
| customer | 85٪ | 85٪ | 97٪ |
| memory | 92٪ | 92٪ | 92٪ |
| wallet | 89٪ | 89٪ | 100٪ |
| reports | 76٪ | 79٪ | 84٪ |
| inventory | 67٪ | 80٪ | 93٪ |
| accounting | 60٪ | 67٪ | 90٪ |
| support | 57٪ | 72٪ | 83٪ |
| CRM | 48٪ | 76٪ | 86٪ |
| workflow | **36٪** | **48٪** | **56٪** |

Workflow حتی در K=۴۸ زیر ۶۰٪ است — شکاف alias/keyword، نه فقط سقف.

---

## 7. Per-Difficulty Recall

| | K=10 | K=15 | K=20 | K=48 |
|--|------|------|------|------|
| easy | 40٪ | 86٪ | 90٪ | 94٪ |
| medium | 36٪ | 67٪ | 77٪ | 88٪ |
| hard | 25٪ | 53٪ | 63٪ | 83٪ |
| ambiguous | 35٪ | 87٪ | 87٪ | 96٪ |

---

## 8. Hard Cases (K=15)

| نوع | Recall@15 |
|-----|-----------|
| synonyms | 100٪ |
| similar_tools | 100٪ |
| multi-intent | 100٪ |
| conversational | 93٪ |
| english | 86٪ |
| short | 84٪ |
| ambiguous | 67٪ |
| persian_accounting | 60٪ |
| typos | **45٪** |

غلط املایی ضعیف‌ترین خانواده است (keyword exact). Semantic search اینجا بعداً ارزش دارد — ولی نه قبل از درست شدن ranking.

---

## 9. Failure Analysis

در K=۱۵ حدود **۱۳۱** query تطبیقی شکست خورد (نمونهٔ ۵۰تایی در `latest.json`).

الگوی غالب:

1. **Core crowding:** `get_business_dashboard` / `get_account` / `query_business_data` جای Tool دم‌بلند را می‌گیرند (`list_cash_registers`, `list_frequent_descriptions`, `get_document_numbering_settings`).
2. **Alias gap:** «دفتر کل»، «تنخواه»، «جانمایی انبار»، «شرح پرتکرار» در aliases نیستند.
3. **Workflow vocabulary:** «دیباگ اجرا»، «poll»، «نود آماده» با `list_workflows` قاطی می‌شود.
4. **Ambiguous gold:** «این را حذف کن» بدون antecedent — Intent problem + dataset.
5. **Score tie at 0:** خیلی از missها `top_score=0` دارند؛ ranking تصادفیِ باقیمانده است.

این‌ها مشکل Metadata/Intent/Ranking هستند نه کمبود embedding.

---

## 10. Token Cost

تخمین همان روش فعلی: `chars // 4` روی name + search_text + JSON schema (payload اگر باشد). بودجهٔ ورودی ۲۸٬۰۰۰.

کاهش K از ۴۸→۲۰ حدود **۴٬۱۶۰ توکن Schema در هر نوبت** ذخیره می‌کند (~۱۵٪ context)، اما ۱۳٪ Recall را می‌سوزاند. با دادهٔ فعلی معاملهٔ قابل قبولی نیست.

---

## 11. Iteration Cost

`get_available_functions` در **هر iteration** حلقهٔ agent دوباره Schema کامل را می‌سازد (`ai_service.py`). Progressive loading پیاده نشد.

| | |
|--|--|
| Schema resent every iteration | yes |
| Avg iterations (gold) | ۵.۸ |
| K=15 × iterations | ~۳۳k schema tokens / request |
| K=48 × iterations | ~۶۵k schema tokens / request |

این عدد برای Phase 7 (کش tool-set) ضروری است. امروز دست نخورد.

---

## 12. Recommended K

**Analyzer K = 48 (بدون تغییر).**  
**Autonomous K = 128 (بدون تغییر).**

Adaptive-K prototype (فقط eval): میانگین K=۱۲.۹ با Retrieval Success ۴۸٪ — بدتر از K ثابت ۱۵. به production وصل نشد.

---

## 13. Confidence Analysis

`DiscoveryOffer` حالا `top_score`, `second_score`, `score_gap`, `low_confidence` دارد. کاندیداها بر اساس score مرتب می‌شوند (ترتیب Schema ارسالی به LLM).

- Chitchat («هوا امروز چطوره؟»): `low_confidence=True` چون score≈۰.
- Discovery هنوز مجموعهٔ غیرخالی برمی‌گرداند (core / fallback دسته). **Empty offer در production فعال نشد.**
- `no_match_success=1.0` یعنی تشخیص low-confidence، نه اینکه Tool حسابداری به مدل نرود.
- Score کالیبره نشد. فاصلهٔ صفر در missهای دم‌بلند رایج است.

---

## 14. Remaining Retrieval Problems

1. `rank_and_cap` core را به امتیاز query ترجیح می‌دهد → Tight Top-K غیرممکن است تا این عوض شود.
2. `detect_categories` برای سوال بی‌کلیدواژه به financial/warehouse/crm/misc fallback می‌کند.
3. Workflow / settings / long-tail alias ضعیف.
4. Typo بدون fuzzy/embedding شکست می‌خورد.
5. No-match هنوز Schema حسابداری می‌فرستد.
6. Precision در همهٔ K پایین است (مجموعه شلوغ است).

---

## 15. Phase 6 Recommendation

**Case C + تشخیص Case B:** Hybrid/Semantic را شروع نکنید.

ترتیب بعدی:

1. Ranking: امتیاز query قبل از پر کردن با core (سپس همین eval را دوباره اجرا کنید).
2. Alias برای workflow و اصطلاحات حسابداری که در failure آمده.
3. سیاست empty/low-confidence برای no-match.
4. اگر بعد از آن Recall@15 ≥ ۹۵٪ شد، Tight Top-K را deploy کنید.
5. تازه بعد از آن Hybrid برای typo/synonym باقیمانده.

Eval فعلی قرارداد هر تغییر Discovery بعدی است.
