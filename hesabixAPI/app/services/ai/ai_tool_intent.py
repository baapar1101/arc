"""
انتخاب زیرمجموعهٔ ابزارها بر اساس intent متن کاربر (بدون API دوم).
همچنین تخمین پیچیدگی سوال برای تنظیم تعداد iteration.
"""
from __future__ import annotations

import re
from typing import AbstractSet, Iterable, List, Optional, Sequence, Set, Union

from app.services.ai.ai_constants import (
    MAX_TOOLS_AUTONOMOUS,
    MAX_TOOLS_PER_REQUEST,
    QUERY_COMPLEXITY_ITERATIONS,
)
from app.services.ai.ai_tool_index import get_tool_index

_TOOL_INDEX = get_tool_index()
_CATEGORY_TOOLS = _TOOL_INDEX.category_tools
_CORE_TOOL_NAMES = _TOOL_INDEX.core_names
_WRITE_TOOLS = _TOOL_INDEX.intent_write_names
_WRITE_TOOL_COMPANIONS = _TOOL_INDEX.companions
MEMORY_TOOL_NAMES = _CATEGORY_TOOLS.get("memory", frozenset())


# کلیدواژهٔ فارسی/انگلیسی → دسته
_KEYWORD_CATEGORIES: List[tuple[str, str]] = [
    (r"فاکتور|invoice|فروش|خرید|دریافت|پرداخت|چک|انتقال|سند|حساب|بانک|صندوق|سال\s*مال|تراز|افتتاح|اقساط|اعتبار|credit|receipt|payment|بدهکار|بستانکار|debtor|creditor", "financial"),
    (r"انبار|موجودی|حواله|warehouse|stock|کاردکس|bom|تولید|production", "warehouse"),
    (r"سرنخ|lead|معامله|deal|crm|قیف|pipeline|فعالیت\s*crm", "crm"),
    (r"باشگاه|امتیاز|rfm|مشتری\s*وفادار|customer\s*club", "customer_club"),
    (r"مالیات|مودیان|tax|کارپوشه", "tax"),
    (r"پروژه|project", "projects"),
    (r"ووکامرس|woocommerce|باسلام|basalam|کانکتور|connector|یکپارچه", "integration"),
    (r"مرحله|گام|قدم|سناریو|چند\s*مرحله|گام\s*به\s*گام|برنامه\s*کار|checklist|todo", "agent"),
    (r"فروش\s*سریع|quick\s*sales|لیست\s*قیمت|price\s*list|لاگ|فعالیت\s*سیستم|workflow|تعمیر|گارانتی|توزیع|صندوق\s*خرد", "misc"),
    (r"شخص|مشتری|تامین|تأمین|supplier|customer|people|گروه\s*اشخاص|طرف[\s\-]*حساب", "people"),
    (r"دسته\s*بندی|category|ویژگی\s*کالا|attribute|کالا|محصول|product", "products_write"),
    (r"فیلتر\s*پیشرفته|عملگر|بزرگتر\s*از|کمتر\s*از|شامل|list_queryable|query_business", "query"),
    (r"ماه\s*گذشته|هفته\s*اخیر|امروز|دیروز|فروردین|اردیبهشت|خرداد|مرداد|شهریور|آبان|اسفند|بازه\s*تاریخ|resolve_date|از\s*تاریخ|تا\s*تاریخ", "query"),
    (r"گزارش\s*یکپارچه|get_report|batch_query|list_available_reports", "reports_meta"),
    (r"خروجی|export|اکسل|excel|دانلود\s*لیست", "reports_meta"),
    (r"تراز\s*آزمایشی|دفتر\s*کل|دفتر\s*روزنامه|سود\s*و\s*زیان|مرور\s*حساب|trial\s*balance|ledger", "reports_meta"),
    (r"قالب\s*گزارش|قالب\s*فاکتور|قالب\s*چاپ|report\s*template", "report_templates"),
    (r"بازار\s*افزونه|افزونه\s*فعال|plugin\s*marketplace|marketplace|افزونه", "marketplace"),
    (r"dead\s*letter|صف\s*خطا|خلاصه\s*باسلام", "integration"),
    (r"هزینه|درآمد|expense|income|مالی", "financial"),
    (r"اتوماسیون|automation|workflow|گردش\s*کار|اجرای\s*workflow|تریگر\s*workflow", "workflow"),
    (r"کیف\s*پول|wallet|درگاه\s*پرداخت|سرفصل|حساب\s*کل", "financial"),
    (r"hscript|اچ[\s\-]*اسکریپت|اسکریپت\s*حسابیکس", "hscript"),
    (
        r"حافظه\s*دستیار|دستورات\s*همیشگی|چی\s*درباره(?:‌|\s)*من|"
        r"what do you (?:know|remember) about me|از حافظه|"
        r"فراموش(?:ش)?\s*کن|به\s*خاطر\s*بسپار|remember (?:this|that|me)|"
        r"forget (?:this|that|my)|read_memory|upsert_memory",
        "memory",
    ),
]

_WRITE_KEYWORDS = re.compile(
    r"ثبت|ایجاد|اضافه|بساز|بزن|ویرایش|حذف|create|update|add|new\s+invoice|مشتری\s+جدید|کالای\s+جدید",
    re.IGNORECASE,
)

_PEOPLE_KEYWORDS = re.compile(
    r"شخص|مشتری|تامین|تأمین|supplier|customer|people|person|علی|نام\s+",
    re.IGNORECASE,
)


def _normalize_query(q: Optional[str]) -> str:
    return (q or "").strip().lower()


_GREETING_ONLY = re.compile(
    r"^(سلام|درود|hello|hi|hey|صبح بخیر|عصر بخیر|وقت بخیر)\b",
    re.IGNORECASE,
)
# سلام/درود ابتدای جمله — باید قبل از تشخیص دامنه حذف شود تا «سلام یه گزارش
# هزینه‌ها بده» به‌اشتباه به‌عنوان صرفاً خوش‌وبش تشخیص داده نشود.
_LEADING_GREETING = re.compile(
    r"^(سلام|درود|صبح\s*بخیر|عصر\s*بخیر|وقت\s*بخیر|hello|hi|hey)[\s,،!؛:.]*",
    re.IGNORECASE,
)
_KNOWLEDGE_HINTS = re.compile(
    r"دانشنامه|قوانین|سیاست|رویه|دستورالعمل|راهنما|مقررات|فرآیند|فرایند|"
    r"documentation|policy|procedure|how\s+to",
    re.IGNORECASE,
)


def _strip_leading_greeting(user_query: Optional[str]) -> str:
    """حذف سلام/درود ابتدای جمله قبل از تشخیص دامنه ابزار."""
    text = (user_query or "").strip()
    stripped = _LEADING_GREETING.sub("", text, count=1).strip()
    return stripped or text


def query_needs_knowledge(user_query: Optional[str]) -> bool:
    """آیا جستجوی دانشنامه (embedding) برای این سوال ارزش تأخیر دارد؟"""
    q = (user_query or "").strip()
    if len(q) < 12:
        return False
    if _GREETING_ONLY.match(q) and len(q) < 48:
        return False
    if _KNOWLEDGE_HINTS.search(q):
        return True
    if any(
        token in q
        for token in (
            "چگونه",
            "چطور",
            "چطوری",
            "نحوه",
            "آموزش",
            "توضیح بده",
            "راهنمایی",
        )
    ):
        return True
    return len(q) >= 56


def matched_query_categories(user_query: Optional[str]) -> Set[str]:
    """دسته‌هایی که واقعاً در متن آمده‌اند (بدون fallback عمومی)."""
    text = _normalize_query(user_query)
    if not text:
        return set()
    found: Set[str] = set()
    for pattern, category in _KEYWORD_CATEGORIES:
        if re.search(pattern, text, re.IGNORECASE):
            found.add(category)
    return found


def detect_categories(user_query: Optional[str]) -> Set[str]:
    text = _normalize_query(user_query)
    if not text:
        return set(_CATEGORY_TOOLS.keys()) - {"memory"}
    found = matched_query_categories(user_query)
    if not found:
        # سوال عمومی — چند دستهٔ پرکاربرد
        return {"financial", "warehouse", "crm", "misc"}
    return found


# ---- الگوهای تشخیص پیچیدگی ----
_COMPLEX_PATTERNS = re.compile(
    r"مقایسه|تحلیل|گزارش\s*جامع|روند|پیش‌بینی|همه\s*محصولات|تمام\s*فاکتورها|"
    r"compare|analysis|trend|forecast|comprehensive|overview|summary.*and.*"
    r"|چند.*گزارش|چند.*بررسی|هم.*هم|ضمناً|همچنین.*و.*و",
    re.IGNORECASE,
)
_SIMPLE_PATTERNS = re.compile(
    r"^(سلام|درود|hello|hi|ممنون|خوبی|باشه|اوکی|ok|thanks?)\b",
    re.IGNORECASE,
)
_MEDIUM_PATTERNS = re.compile(
    r"چند|چقدر|لیست|تعداد|جمع|میانگین|how\s+many|total|list|count|average",
    re.IGNORECASE,
)
_REPORT_FORCE_MEDIUM = re.compile(
    r"تراز\s*آزمایشی|ترازنامه|سود\s*و\s*زیان|بدهکار|بستانکار|گردش\s*حساب|"
    r"دفتر\s*کل|دفتر\s*روزنامه|کاردکس|موجودی\s*انبار|سن\s*بدهی|"
    r"trial\s*balance|balance\s*sheet|aging|گزارش",
    re.IGNORECASE,
)
_REPORT_FORCE_COMPLEX = re.compile(
    r"گزارش\s*جامع|تحلیل\s*کامل|بسته\s*مالی|financial\s*package|"
    r"چند\s*گزارش|مقایسه.*گزارش",
    re.IGNORECASE,
)


def estimate_query_complexity(
    user_query: Optional[str],
    history_messages: Optional[List[dict]] = None,
) -> str:
    """
    تخمین پیچیدگی سوال: simple / medium / complex.
    از تاریخچه مکالمه، دسته‌بندی ابزار و الگوهای متنی استفاده می‌کند.
    """
    q = (user_query or "").strip()
    if not q:
        return "simple"

    if _REPORT_FORCE_COMPLEX.search(q):
        return "complex"
    if _REPORT_FORCE_MEDIUM.search(q):
        domain_cats = matched_query_categories(q) - {"query", "reports_meta", "misc"}
        if len(domain_cats) >= 2 or len(q) > 80:
            return "complex"
        return "medium"

    # سوال بسیار کوتاه یا خوش‌و‌بش
    if len(q) < 15 or _SIMPLE_PATTERNS.match(q):
        return "simple"

    categories = matched_query_categories(q)
    if len(categories) >= 3:
        return "complex"
    if len(categories) >= 2 and (
        _MEDIUM_PATTERNS.search(q) or _COMPLEX_PATTERNS.search(q)
    ):
        return "complex"

    # عملیات نوشتنی معمولاً چندمرحله‌ای است
    if _WRITE_KEYWORDS.search(q):
        if len(q) > 80 or len(categories) >= 2:
            return "complex"
        return "medium"

    # الگوهای صریحاً پیچیده
    if _COMPLEX_PATTERNS.search(q) or len(q) > 200:
        return "complex"

    # تعداد علائم سوالی یا ترکیب چند موضوع
    question_marks = q.count("؟") + q.count("?")
    conjunctions = len(re.findall(r"\bو\b|\bهم\b|and\b|also\b|plus\b", q, re.IGNORECASE))
    if question_marks >= 2 or conjunctions >= 2:
        return "complex"

    # بررسی تاریخچه: اگر مکالمه طولانی است سوال احتمالاً عمیق‌تر است
    if history_messages and len(history_messages) >= 6:
        if _MEDIUM_PATTERNS.search(q) or len(categories) >= 2:
            return "complex"

    if _MEDIUM_PATTERNS.search(q) or len(q) > 60 or len(categories) >= 2:
        return "medium"

    return "simple"


# Date/filter words ("امروز") are too broad to count as an accounting domain.
_RANKING_WEAK_DOMAINS = frozenset({"query"})
_STRONG_DATE_INTENT = re.compile(
    r"از\s*تاریخ|تا\s*تاریخ|ماه\s*گذشته|هفته\s*اخیر|بازه\s*تاریخ|"
    r"فروردین|اردیبهشت|خرداد|مرداد|شهریور|آبان|اسفند|"
    r"resolve_date|\d+\s*ماه\s*پیش|سه\s*ماه|۳\s*ماه",
    re.IGNORECASE,
)


def ranking_intent_domains(
    user_query: Optional[str],
    history_messages: Optional[List[dict]] = None,
) -> Set[str]:
    """دسته‌های واقعاً تطبیق‌یافته برای امتیازدهی — بدون dump عمومی.

    detect_categories برای پیچیدگی هنوز fallback دارد؛ Ranking نباید از آن
    برای پر کردن Top-K استفاده کند.
    """
    found = matched_query_categories(_strip_leading_greeting(user_query))
    q = (user_query or "").strip()
    if history_messages and (not (found - _RANKING_WEAK_DOMAINS) or len(q) < 40):
        for msg in reversed(history_messages[-8:]):
            if msg.get("role") != "user":
                continue
            content = msg.get("content") or ""
            if len(content) < 10:
                continue
            prev = matched_query_categories(content) - _RANKING_WEAK_DOMAINS
            if prev:
                found |= prev
                break
    return found - _RANKING_WEAK_DOMAINS


def query_targets_tool_domain(user_query: Optional[str]) -> bool:
    """آیا سوال کاربر به دامنهٔ داده/ابزار کسب‌وکار اشاره دارد (routing، نه پاسخ مدل)."""
    text = _normalize_query(_strip_leading_greeting(user_query))
    if not text or len(text) < 8:
        return False
    if _SIMPLE_PATTERNS.match(text):
        return False
    found = matched_query_categories(text)
    if found - _RANKING_WEAK_DOMAINS:
        return True
    # «امروز» به‌تنهایی (مثلاً آب‌وهوا) دامنهٔ ابزار نیست؛ بازهٔ تاریخ هست.
    if "query" in found and _STRONG_DATE_INTENT.search(text):
        return True
    return False


def query_expects_tool_use(
    user_query: Optional[str],
    history_messages: Optional[List[dict]] = None,
) -> bool:
    """آیا سوال برای پاسخ به ابزار/data وابسته است (بدون regex روی پاسخ مدل)."""
    effective_query = _strip_leading_greeting(user_query)
    if estimate_query_complexity(effective_query, history_messages) in (
        "medium",
        "complex",
    ):
        return True
    if query_targets_tool_domain(effective_query):
        return True
    q = effective_query.strip()
    # پیام‌های پیگیری کوتاه («انجامش بده») هم باید به context قبلی مراجعه کنند —
    # سقف بزرگ‌تر از تشخیص greeting/غیر-داده صرف تا follow-upهای کمی طولانی‌تر را هم بگیرد.
    if len(q) < 40 and history_messages:
        for msg in reversed(history_messages[-8:]):
            if msg.get("role") != "user":
                continue
            prior = (msg.get("content") or "").strip()
            if len(prior) < 8:
                continue
            if query_targets_tool_domain(prior):
                return True
            if estimate_query_complexity(prior) in ("medium", "complex"):
                return True
    return False


def iterations_for_query(
    user_query: Optional[str],
    history_messages: Optional[List[dict]] = None,
) -> int:
    """تعداد iteration پیشنهادی برای یک سوال."""
    complexity = estimate_query_complexity(user_query, history_messages)
    return QUERY_COMPLEXITY_ITERATIONS[complexity]


def detect_categories_from_history(
    user_query: Optional[str],
    history_messages: Optional[List[dict]] = None,
) -> Set[str]:
    """
    تشخیص دسته‌بندی با در نظر گرفتن تاریخچه مکالمه.
    اگر سوال فعلی مبهم یا کوتاه (پیگیری) باشد از پیام‌های قبلی استفاده می‌کند.
    """
    cats = detect_categories(user_query)
    q = (user_query or "").strip()
    default_generic = {"financial", "warehouse", "crm", "misc"}
    generic = not cats or cats == default_generic
    short_followup = len(q) < 40
    if not history_messages or (not generic and not short_followup):
        return cats

    for msg in reversed(history_messages[-8:]):
        if msg.get("role") != "user":
            continue
        content = msg.get("content") or ""
        if len(content) < 10:
            continue
        prev_cats = detect_categories(content)
        specific = prev_cats - {"misc", "financial"}
        if specific:
            cats |= specific
            break
    return cats


def merge_tool_allowlists(
    intent_names: Iterable[str],
    *,
    skill_names: Optional[AbstractSet[str]] = None,
    forced_names: Optional[AbstractSet[str]] = None,
) -> Set[str]:
    """اتحاد intent + مهارت + اجباری — مهارت نباید دامنه را حذف کند."""
    out = set(intent_names)
    if skill_names:
        out |= set(skill_names)
    if forced_names:
        out |= set(forced_names)
    return out


def select_catalog_tool_names(
    all_names: Iterable[str],
    user_query: Optional[str],
    *,
    max_tools: int = MAX_TOOLS_AUTONOMOUS,
    protected_names: Optional[AbstractSet[str]] = None,
    prefer_names: Optional[AbstractSet[str]] = None,
    history_messages: Optional[List[dict]] = None,
) -> Set[str]:
    """کاتالوگ کامل مجاز با سقف ایمنی ارائه‌دهنده.

    Ranking فقط روی مجموعهٔ امنیتی‌شده انجام می‌شود.
    protected هرگز به‌خاطر سقف حذف نمی‌شود، اما نمی‌تواند Tool غیرمجاز را برگرداند.
    """
    from app.services.ai.ai_tool_rank import rank_and_cap_tool_names
    from app.services.ai.ai_tool_security import filter_security_candidates

    available = filter_security_candidates(
        {n for n in all_names if n},
        user_query,
        history_messages=history_messages,
        unknown_policy="allow",
    )
    return rank_and_cap_tool_names(
        available,
        user_query,
        max_tools=max_tools,
        core_names=_CORE_TOOL_NAMES,
        prefer_names=prefer_names,
        protected_names=protected_names,
        intent_domains=ranking_intent_domains(user_query, history_messages),
    )


def select_tool_names(
    all_names: Iterable[str],
    user_query: Optional[str],
    *,
    max_tools: int = MAX_TOOLS_PER_REQUEST,
    history_messages: Optional[List[dict]] = None,
    prefer_names: Optional[AbstractSet[str]] = None,
    protected_names: Optional[AbstractSet[str]] = None,
) -> Set[str]:
    """
    زیرمجموعهٔ نام functionها برای ارسال به مدل.

    Security filter قبل از Ranking اعمال می‌شود؛ امتیاز keyword امنیت را دور نمی‌زند.
    """
    from app.services.ai.ai_tool_rank import rank_and_cap_tool_names
    from app.services.ai.ai_tool_security import filter_security_candidates

    available = filter_security_candidates(
        {n for n in all_names if n},
        user_query,
        history_messages=history_messages,
        unknown_policy="allow",
    )
    cats = ranking_intent_domains(user_query, history_messages)
    prefer: Set[str] = set(prefer_names or ()) & available
    if _WRITE_KEYWORDS.search(user_query or ""):
        for name in _WRITE_TOOLS & available:
            prefer |= set(_WRITE_TOOL_COMPANIONS.get(name, ()))
        prefer &= available
    if _PEOPLE_KEYWORDS.search(user_query or ""):
        prefer |= _CATEGORY_TOOLS.get("people", frozenset()) & available

    # Core وارد استخر می‌شود اما ظرفیت Top-K را reserve نمی‌کند.
    return rank_and_cap_tool_names(
        available,
        user_query,
        max_tools=max_tools,
        core_names=_CORE_TOOL_NAMES,
        prefer_names=prefer,
        protected_names=protected_names,
        intent_domains=cats,
    )


def filter_function_definitions(
    definitions: List[dict],
    allowed_names: Union[AbstractSet[str], Sequence[str]],
) -> List[dict]:
    """فقط تعاریف داخل allowed_names. مجموعهٔ خالی = هیچ Tool (fail-closed).

    اگر allowed_names دنباله باشد، ترتیب Discovery حفظ می‌شود.
    """
    if not allowed_names:
        return []
    if isinstance(allowed_names, (set, frozenset)):
        allowed = {n for n in allowed_names if n}
        if not allowed:
            return []
        return [
            d
            for d in definitions
            if (d.get("function") or {}).get("name") in allowed
        ]
    ordered = [n for n in allowed_names if n]
    allowed = set(ordered)
    if not allowed:
        return []
    by_name = {}
    for d in definitions:
        fn = (d.get("function") or {}).get("name")
        if fn and fn in allowed and fn not in by_name:
            by_name[fn] = d
    return [by_name[n] for n in ordered if n in by_name]
