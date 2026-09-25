# Tool Schema Loading Evaluation

Gold: `2026-08-19.v1` (۴۴۳ match queries). Discovery همان Phase 6 است؛ این eval فقط هزینهٔ schema را جدا می‌کند.

منبع: `hesabixAPI/app/services/ai/ai_tool_schema_eval.py`

```bash
cd hesabixAPI && .venv/bin/python -m app.services.ai.ai_tool_schema_eval
```

## Modes

| Mode | K | Progressive | Recall | Initial schema tokens | Additional | Wire schema tokens / request | Avg iterations |
|------|---|-------------|--------|-----------------------|------------|------------------------------|----------------|
| Current K=48 | 48 | no | 98.19٪ | 7,862 | 0 | 42,977 | 4.98 |
| Current K=20 | 20 | no | 98.19٪ | 4,621 | 0 | 24,837 | 4.98 |
| Progressive K=15 | 15 | yes | 97.52٪ | 3,706 | 6 | 19,955 | 4.98 |
| Progressive K=10 | 10 | yes | 95.49٪ | 2,605 | 13 | 14,028 | 4.98 |

Progressive K=15 در برابر Current K=48: **−۵۳.۶٪** توکن schema روی سیم — فقط اگر مجموعهٔ کوچک‌تر واقعاً در HTTP body برود.

Production هنوز Current K=48 است (`PROGRESSIVE_SCHEMA_LOADING = False`).

## Honest split

```text
Application-side duplication: solved
LLM wire/context duplication: reduced_if_smaller_k_sent_each_iteration
```

فایل‌ها: `latest.json`, `current_k48.json`, `current_k20.json`, `progressive_k15.json`, `progressive_k10.json`.
