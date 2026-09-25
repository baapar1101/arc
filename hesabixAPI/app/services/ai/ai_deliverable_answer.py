"""
تشخیص «پاسخ تحویلی» (deliverable) در برابر narrative برنامه‌ریزی / وضعیت.

Plan C+: goal_reached و persist فقط وقتی مجاز است که متن واقعاً پاسخ کاربر باشد،
نه توضیح قصد استفاده از ابزار یا بلوک JSON پارامترها.
"""
from __future__ import annotations

import re
from typing import Any, Dict, List, Optional

from app.services.ai.ai_premature_answer import looks_like_status_narrative
from app.services.ai.ai_tool_intent import query_expects_tool_use

# وقتی سوال داده‌محور است ولی هیچ ابزاری اجرا نشده، ادعای کسب‌وکار persist نمی‌شود.
UNGROUNDED_TOOL_REQUIRED_MESSAGE_FA = (
    "برای پاسخ دقیق به این سوال باید داده‌های کسب‌وکار را از سیستم بخوانم، "
    "اما هنوز ابزاری اجرا نشده است. لطفاً سوال را دوباره بفرستید "
    "یا بازهٔ زمانی و موجودیت موردنظر را دقیق‌تر مشخص کنید."
)

# ادعای نبود/وجود دادهٔ کسب‌وکار بدون اجرای ابزار
_ABSENCE_OR_ENTITY_CLAIM = re.compile(
    r"(فاکتور|رسید|پرداخت|سند|سفارش|سرنخ|فرصت|چک|موجودی|بدهکار|بستانکار|"
    r"فروش|خرید|انبار|مشتری|کالا|تراکنش|هزینه|درآمد).{0,48}"
    r"(نیست|نیستند|وجود\s*ندارد|یافت\s*نشد|پیدا\s*نشد|نداریم|"
    r"صفر(?:\s*است)?|ثبت\s*نشده|ندارد)|"
    r"(هیچ|بدون).{0,24}(فاکتور|رکورد|نتیجه|مورد|سند)|"
    r"(no\s+(?:invoices?|records?|results?)|not\s+found)",
    re.IGNORECASE,
)

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


def looks_like_ungrounded_business_claim(text: str) -> bool:
    """آیا متن بدون ابزار، دادهٔ کسب‌وکار (نبود رکورد / عدد / جدول) ادعا می‌کند؟"""
    stripped = (text or "").strip()
    if not stripped:
        return False
    if _ABSENCE_OR_ENTITY_CLAIM.search(stripped):
        return True
    if has_substantive_answer_markers(stripped):
        return True
    return False


def has_real_tool_evidence(
    function_calls: Optional[List[Any]] = None,
    function_results: Optional[Dict[str, Any]] = None,
) -> bool:
    """شواهد ابزار واقعی — کلیدهای متادیتا (_agent_run و مشابه) شمرده نمی‌شوند."""
    if function_calls:
        return True
    if not isinstance(function_results, dict):
        return False
    return any(not str(key).startswith("_") for key in function_results)


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
    if needs_tools and not has_tool_evidence:
        # سلام / سوال شفاف‌سازی مجاز است؛ ادعای دادهٔ کسب‌وکار بدون tool خیر.
        if looks_like_ungrounded_business_claim(stripped):
            return False
        return len(stripped) >= 8
    return len(stripped) >= 8


def gate_ungrounded_assistant_content(
    content: str,
    *,
    user_query: str,
    history_messages: Optional[List[Dict[str, Any]]] = None,
    function_calls: Optional[List[Any]] = None,
    function_results: Optional[Dict[str, Any]] = None,
) -> str:
    """اگر سوال ابزار می‌خواهد و evidence نیست، ادعای کسب‌وکار را با شفاف‌سازی عوض کن."""
    if not query_expects_tool_use(user_query, history_messages):
        return content
    if has_real_tool_evidence(function_calls, function_results):
        return content
    stripped = (content or "").strip()
    if not stripped:
        return content
    if is_deliverable_answer(
        stripped,
        needs_tools=True,
        has_tool_evidence=False,
    ):
        return content
    return UNGROUNDED_TOOL_REQUIRED_MESSAGE_FA
