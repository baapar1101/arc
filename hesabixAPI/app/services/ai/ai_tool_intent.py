"""
انتخاب زیرمجموعهٔ ابزارها بر اساس intent متن کاربر (بدون API دوم).
"""
from __future__ import annotations

import re
from typing import AbstractSet, Iterable, List, Optional, Set

from app.services.ai.ai_constants import MAX_TOOLS_PER_REQUEST

# همیشه در دسترس (پرس‌وجو و دادهٔ پایه)
_CORE_TOOL_NAMES: frozenset[str] = frozenset({
    "query_business_data",
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
    }),
    "customer_club": frozenset({
        "get_customer_club_settings",
        "list_customer_club_tiers",
        "list_customer_club_ledger",
        "get_customer_club_rfm_summary",
        "search_customer_club_rfm_persons",
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
    }),
    "misc": frozenset({
        "get_quick_sales_settings",
        "list_price_lists",
        "search_activity_logs",
        "list_workflows",
        "list_workflow_executions",
        "search_repair_orders",
        "get_repair_order_details",
        "list_distribution_routes",
        "search_warranty_codes",
        "list_petty_cash",
        "get_person_transactions",
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
]

_WRITE_KEYWORDS = re.compile(
    r"ثبت|ایجاد|بساز|بزن|ویرایش|حذف|create|update|add\s+invoice|new\s+invoice",
    re.IGNORECASE,
)

_WRITE_TOOLS = frozenset({
    "create_invoice",
    "create_person",
    "update_person",
    "create_receipt_payment",
})


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


def select_tool_names(
    all_names: Iterable[str],
    user_query: Optional[str],
    *,
    max_tools: int = MAX_TOOLS_PER_REQUEST,
) -> Set[str]:
    """
    زیرمجموعهٔ نام functionها برای ارسال به مدل.
    """
    available = set(all_names)
    selected: Set[str] = set(_CORE_TOOL_NAMES) & available

    for cat in detect_categories(user_query):
        selected |= _CATEGORY_TOOLS.get(cat, frozenset()) & available

    if _WRITE_KEYWORDS.search(user_query or ""):
        selected |= _WRITE_TOOLS & available

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
