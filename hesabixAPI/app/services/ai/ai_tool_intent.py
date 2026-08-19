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
    "resolve_date_range",
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
        "create_receipt_payment",
        "create_expense_income",
        "update_expense_income",
        "delete_expense_income",
        "update_receipt_payment",
        "delete_receipt_payment",
        "update_invoice",
        "delete_invoice",
        "list_accounts",
        "get_account",
        "get_wallet_overview",
        "list_wallet_transactions",
        "list_payment_gateways",
        "list_currencies",
        "list_currency_rates",
        "resolve_currency_rate",
        "list_loan_facilities",
        "get_loan_facility",
        "get_document_numbering_settings",
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
        "list_warehouse_locations",
        "list_warehouse_placements",
        "get_warehouse_report",
        "create_warehouse_document",
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
    "agent": frozenset({
        "create_session_plan",
        "list_session_todos",
        "update_session_todo",
        "spawn_subagent",
        "await_subagent",
        "cancel_subagent",
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
        "list_product_attributes",
        "get_product_attribute",
        "search_product_instances",
        "list_price_lists",
        "list_price_list_items",
        "list_currencies",
    }),
    "query": frozenset({
        "query_business_data",
        "list_queryable_fields",
        "resolve_date_range",
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
    "hscript": frozenset({
        "hscript_search_docs",
        "hscript_retrieve_docs",
        "hscript_read_doc",
        "hscript_validate_script",
        "hscript_language_guide",
        "hscript_run_preview",
        "hscript_fix_script",
    }),
    "memory": frozenset({
        "read_memory",
        "upsert_memory_entry",
        "delete_memory_entry",
    }),
}

MEMORY_TOOL_NAMES = _CATEGORY_TOOLS["memory"]

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
    (r"شخص|مشتری|تامین|تأمین|supplier|customer|people|گروه\s*اشخاص", "people"),
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
    "update_expense_income",
    "update_receipt_payment",
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
    "create_account",
    "update_account",
    "delete_account",
    "create_warehouse_document",
})

# ابزارهای کمکی که مدل برای تکمیل آرگومان write نیاز دارد — prefer تا سقف ۴۸ حذف‌شان نکند
_WRITE_TOOL_COMPANIONS: dict[str, frozenset[str]] = {
    "create_invoice": frozenset({
        "search_persons",
        "search_products",
        "get_product_info",
        "list_currencies",
        "list_warehouses",
        "get_current_fiscal_year",
        "list_bank_accounts",
        "list_cash_registers",
        "list_petty_cash",
        "list_accounts",
        "search_projects",
        "search_checks",
        "get_tax_settings",
    }),
    "update_invoice": frozenset({
        "search_invoices",
        "get_invoice_details",
        "search_persons",
        "search_products",
        "list_currencies",
        "list_warehouses",
        "list_bank_accounts",
        "list_cash_registers",
        "list_petty_cash",
        "list_accounts",
        "search_projects",
        "search_checks",
    }),
    "create_receipt_payment": frozenset({
        "search_persons",
        "list_currencies",
        "list_bank_accounts",
        "list_cash_registers",
        "list_petty_cash",
        "search_checks",
        "search_projects",
        "search_invoices",
        "search_receipts_payments",
    }),
    "update_receipt_payment": frozenset({
        "search_receipts_payments",
        "search_persons",
        "list_currencies",
        "list_bank_accounts",
        "list_cash_registers",
        "list_petty_cash",
        "search_checks",
        "search_projects",
        "search_invoices",
    }),
    "create_check": frozenset({
        "search_persons",
        "list_currencies",
        "search_checks",
        "get_check_details",
    }),
    "create_product": frozenset({
        "search_products",
        "search_categories",
        "list_warehouses",
        "list_product_attributes",
        "list_currencies",
        "search_persons",
        "get_tax_settings",
        "get_current_fiscal_year",
        "list_price_lists",
        "list_price_list_items",
    }),
    "update_product": frozenset({
        "search_products",
        "get_product_info",
        "search_categories",
        "list_warehouses",
        "list_product_attributes",
        "list_currencies",
        "search_persons",
        "get_tax_settings",
        "get_current_fiscal_year",
        "list_price_lists",
        "list_price_list_items",
    }),
    "create_expense_income": frozenset({
        "list_accounts",
        "list_currencies",
        "search_persons",
        "list_bank_accounts",
        "list_cash_registers",
        "list_petty_cash",
        "search_checks",
        "search_projects",
        "search_expense_income",
    }),
    "update_expense_income": frozenset({
        "search_expense_income",
        "list_accounts",
        "list_currencies",
        "search_persons",
        "list_bank_accounts",
        "list_cash_registers",
        "list_petty_cash",
        "search_checks",
        "search_projects",
    }),
    "create_transfer": frozenset({
        "list_currencies",
        "list_bank_accounts",
        "list_cash_registers",
        "list_petty_cash",
        "search_transfers",
    }),
    "create_lead": frozenset({
        "search_leads",
        "get_pipeline_report",
    }),
    "create_person": frozenset({
        "search_persons",
        "list_person_groups",
    }),
    "create_warehouse_document": frozenset({
        "list_warehouses",
        "search_products",
        "search_warehouse_documents",
        "get_inventory_status",
        "get_current_fiscal_year",
    }),
    "create_workflow": frozenset({
        "list_workflows",
        "get_workflow_design_rules",
        "list_workflow_trigger_catalog",
        "list_workflow_action_catalog",
        "validate_workflow_draft",
    }),
    "update_workflow": frozenset({
        "get_workflow",
        "get_workflow_design_rules",
        "validate_workflow_draft",
        "list_workflows",
    }),
    "execute_workflow": frozenset({
        "list_workflows",
        "get_workflow",
    }),
    "create_account": frozenset({
        "list_accounts",
        "get_account",
    }),
}

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

    categories = detect_categories(q)
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


def query_targets_tool_domain(user_query: Optional[str]) -> bool:
    """آیا سوال کاربر به دامنهٔ داده/ابزار کسب‌وکار اشاره دارد (routing، نه پاسخ مدل)."""
    text = _normalize_query(_strip_leading_greeting(user_query))
    if not text or len(text) < 8:
        return False
    if _SIMPLE_PATTERNS.match(text):
        return False
    for pattern, _category in _KEYWORD_CATEGORIES:
        if re.search(pattern, text, re.IGNORECASE):
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


def select_tool_names(
    all_names: Iterable[str],
    user_query: Optional[str],
    *,
    max_tools: int = MAX_TOOLS_PER_REQUEST,
    history_messages: Optional[List[dict]] = None,
    prefer_names: Optional[AbstractSet[str]] = None,
) -> Set[str]:
    """
    زیرمجموعهٔ نام functionها برای ارسال به مدل.
    """
    from app.services.ai.ai_tool_rank import rank_and_cap_tool_names

    available = set(all_names)
    selected: Set[str] = set(_CORE_TOOL_NAMES) & available

    cats = detect_categories_from_history(user_query, history_messages)
    for cat in cats:
        selected |= _CATEGORY_TOOLS.get(cat, frozenset()) & available

    if _WRITE_KEYWORDS.search(user_query or ""):
        selected |= _WRITE_TOOLS & available

    if _PEOPLE_KEYWORDS.search(user_query or ""):
        selected |= _CATEGORY_TOOLS.get("people", frozenset()) & available

    if prefer_names:
        selected |= set(prefer_names) & available

    companions: Set[str] = set()
    for name in list(selected):
        companions |= _WRITE_TOOL_COMPANIONS.get(name, frozenset())
    companions &= available
    selected |= companions
    effective_prefer: Set[str] = set(prefer_names or ()) | companions

    # اگر هنوز کم است، ابزارهای پرکاربرد اضافه
    if len(selected) < 12:
        for cat in ("financial", "warehouse", "crm"):
            selected |= _CATEGORY_TOOLS.get(cat, frozenset()) & available

    return rank_and_cap_tool_names(
        selected,
        user_query,
        max_tools=max_tools,
        core_names=_CORE_TOOL_NAMES,
        prefer_names=effective_prefer,
    )


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
