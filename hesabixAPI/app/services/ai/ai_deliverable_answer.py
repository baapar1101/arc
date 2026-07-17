"""
تشخیص «پاسخ تحویلی» (deliverable) در برابر narrative برنامه‌ریزی / وضعیت.

Plan C+: goal_reached و persist فقط وقتی مجاز است که متن واقعاً پاسخ کاربر باشد،
نه توضیح قصد استفاده از ابزار یا بلوک JSON پارامترها.
"""
from __future__ import annotations

import re

from app.services.ai.ai_premature_answer import looks_like_status_narrative

# برنامهٔ چندمرحله‌ای: «ابتدا … سپس …»
_PLANNING_MULTI_STEP = re.compile(
    r"(ابتدا|اول(?:اً)?).{3,200}(سپس|بعد(?:اً)?|then|after\s+that)",
    re.IGNORECASE | re.DOTALL,
)

# افعال آیندهٔ planning بدون ارائهٔ داده
_PLANNING_FUTURE_INTENT = re.compile(
    r"(مشخص\s*می‌کنم|دریافت\s*می‌کنم|تبدیل\s*می‌کنم|محاسبه\s*می‌کنم|"
    r"جمع‌آوری\s*می‌کنم|استخراج\s*می‌کنم|"
    r"i\s+will\s+(?:call|fetch|get|convert|retrieve))",
    re.IGNORECASE,
)

# بلوک JSON که فقط پارامتر ابزار است (نه گزارش)
_TOOL_ARGS_JSON_BLOCK = re.compile(
    r"```(?:json)?\s*\{[^}]*"
    r"(?:relative|from_date|to_date|calendar_type|fiscal_year)"
    r"[^}]*\}\s*```",
    re.IGNORECASE | re.DOTALL,
)

# اعلام صریح فراخوانی ابزار بدون دادهٔ گزارش
_TOOL_CALL_ANNOUNCEMENT = re.compile(
    r"(?:تابع|function|tool)\s+[\w_]+|"
    r"resolve_date_range|get_financial_summary|get_sales_report|"
    r"get_purchase_report|get_cash_flow|get_debtors_report|query_business_data",
    re.IGNORECASE,
)

# نشانه‌های پاسخ داده‌محور (عدد، جدول، خلاصه با مقدار)
_SUBSTANTIVE_NUMBER = re.compile(
    r"[\d۰-۹٠-٩]{2,}|"
    r"(?:ریال|تومان|میلیون|میلیارد|درصد|٪|%)",
    re.IGNORECASE,
)

_MARKDOWN_TABLE = re.compile(r"\|.+\|.+\|", re.DOTALL)

_REPORT_HEADER = re.compile(
    r"(?:\*\*)?(?:خلاصه|گزارش|نتیجه|جمع‌بندی|وضعیت\s*مالی)",
    re.IGNORECASE,
)


def looks_like_planning_narrative(text: str) -> bool:
    """آیا متن فقط برنامه‌ریزی agent است (نه پاسخ تحویلی)؟"""
    stripped = (text or "").strip()
    if not stripped:
        return False
    if _PLANNING_MULTI_STEP.search(stripped):
        return True
    if _TOOL_ARGS_JSON_BLOCK.search(stripped):
        return True
    if _PLANNING_FUTURE_INTENT.search(stripped):
        if not _SUBSTANTIVE_NUMBER.search(stripped):
            return True
    if len(stripped) < 400 and _TOOL_CALL_ANNOUNCEMENT.search(stripped):
        if not _SUBSTANTIVE_NUMBER.search(stripped):
            return True
    return False


def has_substantive_answer_markers(text: str) -> bool:
    """آیا متن نشانه‌های پاسخ واقعی (عدد/جدول/خلاصه) دارد؟"""
    stripped = (text or "").strip()
    if not stripped:
        return False
    if _SUBSTANTIVE_NUMBER.search(stripped):
        return True
    if _MARKDOWN_TABLE.search(stripped):
        return True
    if _REPORT_HEADER.search(stripped) and len(stripped) >= 80:
        return True
    return False


def is_deliverable_answer(
    text: str,
    *,
    needs_tools: bool = False,
    has_tool_evidence: bool = False,
) -> bool:
    """آیا متن پاسخ نهایی قابل تحویل به کاربر است؟"""
    stripped = (text or "").strip()
    if not stripped:
        return False
    if looks_like_status_narrative(stripped):
        return False
    if looks_like_planning_narrative(stripped):
        return False
    if needs_tools and has_tool_evidence:
        return has_substantive_answer_markers(stripped)
    return len(stripped) >= 8
