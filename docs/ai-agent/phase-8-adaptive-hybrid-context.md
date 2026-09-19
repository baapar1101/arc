# Phase 8 — Adaptive Discovery + Hybrid Retrieval + Provider Context

**وضعیت:** در کد پیاده شده است. سقف production و flagهای Adaptive/Hybrid/Progressive خاموش‌اند.  
**تاریخ:** ۲۰ اوت ۲۰۲۶  
**نتایج:** [`evals/phase-8/latest.json`](evals/phase-8/latest.json) · [`evals/tool-adaptive-k/latest.json`](evals/tool-adaptive-k/latest.json) · [`evals/tool-hybrid/latest.json`](evals/tool-hybrid/latest.json) · [`evals/tool-scale/latest.json`](evals/tool-scale/latest.json)

> Security is a hard boundary, never a ranking signal.

> Semantic retrieval may improve discovery, but it can never authorize a tool.

> Cached context is never an authorization decision.

Neural embeddings / pgvector table جدا برای Toolها ساخته نشد. Hybrid از hashed n-gram روی metadata استفاده می‌کند و **رتبهٔ واژه‌ای Phase 6 را حذف نمی‌کند**.

---

## 1. Phase 7 Baseline

| | مقدار |
|--|--|
| Tools | ۱۸۰ |
| Recall@10 | ۹۵.۴۹٪ |
| Recall@15 | ۹۷.۵۲٪ |
| Recall@20 / @48 | ۹۸.۱۹٪ |
| Production K | ۴۸ / ۱۲۸ |
| Progressive flag | False |
| Schema tokens K=48 | ~۴۲٬۹۷۷ / request |
| Schema tokens Progressive K=15 | ~۱۹٬۹۵۵ / request |

LLM همچنان نباید ۱۲۰۰ Tool ببیند. مدل فقط Adaptive Top-K (۵–۲۰) Schema می‌گیرد.

---

## 2. Adaptive K

`AdaptiveKPolicy` مستقل از OpenAI / Anthropic / MCP است.

Pipeline:

```text
Security → Discovery (wide, production limit) → Rank → Confidence → Adaptive K → Schema Loading → LLM
```

Production: `ADAPTIVE_DISCOVERY_K = False` — truncation اعمال نمی‌شود؛ `recommended_k` فقط telemetry است.

Eval روی Gold، برنده با شرط Recall≥۹۵٪ و کمترین Average K:

| Policy | Recall | Avg K | Schema tokens/request |
|--------|--------|-------|------------------------|
| Fixed 10 | ۹۵.۴۹٪ | ۹.۴۳ | ۱۳٬۹۵۸ |
| Fixed 15 | ۹۷.۵۲٪ | ۱۳.۵۱ | ۱۹٬۹۳۱ |
| Fixed 20 | ۹۸.۱۹٪ | ۱۷.۰۵ | ۲۴٬۸۳۷ |
| **tight** | **۹۶.۶۱٪** | **۱۰.۱۹** | **۱۵٬۳۳۰** |
| gap_v1 | ۹۷.۰۷٪ | ۱۱.۲۳ | ۱۶٬۷۷۶ |
| wide | ۹۷.۰۷٪ | ۱۱.۷۲ | ۱۷٬۴۴۱ |

`DEFAULT_ADAPTIVE_POLICY = tight` (high/normal→۱۰، low→۱۵، fail→۲۰).

---

## 3. Confidence Model

`DiscoveryConfidence`: `level`, `score`, `reason`, `recommended_k` به‌علاوه top/second/gap.

سطوح: `none` / `high` / `normal` / `low` / `fail`.

روی Gold tight: ۳۰۸ high، ۳۷ normal، ۸۷ low، ۱۰ none، ۱ fail.

**confidence ≠ permission.** Tool با score بالا بدون authorization وارد candidate نمی‌شود.

---

## 4. Hybrid Architecture

```text
Authorized Candidates
        ↓
Existing lexical/intent ranker   (حفظ شد)
        ↓
Semantic retrieval (authorized-only)
        ↓
Similar-tool protection
        ↓
Score fusion
        ↓
Top-K
```

`HYBRID_TOOL_DISCOVERY = False`. Default engine همان Keyword/Intent است.

---

## 5. Embedding Index

`ToolEmbeddingIndex` داخل process:

| فیلد | مقدار |
|------|--------|
| model | `charngram-hash-v1` |
| dimension | ۲۵۶ |
| source | `search_text` (نه JSON Schema) |
| invalidation | `sha256(search_text)` |

pgvector در پروژه برای `ai_knowledge_chunks` موجود است. برای ۱۸۰–۱۲۰۰ Tool ایندکس حافظه کافی است. جدول جداگانه Tool embedding ساخته نشد.

---

## 6. Weight Calibration

سه وزن روی Gold:

| Weights | Recall@10 | Recall@15 | NDCG@15 | MRR@15 | delete-family FP |
|---------|-----------|-----------|---------|--------|------------------|
| Keyword (Phase 6) | **۹۵.۴۹٪** | **۹۷.۵۲٪** | ۰.۸۱۴ | ۰.۷۸۷ | — |
| lexical_dominant | ۹۴.۵۸٪ | ۹۶.۳۹٪ | ۰.۸۰۹ | ۰.۷۸۶ | ۱/۲۰ |
| balanced | ۹۴.۵۸٪ | ۹۶.۱۶٪ | ۰.۸۰۷ | ۰.۷۸۶ | ۱/۲۰ |
| semantic_dominant | ۹۴.۱۳٪ | ۹۵.۷۱٪ | ۰.۸۰۴ | ۰.۷۸۵ | ۱/۲۰ |

Hybrid **بهتر از ranker فعلی نیست**. وارد production نمی‌شود. بهترین وزن Hybrid همان lexical_dominant است.

---

## 7. Similar Tool Protection

برای `delete_*` / `update_*` / `create_*` / `get_*` / `search_*`:

* mismatch عملیات query ↔ prefix → semantic ×۰.۱۲
* همان خانواده بدون overlap موجودیت/alias → ×۰.۲۲

False positive باقی‌مانده: ۱ از ۲۰ query حذف.

---

## 8. Provider Context Optimization

`ProviderContextPolicy` + `tool_context_fingerprint(name, schema_version)`.

| Provider | Prompt cache | Tool prefix cache | Strategy |
|----------|--------------|-------------------|----------|
| OpenAI official | `prompt_cache_key` + fingerprint | خیر (tools در body) | fingerprint در key |
| Anthropic | system `cache_control` | last-tool `cache_control` hint | tools همچنان resent |
| Local | ندارد | ندارد | فقط schema لازم |

Fingerprint مجوز را cache نمی‌کند. هر iteration authorization جدا است.

---

## 9. Progressive Rollout

```text
off → eval → canary (5%) → majority (50%) → full
```

`PROGRESSIVE_SCHEMA_LOADING` همچنان master است. Stage به‌تنهایی چیزی را روشن نمی‌کند.

---

## 10. Production Telemetry

Events:

* `tool_discovery` — `confidence_level`, `recommended_k`, `average_k`
* `tool_discovery_miss`
* `tool_rediscovery`
* `empty_discovery`
* `tool_schema_round` (Phase 7)

---

## 11. Recovery / Rediscovery

```text
UNKNOWN_TOOL → Security recheck → queue if authorized → next round load schema
max_discovery_retries = 1
```

Call جاری **اجرا نمی‌شود**. مدل در iteration بعد schema جدید را می‌بیند.

---

## 12. 1200 Tool Benchmark

Fixture مصنوعی؛ وارد Registry production نمی‌شود.

| Size | Rank ms | Semantic ms | Schema (Top-15) ms | DB |
|------|---------|-------------|--------------------|----|
| 180 | ۳۷ | ۳۷ | ۳.۹ | ۰ |
| 1,200 | ۱۰۴ | ۲۶۳ | ۳.۷ | ۰ |
| 10,000 | ۵۶۶ | ۲۰۸۴ | ۳.۵ | ۰ |

Schema loading با K کوچک تقریباً ثابت است. گلوگاه ۱۰۰۰۰+ جستجوی خطی semantic است نه تعداد schema روی LLM.

---

## 13. Security Guarantees

1. Semantic فقط روی authorized universe
2. Adaptive K فقط truncate می‌کند؛ نام جدید اضافه نمی‌کند مگر forced/rediscovery مجاز
3. Schema cache / fingerprint / provider cache ≠ authorization
4. Rediscovery اگر Tool در authorized نباشد reject است

---

## 14. Evaluation

Gold بدون تغییر labels.

Adaptive tight: Recall ۹۶.۶۱٪ با Avg K ۱۰.۱۹ — هدف «کمترین K با Recall≥۹۵٪» برقرار است.

gap_v1 اگر Recall نزدیک‌تر به ۹۷٪ بخواهید: Avg K ۱۱.۲۳.

---

## 15. Token Impact

اگر Adaptive tight روی سیم برود (هنوز flag خاموش):

```text
Production K=48:     ~42,977 schema tokens/request
Adaptive tight:      ~15,330
Reduction:           −64.3%
```

این کاهش فقط با فرستادن K کوچک‌تر واقعی است. Python set به‌تنهایی کافی نیست.

Hybrid توکن را کم نکرد و Recall را کمی پایین آورد.

---

## 16. Recommendation for Phase 9

Canary Adaptive K با telemetry typed و assignment پایدار پیاده شد. Production percent = ۰. Hybrid OFF ماند.

Phase 10: Scalable Tool Index (۱٬۲۰۰–۱۰٬۰۰۰+) نه بهبود دوباره Hybrid.
