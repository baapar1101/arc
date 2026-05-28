"""
انتخاب زیرمجموعهٔ ابزارها بر اساس intent متن کاربر (بدون API دوم).
همچنین تخمین پیچیدگی سوال برای تنظیم تعداد iteration.
"""
from __future__ import annotations

import re
from typing import AbstractSet, Iterable, List, Optional, Set

from app.services.ai.ai_constants import MAX_TOOLS_PER_REQUEST, QUERY_COMPLEXITY_ITERATIONS

# همیشه در دسترس (پرس‌وجو و دادهٔ پایه)
_CORE_TOOL_NAMES: frozenset[str] = frozenset({
    "query_business_data",
    "list_queryable_fields",
    "get_business_info",
    "get_business_dashboard",
    "search_persons",
    "get_person_balance",
    "get_financial_summary",
    "search_invoices",
    "get_invoice_details",
    "search_products",
    "get_product_info",
})

# دسته → ابزارها
_CATEGORY_TOOLS: dict[str, frozenset[str]] = {
    "financial": frozenset({
        "search_invoices",
        "get_invoice_details",
        "get_invoices_count",
        "search_receipts_payments",
        "get_sales_report",
        "get_purchase_report",
        "get_debtors_report",
        "get_creditors_report",
        "get_cash_flow",
        "search_documents",
        "get_document_details",
        "list_bank_accounts",
        "list_cash_registers",
        "list_fiscal_years",
        "get_current_fiscal_year",
        "get_opening_balance",
        "get_business_credit_settings",
        "list_credit_installment_plans",
        "get_person_credit",
        "search_checks",
        "get_check_details",
        "search_transfers",
        "search_expense_income",
        "create_expense_income",
        "update_invoice",
        "delete_invoice",
    }),
    "warehouse": frozenset({
        "search_warehouse_documents",
        "get_warehouse_document_details",
        "list_warehouses",
        "get_warehouse_stock_summary",
        "get_inventory_status",
        "get_product_kardex",
        "get_inventory_valuation",
        "search_production_documents",
        "list_boms",
        "get_bom_details",
    }),
    "crm": frozenset({
        "search_leads",
        "get_lead_details",
        "search_deals",
        "get_deal_details",
        "search_activities",
        "get_crm_summary",
        "get_pipeline_report",
        "get_lead_funnel_report",
        "create_lead",
    }),
    "customer_club": frozenset({
        "get_customer_club_settings",
        "list_customer_club_tiers",
        "list_customer_club_ledger",
        "get_customer_club_rfm_summary",
        "search_customer_club_rfm_persons",
        "adjust_customer_club_points",
        "recalculate_customer_club_rfm",
        "update_customer_club_settings",
    }),
    "tax": frozenset({
        "get_tax_settings",
        "search_tax_workspace",
        "get_tax_data_quality",
    }),
    "projects": frozenset({
        "search_projects",
        "get_project_summary",
    }),
    "integration": frozenset({
        "invoke_business_connector",
        "list_woocommerce_orders",
        "list_woocommerce_products",
        "list_basalam_synced_invoices",
        "list_basalam_product_conflicts",
        "get_basalam_overview",
        "list_basalam_dead_letter",
    }),
    "workflow": frozenset({
        "list_workflow_trigger_catalog",
        "list_workflow_action_catalog",
        "list_workflow_builtin_nodes",
        "get_workflow_component_schema",
        "get_workflow_design_rules",
        "validate_workflow_draft",
        "get_workflow",
        "create_workflow",
        "update_workflow",
        "delete_workflow",
        "test_workflow",
        "get_workflow_execution_debug",
        "poll_workflow_execution",
        "list_workflows",
        "list_workflow_executions",
        "execute_workflow",
    }),
    "misc": frozenset({
        "get_quick_sales_settings",
        "list_price_lists",
        "search_activity_logs",
        "search_repair_orders",
        "get_repair_order_details",
        "list_distribution_routes",
        "search_warranty_codes",
        "list_petty_cash",
        "get_person_transactions",
    }),
    "people": frozenset({
        "search_persons",
        "get_customer_info",
        "get_person_balance",
        "get_person_transactions",
        "create_person",
        "update_person",
        "delete_person",
        "list_person_groups",
    }),
    "products_write": frozenset({
        "search_products",
        "get_product_info",
        "create_product",
        "update_product",
        "search_categories",
    }),
    "query": frozenset({
        "query_business_data",
        "list_queryable_fields",
        "batch_query_business_data",
        "search_invoices",
        "search_persons",
        "search_products",
        "search_checks",
        "search_transfers",
        "search_expense_income",
        "search_documents",
        "search_receipts_payments",
        "search_warehouse_documents",
    }),
    "reports_meta": frozenset({
        "get_report",
        "list_available_reports",
        "batch_query_business_data",
        "export_business_data",
        "get_debtors_report",
        "get_creditors_report",
        "get_sales_report",
        "get_purchase_report",
        "get_inventory_valuation",
        "get_cash_flow",
    }),
    "report_templates": frozenset({
        "list_report_templates",
        "get_report_template",
        "get_report_template_scope_catalog",
        "set_default_report_template",
        "publish_report_template",
    }),
    "marketplace": frozenset({
        "list_marketplace_plugins",
        "list_business_plugins",
    }),
}

# کلیدواژهٔ فارسی/انگلیسی → دسته
_KEYWORD_CATEGORIES: List[tuple[str, str]] = [
    (r"فاکتور|invoice|فروش|خرید|دریافت|پرداخت|چک|انتقال|سند|حساب|بانک|صندوق|سال\s*مال|تراز|افتتاح|اقساط|اعتبار|credit|receipt|payment", "financial"),
    (r"انبار|موجودی|حواله|warehouse|stock|کاردکس|bom|تولید|production", "warehouse"),
    (r"سرنخ|lead|معامله|deal|crm|قیف|pipeline|فعالیت\s*crm", "crm"),
    (r"باشگاه|امتیاز|rfm|مشتری\s*وفادار|customer\s*club", "customer_club"),
    (r"مالیات|مودیان|tax|کارپوشه", "tax"),
    (r"پروژه|project", "projects"),
    (r"ووکامرس|woocommerce|باسلام|basalam|کانکتور|connector|یکپارچه", "integration"),
    (r"فروش\s*سریع|quick\s*sales|لیست\s*قیمت|price\s*list|لاگ|فعالیت\s*سیستم|workflow|تعمیر|گارانتی|توزیع|صندوق\s*خرد", "misc"),
    (r"شخص|مشتری|تامین|تأمین|supplier|customer|people|گروه\s*اشخاص", "people"),
    (r"دسته\s*بندی|category|ویژگی\s*کالا|attribute", "products_write"),
    (r"فیلتر\s*پیشرفته|عملگر|بزرگتر\s*از|کمتر\s*از|شامل|list_queryable|query_business", "query"),
    (r"گزارش\s*یکپارچه|get_report|batch_query|list_available_reports", "reports_meta"),
    (r"خروجی|export|اکسل|excel|دانلود\s*لیست", "reports_meta"),
    (r"تراز\s*آزمایشی|دفتر\s*کل|دفتر\s*روزنامه|سود\s*و\s*زیان|مرور\s*حساب|trial\s*balance|ledger", "reports_meta"),
    (r"قالب\s*گزارش|قالب\s*فاکتور|قالب\s*چاپ|report\s*template", "report_templates"),
    (r"بازار\s*افزونه|افزونه\s*فعال|plugin\s*marketplace|marketplace", "marketplace"),
    (r"dead\s*letter|صف\s*خطا|خلاصه\s*باسلام", "integration"),
    (r"هزینه|درآمد|expense|income", "financial"),
    (r"اتوماسیون|automation|workflow|گردش\s*کار|اجرای\s*workflow|تریگر\s*workflow", "workflow"),
]

_WRITE_KEYWORDS = re.compile(
    r"ثبت|ایجاد|اضافه|بساز|بزن|ویرایش|حذف|create|update|add|new\s+invoice|مشتری\s+جدید|کالای\s+جدید",
    re.IGNORECASE,
)

_WRITE_TOOLS = frozenset({
    "create_invoice",
    "create_person",
    "update_person",
    "create_receipt_payment",
    "delete_person",
    "create_product",
    "update_product",
    "create_check",
    "create_transfer",
    "create_expense_income",
    "update_invoice",
    "delete_invoice",
    "create_lead",
    "execute_workflow",
    "create_workflow",
    "update_workflow",
    "delete_workflow",
    "export_business_data",
    "set_default_report_template",
    "publish_report_template",
    "adjust_customer_club_points",
    "recalculate_customer_club_rfm",
    "update_customer_club_settings",
})

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
_KNOWLEDGE_HINTS = re.compile(
    r"دانشنامه|قوانین|سیاست|رویه|دستورالعمل|راهنما|مقررات|فرآیند|فرایند|"
    r"documentation|policy|procedure|how\s+to",
    re.IGNORECASE,
)


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


def detect_categories(user_query: Optional[str]) -> Set[str]:
    text = _normalize_query(user_query)
    if not text:
        return set(_CATEGORY_TOOLS.keys())
    found: Set[str] = set()
    for pattern, category in _KEYWORD_CATEGORIES:
        if re.search(pattern, text, re.IGNORECASE):
            found.add(category)
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


def estimate_query_complexity(
    user_query: Optional[str],
    history_messages: Optional[List[dict]] = None,
) -> str:
    """
    تخمین پیچیدگی سوال: simple / medium / complex.
    از تاریخچه مکالمه برای بافت چندوجهی استفاده می‌کند.
    """
    q = (user_query or "").strip()
    if not q:
        return "simple"

    # سوال بسیار کوتاه یا خوش‌و‌بش
    if len(q) < 15 or _SIMPLE_PATTERNS.match(q):
        return "simple"

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
        if _MEDIUM_PATTERNS.search(q):
            return "complex"

    if _MEDIUM_PATTERNS.search(q) or len(q) > 60:
        return "medium"

    return "simple"


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
    اگر سوال فعلی مبهم باشد از پیام‌های قبلی استفاده می‌کند.
    """
    cats = detect_categories(user_query)
    if cats and "financial" not in cats | {"misc"}:
        return cats

    # اگر نتیجه عمومی بود، از آخرین پیام‌های کاربر کمک بگیر
    if history_messages:
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


def select_tool_names(
    all_names: Iterable[str],
    user_query: Optional[str],
    *,
    max_tools: int = MAX_TOOLS_PER_REQUEST,
    history_messages: Optional[List[dict]] = None,
) -> Set[str]:
    """
    زیرمجموعهٔ نام functionها برای ارسال به مدل.
    """
    available = set(all_names)
    selected: Set[str] = set(_CORE_TOOL_NAMES) & available

    cats = detect_categories_from_history(user_query, history_messages)
    for cat in cats:
        selected |= _CATEGORY_TOOLS.get(cat, frozenset()) & available

    if _WRITE_KEYWORDS.search(user_query or ""):
        selected |= _WRITE_TOOLS & available

    if _PEOPLE_KEYWORDS.search(user_query or ""):
        selected |= _CATEGORY_TOOLS.get("people", frozenset()) & available

    # اگر هنوز کم است، ابزارهای پرکاربرد اضافه
    if len(selected) < 12:
        for cat in ("financial", "warehouse", "crm"):
            selected |= _CATEGORY_TOOLS.get(cat, frozenset()) & available

    if len(selected) > max_tools:
        # اولویت: core + دسته‌های تشخیص‌داده‌شده
        ordered: List[str] = []
        for name in sorted(selected):
            if name in _CORE_TOOL_NAMES:
                ordered.append(name)
        for cat in detect_categories(user_query):
            for name in sorted(_CATEGORY_TOOLS.get(cat, frozenset())):
                if name in selected and name not in ordered:
                    ordered.append(name)
        for name in sorted(selected):
            if name not in ordered:
                ordered.append(name)
        selected = set(ordered[:max_tools])

    return selected


def filter_function_definitions(
    definitions: List[dict],
    allowed_names: AbstractSet[str],
) -> List[dict]:
    if not allowed_names:
        return definitions
    out: List[dict] = []
    for d in definitions:
        fn = (d.get("function") or {}).get("name")
        if fn and fn in allowed_names:
            out.append(d)
    return out
