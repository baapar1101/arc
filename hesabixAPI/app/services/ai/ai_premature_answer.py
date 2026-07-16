"""
تشخیص «narrative وضعیت» در متن پاسخ — فقط برای eval/logging/متریک.

⚠️ Plan C: این ماژول هرگز نباید در مسیر تصمیم continue/stop تولید (runtime)
استفاده شود. تصمیم agent باید صرفاً بر اساس evidence ساختاری (tool calls و
نتایج آن‌ها) باشد، نه regex روی متن مدل. این تابع فقط برای:
  - تست‌های regression (شناسایی نمونه‌های شناخته‌شده باگ)
  - هشدار نرم (log warning) هنگام persist، بدون تغییر رفتار
استفاده می‌شود.
"""
from __future__ import annotations

import re

# الگوهای رایج narrative میانی («در حال …»، «می‌خواهم …») که کاربر نباید آن را
# به‌جای پاسخ نهایی ببیند — برگرفته از نمونه‌های واقعی باگ در DB.
_STATUS_NARRATIVE_PATTERNS = re.compile(
    r"^(در\s*حال|می‌خواهم|می‌خوام|قصد\s*دارم|ابتدا|اول\s*باید|برای\s*این\s*کار|"
    r"we\s*will\s*call|i\s*will\s*call|i'm\s*going\s*to|let\s*me)\b",
    re.IGNORECASE,
)

# جملاتی که صرفاً می‌گویند تابع/ابزاری صدا زده می‌شود، بدون داده واقعی.
_TOOL_INTENT_ANNOUNCEMENT = re.compile(
    r"(صدا\s*می‌زنیم|صدا\s*می‌زنم|فراخوانی\s*می‌کنم|call\s+\w+|resolve_date_range|"
    r"get_financial_summary|query_business_data)",
    re.IGNORECASE,
)


def looks_like_status_narrative(text: str) -> bool:
    """آیا متن شبیه narrative وضعیتِ میانی است (نه پاسخ نهایی)؟

    فقط برای eval/logging — هرگز در مسیر production continue/stop استفاده
    نشود (به‌جای آن از ai_agent_continuation.assess_text_round_evidence که
    evidence-based است استفاده کنید).
    """
    stripped = (text or "").strip()
    if not stripped:
        return False
    if _STATUS_NARRATIVE_PATTERNS.match(stripped):
        return True
    # پاسخ کوتاه که فقط اعلام قصد استفاده از ابزار می‌کند (بدون داده)
    if len(stripped) < 240 and _TOOL_INTENT_ANNOUNCEMENT.search(stripped):
        return True
    return False
