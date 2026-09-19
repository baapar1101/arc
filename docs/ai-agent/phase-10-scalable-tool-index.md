# Phase 10 — Scalable Tool Index for 1,200–10,000+ Tools

**وضعیت:** ایندکس مشتق‌شده در کد است. Retrieval Production هنوز همان Ranker کامل روی Authorized universe است.  
**تاریخ:** ۲۱ اوت ۲۰۲۶  
**نتایج:** [`evals/phase-10/latest.json`](evals/phase-10/latest.json) · [`evals/tool-scale/latest.json`](evals/tool-scale/latest.json)

> Scale the candidate retrieval layer, not the LLM tool surface.

> The model should remain unaware of the size of the global Tool Catalog.

> Fast retrieval finds candidates; the existing ranker decides relevance; Security decides authorization; the LLM only sees the final small schema set.

> Vector retrieval is a candidate generator, not an authorization mechanism and not the final ranking authority.

---

## 1. Phase 9 findings

- Adaptive K روی Gold ارزان است (Avg K ≈ ۱۰.۱۹، Recall ۹۶.۶۱٪) ولی **HOLD** ماند چون ترافیک زنده صفر بود.
- Hybrid از Keyword بهتر نیست → OFF.
- Semantic linear در ۱۰٬۰۰۰ Tool ≈ ۲s → برای Production ممنوع.
- Inverted prototype در Bench حدود ۱۲ms بود — فقط Prototype داخل `ai_tool_scale_bench`، نه ایندکس واقعی.

Production flags بعد از Phase 9 (و این Phase) بدون تغییر:

```text
PROGRESSIVE_SCHEMA_LOADING = False
ADAPTIVE_DISCOVERY_K = False
ADAPTIVE_K_ROLLOUT_PERCENT = 0
HYBRID_TOOL_DISCOVERY = False
INDEXED_CANDIDATE_RETRIEVAL = False
VECTOR_CANDIDATE_RETRIEVAL = False
Analyzer = 48 / Autonomous = 128
```

---

## 2. Scaling problem

| Size | Keyword linear | Inverted query | Semantic linear |
|------|----------------|----------------|-----------------|
| 180 | ~۴۰ms | ~۶ms | ~۳۸ms |
| 1,200 | ~۹۱ms | ~۶ms | ~۲۴۲ms |
| 5,000 | ~۲۹۳ms | ~۹ms | ~۹۹۹ms |
| 10,000 | ~۵۴۷ms | ~۱۳ms | ~۲۰۵۹ms |
| 100,000 | skipped | ~۱۱۰ms | skipped |

O(N) semantic و حتی keyword scan برای ۵k+ روی مسیر آنلاین قابل قبول نیست. Schema Top-15 همچنان ~۴ms است. گلوگاه **جستجو** است نه JSON Schema.

---

## 3. Target architecture

```text
                      Tool Registry  (source of truth)
                           │
                           ▼
                    Security Boundary
                           │
                           ▼
                  Candidate Retrieval     (derived index)
                       /         \
                      /           \
             Inverted Index      Vector ANN (optional, off)
                    \              /
                     \            /
                      ▼          ▼
                      Candidate Merge
                            │
                            ▼
                     Existing Ranker     (Phase 6, unchanged)
                            │
                            ▼
                      Adaptive K         (flag off)
                            │
                            ▼
                 Progressive Schema     (flag off)
                            │
                            ▼
                           LLM
```

Candidate Retrieval ≠ Final Ranking. Index score فقط برای برش Top-N است.

---

## 4. Inverted index

قبل از این Phase:

| قطعه | نقش |
|------|------|
| `ai_tool_index.ToolIndex` | metadata مشتق (domain / alias / write) — posting list نیست |
| `ai_tool_scale_bench.build_inverted_index` | Prototype Bench |
| `ai_tool_embedding.ToolEmbeddingIndex` | hashed n-gram خطی، authorized-only |

الان:

`ai_tool_retrieval_index.ToolRetrievalIndex` — Derived Data از Manifest.

Index می‌کند: name, aliases, keywords, description/extra, capability, domain, namespace, examples.

Tokenizer (`ai_tool_text`): اعداد از `smart_normalize_numbers`، ZWNJ/ZWJ، ي→ی، ك→ک، lower-case. Ranker Phase 6 (`tokenize_query`) عوض نشد.

وزن نهایی با Ranker است نه با TF-IDF ایندکس.

---

## 5. Candidate retrieval

`retrieve_candidates(query, authorized, n)`:

1. Intersection با Authorized universe (permission داخل ایندکس نیست)
2. Keyword postings ∪ capability exact ∪ domain (اگر query ابزار می‌خواهد)
3. Optional vector merge اگر `VECTOR_CANDIDATE_RETRIEVAL`
4. برش Top-N
5. Forced / prefer همیشه می‌مانند
6. Disabled / deprecated از posting خارج‌اند
7. No-match می‌تواند تهی باشد؛ False-empty با Gold اندازه گرفته شد

`INDEXED_CANDIDATE_RETRIEVAL` در Production خاموش است؛ `KeywordIntentStrategy` همان Ranker کامل را صدا می‌زند.

---

## 6. Candidate Recall

Gold `2026-08-19.v1`، ۴۴۳ query دارای Tool مورد انتظار:

| N | Candidate Recall | p50 | p95 |
|---|------------------|-----|-----|
| 20 | ۹۴.۵۸٪ | ۰.۷۶ms | ۱.۰۰ms |
| 50 | ۹۸.۶۵٪ | ۰.۸۴ms | ۱.۱۴ms |
| **100** | **۹۸.۸۷٪** | ۰.۸۵ms | ۱.۳۴ms |
| 200 | ۹۸.۸۷٪ | ۰.۸۶ms | ۱.۳۵ms |

هدف ۹۹٪+ با هیچ N ای نرسید. N=۱۰۰ و N=۲۰۰ یکی‌اند: پنج miss باقی‌مانده اصلاً در posting/domain نیستند (`get_person_balance` / `list_currencies` / `get_business_dashboard` / `get_business_info`×۲) — مشکل metadata است نه اندازهٔ N.

**Candidate N انتخابی برای مسیر opt-in: ۱۰۰** (نقطهٔ اشباع). Production همچنان کل Authorized را rank می‌کند تا این gap بسته شود.

No-match (۳۰ query): ۵۰٪ candidate set تهی. بقیه معمولاً توکن ضعیفی مثل «امروز» دارند. False-empty کامل نیست؛ با fallback Production (اگر flag روشن شود) Ranker فعلی حفظ می‌شود.

---

## 7. Vector ANN

ارزیابی:

| گزینه | تصمیم |
|--------|--------|
| pgvector HNSW | برای **knowledge chunks** موجود است. جدول Tool نساز. charngram برای pgvector مناسب نیست. |
| FAISS | وابستگی جدید؛ بدون embedding عصبی ارزش ندارد. |
| New vector DB | ممنوع در این Phase. |
| In-process hashed n-gram | Baseline.eval؛ O(N) بالای `VECTOR_BRUTE_FORCE_MAX=512` عمداً اجرا نمی‌شود. |

Neural embedding: Benchmark نشد (بدون مدل versioned در CI). charngram-hash-v1 در Phase 8 از Keyword بهتر نبود → Production نشد.

---

## 8. Hybrid candidate merge

```text
Keyword Index ──┐
                ├──→ Candidate Merge → Existing Ranker
Vector ANN ─────┘
```

`VECTOR_CANDIDATE_RETRIEVAL = False`. Hybrid Tool Discovery همچنان OFF.

---

## 9. Existing Ranker

`score_tool_for_query` / `rank_and_cap_tool_names` دست‌نخورده‌اند.

مسیر indexed (فقط eval): Candidate N → `discover_tools(permissioned_names=candidates, limit=K)`.

Final Recall با N=۱۰۰:

| K | Indexed | Baseline (full authorized) |
|---|---------|----------------------------|
| 10 | ۹۵.۰۳٪ | ۹۵.۴۹٪ |
| 15 | ۹۷.۰۷٪ | ۹۷.۵۲٪ |
| 20 | ۹۷.۷۴٪ | ۹۸.۱۹٪ |

افت ~۰.۴–۰.۵ نقطه همان ۵ miss کاندیداست. برای همین flag Production خاموش ماند.

---

## 10. Incremental updates

`upsert` / `remove` / `disable` / `is_stale(search_text_hash, version, schema_version)`.

`load_many` برای rebuild انبوه (mutable سپس freeze) تا O(N²) copy-on-write رخ ندهد. Upsert تکی همچنان copy-on-write روی postingهای Frozenset است.

---

## 11. Versioning

هر رکورد: `version`, `schema_version`, `search_text_hash`, `indexed_at`. اگر Manifest عوض شود و hash فرق کند، رکورد stale است و باید upsert شود. منبع حقیقت همچنان Manifest/Registry است.

---

## 12. Multi-tenant security

ایندکس سراسری است. Permission encode نمی‌شود.

```text
Global Tool Index
        ↓
Authorized Universe  (tenant / role / mode / side_effect)
        ↓
Candidate Retrieval ∩ authorized
```

Unauthorized هرگز candidate نمی‌شود. Security قبل و روی intersection سخت است.

---

## 13. Performance

هدف اولیه candidate retrieval < ۵۰ms:

- ۱۸۰…۱۰٬۰۰۰: p50 تک‌درخواستی حدود ۶–۱۳ms — برقرار است.
- ۱۰۰٬۰۰۰ metadata: ~۱۱۰ms تک‌درخواستی — بالای ۵۰ms؛ برای این مقیاس postingهای داغ باید فشرده/شارد شوند (Phase 11).

Index memory تخمینی: ۱۸۰ Tool ≈ ۱۲۰KB posting؛ ۱۰k ≈ چند MB.

---

## 14. Stress test

تک‌درخواستی @10k: p50 ≈ ۶–۱۴ms (زیر هدف ۵۰ms).

Burst در یک فرآیند CPython (GIL):

| Concurrency | p50 | p95 | wall |
|-------------|-----|-----|------|
| 1 | ~۱۶ms | ~۱۶ms | ~۱۹ms |
| 10 | ~۸۷ms | ~۱۳۸ms | ~۲۲۷ms |
| 50 | ~۱.۴s | ~۱.۵s | ~۱.۶s |
| 100 | ~۲.۸s | ~۳.۰s | ~۳.۲s |

این Burst معادل QPS پایدار نیست. ۵۰–۱۰۰ thread همزمان روی یک interpreter محدود به GIL است. مسیر آنلاین فعلی هنوز Ranker کامل است؛ ایندکس opt-in است.

---

## 15. Benchmark

حفظ شد: ۱۸۰ / ۵۰۰ / ۱٬۲۰۰ / ۵٬۰۰۰ / ۱۰٬۰۰۰ + ۱۰۰٬۰۰۰ (بدون semantic).

هیچ Tool مصنوعی وارد Registry Production نمی‌شود.

---

## 16. Production status

UNCHANGED.

LLM همان K=۴۸/۱۲۸ و Ranker Phase 6 را می‌بیند. ایندکس آمادهٔ opt-in است، روشن نیست. Adaptive K HOLD. Hybrid OFF.

---

## 17. Phase 11 recommendation

1. بستن ۵ miss کاندیدا با alias/example روی Manifest (نه با بزرگ کردن N).
2. بعد از Candidate Recall ≥ ۹۹٪ روی Gold، Canary جدا برای `INDEXED_CANDIDATE_RETRIEVAL` (مثل Phase 9، مستقل از Adaptive K).
3. اگر Neural embedding versioned آمد: pgvector HNSW روی **همان Postgres** به‌عنوان generator دوم — نه جایگزین Keyword.
4. فشرده‌سازی posting برای ۱۰۰k+.
5. Adaptive K را فقط وقتی Live Canary Phase 9 اجازه داد Promote کنید.
