# ممیزی سیستم چت و ایجنت هوش مصنوعی حسابیکس

**نسخه سند:** 2.8  
**تاریخ ممیزی:** ۱۴۰۵/۰۵/۲۸ (۱۸ اوت ۲۰۲۶) — بازبینی runtime: subagent، ابزار موازی، تکرار context  
**وضعیت:** زنده — پس از هر اصلاح، وضعیت آیتم را عوض کنید و در [تاریخچهٔ به‌روزرسانی](#تاریخچه-بهروزرسانی) ثبت کنید.  
**دامنه:** چت درون‌برنامه، حلقهٔ ایجنت، ابزارها، حافظه، دانش، مهارت، صوت، تلگرام، CRM AI، تیکت، ورک‌فلو، MCP، مشاهده‌پذیری، UX.

> این سند جایگزین سناریوهای اجرایی قبلی نیست. جزئیات فاز ابزارها در [`AI_EXECUTION_PHASES.md`](AI_EXECUTION_PHASES.md)، باگ‌های رفع‌شدهٔ چت در [`AI_CHAT_ISSUES.md`](AI_CHAT_ISSUES.md)، شکاف پوشش دامنه در [`AI_CAPABILITY_GAP_SCENARIO_V2.md`](AI_CAPABILITY_GAP_SCENARIO_V2.md)، و سناریوی subagent / ابزار موازی / cache بینش در [`AI_AGENT_RUNTIME_CAPABILITIES_SCENARIO.md`](AI_AGENT_RUNTIME_CAPABILITIES_SCENARIO.md) است. اینجا **نقشهٔ کیفیت سطح محصول ایجنت‌محور جهانی** است.
>
> صف باگ‌های محصولی که کاربر الان در چت می‌بیند (ابزار، زیر-ایجنت، جدول داخلی، markdown، زبان تفکر، تأیید نوشتن): [`AI_CHAT_PRODUCT_ISSUES.md`](AI_CHAT_PRODUCT_ISSUES.md).

---

## چگونه از این سند استفاده کنیم

1. از [نقشهٔ سیستم](#نقشهٔ-سیستم) شروع کنید تا لایه را بشناسید.
2. هر آیتم یک شناسه دارد (`AGT-xx`, `UX-xx`, …). وضعیت را فقط از مجموعهٔ زیر انتخاب کنید:
   - `باز` — هنوز اصلاح نشده
   - `در حال اصلاح` — در شاخه/PR جاری
   - `انجام‌شده` — در کد اصلی است؛ معیار پذیرش را تیک بزنید
   - `موکول` — آگاهانه بعداً
   - `نپذیرفته` — بررسی شد و تصمیم گرفتیم انجام نشود
3. بعد از هر اصلاح: وضعیت + تاریخ + یک خط «چه شد» در همان آیتم، و یک سطر در تاریخچه.
4. وقتی یک بخش کامل سبز شد، امتیاز [کارت امتیاز](#کارت-امتیاز-نسبت-به-سطح-جهانی) همان بخش را به‌روز کنید.
5. ممیزی مجدد پیشنهادی: هر اسپرینت برای آیتم‌های `P0/P1`، هر فصل برای کل سند.

**معیار سطح جهانی** که در این سند با آن مقایسه می‌کنیم: ChatGPT (حافظه، Canvas، Custom GPT)، Claude (Skills، Artifacts، Computer Use)، Cursor (ایجنت چندمرحله‌ای، resume، subagent)، Intercom Fin / Zendesk AI (پاسخ مبتنی بر دانش با citation)، OpenAI Agents SDK / LangGraph (run state بادوام)، n8n AI Agent (ابزار در اتوماسیون).

---

## خلاصهٔ اجرایی

سیستم فعلی از نظر **عرض قابلیت** جلوتر از بسیاری از ERPهای منطقه‌ای است: حلقهٔ چندنوبتی با بودجه، حالت اجرا (تحلیلگر / با تأیید / خودکار)، تایم‌لاین تفکر، دانشنامه، حافظهٔ دوم‌لایه، مهارت، صوت محلی، MCP، و حدود ۱۰۰+ ابزار دامنه.

شکاف اصلی با محصولات ایجنت‌محور جهانی **عمق runtime و محصول** است، نه تعداد tool:

| محور | وضعیت امروز | سطح جهانی |
|------|-------------|-----------|
| حلقهٔ ایجنت | حلقهٔ واحد (استریم + aggregator)؛ run persist و ادامه؛ plan اجباری برای سوال complex؛ **subagent موقت** (`spawn_subagent`، سقف ۲×۴ نوبت، بدون write)؛ worker پس‌زمینه هنوز نیست | run بادوام، checkpoint، ادامه پس از قطع، subagent |
| انتخاب ابزار | فیلتر کلیدواژه‌ای + سقف ۴۸ + envelope برش نتیجه | progressive disclosure / router معنایی / skill-first |
| UX چت | SSE با event id و بنر ادامه؛ Enter-to-send در دسکتاپ؛ حلقهٔ استریم در `consume`؛ جلسهٔ صوت در کنترلر جدا؛ God Widget هنوز کروم UI را نگه داشته | streaming-first، بازیابی اتصال، Canvas/Artifact |
| دانش و استناد | RAG ترکیبی با fallback واژه‌ای؛ chip منبع از envelope ابزار (فاکتور/شخص/سرنخ/فرصت) | retrieval با نمره، منبع کلیک‌پذیر، ضد hallucination |
| ارزیابی | substring روی چند کیس پیش‌فرض | LLM-as-judge + tool-call assertion + eval در CI |
| مشاهده‌پذیری | `logger.info` با برچسب `AI_METRIC` | trace کامل (Langfuse/Phoenix)، هزینه، latency، کیفیت |
| چندرسانه‌ای | متن + PDF محدود؛ بدون تصویر در چت | تصویر، اسکرین‌شات، اکسل واقعی، صوت هم‌تراز متن |
| کانال‌های جانبی | تلگرام با typing و دکمهٔ تأیید؛ CRM/تیکت حلقه با allowlist (بدون استریم) | همان کیفیت ایجنت در همهٔ سطح‌ها |

**پیشنهاد ترتیب اصلاح (۱۲ هفتهٔ اول):** پایداری استریم و resume → شکستن God Objectها → **cache نیمه‌پایدار بینش (PRM-04)** → انتخاب ابزار skill-first → subagent (AGT-06) → citation قابل کلیک → eval واقعی → چندرسانه‌ای → مشاهده‌پذیری.

---

## کارت امتیاز نسبت به سطح جهانی

امتیاز ۰ تا ۵. پس از اصلاح هر بخش، عدد را عوض کنید.

| بخش | شناسه | امتیاز فعلی | هدف ۳ ماه | هدف ۱۲ ماه |
|-----|--------|-------------|-----------|------------|
| حلقهٔ ایجنت و بودجه | AGT | 4.3 | 4.0 | 4.5 |
| انتخاب و اجرای ابزار | TOOL | 4.1 | 4.0 | 4.5 |
| امنیت و تأیید نوشتن | SEC | 4.3 | 4.0 | 4.5 |
| استریم و قرارداد SSE | STR | 4.5 | 4.5 | 5.0 |
| Prompt و مدل | PRM | 4.0 | 3.5 | 4.5 |
| حافظه | MEM | 3.0 | 4.0 | 4.5 |
| دانش / RAG / استناد | RAG | 3.5 | 4.0 | 4.5 |
| مهارت و مارکت | SKL | 3.0 | 3.5 | 4.5 |
| UX چت Flutter | UX | 4.2 | 4.0 | 4.5 |
| صوت | VOI | 3.0 | 3.5 | 4.0 |
| تلگرام / CRM / تیکت | CHN | 3.6 | 3.0 | 4.0 |
| ورک‌فلو ایجنت | WFA | 3.3 | 3.5 | 4.0 |
| MCP و کانکتور | MCP | 2.8 | 3.5 | 4.5 |
| ارزیابی و مشاهده‌پذیری | OBS | 3.0 | 3.5 | 4.5 |
| سهمیه و صورتحساب | BIL | 3.5 | 4.0 | 4.5 |
| معماری و تست | ARC | 3.4 | 4.0 | 4.5 |

---

## نقشهٔ سیستم

```
کاربر (وب/دسکتاپ/موبایل Flutter)
  ├─ AIChatDialog  (~2586 خط، state متمرکز)
  │    ├─ AIChatStreamController  (SSE state + consume نوبت)
  │    ├─ AIChatStreamTurn  (انباشتگر نوبت)
  │    ├─ AIChatSessionController  (جلسه / پیام / ارسال)
  │    ├─ AIChatVoiceSessionController  (فاز صوت + تفسیر رویداد WS)
  │    ├─ AIChatTurn helpers  (send guard / voice phase / usage patch)
  │    ├─ AIService (Dart, ~1700 خط)
  │    └─ VoiceChatController → WS /ws/ai/voice
  │
  POST /api/v1/ai/chat/sessions/{id}/messages?stream=true
  │
  chat.py  (~2500 خط)
  │    ├─ سهمیه / مدل / execution_mode
  │    ├─ persist پیام کاربر
  │    └─ SSE: status, heartbeat, trace_step, tool_*, content, done
  │
  AIService (Python, ~3600 خط + mixin مسیریابی/سهمیه)  ← قلب سیستم
  │    ├─ build_system_prompt (نقش + دامنه + حافظه + دانش + مهارت)
  │    ├─ filter tools by intent (سقف ۴۸)
  │    ├─ chat_completion_stream  ← حلقهٔ ایجنت
  │    │     ├─ AgentBudget (نوبت / توکن / زمان / بی‌حاصلی)
  │    │     ├─ Exploration / ObservationStore
  │    │     ├─ Goal assessment + continuation
  │    │     ├─ Write guard + execution policy
  │    │     └─ Forced synthesis اگر متن نهایی نیامد
  │    └─ chat_completion  ← aggregator روی همان generator
  │
سطح‌های دیگر (همان حلقه؛ UX استریم هنوز فقط چت درون‌برنامه)
  ├─ TelegramAIChatService  (typing + دکمهٔ تأیید/رد)
  ├─ /ai/crm/*  (ابزار فقط‌خواندنی CRM، سقف ۴ نوبت)
  ├─ /support/tickets/{id}/ai-suggest-reply  (ابزار مالی فقط‌خواندنی، سقف ۴ نوبت)
  ├─ Workflow AIAgentAction
  ├─ /ai/mcp  (JSON-RPC روی HTTP)
  └─ scheduled tasks (کرون ثابت، ۴ تسک built-in)
```

**اندازهٔ فعلی (بدهی معماری):**

| فایل | خطوط | نقش |
|------|------|------|
| `hesabixAPI/app/services/ai/ai_service.py` | ~3600 | ارکستراسیون حلقه (routing/quota جدا) |
| `hesabixAPI/app/services/ai/ai_model_router.py` | ~370 | mixin مسیریابی مدل |
| `hesabixAPI/app/services/ai/ai_usage_meter.py` | ~370 | mixin سهمیه و لاگ مصرف |
| `hesabixAPI/adapters/api/v1/ai/chat.py` | ~2500 | API چت |
| `hesabixUI/.../ai_chat_dialog.dart` | ~2586 | UI و state |
| `hesabixAPI/app/services/ai/function_registry.py` | ~1900 | ثبت ابزار |
| `hesabixUI/.../ai_service.dart` | ~1700 | کلاینت API |
| بستهٔ `app/services/ai/` | ۱۰۷ فایل | زیرسیستم‌ها |

---

## قرارداد وضعیت آیتم‌ها

هر آیتم این قالب را دارد:

```
### شناسه — عنوان
- وضعیت: باز
- اولویت: P0 | P1 | P2 | P3
- مالک پیشنهادی: backend / flutter / infra / product
- فایل‌های اصلی: …
- مشکل: …
- معیار پذیرش سطح جهانی: …
- پیشنهاد اصلاح: …
- یادداشت اصلاح: (خالی تا انجام شود)
```

اولویت: `P0` مانع تجربه یا امنیت است؛ `P1` فاصلهٔ واضح با رقبا؛ `P2` کیفیت؛ `P3` تمایز بلندمدت.

---

# A. حلقهٔ ایجنت و Runtime

### AGT-01 — Run state سبک است؛ resume واقعی وجود ندارد
- وضعیت: انجام‌شده
- اولویت: P0
- مالک: backend + flutter
- فایل‌ها: `ai_agent_run.py`، `ai_agent_run_store.py`، `adapters/db/models/ai_agent_run.py`، `chat.py`، `ai_chat_dialog.dart`
- مشکل: `AgentRunState` صریحاً «FSM کامل نیست». `extract_agent_run_checkpoint` فقط از `function_results` می‌خواند و کامنت می‌گوید UI ادامه هنوز پیاده نشده. قطع شبکه، kill سرور، یا رسیدن به سقف بودجه یعنی از دست رفتن کار. محصولات جهانی (Cursor، ChatGPT، Claude) run را persist می‌کنند و دکمهٔ Continue دارند.
- معیار پذیرش: پس از قطع استریم، کاربر بتواند همان `run_id` را ادامه دهد؛ ابزارهای تکراری دوباره اجرا نشوند؛ todos جلسه حفظ شوند.
- پیشنهاد:
  1. جدول `ai_agent_runs` با `run_id`, `session_id`, `phase`, `iteration`, `observation_store`, `budget_snapshot`, `status`.
  2. هر نوبت tool یک checkpoint بنویسد.
  3. API `POST .../runs/{run_id}/continue` و رویداد SSE `run_resumed`.
  4. در UI دکمهٔ «ادامهٔ تحلیل» وقتی پیام `done` با `stop_reason=budget|disconnect` است.
- یادداشت اصلاح: ۱۴۰۵/۰۵/۲۶ — جدول `ai_agent_runs`، checkpoint هر نوبت tool، `POST /sessions/{id}/runs/{run_id}/continue`، رویداد `run_resumed`/`agent_run`، بنر «ادامهٔ تحلیل». حلقه هنوز داخل همان درخواست HTTP است (AGT-02). میگریشن `20260817_000002_ai_agent_runs`.

### AGT-02 — حلقه داخل یک درخواست HTTP زندگی می‌کند
- وضعیت: باز
- اولویت: P1
- مالک: backend
- فایل‌ها: `adapters/api/v1/ai/chat.py` (`_stream_message_response`)، `ai_service.py`
- مشکل: کل حلقه تا ۳۰۰ ثانیه (سوال پیچیده) روی یک اتصال SSE است. persist پس از disconnect با `_schedule_stream_persist_after_disconnect` بهتر از هیچ است، اما worker جدا برای ایجنت وجود ندارد. مقیاس و timeout پروکسی (nginx) شکننده است.
- معیار پذیرش: اجرای ایجنت روی job/queue با fan-out رویداد به کلاینت؛ قطع مرورگر اجرای سرور را نکشد.
- پیشنهاد: الگوی «run در پس‌زمینه + SSE/WS subscribe». مشابه OpenAI Assistants `runs` یا LangGraph Server.
- یادداشت اصلاح:

### AGT-03 — سقف بودجه و ضد حلقه خوب است؛ سیگنال به کاربر ضعیف است
- وضعیت: انجام‌شده
- اولویت: P1
- مالک: backend + flutter
- فایل‌ها: `ai_budget.py`، `ai_stream_helpers.py`، `ai_error_recovery_banner.dart`، `ai_chat_dialog.dart`
- مشکل: بودجهٔ چندبعدی (نوبت ۳–۱۵، توکن، wall-clock، ۲ نوبت بی‌حاصل، تمدید حداکثر ۲ بار) طراحی پخته‌ای است. وقتی حلقه به‌خاطر `unproductive` یا `identical tool repeats` می‌ایستد، کاربر اغلب فقط یک پاسخ ناقص یا سنتز اجباری می‌بیند؛ دلیل توقف و «چه داده کم است» شفاف نیست.
- معیار پذیرش: در UI و متن نهایی: دلیل توقف + یافته‌های جمع‌شده + پیشنهاد ادامه با یک کلیک.
- پیشنهاد: `stop_reason` را در `done` و در پیام ذخیره کنید؛ بنر «تحلیل ناقص ماند چون …» با CTA ادامه.
- یادداشت اصلاح: ۱۴۰۵/۰۵/۲۶ — `stop_reason` / `stop_message_fa` روی رویداد `done`؛ بنر ادامه متن `stop_message_fa` را نشان می‌دهد. یافته‌های جمع‌شده هنوز در پنل استدلال است نه داخل بنر.

### AGT-04 — Forced synthesis و پاسخ زودهنگام هنوز dual-path هستند
- وضعیت: انجام‌شده
- اولویت: P1
- مالک: backend
- فایل‌ها: `ai_deliverable_answer.py`، `ai_service.py` (پایان استریم)، `chat.py` (persist)
- مشکل: تشخیص «پاسخ تحویلی» چند ماژول موازی دارد؛ در persist فقط log می‌شود و کاربر پاسخ نیمه‌کاره می‌بیند. تست‌ها خوب‌اند اما در پروداکشن هنوز hallucination وضعیت («فاکتوری نیست») بدون tool ممکن است برسد.
- معیار پذیرش: اگر `query_expects_tool_use` و evidence نیست، هرگز `done` با ادعای دادهٔ کسب‌وکار نرود؛ یا tool اجباری یا سوال شفاف‌سازی.
- پیشنهاد: یک دروازهٔ واحد قبل از persist؛ کیس eval برای «بدون tool جواب نده».
- یادداشت اصلاح: ۱۴۰۵/۰۵/۲۶ — `is_deliverable_answer` ادعای داده بدون tool را رد می‌کند؛ `gate_ungrounded_assistant_content` قبل از persist و در پایان استریم متن را با شفاف‌سازی عوض می‌کند؛ `final_content` روی `done` UI را با نسخهٔ persist هم‌تراز می‌کند. سلام و سوال شفاف‌سازی حفظ می‌شود. eval suite طلایی هنوز OBS-01 است.

### AGT-05 — Planning و todos جلسه هنوز اختیاری و دیرهنگام‌اند
- وضعیت: انجام‌شده
- اولویت: P2
- مالک: backend + flutter
- فایل‌ها: `ai_session_todo_service.py`، `ai_function_extensions_session_todos.py`، `ai_agent_todo_list.dart`، `ai_constants.py` (`PLANNING_STEP_MIN_CHARS`)
- مشکل: todos سقف ۲۰ آیتم دارند و در UI نمایش داده می‌شوند. «plan» در استریم اغلب فقط یک `trace_step` آرایشی با متن هدف است (`ai_service.py` حدود ۲۹۲۵–۲۹۳۵) نه فراخوانی مدل برنامه‌ریز یا DAG ابزار. در `AI_CHAT_ISSUES.md` هم برنامه‌ریزی زودهنگام به‌عنوان پیشنهاد مانده. Cursor قبل از ابزار یک plan مرئی می‌سازد. Intent فیلتر قبلاً `create_session_plan` را قبل از منطق expose حذف می‌کرد مگر کلیدواژهٔ «مرحله/گام».
- معیار پذیرش: برای سوال `complex`، قبل از اولین tool یک plan با todos ساخته شود و کاربر بتواند آیتم را رد/تأیید کند.
- پیشنهاد: toolهای plan را در iteration 0 اجباری کنید وقتی complexity=complex؛ UI plan را بالای thread پین کند.
- یادداشت اصلاح: ۱۴۰۵/۰۵/۲۶ — ابزارهای plan در allowlist با `prefer_names`/`forced_names` می‌مانند (حتی بدون کلیدواژهٔ برنامه). برای `complex` بدون برنامهٔ باز، prompt `require_first` و در OpenAI/Anthropic `tool_choice` روی `create_session_plan` است؛ medium فقط expose می‌شود. برنامه بالای پنل استدلال پین می‌شود. کاربر می‌تواند آیتم باز را از UI `skipped`/`done` کند (`PATCH .../todos/{id}`، فقط از `pending`/`in_progress`).

### AGT-06 — Subagent / کار موازی وجود ندارد
- وضعیت: انجام‌شده (فاز ۰–۲؛ UI و citation ادغام موکول)
- اولویت: P1
- مالک: backend + flutter
- فایل‌ها: `ai_subagent.py`، `ai_function_extensions_subagent.py`، `ai_service.py` (`handle_function_calls_async`)، `function_registry.py`، `ai_agent_run.py`؛ سناریو: [`AI_AGENT_RUNTIME_CAPABILITIES_SCENARIO.md`](AI_AGENT_RUNTIME_CAPABILITIES_SCENARIO.md)
- مشکل: همهٔ کار در یک حلقه و یک مدل است. هیچ ابزار spawn/delegate نیست. ایجنت‌های جهانی برای «گزارش فروش + موجودی + بدهکاران» چند subagent موازی می‌زنند، منتظر اتمام می‌مانند یا قطع می‌کنند، بعد نتیجه را نقد و ادغام می‌کنند. `GAP-07` (شخصیت ثابت حسابدار/انباردار) این قابلیت نیست.
- معیار پذیرش: والد بتواند حداکثر ۲ زیر-اجرا با allowlist و سقف ۴ نوبت بسازد؛ پیش‌فرض بدون write؛ cancel والد فرزند را هم ببندد؛ نتیجه به‌صورت envelope + citation به والد برگردد؛ سوال ساده spawn نکند.
- پیشنهاد: الگوی Cursor Task tool / LangGraph subgraph روی همان `AIService` با `operation=subagent`. بعد از AGT-01 و سقف TOOL-06.
- یادداشت اصلاح: ۱۴۰۵/۰۵/۲۸ — بررسی کد: صفر hit برای spawn/subagent در سرویس AI. اولویت از P3 به P1. سناریوی فاز ۰–۴ نوشته شد. ۱۴۰۵/۰۵/۲۸ (همان روز) — فاز ۰–۲: ابزارهای `spawn_subagent` / `await_subagent` / `cancel_subagent`؛ حلقهٔ تو در تو analyzer با سقف ۲ همزمان و ۴ نوبت؛ write در فرزند fail-closed؛ سوال ساده ابزار spawn نمی‌بیند؛ cancel والد فرزندان در حال اجرا را قطع می‌کند. persist جدول SQL و `trace_step` kind=subagent (فاز ۳–۴) موکول. شکاف UI برای کاربر: [`AI_CHAT_PRODUCT_ISSUES.md`](AI_CHAT_PRODUCT_ISSUES.md) آیتم CHAT-02.

### AGT-07 — شاخهٔ مرده در ادامهٔ evidence (`prior_goal_reached`)
- وضعیت: انجام‌شده
- اولویت: P1
- مالک: backend
- فایل‌ها: `ai_agent_continuation.py`
- مشکل: بعد از `if had_evidence: return …` بلوک `prior_goal_reached` هرگز اجرا نمی‌شد.
- معیار پذیرش: یا شاخه حذف شود، یا ترتیب شرط‌ها طوری باشد که `prior_goal_reached` قبل از return شواهد ارزیابی شود؛ تست واحد برای هر دو مسیر.
- پیشنهاد: بازنویسی `assess_text_round_evidence` با جدول تصمیم صریح (loop / todos / discovery / evidence / prior).
- یادداشت اصلاح: ۱۴۰۵/۰۵/۲۶ — شرط `prior_goal_reached` به قبل از بلوک thoughts منتقل شد؛ تست `test_stop_when_prior_goal_reached_with_evidence`.

### AGT-08 — آستانهٔ حلقهٔ ابزار تکراری خیلی تند است
- وضعیت: انجام‌شده
- اولویت: P2
- مالک: backend
- فایل‌ها: `ai_constants.py` (`AGENT_MAX_IDENTICAL_TOOL_REPEATS = 1`، `AGENT_MAX_IDENTICAL_TOOL_FAILURES = 2`)، `ai_goal_assessment.py`
- مشکل: دومین فراخوانی عیناً همان tool+args حلقه را می‌بندد. برای صفحه‌بندی (`offset`) یا تأیید پس از mismatch ممکن است false positive باشد.
- معیار پذیرش: تکرار مجاز اگر args فرق کند (مثلاً page) یا اگر نتیجهٔ قبلی خطا/خالی بوده؛ در غیر این صورت stop با پیام واضح.
- پیشنهاد: کلید loop شامل نام + canonical args + کد نتیجهٔ قبلی.
- یادداشت اصلاح: ۱۴۰۵/۰۵/۲۶ — موفقیت عیناً تکراری همان سقف ۱؛ خطا/خالی/تأیید تا ۲ بار مجاز است (`classify_tool_result_outcome`). offset متفاوت loop نیست.

---

# B. ابزارها (Function calling)

### TOOL-01 — انتخاب ابزار کلیدواژه‌ای است و سقف ۴۸ دارد
- وضعیت: انجام‌شده
- اولویت: P0
- مالک: backend
- فایل‌ها: `ai_tool_intent.py`، `ai_tool_rank.py`، `ai_service.get_available_functions`، `tests/test_ai_tool_intent_gold.py`
- مشکل: با ~۱۱۳ tool، مدل در هر درخواست حداکثر ۴۸ تا را می‌بیند. اگر intent اشتباه دسته را حدس بزند (مثلاً «باسلام» در `integration` نیاید)، مدل ابزار را hallucinate یا از query عمومی استفاده می‌کند. کاتالوگ برای سوال «چه ابزارهایی داری؟» خوب است، اما routing روزمره ضعیف است.
- معیار پذیرش: recall ابزار درست روی مجموعهٔ طلایی سوالات دامنه ≥ ۹۵٪؛ هیچ tool بدون entry در intent/permission/l10n اضافه نشود (از قبل در چک‌لیست فازها هست).
- پیشنهاد:
  1. کوتاه‌مدت: embedding کوچک روی `(name, description, examples)` برای ranking به‌جای/در کنار regex.
  2. میان‌مدت: skill-first — فقط core (~۱۲) + ابزارهای skill فعال + ۲ دستهٔ top.
  3. مثال‌های few-shot per tool در schema (مدل‌های جدید با این خیلی بهتر انتخاب می‌کنند).
- یادداشت اصلاح: ۱۴۰۵/۰۵/۲۶ — سقف ۴۸ با رتبهٔ واژه‌ای (نام+alias) به‌جای الفبا؛ تاریخچه به `select_tool_names` می‌رسد؛ مهارت با دامنه اتحاد می‌شود نه جایگزینی؛ دسته/کلیدواژه برای کیف پول، سرفصل، کالا، بدهکار، hscript. مجموعه طلایی ۱۶ کیس با recall ≥ ۹۵٪. embedding هنوز نیست (مرحله بعد).

### TOOL-02 — God registry و ثبت ناقص نقش‌ها
- وضعیت: باز
- اولویت: P1
- مالک: backend
- فایل‌ها: `function_registry.py` خطوط ۱۶۳۵–۱۶۴۸
- مشکل: `_register_operator_functions`، `_register_admin_functions`، `_register_business_owner_functions` همگی `pass` با کامنت «بعداً». نقش در enum هست اما ابزار اختصاصی نیست. اپراتور پشتیبانی و ادمین همان ابزار کاربر را با prompt امنیتی می‌گیرند.
- معیار پذیرش: کاتالوگ جدا برای operator (تیکت، جلسه، وضعیت سیستم) و admin (tenant، usage، eval) با permission سخت.
- پیشنهاد: هر نقش یک ماژول `ai_function_extensions_<role>.py`؛ پیش‌فرض deny.
- یادداشت اصلاح:

### TOOL-03 — پوشش دامنه هنوز ناقص است (فاز ۹)
- وضعیت: باز
- اولویت: P1
- مالک: backend + product
- فایل‌ها: `AI_EXECUTION_PHASES.md` فاز ۹، `ai_function_extensions_phase8.py`
- مشکل: گزارشات/قالب/باشگاه MVP شده؛ هنوز خرید افزونه، sync باسلام، conflict، ووکامرس overview، ساخت قالب و preview PDF از چت نیست. قالب اعلان ۰٪.
- معیار پذیرش: سناریوهای پذیرش بخش ۵ در `AI_CAPABILITY_GAP_SCENARIO_V2.md` همه سبز.
- پیشنهاد: همان فاز ۹؛ هر tool جدید را به eval طلایی وصل کنید.
- یادداشت اصلاح:

### TOOL-04 — نتایج ابزار کوتاه و بدون schema پایدار برای UI
- وضعیت: انجام‌شده
- اولویت: P2
- مالک: backend + flutter
- فایل‌ها: `ai_tool_result.py`، `ai_constants.py` (`MAX_TOOL_RESULT_JSON_CHARS` / `MAX_TOOL_RESULT_RECORDS`)، `ai_citation_service.py`، `ai_chat_table_widget.dart`، `ai_tool_envelope.dart`
- مشکل: برش ۶۰۰۰ کاراکتر باعث از دست رفتن ردیف‌های گزارش می‌شود؛ مدل جمع می‌بندد. Citation با حدس کلید `items/data/results` ساخته می‌شود نه با قرارداد اجباری. جدول/نمودار به markdown یا spec وابسته است.
- معیار پذیرش: هر tool read یک `ToolResultEnvelope` با `records`, `summary`, `citations[]`, `truncated` برگرداند؛ UI جدول را از envelope بکشد نه از markdown.
- پیشنهاد: envelope واحد + صفحه‌بندی اجباری (`offset/limit`) در همهٔ list toolها.
- یادداشت اصلاح: ۱۴۰۵/۰۵/۲۶ — لایهٔ dispatch: اگر نتیجه بزرگ باشد envelope معتبر با `truncated`/`omitted_count`/`citations`/`note` ساخته می‌شود (دیگر JSON وسط قطع نمی‌شود). Citation اول از `citations` می‌خواند. UI اگر markdown جدول نداشته باشد از رکوردهای ابزار جدول می‌کشد. بازنویسی تک‌تک list toolها و `offset/limit` اجباری هنوز نیست. ۱۴۰۵/۰۵/۲۷ — اثر جانبی: همان جدول خودکار `_reasoning_trace` را با ستون‌های `trace_id`/`step_id`/`kind` نشان می‌دهد (CHAT-03).

### TOOL-05 — کش ابزار فقط TTL کوتاه و درون‌جلسه‌ای است
- وضعیت: باز
- اولویت: P3
- مالک: backend
- فایل‌ها: `ai_tool_cache.py`، `TOOL_CACHE_TTL_SEC = 60`
- مشکل: ۶۰ ثانیه برای داشبورد خوب است؛ برای گزارش سنگین کوتاه است. بین جلسات اشتراک نیست. invalidation روی write مشخص نیست.
- معیار پذیرش: پس از write موفق، کلیدهای مرتبط همان موجودیت invalidate شوند؛ TTL قابل تنظیم per-tool.
- پیشنهاد: tag محور (`entity:invoice:123`) و drop روی write guard success.
- یادداشت اصلاح:

### TOOL-06 — اجرای موازی ابزار بدون سقف و بدون تراکنش
- وضعیت: انجام‌شده
- اولویت: P1
- مالک: backend
- فایل‌ها: `ai_tool_parallel.py`، `ai_service.py` (`handle_function_calls_async`)، `ai_constants.py` (`MAX_PARALLEL_READ_TOOLS = 4`)
- مشکل: همهٔ toolهای یک نوبت موازی‌اند. چند write + چند read روی همان موجودیت race می‌کنند؛ invalidation کش بعد از هر write است نه اتمیک برای کل round. stampede روی DB در سوال پیچیده محتمل است.
- معیار پذیرش: سقف همزمانی (مثلاً ۴)؛ writeها سریال؛ readهای readonly موازی؛ ترتیب پایدار در trace.
- پیشنهاد: semaphore + جدا کردن write/read در round.
- یادداشت اصلاح: ۱۴۰۵/۰۵/۲۶ — دسته‌بندی پایدار read/write؛ read حداکثر ۴تایی موازی؛ write سد سریال؛ ترتیب مدل حفظ می‌شود. تراکنش اتمیک کل round هنوز نیست. ۱۴۰۵/۰۵/۲۸ — تأیید شد مدل مجاز است چند `tool_calls` در یک نوبت بدهد (`parallel_tool_calls` غیرفعال نشده؛ prompt مسیریابی موازی را تشویق می‌کند). شکاف باقی: نمایش موازی در UI، و قفل `tool_choice` روی plan در نوبت صفر `complex`. ۱۴۰۵/۰۵/۲۸ — فاز A–B و سقف prompt: متریک `tool_round_parallel` (`tool_calls_in_round` / `parallel_read_count`)؛ کیس eval طلایی فروش+موجودی+بدهکار با `min_tools_in_round`؛ در routing سقف ۴ read نوشته شد. فاز C (UI موازی) موکول.

### TOOL-07 — `tool_choice=required` فقط برای OpenAI
- وضعیت: انجام‌شده
- اولویت: P2
- مالک: backend
- فایل‌ها: `ai_service.py`، `ai_provider.py` Anthropic stream، `ai_constants.py` (`PROVIDERS_WITH_FORCED_TOOLS`)
- مشکل: در iteration اول وقتی `needs_tools` است، OpenAI مجبور به tool می‌شود؛ Anthropic/Local این سیگنال را نمی‌گیرند. مسیر غیر OpenAI بیشتر در معرض پاسخ زودهنگام است.
- معیار پذیرش: معادل Anthropic (`tool_choice` / `disable_parallel` مطابق API جاری) یا prompt اجباری یکسان؛ تست با هر provider.
- یادداشت اصلاح: ۱۴۰۵/۰۵/۲۶ — `required` → `{"type":"any"}` و function object → `{"type":"tool","name":…}`. Local هنوز بدون tool_choice است.

---

# C. امنیت، تأیید نوشتن، چندمستأجری

### SEC-01 — تأیید نوشتن با تطبیق دقیق JSON شکننده است
- وضعیت: انجام‌شده
- اولویت: P1
- مالک: backend + flutter
- فایل‌ها: `ai_write_guard.py` (`resolve_approved_write`)، `ai_execution_policy.py`، `ai_write_approval_banner.dart`
- مشکل: تأیید فقط اگر `function` و `arguments` با JSON canonical عیناً یکی باشند. اگر مدل بعد از تأیید فیلد بی‌ضرری را عوض کند → `APPROVAL_MISMATCH`. تجربهٔ جهانی: کارت تأیید با diff و تأیید «همین عملیات» با id پایدار، نه hash کل args.
- معیار پذیرش: هر write یک `approval_id` می‌گیرد؛ تأیید روی id است؛ تغییر args نیاز به تأیید مجدد با diff دارد.
- پیشنهاد: جدول/فیلد pending approvals در session؛ UI diff فارسی.
- یادداشت اصلاح: ۱۴۰۵/۰۵/۲۶ — هر `APPROVAL_REQUIRED` یک `approval_id` دارد. اگر فقط یک کارت برای همان تابع در انتظار باشد، آرگومان ذخیره‌شده اجرا می‌شود (نه آرگومان جهش‌یافتهٔ مدل). دو کارت هم‌نام هنوز تطبیق دقیق می‌خواهند. UI diff فارسی هنوز نیست.

### SEC-02 — MCP می‌تواند write را با query string باز کند
- وضعیت: انجام‌شده
- اولویت: P0
- مالک: backend
- فایل‌ها: `adapters/api/v1/ai/mcp.py`، `ai_mcp_service.py`
- مشکل: `approve_writes=true` روی URL یعنی هر کلاینت MCP با همان API key می‌تواند ابزار مخرب را بدون HITL بزند.
- معیار پذیرش: MCP به‌صورت پیش‌فرض read-only؛ write فقط با header/body امضاشده یا همان کارت تأیید آسنکرون؛ هرگز query flag.
- پیشنهاد: حذف query؛ scope در API key (`ai:tools:read` / `ai:tools:write`)؛ audit log اجباری.
- یادداشت اصلاح: ۱۴۰۵/۰۵/۲۶ — query flag حذف شد؛ `_approve_writes` در آرگومان ابزار نادیده گرفته می‌شود؛ فقط `params.approve_writes === true` در JSON-RPC مجاز است. scope API key هنوز باز است.

### SEC-03 — کانکتور HTTP SSRF را تا حدی می‌بندد؛ هنوز کامل نیست
- وضعیت: در حال اصلاح
- اولویت: P1
- مالک: backend
- فایل‌ها: `ai_connector_service.py`، `tests/test_ai_connector_security.py`
- مشکل: بلاک IP خصوصی، metadata AWS/GCP، و scheme محدود شده. DNS rebinding (resolve به عمومی سپس به خصوصی)، IPv6 link-local، و redirect به metadata ممکن است باقی بماند. فقط GET/POST.
- معیار پذیرش: resolve DNS سپس بررسی IP نهایی؛ رد redirect به غیرعمومی؛ allowlist دامنه per کسب‌وکار.
- پیشنهاد: تست‌های `test_ai_connector_security.py` را با rebinding و IPv6 گسترش دهید.
- یادداشت اصلاح: ۱۴۰۵/۰۵/۲۶ — IPv6 link-local، IPv4-mapped خصوصی، و metadata IP مسدود است؛ `trust_env=False`؛ پاسخ ۳xx بدون دنبال کردن و بدون افشای Location به مدل برمی‌گردد. پین TLS به IP resolveشده هنوز نیست؛ allowlist دامنه per کسب‌وکار هنوز نیست.

### SEC-04 — دفاع prompt injection و نشت PII عمدتاً prompt است نه کنترل
- وضعیت: در حال اصلاح
- اولویت: P1
- مالک: backend
- فایل‌ها: `ai_untrusted.py`، `ai_knowledge_service.py`، `crm_ai.py`
- مشکل: sanitize فقط توکن Harmony را پاک می‌کند. دستورات امنیتی اپراتور/ادمین در prompt هستند. CRM AI شماره موبایل را خام به مدل می‌فرستد. دانشنامه و کانکتور می‌توانند دستور «ignore previous» تزریق کنند.
- معیار پذیرش: جداسازی دادهٔ بازیابی‌شده در بلاک quoteشده؛ ماسک PII قبل از LLM برای کانال‌های غیرضروری؛ تست حمله روی دانشنامه و tool result.
- پیشنهاد: سیاست «tool output is untrusted data»؛ redaction لایهٔ میانی؛ eval امنیتی جدا.
- یادداشت اصلاح: ۱۴۰۵/۰۵/۲۶ — سیاست untrusted در prefix استاتیک prompt؛ دانشنامه داخل `<untrusted_knowledge>`؛ موبایل/ایمیل CRM ماسک می‌شود. نتیجهٔ ابزار JSON خام می‌ماند تا function calling نشکند. eval حمله روی tool result هنوز نیست.

### SEC-05 — لیست استاتیک WRITE_FUNCTIONS با registry هم‌گام نیست
- وضعیت: انجام‌شده
- اولویت: P2
- مالک: backend
- فایل‌ها: `ai_write_guard.py` (`WRITE_FUNCTIONS`)، `AIFunction.requires_approval`
- مشکل: دو منبع حقیقت. اگر tool جدید `requires_approval=True` داشته باشد ولی در fallback نباشد، مسیر بدون registry ناامن می‌شود (مثلاً MCP که `is_write_function(name)` را گاهی بدون registry صدا می‌زند).
- معیار پذیرش: یک منبع: فقط registry؛ تست که هر `requires_approval` در مسیر MCP/workflow هم بایستد.
- پیشنهاد: حذف تدریجی `WRITE_FUNCTIONS`؛ fail-closed اگر function در registry نیست.
- یادداشت اصلاح: ۱۴۰۵/۰۵/۲۶ — با registry، `requires_approval` منبع حقیقت است و نام ناشناخته fail-closed (write) است. بدون registry همان لیست استاتیک می‌ماند. حذف کامل لیست استاتیک هنوز نیست.

---

# D. استریم، قرارداد SSE، پایداری اتصال

### STR-01 — بدون Last-Event-ID و reconnect
- وضعیت: انجام‌شده
- اولویت: P0
- مالک: backend + flutter
- فایل‌ها: `ai_stream_helpers.py`، `ai_sse_event_buffer.py`، `ai_sse_client_web.dart` / stub، `ai_chat_stream_controller.dart`، `ai_service.dart`
- مشکل: اگر تب پس‌زمینه شود، پروکسی قطع کند، یا Wi-Fi بپرد، استریم می‌میرد. ChatGPT/Claude از event id و replay استفاده می‌کنند. کلاینت وب و غیر وب SSE جدا دارند.
- معیار پذیرش: reconnect با `Last-Event-ID` تا ۱۵ دقیقه؛ UI بدون پیام تکراری؛ اگر run در پس‌زمینه است (AGT-02) فقط subscribe مجدد.
- پیشنهاد: `id:` در هر SSE؛ بافر حلقوی per run در Redis؛ Dart: retry با backoff.
- یادداشت اصلاح: ۱۴۰۵/۰۵/۲۶ — `id:` + `sse_id` روی هر رویداد؛ بافر درون‌پردازه‌ای ۱۵ دقیقه (نه Redis)؛ کلاینت `Last-Event-ID` می‌فرستد؛ اگر producer مرده باشد reconnect برابر continue همان `run_id` است (AGT-01). worker پس‌زمینه هنوز AGT-02 است.

### STR-02 — مسیر non-stream هنوز بزرگ و دوگانه است
- وضعیت: انجام‌شده
- اولویت: P1
- مالک: backend
- فایل‌ها: `ai_stream_aggregate.py`، `ai_service.chat_completion`، `chat.py`، تلگرام/CRM/تیکت/ورک‌فلو
- مشکل: مسیر غیر استریم exploration، Plan C، سنتز اجباری، `tool_choice=required` و wall-clock وسط استریم را ندارد. تلگرام/CRM/تیکت/ورک‌فلو روی همین مسیر نازک‌اند؛ کیفیت ایجنت بین کانال‌ها دوشاخه شده.
- معیار پذیرش: یک حلقهٔ واحد؛ non-stream فقط aggregator روی همان generator.
- پیشنهاد: `chat_completion` را به consume کردن `chat_completion_stream` تبدیل کنید.
- یادداشت اصلاح: ۱۴۰۵/۰۵/۲۶ — `chat_completion` فقط `aggregate_chat_completion_stream` است؛ `temperature_override` به استریم رسید. UX استریم برای CRM/تیکت هنوز CHN-02 است.

### STR-03 — heartbeat و status خوب‌اند؛ event id و schema نسخه‌بندی ندارند
- وضعیت: باز
- اولویت: P2
- مالک: backend + flutter
- فایل‌ها: `AI_CHAT_ISSUES.md` جدول SSE، `ai_stream_event.dart`
- مشکل: قرارداد در markdown است نه در OpenAPI/JSON Schema. کلاینت قدیمی با فیلد جدید می‌شکند یا نادیده می‌گیرد. `trace_id` در ISSUES به‌عنوان پیشنهاد مانده.
- معیار پذیرش: `protocol_version` در اولین event؛ schema تولیدشده؛ `trace_id`/`run_id` روی همهٔ eventها.
- پیشنهاد: Pydantic مدل برای SSE + تست سازگاری Dart.
- یادداشت اصلاح:

### STR-04 — Local/Ollama در استریم ابزار ندارد
- وضعیت: باز
- اولویت: P1
- مالک: backend
- فایل‌ها: `ai_provider.py` کلاس `LocalProvider` (~۸۰۶)
- مشکل: هم `chat_completion` و هم stream، `tools` را به Ollama نمی‌فرستند. ایجنت روی مدل محلی عملاً چت متنی است. Timeout جدا (۶۰/۱۲۰) با ثابت‌های OpenAI (۱۲۰/۱۸۰) ناهماهنگ است. httpx sync client در سازنده.
- معیار پذیرش: tool call در Ollama (API `/api/chat` با `tools`) در stream parse شود؛ اگر مدل پشتیبانی نکند، خطا واضح به UI.
- پیشنهاد: آداپتور OpenAI-compatible برای vLLM/Ollama؛ حذف مسیر اختصاصی شکننده.
- یادداشت اصلاح:

### STR-05 — رویداد `done` فیلدهای حیاتی سرویس را دور می‌ریزد
- وضعیت: انجام‌شده
- اولویت: P0
- مالک: backend + flutter
- فایل‌ها: `chat.py`، `ai_stream_helpers.py`، `ai_stream_event.dart`، `ai_service.dart`
- مشکل: سرویس روی chunk پایانی `agent_budget`، `awaiting_approval`، `citations_context`، `execution_mode`، `resolved_model` می‌فرستاد؛ لایهٔ API هنگام rebuild آن‌ها را دور می‌ریخت.
- معیار پذیرش: همهٔ فیلدهای done سرویس به کلاینت برسند؛ تست قرارداد SSE که فیلدها drop نشوند.
- پیشنهاد: مدل Pydantic واحد برای SSE + `message_id` پس از persist.
- یادداشت اصلاح: ۱۴۰۵/۰۵/۲۶ — `build_chat_done_sse_data` + capture کامل در chat.py؛ کلاینت `awaitingApproval` / بودجهٔ تمدید را می‌خواند.

### STR-06 — پاسخ نهایی اغلب توکن‌استریم واقعی نیست + پد nginx
- وضعیت: باز
- اولویت: P2
- مالک: backend
- فایل‌ها: `ai_service.py` (برش مصنوعی ~۴۸ کاراکتر + `asyncio.sleep(0)` هنگام سنتز از trace)؛ `chat.py` حدود ۱۳۷۵–۱۳۷۷ (کامنت پد ~۲KB روی هر event)
- مشکل: وقتی پاسخ از trace سنتز می‌شود کاربر «تایپ شدن» ساختگی می‌بیند نه توکن مدل. پد ۲KB برای هر heartbeat/status پهنای باند را در تحلیل طولانی بالا می‌برد.
- معیار پذیرش: اگر متن از مدل است، delta واقعی؛ پد فقط روی event اول یا با flag محیطی برای nginx buffering.
- یادداشت اصلاح:

---

# E. Prompt، مدل، زبان

### PRM-01 — ترکیب prompt از چند بلوک؛ بودجهٔ سیستم ۳۲k کاراکتر
- وضعیت: در حال اصلاح
- اولویت: P1
- مالک: backend
- فایل‌ها: `ai_system_prompt.py`، `ai_prompt_cache.py`، `ai_untrusted.py`، `ai_usage_meter.py`
- مشکل: نقش + حسابداری + routing + فیلتر + visualization + workflow + حافظه + دانش + مهارت + execution_mode. برای مدل‌های کوچک overload است؛ برای مدل‌های بزرگ prefix cache کمک می‌کند (`PROMPT_CACHE_ENABLED`) اما ترتیب بلاک‌ها برای cache Anthropic/OpenAI باید پایدار باشد. تغییر یک بلاک کل cache را می‌شکند.
- معیار پذیرش: بلاک استاتیک (نقش، سیاست) جدا از بلاک داینامیک (دانش، حافظه جلسه)؛ hit rate cache در usage log دیده شود.
- پیشنهاد: اندازه‌گیری `cached_tokens` در داشبورد ادمین؛ کوتاه کردن routing با skill-first (TOOL-01).
- یادداشت اصلاح: ۱۴۰۵/۰۵/۲۶ — `StructuredSystemPrompt` از قبل static/dynamic جدا بود. سیاست untrusted به static_core اضافه شد (پایدار برای cache). `cached_tokens` در context مصرف لاگ و شمارندهٔ `usage_logged` می‌آید. داشبورد ادمین هنوز نیست.

### PRM-02 — تخمین پیچیدگی و routing مدل heuristic است
- وضعیت: انجام‌شده
- اولویت: P2
- مالک: backend
- فایل‌ها: `ai_tool_intent.estimate_query_complexity`، `ai_constants` (`REASONING_EFFORT_BY_COMPLEXITY`)، `AI_OPERATION_*`
- مشکل: medium/complex با طول و کلیدواژه. سوال کوتاه «تراز آزمایشی فروردین» ممکن است simple شود و iteration=3 بگیرد. مدل `auto` بر همین سیگنال است.
- معیار پذیرش: روی مجموعهٔ طلایی، complexity با برچسب انسانی ≥ ۸۰٪ توافق؛ هزینهٔ مدل auto نسبت به دستی بهتر یا برابر با کیفیت برابر.
- پیشنهاد: classifier سبک یا چند قانون دامنه (نام گزارش = complex/medium اجباری).
- یادداشت اصلاح: ۱۴۰۵/۰۵/۲۶ — نام گزارش‌های حسابداری (تراز آزمایشی، بدهکاران، کاردکس، …) حداقل medium است؛ چند دامنهٔ واقعی یا متن بلند complex می‌شود. classifier مدل هنوز نیست.

### PRM-03 — تاریخچه با سقف ۴۰ پیام و خلاصهٔ ترکیبی
- وضعیت: باز
- اولویت: P1
- مالک: backend
- فایل‌ها: `ai_history_summarizer.py`، `MAX_HISTORY_MESSAGES = 40`، `CONTEXT_INPUT_TOKEN_BUDGET = 28000`
- مشکل: بودجهٔ ۲۸k توکن برای مدل‌های ۲۰۰k–۱M خیلی محافظه‌کارانه است و برای گزارش‌های بلند تنگ. خلاصهٔ LLM usage دارد اما خلاصه به‌عنوان پیام first-class پایدار (مثل ChatGPT memory of conversation) مشخص نیست. fallback قاعده‌ای فقط برش متن است.
- معیار پذیرش: خلاصهٔ جلسه persist شود و در prompt با برچسب «خلاصهٔ قطعی» بیاید؛ بودجه بر اساس context window مدل انتخاب شود نه ثابت جهانی.
- پیشنهاد: per-model budget از کاتالوگ مدل؛ hierarchical summary (جلسه / بخش).
- یادداشت اصلاح:

### PRM-04 — بینش و بلوک runtime هر نوبت به مدل می‌روند؛ در تاریخچه تکرار نمی‌شوند
- وضعیت: انجام‌شده (فاز ۰–۱؛ دانش-به‌ابزار و خط «بینش به‌روز شد» موکول)
- اولویت: P1
- مالک: backend
- فایل‌ها: `build_system_prompt_stream`، `ai_system_prompt.py`، `ai_prompt_cache.py`، `ai_insight_service.py` (`INSIGHTS_CACHE_TTL_SEC = 300`)، `ai_context_budget.py`؛ سناریو: [`AI_AGENT_RUNTIME_CAPABILITIES_SCENARIO.md`](AI_AGENT_RUNTIME_CAPABILITIES_SCENARIO.md)
- مشکل: هر پیام جدید HTTP جدا است. system از نو ساخته می‌شود: نقش (cacheپذیر) + شناسه کسب‌وکار (cacheپذیر) + datetime/حافظه/بینش/دانش/مهارت/کانکتور/پیوست/todo (dynamic). پیام‌های جلسه در DB این بلوک‌ها را ندارند — فرض «تکرار داخل تاریخچه» نادرست است. تکرار واقعی در **ورودی مدل** است و cache ارائه‌دهنده فقط prefix ثابت را می‌پوشاند. دانش حتی وابسته به متن سوال است (`query_needs_knowledge`).
- معیار پذیرش: در usage نوبت دوم همان جلسه، اگر KPI عوض نشده، `cache_read_tokens` برای لایهٔ بینش/حافظه دیده شود؛ بینش در ردیف‌های `ai_chat_message` ذخیره نشود؛ دانش از prefix ثابت خارج بماند.
- پیشنهاد: لایهٔ `semi_static` با hash محتوا و TTL هم‌تراز کش بینش (۵ دقیقه، هم‌راستا با Anthropic ephemeral). دانش را به ابزار بازیابی بسپارید نه به system هر سوال.
- یادداشت اصلاح: ۱۴۰۵/۰۵/۲۸ — مسیر کد تأیید شد. کش ۳۰۰ثانیه‌ای فقط SQL را کم می‌کند نه توکن ارسالی. همان روز فاز ۰–۱: لایهٔ `semi_static` (حافظه+بینش+کانکتور) با breakpoint جدا در Anthropic/OpenAI؛ datetime/دانش/مهارت در dynamic ماند؛ `context_usage` فیلدهای `static_tokens` / `semi_static_tokens` / `insights_tokens` / `runtime_tokens` را می‌فرستد. دانش هنوز در system است اگر `query_needs_knowledge` (فاز ۲ موکول).

---

# F. حافظه

### MEM-01 — دو نسل حافظه هم‌زمان (متن آزاد + آیتم)
- وضعیت: باز
- اولویت: P1
- مالک: backend + flutter
- فایل‌ها: `ai_memory_service.py`، `ai_memory_item_service.py`، `ai_memory_structured.py`، `ai_chat_memory_sheet.dart`
- مشکل: دستورات همیشگی (۴۰۰۰ کاراکتر) و آیتم‌های v2 (`fact/term/preference/goal/hint`، سقف ۲۰۰). `structured` در upsert نادیده گرفته می‌شود (سازگاری عقب‌رو). کاربر باید بداند دستیار «چه چیزی را به خاطر سپرده» — ChatGPT این را شفاف کرده.
- معیار پذیرش: یک UI واحد: دستورات من / حقایق یادگرفته / در انتظار تأیید؛ هر آیتم قابل حذف؛ یادگیری خودکار فقط با دستهٔ auto-approve.
- پیشنهاد: deprecate متن آزاد به‌جز «custom instructions»؛ بقیه فقط item.
- یادداشت اصلاح:

### MEM-02 — یادگیری از فیدبک محدود و بدون بازخورد به کاربر
- وضعیت: باز
- اولویت: P2
- مالک: backend
- فایل‌ها: `ai_memory_feedback_service.py`، `ai_memory_hooks.py`، `ai_memory_proactive_service.py`، `MAX_MEMORY_FEEDBACK_UPDATES_PER_DAY = 8`
- مشکل: سقف روزانه در dict درون‌پرداز (`_feedback_daily`) است و با چند worker غلط می‌شود. `schedule_memory_update_after_chat` با `asyncio.create_task` اگر loop نباشد شکننده است. استخراج با regex است نه LLM. `format_memory_goal_hint_for_insights` خالی برمی‌گردد. تست‌ها فقط extract/strip/merge را می‌پوشانند نه CRUD آیتم و hooks.
- معیار پذیرش: پس از thumbs-down، پیشنهاد «این را به خاطر بسپار» با پیش‌نمایش؛ سقف روزانه در Redis/DB؛ تست hooks.
- پیشنهاد: HITL برای hint/goal؛ auto فقط برای preference/term.
- یادداشت اصلاح:

---

# G. دانشنامه، RAG، استناد

### RAG-01 — ایندکس embedding ممکن است بی‌صدا شکست بخورد
- وضعیت: انجام‌شده
- اولویت: P0
- مالک: backend
- فایل‌ها: `ai_knowledge_service.py`، `ai_chat_knowledge_sheet.dart`
- مشکل: اگر pgvector یا API امبدینگ نباشد، سند ذخیره می‌شد و جستجو بی‌خبر به overlap واژه برمی‌گشت.
- معیار پذیرش: وضعیت ایندکس در UI (آماده / واژه‌ای / خطا)؛ reindex با گزارش تعداد chunk؛ عدم `pass` خاموش.
- پیشنهاد: وضعیت روی سند (`index_status`); آلارم ops اگر نرخ fallback بالا باشد.
- یادداشت اصلاح: ۱۴۰۵/۰۵/۲۶ — شکست ایندکس لاگ می‌شود؛ API فیلدهای `index_status` / `chunk_count` / `embedded_count` برمی‌گرداند؛ شیت دانش برچسب معنایی/واژه‌ای/خطا نشان می‌دهد. ستون DB هنوز اضافه نشده.

### RAG-02 — استناد برای کاربر قابل کلیک و الزام‌آور نیست
- وضعیت: انجام‌شده
- اولویت: P1
- مالک: backend + flutter
- فایل‌ها: `ai_citation_service.py`، `ai_citation_chips.dart`، `ai_stream_helpers.py`، `ai_eval_assertions.py`
- مشکل: citation به system prompt تزریق می‌شود تا مدل «تشویق» شود ارجاع بدهد. Perplexity/Fin منبع را اجباری و لینک می‌کنند. اینجا حدس از کلیدهای JSON و حداکثر ۸ منبع است.
- معیار پذیرش: هر عدد/ادعا از tool یا دانش یک chip لینک به موجودیت UI داشته باشد؛ اگر منبع نباشد، مدل حق عدد قطعی ندارد.
- پیشنهاد: post-processor: اگر عدد در خروجی است و در envelope نیست، هشدار «بدون منبع».
- یادداشت اصلاح: ۱۴۰۵/۰۵/۲۶ — منابع ساخت‌یافته در `_citations` persist و روی `done` می‌آیند؛ chip زیر پاسخ برای فاکتور/شخص/سرنخ/فرصت/گردش‌کار/سند انبار لینک می‌شود. prompt عدد بدون منبع را منع می‌کند؛ اگر پاسخ مالی باشد و منبعی نباشد هشدار UI نشان داده می‌شود. دروازهٔ persist که متن را بازنویسی کند هنوز نیست.

### RAG-03 — دانش از فایل‌های آفیس/تصویر تغذیه نمی‌شود
- وضعیت: باز
- اولویت: P2
- مالک: backend
- فایل‌ها: `ai_attachment_service.py` (`ALLOWED_EXTENSIONS` بدون xlsx/docx/تصویر؛ PDF جداگانه و در لیست مجاز نیست در حالی که parser دارد)
- مشکل: ناسازگاری PDF در allowlist. اکسل حسابداری رایج است و پشتیبانی نمی‌شود. تصویر فاکتور/کارت ملی برای ERP حیاتی است و در چت vision نیست.
- معیار پذیرش: PDF در allowlist؛ xlsx به جدول؛ تصویر با مدل vision در همان جلسه.
- پیشنهاد: پایپلاین پیوست → متن/جدول/تصویر چندبخشی در پیام user (content parts).
- یادداشت اصلاح:

---

# H. مهارت‌ها (Skills) و مارکت

### SKL-01 — فعال‌سازی مهارت با overlap واژه است؛ اسکریپت اجرا نمی‌شود
- وضعیت: در حال اصلاح
- اولویت: P1
- مالک: backend
- فایل‌ها: `ai_skill_runtime.py` (`_tokenize`، سقف ۳ مهارت، ۱۲k کاراکتر بدنه)، `ai_activated_skill_chips.dart`، `AI_SKILLS_MARKETPLACE_PHASES.md`
- مشکل: فاز ۱ portable: ZIP + SKILL.md. اسکریپت‌ها هشدار «اجرا نمی‌شوند». انتخاب با اشتراک توکن توضیحات — مهارت‌های فارسی با slug انگلیسی فعال نمی‌شوند. Anthropic native (فاز ۲) و مارکت UGC (فاز ۳) باز است.
- معیار پذیرش: progressive disclosure استاندارد agentskills.io: metadata همیشه، بدنه فقط با match قوی یا انتخاب کاربر؛ اعلام صریح در UI که کدام مهارت فعال شد.
- پیشنهاد: chip مهارت در composer (مثل mention)؛ embedding روی description؛ sandbox برای scripts در فاز بعد.
- یادداشت اصلاح: ۱۴۰۵/۰۵/۲۶ — match روی slug داخل پرسش؛ مهارت فعال‌شده در `_activated_skills` persist و به‌صورت chip زیر پاسخ دیده می‌شود. اجرای اسکریپت و chip در composer هنوز نیست.

### SKL-02 — UI مهارت از API جلوتر/عقب‌تر است و تست Flutter ندارد
- وضعیت: باز
- اولویت: P2
- مالک: flutter
- فایل‌ها: `ai_chat_skills_sheet.dart`، `ai_skill_marketplace_card.dart`، `ai_skills_admin_page.dart`
- مشکل: شیت‌ها وجود دارند اما جریان import ZIP، سازگاری، و خطای script برای کاربر عادی مبهم است.
- معیار پذیرش: کاربر غیر فنی بتواند یک مهارت رسمی را نصب، فعال و در یک چت تست کند زیر ۲ دقیقه.
- پیشنهاد: onboarding مهارت با یک پکیج نمونهٔ حسابداری.
- یادداشت اصلاح:

---

# I. رابط کاربری چت (Flutter)

### UX-01 — God Widget و state غیرقابل تست
- وضعیت: در حال اصلاح
- اولویت: P0
- مالک: flutter
- فایل‌ها: `ai_chat_dialog.dart` (~2586)، `ai_chat_session_controller.dart`، `ai_chat_stream_turn.dart`، `ai_chat_voice_session.dart`، `ai_chat_turn.dart`، `ai_chat_message_sheet.dart`، `ai_service.dart` (~1736)، `ai_chat_resume.dart`، `ai_chat_stream_controller.dart`
- مشکل: جلسه، استریم، صوت، پیوست، مدل، execution mode، فیدبک، سایدبار، تأیید نوشتن همه در یک State. در `AI_CHAT_ISSUES.md` هم Riverpod/Bloc پیشنهاد شده. تست UI قبلاً فقط `ai_markdown_table_parser_test.dart` بود.
- معیار پذیرش: dialog نازک؛ کنترلرها جدا (session, stream, composer, voice)؛ پوشش تست برای ارسال، لغو، تأیید write، reconnect.
- پیشنهاد: استخراج `AIChatSessionController`؛ golden test برای empty/streaming/error.
- یادداشت اصلاح: ۱۴۰۵/۰۵/۲۶ — برش اول تا سوم: resume / approval / turn helpers. برش چهارم: شیت اقدامات پیام. برش پنجم: `AIChatSessionController` مالک جلسه/پیام‌ها و `planChatSend`. برش ششم (۱۴۰۵/۰۵/۲۸): حلقهٔ SSE به `AIChatStreamController.consume` و `AIChatStreamTurn`. برش هفتم: `AIChatVoiceSessionController` و `interpretVoiceServerEvent`؛ ساخت `VoiceChatController` هنوز در dialog است.

### UX-02 — i18n ناقص در سطح چت
- وضعیت: در حال اصلاح
- اولویت: P1
- مالک: flutter
- فایل‌ها: `ai_chat_dialog.dart`، `ai_chat_composer.dart`، `ai_write_approval_banner.dart`، `ai_chat_l10n.dart`، `app_en.arb` / `app_fa.arb`
- مشکل: بخشی از برچسب ابزار l10n شده؛ snackbar و tooltip و لیبل حالت اجرا هنوز فارسی hardcoded. محصول چندزبانه است.
- معیار پذیرش: صفر رشتهٔ کاربرنما در Dart/Python بدون کلید l10n برای سطح چت.
- پیشنهاد: اسکریپت grep رشته‌های فارسی در `lib/widgets/ai`.
- یادداشت اصلاح: ۱۴۰۵/۰۵/۲۶ — کلیدهای ارسال/تأیید جلسه. ۱۴۰۵/۰۵/۲۸ — کروم composer، app bar، بنر تأیید نوشتن و شیت اقدامات پیام به arb رفت. پاسخ خالی دستیار: `aiChatEmptyAssistantReply`. snackbarهای چت، شیت حافظه، شیت دانشنامه، خطاهای صوت و تنظیمات صدا l10n شدند. منوی بیشتر، دیالوگ سهمیه، حالت اجرا و slash هنوز hardcoded است.

### UX-03 — تجربهٔ سطح ChatGPT هست؛ Canvas / Artifact نیست
- وضعیت: باز
- اولویت: P2
- مالک: flutter + backend
- فایل‌ها: `ai_chat_message_body.dart`، `ai_chat_table_widget.dart`، `ai_chat_chart_widget.dart`
- مشکل: جدول، نمودار، کد قابل کپی، trace، todos موجودند. خروجی بلند (گزارش ماهانه، پیش‌نویس قرارداد، HScript) داخل حباب می‌ماند. Claude Artifacts و ChatGPT Canvas سند را کنار چت ویرایش می‌کنند.
- معیار پذیرش: برای `export` / گزارش / HScript یک پنل کناری با نسخه و «اعمال در سیستم».
- پیشنهاد: reuse استودیو HScript (`onApplyHScriptCode` از قبل هست) به‌صورت Artifact عمومی.
- یادداشت اصلاح:

### UX-04 — جستجو، پین، فورک هست؛ اشتراک و شاخهٔ مرئی ضعیف است
- وضعیت: باز
- اولویت: P2
- مالک: flutter
- فایل‌ها: API `fork`/`export`/`messages/search`، `ai_session_pins_store.dart`، `ai_conversation_rail.dart`
- مشکل: فورک سمت سرور هست؛ UX شاخه‌ها مثل ChatGPT (درخت پیام) نیست. اشتراک لینک امن با انقضا نیست.
- معیار پذیرش: نمایش «این گفت‌وگو از جلسه X منشعب شد»؛ export PDF/Excel علاوه بر Markdown.
- پیشنهاد: بعد از پایدار شدن استریم.
- یادداشت اصلاح:

### UX-05 — دسترسی‌پذیری و موبایل
- وضعیت: در حال اصلاح
- اولویت: P2
- مالک: flutter
- مشکل: RTL رعایت شده. composer در مرکز/پایین حالت ChatGPT دارد. Voice چت متنی را قفل می‌کند. Focus و screen reader برای trace/approval مشخص نیست. صفحهٔ چت در موبایل با سایدبار و شیت‌های زیاد شلوغ است.
- معیار پذیرش: تأیید نوشتن با کیبورد؛ announce وضعیت استریم برای TalkBack/VoiceOver؛ composer در موبایل همیشه قابل‌مشاهده.
- پیشنهاد: ممیزی a11y جدا روی `AIChatComposer` و `AIWriteApprovalBanner`.
- یادداشت اصلاح: ۱۴۰۵/۰۵/۲۸ — `Semantics(liveRegion)` روی بنر تأیید و برچسب «در حال پاسخ»؛ دکمهٔ ارسال label دارد. کیبورد Enter برای تأیید بنر هنوز نیست.

### UX-06 — Slash commandها ثابت و فارسی‌اند
- وضعیت: باز
- اولویت: P3
- مالک: flutter
- فایل‌ها: `ai_chat_composer.dart` (`kSlashCommands`)
- مشکل: هفت دستور ثابت. به مهارت، نقش، یا داده‌های زنده وصل نیستند. پیشنهادهای پویا API جدا دارند (`/suggestions`) اما slash نه.
- معیار پذیرش: slash از پیشنهادهای سرور + مهارت‌های نصب‌شده ساخته شود.
- یادداشت اصلاح:

### UX-07 — باگ بازیابی خطا در استریم UI
- وضعیت: انجام‌شده
- اولویت: P0
- مالک: flutter
- فایل‌ها: `ai_chat_dialog.dart` (`_runAssistantStream`)
- مشکل: بنر پاسخ خالی در همان setState پاک می‌شد؛ `chunk.error` حباب استریم را رها می‌کرد؛ `onError` و chunk خطا دوبار هندل می‌شدند.
- معیار پذیرش: یک مسیر خطا؛ بنر خالی‌بودن پاسخ دیده شود؛ پس از error استریم پاک و retry کار کند.
- پیشنهاد: تست واحد روی `AIChatStreamController` + تست ویجت برای error/empty.
- یادداشت اصلاح: ۱۴۰۵/۰۵/۲۶ — خطا و پاسخ خالی بنر را نگه می‌دارند؛ partial روی error ذخیره می‌شود؛ parse SSE دیگر onError جدا برای error typed صدا نمی‌زند. تست ویجت هنوز باز است.

### UX-08 — ویجت‌های ناتمام و APIهای بی‌استفاده در چت
- وضعیت: باز
- اولویت: P2
- مالک: flutter
- فایل‌ها: `ai_chat_toolbar.dart`، `ai_conversation_rail.dart`، `ai_conversation_nav_sheet.dart`؛ `updateChatSession(title:)` بدون UI
- مشکل: ریل/ناوبری/تولبار ساخته شده‌اند ولی flag طراحی خاموش است — نشانهٔ نیمه‌کاره ماندن بازطراحی. تغییر عنوان جلسه API دارد و در UI نیست. پین فقط SharedPreferences محلی است و بین دستگاه‌ها همگام نیست. Enter در دسکتاپ newline است نه ارسال.
- معیار پذیرش: یا ویجت مرده حذف شود یا در محصول روشن شود؛ rename در سایدبار؛ پین سمت سرور یا صریحاً «فقط این دستگاه».
- پیشنهاد: بعد از پایدار شدن استریم.
- یادداشت اصلاح: ۱۴۰۵/۰۵/۲۸ — Enter-to-send دسکتاپ در UX-09 انجام شد؛ بقیهٔ این آیتم (ریل خاموش، rename، پین) باز است.

### UX-09 — بدون mention موجودیت و بدون Enter-to-send
- وضعیت: در حال اصلاح
- اولویت: P2
- مالک: flutter
- مشکل: Cursor/ChatGPT با `@` فایل یا موجودیت را به context می‌آورند. اینجا مهارت و دانش در منوی بیشتر دفن شده‌اند. دسکتاپ بدون میانبر ارسال است.
- معیار پذیرش: `@مشتری` / `@کالا` / `@فاکتور` با جستجوی زنده؛ Enter ارسال و Shift+Enter خط جدید (قابل تنظیم).
- یادداشت اصلاح: ۱۴۰۵/۰۵/۲۸ — در عرض غیر فشرده Enter ارسال می‌کند و Shift+Enter خط جدید می‌گذارد؛ موبایل newline می‌ماند. Enter روی overlay دستور slash همان دستور را اعمال می‌کند. mention موجودیت هنوز باز است.

---

# J. صوت

### VOI-01 — پایپلاین محلی پخته است؛ کیفیت و هم‌ترازی با متن فاصله دارد
- وضعیت: باز
- اولویت: P2
- مالک: backend + flutter
- فایل‌ها: `docs/AI_VOICE_CHAT_IMPLEMENTATION.md`، `voice_ws.py`، `VoiceChatController`
- مشکل: STT/VAD/TTS روی سرور خودتان (Piper فارسی) تمایز حریم خصوصی است. کیفیت TTS/STT از ابر پایین‌تر است. چت متنی هنگام صوت قفل می‌شود. رویدادهای `voice_status` با trace متنی یکی نیستند.
- معیار پذیرش: کاربر بتواند وسط صوت به متن سوییچ کند بدون از دست رفتن context؛ latency perceived < ۱.۵s برای عبارت کوتاه.
- پیشنهاد: barge-in؛ نمایش transcript زنده در همان thread؛ متریک WER روی نمونهٔ فارسی حسابداری.
- یادداشت اصلاح: کیفیت TTS/STT و هم‌ترازی با متن باز است. ۱۴۰۵/۰۵/۲۸ — تفسیر رویداد WS و state جلسه از dialog به `interpretVoiceServerEvent` / `AIChatVoiceSessionController` منتقل شد؛ خطاهای timeout/STT/forbidden l10n شدند. کیفیت TTS/STT و هم‌ترازی با متن باز است. ۱۴۰۵/۰۵/۲۸ — تفسیر رویداد WS و state جلسه از dialog به `interpretVoiceServerEvent` / `AIChatVoiceSessionController` منتقل شد؛ خطاهای timeout/STT/forbidden l10n شدند.

### VOI-02 — احراز هویت WS با api_key در اولین فریم
- وضعیت: باز
- اولویت: P1
- مالک: backend
- فایل‌ها: مستند صوت، `voice_ws.py`
- مشکل: طراحی بهتر از query string است. باید timeout برای فریم auth، محدودیت نرخ، و بستن اتصال بدون auth سخت باشد.
- معیار پذیرش: بدون auth پس از N ثانیه drop؛ rate limit per user؛ عدم ذخیره صوت مگر opt-in (از قبل `voice_data_collection_enabled`).
- یادداشت اصلاح:

---

# K. کانال‌های جانبی (تلگرام، CRM، تیکت، چت وب)

> چت وب وردپرس (`HesabixChatPlugin` + `CrmWebChatPage`) **چت انسان با بازدیدکننده** است نه ایجنت حسابیکس. در این سند جدا می‌ماند تا با AI chat قاطی نشود.

### CHN-01 — تلگرام همان ایجنت را با UX پیام‌رسان ضعیف اجرا می‌کند
- وضعیت: انجام‌شده
- اولویت: P1
- مالک: backend
- فایل‌ها: `telegram_ai_chat_service.py`، `telegram_ai_chat_text.py`، `telegram_ai_chat_handler.py`، `telegram_provider.py`
- مشکل: منوی دکمه و اتصال به جلسهٔ AI هست. استریم، trace، کارت تأیید نوشتن، جدول و نمودار در تلگرام معادل ندارند. قطع پیام طولانی، نبود typing پایدار، و تأیید write در callback نیازمند طراحی جداست.
- معیار پذیرش: write بدون تأیید در تلگرام ممکن نباشد؛ پاسخ‌های بلند صفحه‌بندی شوند؛ وضعیت «در حال تحلیل» دیده شود.
- پیشنهاد: تلگرام فقط روی همان run API (AGT-02) subscribe کند؛ تأیید با inline button = `approval_id`.
- یادداشت اصلاح: ۱۴۰۵/۰۵/۲۶ — `execution_mode=supervised` و `approve_writes=False`؛ نتایج ابزار persist می‌شوند؛ پاسخ بلند صفحه‌بندی می‌شود. دکمهٔ inline `ai:approve:{id}` / `ai:reject:{id}` و `sendChatAction(typing)` اضافه شد. استریم و جدول در تلگرام هنوز نیست (عمداً خارج از معیار پذیرش این آیتم).

### CHN-02 — CRM AI و پیشنهاد تیکت غیر استریم و بدون ابزار دامنهٔ کامل
- وضعیت: در حال اصلاح
- اولویت: P1
- مالک: backend + flutter
- فایل‌ها: `adapters/api/v1/ai/crm_ai.py`، `ai_crm_parse.py`، `adapters/api/v1/support/ai_tickets.py`، `ai_channel_policy.py`، `crm_ai_assistant_widget.dart`
- مشکل: یک completion با context متنی (حتی PII). بدون SSE، بدون function calling کامل، بدون citation. `suggest-deal-probability` در parse ناموفق به **۵۰٪** برمی‌گردد — عدد ساختگی خطرناک است. تاریخچهٔ فعالیت نازک (حدود ۵–۱۰ مورد). تست endpoint وجود ندارد.
- معیار پذیرش: همان حلقهٔ ایجنت با ابزار محدود همان موجودیت؛ اگر احتمال قابل استخراج نیست خطا/نامشخص نه ۵۰؛ استریم در ویجت.
- پیشنهاد: `operation=crm_assist` با tool allowlist؛ نمایش در `crm_ai_assistant_widget.dart`.
- یادداشت اصلاح: ۱۴۰۵/۰۵/۲۶ — fallback ۵۰ حذف شد. حلقه با `execution_mode=analyzer`، allowlist فقط‌خواندنی، سقف ۴ نوبت، حصار untrusted، و فیلدهای `tools_used`/`citations`؛ ویجت CRM chip ابزار و استناد نشان می‌دهد. استریم SSE در ویجت هنوز باز است.

### CHN-03 — چت وب CRM باید مسیر ارجاع به ایجنت داشته باشد
- وضعیت: باز
- اولویت: P3
- مالک: product
- مشکل: اپراتور در صندوق ورودی است؛ ایجنت حسابداری در صفحهٔ دیگر. Fin/Intercom ایجنت را روی همان ویجت مشتری می‌گذارند (با دانش و escalation).
- معیار پذیرش: دکمهٔ «پیشنهاد پاسخ با AI» در صندوق CRM با استناد به دانش کسب‌وکار — نه جایگزینی انسان بدون سیاست.
- یادداشت اصلاح:

---

# L. ایجنت در ورک‌فلو

### WFA-01 — نود AI Agent شبیه n8n است اما از حلقهٔ چت جداست
- وضعیت: انجام‌شده
- اولویت: P1
- مالک: backend
- فایل‌ها: `app/services/workflow/actions/ai_agent_action.py`، `ai_workflow_agent_policy.py`
- مشکل: `max_iterations` پیش‌فرض ۵، `tools_mode` all/category/custom، خروجی JSON. احتمالاً `chat_completion` غیر استریم. ابزارهای create_workflow به‌طور پیش‌فرض denylist — خوب. اما بودجه، write guard، execution_mode، و trace چت را reuse نمی‌کند. خطر حلقهٔ ورک‌فلو↔ایجنت.
- معیار پذیرش: همان write guard و audit؛ log trace در اجرای ورک‌فلو؛ سقف هزینه per execution.
- پیشنهاد: فراخوانی `AIService` با `operation=workflow_agent` و allowlist اجباری؛ هرگز tools=all در پروداکشن پیش‌فرض نباشد.
- یادداشت اصلاح: ۱۴۰۵/۰۵/۲۶ — ابزارهای نوشتنی پیش‌فرض حذف می‌شوند مگر `allow_writes`؛ حالت اجرا analyzer (یا supervised اگر write دیده شود) و `approve_writes=False`. denylist گردش‌کار سر جایش است. سقف هزینهٔ جدا و tools_mode پیش‌فرض all هنوز مانده.

### WFA-02 — سیاست ورک‌فلو جدا (`ai_workflow_agent_policy.py`) باید منبع حقیقت واحد شود
- وضعیت: در حال اصلاح
- اولویت: P2
- مالک: backend
- مشکل: چند سیاست موازی (چت execution_mode، workflow policy، MCP approve). ناسازگاری یعنی یک مسیر write را بی‌تأیید رد می‌کند.
- معیار پذیرش: ماتریس واحد «تابع × کانال × حالت اجرا × تأیید».
- یادداشت اصلاح: ۱۴۰۵/۰۵/۲۶ — `ai_channel_policy.py` شروع ماتریس است (allowlist CRM/تیکت، سقف نوبت، حفظ لیست ابزار کالر تا routing «ساده» کاتالوگ ورک‌فلو را دور نریزد). denylist گردش‌کار هنوز در `ai_workflow_agent_policy.py` جداست.

---

# M. MCP و کانکتورهای خارجی

### MCP-01 — پروتکل قدیمی و فقط tools روی HTTP JSON-RPC
- وضعیت: باز
- اولویت: P2
- مالک: backend
- فایل‌ها: `ai_mcp_service.py` (`MCP_PROTOCOL_VERSION = "2024-11-05"`)، `adapters/api/v1/ai/mcp.py`
- مشکل: استاندارد ۲۰۲۵ resources/prompts/sampling و انتقال SSE/stdio را دارد. `listChanged: false`. کلاینت‌های Cursor/Claude Desktop انتظار handshake و notifications دارند. این endpoint بیشتر یک RPC ابزار است تا MCP کامل. **کلاینت MCP وجود ندارد** — ایجنت نمی‌تواند سرور MCP خارجی کسب‌وکار را مصرف کند (برخلاف Cursor).
- معیار پذیرش: سازگاری با spec جاری؛ resources برای دانشنامه؛ prompts برای مهارت؛ بدون write از طریق query (SEC-02)؛ حداقل یک MCP client برای کانکتور خارجی.
- پیشنهاد: سرور MCP جدا (stdio برای دسکتاپ، SSE برای کلود) با همان registry.
- یادداشت اصلاح:

---

# N. ارزیابی، مشاهده‌پذیری، عملیات

### OBS-01 — Eval برابر substring است
- وضعیت: در حال اصلاح
- اولویت: P0
- مالک: backend
- فایل‌ها: `ai_eval_service.py` (`DEFAULT_EVAL_CASES`)، `ai_eval_assertions.py`، `ai_eval_schedule_service.py`، مدل‌های `ai_eval_*`
- مشکل: سه کیس پیش‌فرض با `expected_substrings`. زمان‌بندی cron و `min_pass_rate` هست. `_schedule_fired` درون‌حافظه است و در چند worker تکراری/ازدست‌رفته می‌شود. این برای رگرسیون prompt کافی نیست: ابزار درست، عدد درست، عدم write بدون تأیید را نمی‌سنجد. حدود ۴۶ فایل `test_ai_*` (~۳۳۰۰ خط) عمدتاً حلقهٔ ایجنت را می‌پوشانند نه محصول.
- معیار پذیرش: هر PR روی ابزار/prompt یک suite: tool_called، no_write_without_approval، citation_present، language_fa. LLM-as-judge برای روانی. Fail CI اگر pass_rate < آستانه. قفل زمان‌بندی در Redis/DB.
- پیشنهاد: کیس‌ها از تیکت‌های واقعی (باscrub)؛ اتصال به `ai_eval_premature`.
- یادداشت اصلاح: ۱۴۰۵/۰۵/۲۶ — امتیازدهی `tool_called`، `no_write_without_approval`، `citation_present`، `language_fa` و `fluency_ok` بدون LLM؛ `tests/test_ai_eval_gold_ci.py` اگر pass_rate آفلاین < `MIN_OFFLINE_EVAL_PASS_RATE` باشد CI را می‌شکند. زمان‌بندی با `SELECT … FOR UPDATE` و slot در `last_run_at` قفل می‌شود. LLM-as-judge و fail روی pass_rate زنده هنوز نیست.

### OBS-02 — متریک فقط لاگ است
- وضعیت: در حال اصلاح
- اولویت: P1
- مالک: backend + infra
- فایل‌ها: `ai_ops_metrics.py` (`log_ai_event` + شمارندهٔ درون‌پردازه‌ای)
- مشکل: بدون داشبورد latency p50/p95، هزینه per business، نرخ fallback دانش، نرخ APPROVAL، نرخ stop_reason. دیباگ پروداکشن بدون trace_id سخت است.
- معیار پذیرش: هر run یک trace با spanهای prompt_build، llm_round، tool، persist؛ قابل جستجو per session.
- پیشنهاد: OpenTelemetry + (Langfuse یا Phoenix)؛ حداقل Prometheus counters.
- یادداشت اصلاح: ۱۴۰۵/۰۵/۲۶ — هر `log_ai_event` شمارندهٔ فرآیند را زیاد می‌کند؛ `metric_snapshot()` برای تست/دیباگ. Prometheus و OTel هنوز نیست.

### OBS-03 — فیدبک کاربر به بهبود مدل/prompt حلقه نشده
- وضعیت: باز
- اولویت: P2
- مالک: backend
- فایل‌ها: `ai_feedback_service.py`، `ai_feedback_analytics_service.py`، API `/feedback/analytics`
- مشکل: thumbs و analytics endpoint هست. حلقهٔ بسته به eval set یا memory HITL کامل نیست.
- معیار پذیرش: هر هفته ۱۰ نمونهٔ thumbs-down وارد eval شود.
- یادداشت اصلاح:

---

# O. سهمیه، مدل، BYOK

### BIL-01 — سهمیه قبل از چت اجباری است؛ شفافیت هزینه وسط چت کم است
- وضعیت: باز
- اولویت: P2
- مالک: flutter + backend
- فایل‌ها: `_ensure_chat_availability`، `ai_quota_helpers.py`، `ai_chat_model_chip.dart` (`modelPricingHint`)
- مشکل: چک اشتراک خوب است. کاربر وسط جلسه نمی‌بیند این پاسخ چقدر واحد مصرف کرد (جز در done). مدل auto ممکن است مدل گران resolve کند بدون توضیح.
- معیار پذیرش: بعد از هر پاسخ: توکن، هزینهٔ تقریبی، مدل واقعی؛ اگر resolve با requested فرق داشت نشان داده شود (`requested_model` در usage context از قبل هست).
- پیشنهاد: chip مدل بعد از پاسخ «اجرا شد با X».
- یادداشت اصلاح:

### BIL-02 — تسک زمان‌بندی‌شده فقط ۴ الگوی ثابت
- وضعیت: باز
- اولویت: P2
- مالک: product + backend
- فایل‌ها: `ai_scheduled_task_service.py`
- مشکل: گزارش هفتگی / معوق / موجودی کم / خلاصه ماهانه. کاربر نمی‌تواند «هر روز بدهکاران بالای X» بسازد. این همان «background agent» محصولات جهانی است.
- معیار پذیرش: تسک سفارشی با prompt + cron + کانال تحویل (ایمیل/درون‌برنامه) با سقف هزینه.
- یادداشت اصلاح:

---

# P. معماری، داده، تست

### ARC-01 — God Object سمت سرور
- وضعیت: در حال اصلاح
- اولویت: P0
- مالک: backend
- فایل‌ها: `ai_service.py` ~3600، `ai_model_router.py`، `ai_usage_meter.py`
- مشکل: سهمیه، routing مدل، prompt، حلقه، tool dispatch، usage در یک کلاس. تغییر استریم ریسک رگرسیون سهمیه دارد. موازی‌سازی توسعه سخت است.
- معیار پذیرش: `AIService` نمای نازک؛ `AgentLoop`, `PromptBuilder`, `UsageMeter`, `ModelRouter` جدا؛ همان تست‌های موجود سبز.
- پیشنهاد: استخراج تدریجی بدون big-bang؛ شروع از `chat_completion_stream`.
- یادداشت اصلاح: ۱۴۰۵/۰۵/۲۶ — `AIModelRouterMixin` و `AIUsageMeterMixin` از کلاس جدا شدند؛ امضای عمومی `AIService` عوض نشده. حلقهٔ استریم و `check_availability` هنوز داخل God Object است.

### ARC-02 — DB سنکرون داخل executor
- وضعیت: باز
- اولویت: P2
- مالک: backend
- مشکل: در ISSUES به‌عنوان باقی‌مانده ثبت شده. برای مقیاس چت همزمان، pool و thread starvation محتمل است.
- معیار پذیرش: مسیر استریم بدون block لوپ؛ session کوتاه per tool یا async SQLAlchemy.
- یادداشت اصلاح:

### ARC-03 — مدل پیام برای ایجنت ناقص است
- وضعیت: باز
- اولویت: P1
- مالک: backend
- فایل‌ها: `ai_chat_message.py` — `function_calls`/`function_results` به‌صورت Text JSON؛ نقش `FUNCTION` در enum هست
- مشکل: trace، budget، todos داخل `function_results` با کلیدهای `_agent_*` قاچاق می‌شوند. گزارش و مهاجرت سخت است. پیام tool به‌عنوان ردیف first-class ذخیره نمی‌شود.
- معیار پذیرش: ستون‌های جدا یا JSONB typed؛ جدول `ai_chat_message_parts` (text, tool_call, tool_result, trace).
- پیشنهاد: مهاجرت تدریجی؛ خواندن backward compatible.
- یادداشت اصلاح:

### ARC-04 — تست Flutter تقریباً صفر است
- وضعیت: انجام‌شده
- اولویت: P1
- مالک: flutter
- مشکل: یک تست پارسر جدول. استریم، تأیید، لغو، مدل chip بدون تست.
- معیار پذیرش: تست واحد برای `AIChatStreamController` (بدون UI) پوشش eventهای SSE؛ ویجت تست برای approval banner.
- یادداشت اصلاح: ۱۴۰۵/۰۵/۲۶ — تست واحد برای stream controller (begin/clear، delta، tool+approval، heartbeat، done، cancel snapshot، merge trace)، `extractPendingApprovalOpsFromResults`، و `AIChatResumeHint`. ۱۴۰۵/۰۵/۲۸ — `consume` نوبت استریم؛ `interpretVoiceServerEvent` (ready/dummy TTS/transcript/delta/done/timeout/empty). ویجت‌تست بنر تأیید هنوز نیست.

### ARC-05 — مسیر dual chat_completion با ThreadPoolExecutor موقت
- وضعیت: انجام‌شده
- اولویت: P2
- مالک: backend
- فایل‌ها: `ai_service.py` — `chat_completion_sync`
- مشکل: ساخت pool به ازای هر فراخوانی sync از context async؛ هزینه و پیچیدگی. بعد از STR-02 حذف می‌شود.
- یادداشت اصلاح: ۱۴۰۵/۰۵/۲۶ — حلقهٔ دوگانه حذف شد (STR-02). `chat_completion_sync` از pool مشترک `_executor` استفاده می‌کند؛ `asyncio.run` تودرتو برای ورک‌فلو از context async هنوز لازم است.

### ARC-06 — پوشش تست زیرسیستم‌ها نازک است
- وضعیت: باز
- اولویت: P1
- مالک: backend
- مشکل: تست قوی روی continuation/budget/routing/write-guard است. تقریباً بدون تست: CRUD حافظهٔ آیتم و hooks، skill runtime/marketplace، hybrid RAG/pgvector، MCP JSON-RPC، invoke کانکتور، صوت، CRM AI، citation/attachment/export، اجرای eval suite، `AIAgentAction`، ترکیب `prompt_service`.
- معیار پذیرش: برای هر زیرسیستم در کارت امتیاز حداقل یک تست مسیر اصلی + یک تست شکست (ایندکس، approval، SSRF).
- پیشنهاد: شروع با MCP write-approval، memory item CRUD، skill `select_skills_for_query`، CRM probability بدون fallback ۵۰.
- یادداشت اصلاح: ۱۴۰۵/۰۵/۲۶ — تست citation/eval assertion و MCP write-guard اضافه شد؛ موج دهم: router mixin، untrusted/PII، SSRF IPv6، gold eval CI، شمارندهٔ متریک. CRUD حافظه، RAG/pgvector، صوت و ورک‌فلو هنوز نازک است.

---

# Q. شکاف قابلیت محصول (سطح جهانی که هنوز نیست)

این‌ها عمداً `P3`اند مگر اینکه محصول تصمیم بگیرد زودتر.

| شناسه | قابلیت | رقیب مرجع | وضعیت |
|--------|---------|------------|--------|
| GAP-01 | Computer use / مرور UI حسابیکس | Claude Computer Use, OpenAI Operator | باز |
| GAP-02 | تصویر فاکتور → سند | ChatGPT vision | باز (RAG-03) |
| GAP-03 | همکاری چندکاربره روی یک جلسه | ChatGPT shared | باز |
| GAP-04 | ایجنت پس‌زمینهٔ سفارشی | ChatGPT scheduled, Cursor background | باز (BIL-02) |
| GAP-05 | فروشگاه مهارت عمومی با پول | GPT Store / Claude skills | فاز ۳ سند مهارت |
| GAP-06 | پاسخ صوتی دوطرفه هم‌تراز GPT-4o Realtime | OpenAI Realtime | جزئی (VOI) |
| GAP-07 | چند ایجنت تخصصی (حسابدار، انباردار، فروش) | Custom GPT / Agent teams | باز — جدا از AGT-06 (subagent موقت) |
| GAP-08 | شبیه‌سازی what-if مالی با sandbox | Copilot for Finance | باز |

---

## ماتریس اولویت ۱۲ هفته

اسپرینت‌ها پیشنهادی‌اند؛ ترتیب را با ظرفیت تیم عوض کنید.

| هفته | تمرکز | آیتم‌ها |
|------|--------|---------|
| ۱–۲ | ایمنی و پایداری | SEC-02✓، STR-01✓، STR-05✓، UX-07✓، RAG-01✓، AGT-01✓ |
| ۳–۴ | معماری قابل حرکت | ARC-01 (شروع: ModelRouter+UsageMeter mixin)، STR-02✓، UX-01 (resume + approval + turn helpers)، AGT-07✓، AGT-03✓، AGT-04✓، ARC-05✓ |
| ۵–۶ | ابزار درست | TOOL-01✓، TOOL-06✓، AGT-05✓، TOOL-04✓، TOOL-07✓ |
| ۷–۸ | اعتماد پاسخ | RAG-02✓، AGT-08✓، OBS-01 (assertion + gold CI)، ARC-06 (شروع) |
| ۹–۱۰ | کانال‌ها | CHN-01✓، CHN-02 حلقه+allowlist (استریم ویجت مانده)، WFA-01✓، WFA-02 شروع ماتریس، SEC-01✓، SEC-05✓، PRM-02✓، SKL-01 (chip) |
| ۱۱–۱۲ | چت و مشاهده | UX-09 Enter-to-send، UX-01 شیت پیام + SessionController + consume استریم + VoiceSession، UX-02 snackbar/حافظه/دانش، PRM-04✓ لایهٔ semi_static، TOOL-06✓ متریک موازی، AGT-06✓ قرارداد+حلقه+cancel subagent |

فاز ۹ ابزار دامنه (`TOOL-03`) می‌تواند موازی با هفتهٔ ۵–۸ جلو برود اگر مالک محصول جدا باشد.

---

## چک‌لیست هر Pull Request مربوط به AI

کپی کنید داخل توصیف PR:

- [ ] ابزار جدید: `function_registry` + `ai_permission_map` + `ai_tool_intent` + `ai_tool_keys` + `ai_chat_l10n` + write guard اگر نوشتنی است
- [ ] کیس eval یا تست واحد برای رفتار جدید
- [ ] SSE: اگر event جدید است، Dart model + نسخه پروتکل
- [ ] بدون رشتهٔ کاربرنما hardcoded (FA/EN)
- [ ] اگر حلقه عوض شد: مسیر stream و non-stream یا تجمیع واحد
- [ ] این سند: وضعیت آیتم + یک سطر تاریخچه

---

## فهرست فایل‌های لنگر (برای مرور جزبه‌جز)

**بک‌اند هسته**  
`ai_service.py` · `ai_model_router.py` · `ai_usage_meter.py` · `ai_agent_run.py` · `ai_agent_continuation.py` · `ai_goal_assessment.py` · `ai_budget.py` · `ai_execution_policy.py` · `ai_write_guard.py` · `ai_untrusted.py` · `ai_tool_intent.py` · `ai_tool_result.py` · `ai_tool_parallel.py` · `ai_subagent.py` · `ai_system_prompt.py` · `ai_prompt_cache.py` · `ai_insight_service.py` · `ai_citation_service.py` · `ai_eval_assertions.py` · `function_registry.py` · `ai_provider.py` · `prompt_service.py` · `adapters/api/v1/ai/chat.py`

**حافظه و دانش**  
`ai_memory_service.py` · `ai_memory_item_service.py` · `ai_knowledge_service.py` · `ai_embedding_service.py` · `ai_citation_service.py` · `ai_attachment_service.py`

**مهارت / MCP / ورک‌فلو**  
`ai_skill_runtime.py` · `ai_mcp_service.py` · `ai_connector_service.py` · `workflow/actions/ai_agent_action.py`

**کانال**  
`telegram_ai_chat_service.py` · `telegram_ai_chat_handler.py` · `telegram_ai_chat_text.py` · `ai_channel_policy.py` · `adapters/api/v1/ai/crm_ai.py` · `adapters/api/v1/support/ai_tickets.py` · `adapters/api/v1/ai/voice_ws.py`

**فرانت**  
`ai_chat_dialog.dart` · `ai_chat_stream_controller.dart` · `ai_chat_stream_turn.dart` · `ai_chat_voice_session.dart` · `ai_chat_session_controller.dart` · `ai_chat_turn.dart` · `ai_chat_composer.dart` · `ai_chat_composer_keys.dart` · `ai_chat_message_sheet.dart` · `ai_chat_memory_sheet.dart` · `ai_chat_knowledge_sheet.dart` · `ai_chat_message_body.dart` · `ai_chat_resume.dart` · `ai_citation_chips.dart` · `ai_tool_envelope.dart` · `ai_write_approval_banner.dart` · `crm_ai_assistant_widget.dart` · `lib/services/ai_service.dart`

**ثابت‌ها**  
`ai_constants.py` — هر تغییر سقف اینجا باید در این سند منعکس شود.

---

## تاریخچهٔ به‌روزرسانی

| تاریخ | نسخه | چه تغییر کرد |
|--------|------|----------------|
| ۱۴۰۵/۰۵/۲۶ | 1.0 | ممیزی اولیه از روی کد؛ همهٔ آیتم‌ها `باز` |
| ۱۴۰۵/۰۵/۲۶ | 1.1 | ادغام یافته‌های خط‌به‌خط: `done` ناقص (STR-05)، باگ خطای UI (UX-07)، شاخهٔ مرده continuation (AGT-07)، ابزار موازی (TOOL-06)، تست زیرسیستم (ARC-06)، CRM احتمال ۵۰، MCP بدون کلاینت |
| ۱۴۰۵/۰۵/۲۶ | 1.2 | پیاده‌سازی موج اول: STR-05، UX-07، AGT-07، SEC-02، RAG-01 |
| ۱۴۰۵/۰۵/۲۶ | 1.3 | موج دوم: TOOL-06 سقف موازی ابزار، AGT-01 جدول+API+UI ادامه، STR-01 event id و Last-Event-ID، CHN-02 حذف fallback احتمال ۵۰ |
| ۱۴۰۵/۰۵/۲۶ | 1.4 | موج سوم: STR-02 aggregator حلقهٔ واحد، AGT-04 دروازهٔ persist بدون ابزار، AGT-03 بنر ادامه با stop_message، ARC-05 pool مشترک |
| ۱۴۰۵/۰۵/۲۶ | 1.5 | موج چهارم: TOOL-01 رتبهٔ واژه‌ای سقف ۴۸، تاریخچه+اتحاد مهارت، مجموعه طلایی recall |
| ۱۴۰۵/۰۵/۲۶ | 1.6 | موج پنجم: AGT-05 ابزار plan در allowlist و tool_choice برای complex؛ UX-01 برش resume hint؛ ARC-04 تست واحد Flutter |
| ۱۴۰۵/۰۵/۲۶ | 1.7 | موج ششم: TOOL-04 envelope برش نتیجه؛ TOOL-07 tool_choice آنتروپیک؛ پین برنامه در UX؛ جدول از رکورد ابزار |
| ۱۴۰۵/۰۵/۲۶ | 1.8 | موج هفتم: AGT-08 تکرار ابزار پس از خطا؛ AGT-05 رد/تأیید todo توسط کاربر؛ UX-01 برش collectPendingApprovalOps |
| ۱۴۰۵/۰۵/۲۶ | 1.9 | موج هشتم: RAG-02 chip استناد قابل کلیک؛ OBS-01 assertionهای tool/write/citation/language بدون LLM |
| ۱۴۰۵/۰۵/۲۶ | 2.0 | موج نهم: SEC-01 approval_id؛ SEC-05 fail-closed؛ WFA-01 بدون write پیش‌فرض؛ PRM-02 گزارش کوتاه medium؛ CHN-01 صفحه‌بندی+persist؛ SKL-01 chip مهارت |
| ۱۴۰۵/۰۵/۲۶ | 2.1 | موج دهم: ARC-01 mixin مسیریابی/سهمیه؛ UX-01 turn helpers؛ OBS-01 دروازه CI + fluency + قفل زمان‌بندی؛ SEC-03/۰۴ SSRF و untrusted؛ PRM-01 سیاست استاتیک؛ OBS-02 شمارنده |
| ۱۴۰۵/۰۵/۲۶ | 2.2 | موج یازدهم: حفظ tools کالر؛ سیاست کانال CRM/تیکت؛ تأیید inline تلگرام + typing؛ chip ابزار/استناد CRM |
| ۱۴۰۵/۰۵/۲۸ | 2.3 | موج دوازدهم (چت): Enter-to-send دسکتاپ؛ شیت اقدامات پیام جدا؛ l10n کروم composer/app bar/بنر تأیید؛ liveRegion دسترسی‌پذیری |
| ۱۴۰۵/۰۵/۲۸ | 2.4 | موج سیزدهم (چت): `AIChatSessionController` برای جلسه/پیام؛ `planChatSend`؛ بدون جابه‌جایی حلقهٔ استریم |
| ۱۴۰۵/۰۵/۲۸ | 2.5 | موج چهاردهم (چت): حلقهٔ SSE در `AIChatStreamController.consume`؛ `AIChatStreamTurn`؛ l10n پاسخ خالی؛ تست نوبت استریم |
| ۱۴۰۵/۰۵/۲۸ | 2.6 | موج پانزدهم (چت): `AIChatVoiceSessionController` + تفسیر رویداد صوت؛ l10n snackbar چت و شیت حافظه/دانش |
| ۱۴۰۵/۰۵/۲۸ | 2.7 | بررسی runtime: AGT-06 بدون subagent (P1)؛ TOOL-06 موازی read موجود؛ PRM-04 تکرار بینش در system نه در تاریخچه؛ سناریوی اجرا |
| ۱۴۰۵/۰۵/۲۸ | 2.8 | PRM-04 لایهٔ semi_static + تفکیک توکن context_usage؛ TOOL-06 متریک موازی و eval چنددامنه‌ای؛ AGT-06 spawn/await/cancel با سقف ۲×۴ و fail-closed نوشتن |
| ۱۴۰۵/۰۵/۲۷ | 2.8+ | لینک صف محصولی [`AI_CHAT_PRODUCT_ISSUES.md`](AI_CHAT_PRODUCT_ISSUES.md) (CHAT-01…06 از گزارش کاربر) |

<!-- الگو:
| ۱۴۰۵/۰۶/۰۱ | 1.1 | STR-01 انجام‌شده — reconnect SSE با Last-Event-ID |
-->
