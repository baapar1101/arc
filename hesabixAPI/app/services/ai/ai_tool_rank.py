"""رتبه‌بندی واژه‌ای ابزارها هنگام سقف MAX_TOOLS_PER_REQUEST (TOOL-01).

بدون API دوم / embedding: نام ابزار + نام مستعار فارسی/انگلیسی در برابر متن سوال.
"""
from __future__ import annotations

import re
from typing import AbstractSet, Iterable, Optional, Set

_TOKEN = re.compile(r"[\w\u0600-\u06FF]+", re.UNICODE)

# نام مستعار پربسامد — فقط برای ranking/truncation، نه جایگزینی دسته.
TOOL_ALIASES: dict[str, tuple[str, ...]] = {
    "search_invoices": ("فاکتور", "invoice", "فروش"),
    "get_invoice_details": ("جزئیات فاکتور", "فاکتور"),
    "get_invoices_count": ("تعداد فاکتور", "چند فاکتور"),
    "get_sales_report": ("گزارش فروش", "فروش", "sales"),
    "get_purchase_report": ("گزارش خرید", "خرید"),
    "get_debtors_report": ("بدهکار", "بدهکاران", "debtor"),
    "get_creditors_report": ("بستانکار", "بستانکاران", "creditor"),
    "get_cash_flow": ("جریان نقد", "نقدینگی", "cash flow"),
    "get_financial_summary": ("خلاصه مالی", "وضعیت مالی"),
    "search_receipts_payments": ("دریافت", "پرداخت", "receipt", "payment"),
    "get_inventory_status": ("موجودی", "انبار", "stock"),
    "get_product_kardex": ("کاردکس", "kardex"),
    "get_warehouse_stock_summary": ("خلاصه موجودی", "انبار"),
    "get_inventory_valuation": ("ارزش موجودی", "ریالی انبار"),
    "search_products": ("کالا", "محصول", "product"),
    "get_product_info": ("کالا", "محصول"),
    "create_product": (
        "کالای جدید",
        "کالا جدید",
        "محصول جدید",
        "خدمت جدید",
        "اضافه کردن کالا",
        "تعریف کالا",
    ),
    "update_product": (
        "ویرایش کالا",
        "ویرایش محصول",
        "اصلاح کالا",
        "قیمت کالا",
    ),
    "search_persons": ("مشتری", "شخص", "تامین"),
    "create_person": ("مشتری جدید", "شخص جدید", "اضافه کردن مشتری"),
    "create_invoice": ("فاکتور جدید", "ثبت فاکتور", "بزن فاکتور"),
    "update_invoice": ("ویرایش فاکتور", "اصلاح فاکتور"),
    "list_currencies": ("ارز", "currency", "واحد پول"),
    "list_price_lists": ("لیست قیمت", "قیمت عمده", "price list"),
    "list_price_list_items": ("قیمت لیست", "قیمت عمده"),
    "list_warehouses": ("انبار", "warehouse"),
    "create_warehouse_document": ("حواله", "حواله انبار", "ورود انبار", "خروج انبار"),
    "create_check": ("چک", "چک دریافتی", "چک پرداختی"),
    "create_transfer": ("انتقال وجه", "انتقال بین حساب"),
    "create_receipt_payment": (
        "دریافت",
        "پرداخت",
        "ثبت دریافت",
        "ثبت پرداخت",
        "سند دریافت",
        "سند پرداخت",
    ),
    "update_receipt_payment": ("ویرایش دریافت", "ویرایش پرداخت", "اصلاح دریافت"),
    "create_expense_income": (
        "هزینه",
        "درآمد",
        "ثبت هزینه",
        "ثبت درآمد",
        "سند هزینه",
        "سند درآمد",
    ),
    "update_expense_income": ("ویرایش هزینه", "ویرایش درآمد", "اصلاح هزینه"),
    "create_workflow": ("اتوماسیون", "گردش کار جدید", "workflow جدید"),
    "get_current_fiscal_year": ("سال مالی", "fiscal"),
    "search_leads": ("سرنخ", "lead"),
    "search_deals": ("معامله", "فرصت", "deal"),
    "get_crm_summary": ("خلاصه crm", "crm"),
    "get_customer_club_settings": ("باشگاه", "امتیاز", "وفادار"),
    "list_customer_club_ledger": ("دفتر امتیاز", "باشگاه"),
    "get_customer_club_rfm_summary": ("rfm", "باشگاه"),
    "get_basalam_overview": ("باسلام", "basalam", "خلاصه باسلام"),
    "list_basalam_dead_letter": ("صف خطا", "dead letter", "باسلام"),
    "list_basalam_synced_invoices": ("سینک باسلام", "فاکتور باسلام"),
    "list_basalam_product_conflicts": ("تعارض باسلام", "conflict"),
    "list_woocommerce_orders": ("ووکامرس", "woocommerce", "سفارش ووکامرس"),
    "list_woocommerce_products": ("محصول ووکامرس", "woocommerce"),
    "list_workflows": ("اتوماسیون", "گردش کار", "workflow"),
    "list_workflow_executions": ("اجرای workflow", "اجرای اتوماسیون"),
    "get_tax_settings": ("مالیات", "مودیان", "tax"),
    "search_tax_workspace": ("کارپوشه", "مودیان"),
    "list_report_templates": ("قالب گزارش", "قالب فاکتور", "قالب چاپ"),
    "list_marketplace_plugins": ("بازار افزونه", "marketplace"),
    "list_business_plugins": ("افزونه فعال", "پلاگین"),
    "list_available_reports": ("لیست گزارش", "گزارش‌های موجود"),
    "get_report": ("گزارش یکپارچه", "get_report"),
    "get_wallet_overview": ("کیف پول", "wallet"),
    "list_wallet_transactions": ("تراکنش کیف پول", "wallet"),
    "list_accounts": ("سرفصل", "حساب کل", "coding"),
    "get_account": ("سرفصل", "حساب"),
    "list_payment_gateways": ("درگاه پرداخت", "gateway"),
    "hscript_search_docs": ("hscript", "اچ اسکریپت", "اسکریپت"),
    "hscript_language_guide": ("راهنمای hscript", "زبان اسکریپت"),
    "resolve_date_range": ("بازه تاریخ", "ماه گذشته", "تقویم"),
    "query_business_data": ("پرس‌وجو", "query"),
}


def tokenize_query(text: str) -> Set[str]:
    return {m.group(0).lower() for m in _TOKEN.finditer(text or "") if len(m.group(0)) >= 2}


def _name_tokens(tool_name: str) -> Set[str]:
    return {p for p in (tool_name or "").lower().replace("-", "_").split("_") if len(p) >= 2}


def score_tool_for_query(
    tool_name: str,
    user_query: str,
    *,
    prefer: bool = False,
) -> int:
    """امتیاز غیرمنفی؛ بالاتر = مرتبط‌تر با سوال."""
    q = (user_query or "").strip().lower()
    if not q or not tool_name:
        return 4 if prefer else 0
    score = 8 if prefer else 0
    q_tokens = tokenize_query(q)
    name_tokens = _name_tokens(tool_name)
    score += 2 * len(q_tokens & name_tokens)
    if tool_name.lower() in q:
        score += 6
    for alias in TOOL_ALIASES.get(tool_name, ()):
        alias_l = alias.lower()
        if not alias_l:
            continue
        if alias_l in q:
            score += 5 + min(len(alias_l), 12)
        alias_tokens = tokenize_query(alias_l)
        score += len(q_tokens & alias_tokens)
    return score


def rank_and_cap_tool_names(
    selected: Iterable[str],
    user_query: Optional[str],
    *,
    max_tools: int,
    core_names: AbstractSet[str],
    prefer_names: Optional[AbstractSet[str]] = None,
) -> Set[str]:
    """حفظ core و ابزار مهارت، سپس پر کردن سقف با بالاترین امتیاز واژه‌ای."""
    names = {n for n in selected if n}
    if len(names) <= max_tools:
        return names
    prefer = set(prefer_names or ()) & names
    query = user_query or ""

    def sort_key(n: str) -> tuple:
        return (
            0 if n in prefer else 1,
            0 if n in core_names else 1,
            -score_tool_for_query(n, query, prefer=n in prefer),
            n,
        )

    ordered = sorted(names, key=sort_key)
    return set(ordered[:max_tools])
