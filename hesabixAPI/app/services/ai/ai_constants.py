"""
ثابت‌های مشترک سرویس AI (تک‌API).
"""
from __future__ import annotations

# حداکثر نوبت LLM ↔ tool در یک پاسخ
MAX_AGENT_ITERATIONS = 8

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
