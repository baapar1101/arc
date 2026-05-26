"""
ثابت‌های مشترک سرویس AI (تک‌API).
"""
from __future__ import annotations

# حداکثر نوبت LLM ↔ tool در یک پاسخ (پیش‌فرض)
MAX_AGENT_ITERATIONS = 8

# تعداد iteration بر اساس پیچیدگی سوال
QUERY_COMPLEXITY_ITERATIONS: dict[str, int] = {
    "simple": 3,    # سوال ساده — پرس‌وجوی تک‌ابزار
    "medium": 6,    # سوال متوسط — چند ابزار یا تحلیل
    "complex": 12,  # سوال پیچیده — گزارش چندمرحله‌ای
}

# حداکثر ابزار ارسالی به مدل در هر درخواست (پس از intent filter)
MAX_TOOLS_PER_REQUEST = 32

# محدودیت پیام‌ها برای context
MAX_HISTORY_MESSAGES = 40
MAX_SINGLE_MESSAGE_CHARS = 12_000
MAX_SYSTEM_PROMPT_CHARS = 32_000

# حداکثر طول JSON نتیجه tool در پیام role=tool
MAX_TOOL_RESULT_JSON_CHARS = 6_000

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
