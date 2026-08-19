"""
ثابت‌های مشترک سرویس AI (تک‌API).
"""
from __future__ import annotations

# مدل مجازی «خودکار» — در کاتالوگ DB نیست؛ runtime resolve می‌شود.
AUTO_MODEL_CODE = "auto"

# انواع عملیات برای routing مدل auto
AI_OPERATION_CHAT = "chat"
AI_OPERATION_TITLE = "title"
AI_OPERATION_HISTORY_SUMMARY = "history_summary"
AI_OPERATION_THOUGHT = "thought_synthesis"
AI_OPERATION_SUBAGENT = "subagent"
AI_OPERATION_MEMORY_CURATE = "memory_curate"

LIGHT_AI_OPERATIONS: frozenset[str] = frozenset({
    AI_OPERATION_TITLE,
    AI_OPERATION_HISTORY_SUMMARY,
    AI_OPERATION_THOUGHT,
    AI_OPERATION_MEMORY_CURATE,
})

# timeout ارتباط با AI Provider (ثانیه)
AI_PROVIDER_TIMEOUT_SEC = 120.0
AI_PROVIDER_STREAM_TIMEOUT_SEC = 180.0

# حداکثر نوبت LLM ↔ tool در یک پاسخ (پیش‌فرض)
MAX_AGENT_ITERATIONS = 8

# تعداد iteration بر اساس پیچیدگی سوال
QUERY_COMPLEXITY_ITERATIONS: dict[str, int] = {
    "simple": 3,    # سوال ساده — پرس‌وجوی تک‌ابزار
    "medium": 6,    # سوال متوسط — چند ابزار یا تحلیل
    "complex": 12,  # سوال پیچیده — گزارش چندمرحله‌ای
}

# حداکثر ابزار ارسالی به مدل در هر درخواست (پس از intent filter)
MAX_TOOLS_PER_REQUEST = 48
# حالت خودکار/با تأیید: کاتالوگ کامل تا سقف ایمنی ارائه‌دهنده؛
# ابزارهای نوشتنی هرگز به‌خاطر ranking حذف نمی‌شوند.
MAX_TOOLS_AUTONOMOUS = 128
# سقف مطلق Discovery — Consumer نمی‌تواند کل کاتالوگ نامحدود را بخواهد.
DISCOVERY_HARD_MAX = 256

# سقف همزمانی ابزارهای read-only در یک نوبت (writeها همیشه سریال‌اند)
MAX_PARALLEL_READ_TOOLS = 4

# سقف subagent موقت (AGT-06) — فقط چت درون‌برنامه
MAX_SUBAGENTS_PER_PARENT = 2
MAX_SUBAGENT_ITERATIONS = 4
SUBAGENT_TIMEOUT_SEC = 90.0
# providerهایی که tool_choice اجباری را به API می‌فرستند
PROVIDERS_WITH_FORCED_TOOLS = frozenset({"openai", "anthropic"})

# بافر SSE درون‌پردازه‌ای برای Last-Event-ID (بدون Redis)
SSE_EVENT_BUFFER_MAX = 400
SSE_EVENT_BUFFER_TTL_SEC = 15 * 60

# محدودیت پیام‌ها برای context
MAX_HISTORY_MESSAGES = 40
MAX_SINGLE_MESSAGE_CHARS = 12_000
MAX_SYSTEM_PROMPT_CHARS = 32_000

# دروازهٔ CI برای suite طلایی آفلاین (بدون فراخوانی مدل زنده)
MIN_OFFLINE_EVAL_PASS_RATE = 100

# بودجهٔ تخمینی توکن ورودی (قبل از ارسال به مدل)
CONTEXT_INPUT_TOKEN_BUDGET = 28_000
CONTEXT_SUMMARIZE_THRESHOLD_RATIO = 0.72
CONTEXT_KEEP_RECENT_MESSAGES = 24
CONTEXT_KEEP_HEAD_MESSAGES = 4

# حافظه بلندمدت — فاصلهٔ به‌روزرسانی خودکار (پیام کاربر)
# منسوخ: یادگیری regex دیگر در مسیر production صدا زده نمی‌شود.
AUTO_SUMMARIZE_USER_MESSAGE_INTERVAL = 6
MAX_MEMORY_FEEDBACK_UPDATES_PER_DAY = 8
MAX_LLM_SUMMARIZE_PER_USER_DAY = 24
MAX_LLM_MEMORY_CURATE_PER_USER_DAY = 80
MEMORY_CURATE_MAX_OPS = 4
MEMORY_CURATE_MIN_CONFIDENCE = 0.55
MEMORY_CURATE_MAX_TOKENS = 500
MEMORY_ALWAYS_KIND_CHAR_BUDGET = 2200
MEMORY_RECALL_KIND_CHAR_BUDGET = 1400
MEMORY_RECALL_MAX_ITEMS = 12

# سقف صفحه‌بندی ابزارهای لیست (هم‌تراز QueryInfo.le=100)
AI_LIST_TAKE_MAX = 100
AI_LIST_TAKE_DEFAULT = 50

# حداکثر طول JSON نتیجه tool در پیام role=tool
MAX_TOOL_RESULT_JSON_CHARS = 6_000
# سقف ردیف در envelope ارسالی به مدل (بقیه در summary.total)
MAX_TOOL_RESULT_RECORDS = 15

# کش بینش کسب‌وکار در prompt (ثانیه)
INSIGHTS_CACHE_TTL_SEC = 300

# حداکثر انتظار برای RAG/embedding در ساخت prompt (ثانیه)
KNOWLEDGE_LOAD_TIMEOUT_SEC = 2.5

# TTL کش نتیجه tool در session (ثانیه) — فقط ابزارهای read-only
TOOL_CACHE_TTL_SEC = 60

# حداکثر تعداد رکورد کش per session
TOOL_CACHE_MAX_ENTRIES = 200

# حداقل طول سوال برای فعال‌سازی planning step
PLANNING_STEP_MIN_CHARS = 30

# Retry LLM
MAX_LLM_RETRIES = 3

# حافظه item-based (v2)
MAX_MEMORY_ITEMS_PER_USER = 200
MAX_MEMORY_ITEM_CONTENT_CHARS = 2048
MEMORY_AUTO_APPROVE_CATEGORIES = frozenset({"fact", "term", "preference"})
MEMORY_KINDS = frozenset({
    "instruction",
    "identity",
    "preference",
    "context",
    "goal",
    "constraint",
})
MEMORY_ALWAYS_KINDS = frozenset({"instruction", "identity", "preference", "constraint"})
MEMORY_RECALL_KINDS = frozenset({"context", "goal"})
MEMORY_CURATOR_AUTO_KINDS = frozenset({
    "identity",
    "preference",
    "context",
    "goal",
    "constraint",
})

# Exploration mode
EXPLORATION_COMPLEXITY_ITERATIONS: dict[str, int] = {
    "simple": 4,
    "medium": 8,
    "complex": 15,
}
EXPLORATION_LLM_THOUGHT_MIN_TOOLS = 2

# ---- بودجهٔ یکپارچهٔ مراحل استدلال (Agent Budget) ----
# سقف چندبعدی برای کنترل «سقف مراحل استدلال»: علاوه بر تعداد نوبت‌ها،
# بودجهٔ توکن کل و سقف زمان دیوار (wall-clock) نیز اعمال می‌شود.

# سقف توکن مصرفی کل (ورودی+خروجی) در یک پاسخ، بر اساس پیچیدگی سوال.
QUERY_COMPLEXITY_TOKEN_BUDGET: dict[str, int] = {
    "simple": 24_000,
    "medium": 80_000,
    "complex": 220_000,
}

# سقف زمان دیوار (ثانیه) برای کل حلقهٔ agent، بر اساس پیچیدگی سوال.
QUERY_COMPLEXITY_WALL_CLOCK_SEC: dict[str, float] = {
    "simple": 45.0,
    "medium": 120.0,
    "complex": 300.0,
}

# توقف زودهنگام: اگر این تعداد نوبت متوالی «بی‌حاصل» (خطا یا بدون دادهٔ جدید)
# رخ دهد، حلقه پیش از رسیدن به سقف متوقف می‌شود.
MAX_UNPRODUCTIVE_ROUNDS = 2

# ---- تمدید پویا بودجه agent (ارزیابی هدف + ضد loop) ----
# وقتی ارزیابی میانی نشان دهد هدف محقق نشده، بودجه تا این حد تمدید می‌شود.
AGENT_BUDGET_EXTENSIONS_MAX = 2
AGENT_BUDGET_EXTENSION_ITERATIONS = 2
AGENT_BUDGET_ABSOLUTE_MAX_ITERATIONS = 15
# بیش از این تکرار همان tool+args با نتیجهٔ موفق → تشخیص loop و توقف تمدید
AGENT_MAX_IDENTICAL_TOOL_REPEATS = 1
# تکرار همان فراخوانی وقتی نتیجه خطا/خالی است؛ سومی حلقه محسوب می‌شود
AGENT_MAX_IDENTICAL_TOOL_FAILURES = 2

# ---- کنترل استدلال درون‌مدلی (reasoning effort) ----
# سطوح مجاز تلاش استدلال برای مدل‌های reasoning (OpenAI o-series/gpt-5 و Anthropic).
REASONING_EFFORT_LEVELS: frozenset[str] = frozenset(
    {"minimal", "low", "medium", "high"}
)

# نگاشت سطح تلاش به بودجهٔ توکن تفکر (thinking) برای Anthropic extended thinking.
ANTHROPIC_THINKING_BUDGET_TOKENS: dict[str, int] = {
    "minimal": 1_024,
    "low": 4_000,
    "medium": 10_000,
    "high": 24_000,
}

# انتخاب خودکار سطح تلاش استدلال بر اساس پیچیدگی سوال (وقتی مدل reasoning است
# ولی سطح صریحی تنظیم نشده باشد).
REASONING_EFFORT_BY_COMPLEXITY: dict[str, str] = {
    "simple": "low",
    "medium": "medium",
    "complex": "high",
}

# حداکثر انتظار برای هر loader زمینهٔ prompt (ثانیه)
PROMPT_LOADER_TIMEOUT_SEC = 4.0

# حداکثر انتظار برای نوبت اضطراری «سنتز اجباری» (بدون ابزار) وقتی حلقه با
# شواهد explored/thought اما بدون پاسخ متنی تمام شده است (Phase 1).
FORCED_SYNTHESIS_TIMEOUT_SEC = 25.0

# حداقل طول پاسخ متنی برای «کافی بودن» بدون فراخوانی ابزار (agent loop)
SUBSTANTIVE_TEXT_MIN_CHARS = 160
# پاسخ کوتاه‌تر از این — ممکن است یک نوبت دیگر مجاز باشد
TEXT_ANSWER_SHORT_THRESHOLD_CHARS = 80

# ---- Prompt Caching (Provider-level) ----
# فعال‌سازی cache_control (Anthropic) و prompt_cache_key (OpenAI)
PROMPT_CACHE_ENABLED = True
# حداقل توکن تخمینی prefix ثابت برای فعال‌سازی (Anthropic Sonnet ≈1024)
PROMPT_CACHE_MIN_STATIC_TOKENS = 1024
# TTL Anthropic: "5m" (پیش‌فرض) یا "1h"
ANTHROPIC_PROMPT_CACHE_TTL = "5m"
# OpenAI extended retention: "in_memory" (پیش‌فرض) یا "24h"
OPENAI_PROMPT_CACHE_RETENTION = "in_memory"
