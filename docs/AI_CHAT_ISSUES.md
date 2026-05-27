# مشکلات و وضعیت بخش چت AI

این سند مشکلات شناسایی‌شده و وضعیت رفع آن‌ها را فهرست می‌کند.

## ✅ رفع‌شده (۲۰۲۶)

| موضوع | وضعیت |
|--------|--------|
| تأخیر `done` به‌خاطر `generate_chat_title` | عنوان در پس‌زمینه؛ `done` بلافاصله پس از commit |
| بارگذاری prompt همه‌یا‌هیچ | trace هر loader به‌محض اتمام؛ RAG با timeout و intent |
| `checkAvailability` قبل از هر پیام | کش ۲ دقیقه‌ای در Flutter |
| نبود بازخورد قبل از اولین chunk SSE | رویدادهای `status` + `heartbeat` + UI optimistic |
| برچسب‌های تکراری ابزار (FA hardcoded) | `ai_tool_keys.py` + کلیدهای l10n در Flutter |
| Function calls sequential | `asyncio.gather` + `run_in_executor` |
| Timeout کوتاه stream | `receiveTimeout` ۱۰ دقیقه در `AIService` |
| Progress فقط spinner | نوار وضعیت + **تایم‌لاین Agent Trace** (زنجیره مراحل) |
| لغو بدون ذخیره partial | ذخیره محتوای نیمه‌کاره + trace در `_stopGenerating` |
| نبود زنجیره تفکر مرئی | `trace_step` SSE + `AIAgentTraceTimeline` + ذخیره در `_agent_trace` |
| Exploration (Cursor-style) | `explore` / `explored` / `thought` trace + `ai_exploration_service` + `mode=explore\|auto\|off` |

## 🟡 باقی‌مانده (متوسط)

### DB همچنان sync
- عملیات SQLAlchemy در `run_in_executor` اجرا می‌شود؛ migration به async DB در صورت نیاز مقیاس بالا.

### بدون retry LLM
- خطای گذرا / rate limit فقط به کلاینت برمی‌گردد.

### Anthropic / Local provider
- map خطای ضعیف‌تر؛ Ollama tools ناقص در streaming.

### Operator/Admin tools
- `_register_operator_functions` و admin هنوز خالی (`pass`).

### CRM / تیکت / workflow
- non-streaming — فقط spinner کلی.

## 🔵 پیشنهاد بعدی

- Refactor state چت به Riverpod/Bloc برای تست‌پذیری
- `trace_id` در SSE برای دیباگ
- planning_tools زودتر (روی اولین delta ابزار از provider)
- i18n کامل سایر متن‌های hardcoded در `ai_chat_dialog.dart`

## قرارداد SSE (خلاصه)

| type | معنی |
|------|------|
| `status` | `phase`, `step?`, `tool_key?` |
| `trace_step` | گام تایم‌لاین: `kind`, `state`, `title_key`, `body_markdown?`, `tool?` |
| `heartbeat` | `elapsed_ms` |
| `tool_start` / `tool_end` | اجرای function |
| `content` | delta متن |
| `done: true` | پایان + usage + `agent_trace` |

انواع `kind` در trace: `context`, `explore`, `explored`, `thought`, `narrative`, `plan`, `tool`, `observation`, `plan_next`, `answer`

### حالت Exploration

| پارامتر | معنی |
|---------|------|
| `mode=auto` (پیش‌فرض) | برای سوال medium/complex فعال می‌شود |
| `mode=explore` | همیشه + Thought با LLM برای bundleهای ≥۲ ابزار |
| `mode=off` | فقط حلقهٔ agent کلاسیک |

فیلدهای اضافه در `trace_step`: `bundle_id`, `explore_target`, `entity_refs`, `findings_count`, `hypothesis`, `confidence`
