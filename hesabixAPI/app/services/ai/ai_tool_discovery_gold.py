"""Gold dataset for tool discovery retrieval eval (Phase 5).

Queries are realistic user language — not tool names. This file is the
contract for future discovery changes. No embeddings.
"""
from __future__ import annotations

from dataclasses import asdict, dataclass
from typing import Any, Dict, List, Optional, Sequence, Tuple

GOLD_DATASET_VERSION = "2026-08-19.v1"
TOOL_CATALOG_VERSION = "180.phase4"

INTENT_READ = "read"
INTENT_WRITE = "write"
INTENT_DELETE = "delete"
INTENT_EXPORT = "export"
INTENT_EXECUTE = "execute"
INTENT_NONE = "none"


@dataclass(frozen=True)
class GoldQuery:
    id: str
    query: str
    primary_expected_tools: Tuple[str, ...]
    acceptable_tools: Tuple[str, ...] = ()
    required_capability: str = ""
    intent: str = INTENT_READ
    category: str = ""
    difficulty: str = "easy"
    hard_case: str = ""
    no_match: bool = False
    history: Tuple[Dict[str, str], ...] = ()
    require_all_primary: bool = False
    source: str = "phase5"

    def to_dict(self) -> Dict[str, Any]:
        payload = asdict(self)
        payload["history"] = list(self.history)
        payload["primary_expected_tools"] = list(self.primary_expected_tools)
        payload["acceptable_tools"] = list(self.acceptable_tools)
        return payload

    def relevance_map(self) -> Dict[str, int]:
        rel: Dict[str, int] = {}
        for name in self.acceptable_tools:
            rel[name] = 1
        for name in self.primary_expected_tools:
            rel[name] = 2
        return rel

    def success_tools(self) -> Tuple[str, ...]:
        seen = []
        for name in self.primary_expected_tools + self.acceptable_tools:
            if name not in seen:
                seen.append(name)
        return tuple(seen)


def _g(
    qid: str,
    query: str,
    primary: Sequence[str],
    *,
    acceptable: Sequence[str] = (),
    capability: str = "",
    intent: str = INTENT_READ,
    category: str = "",
    difficulty: str = "easy",
    hard_case: str = "",
    no_match: bool = False,
    history: Sequence[Dict[str, str]] = (),
    require_all: bool = False,
    source: str = "phase5",
) -> GoldQuery:
    return GoldQuery(
        id=qid,
        query=query,
        primary_expected_tools=tuple(primary),
        acceptable_tools=tuple(t for t in acceptable if t not in set(primary)),
        required_capability=capability,
        intent=intent,
        category=category,
        difficulty=difficulty,
        hard_case=hard_case,
        no_match=no_match,
        history=tuple(history),
        require_all_primary=require_all,
        source=source,
    )


_LEGACY_CASES: Tuple[Tuple[str, Tuple[str, ...]], ...] = (
    ("گزارش فاکتور فروش ماه گذشته", ("search_invoices", "get_sales_report")),
    ("موجودی انبار و کاردکس کالا", ("get_inventory_status", "get_product_kardex")),
    ("سرنخ‌های این هفته را لیست کن", ("search_leads",)),
    ("امتیاز باشگاه مشتریان چقدر است", ("get_customer_club_settings",)),
    ("وضعیت سینک باسلام چطور است", ("get_basalam_overview",)),
    ("سفارش‌های ووکامرس را نشان بده", ("list_woocommerce_orders",)),
    ("گزارش بدهکاران", ("get_debtors_report",)),
    ("یک مشتری جدید به نام علی اضافه کن", ("create_person",)),
    ("یه شخص با نام علی اضافه کن و براش شماره کارت بانک مهر را بگذار", ("create_person",)),
    ("لیست گردش‌کارهای اتوماسیون", ("list_workflows",)),
    ("قالب چاپ فاکتور", ("list_report_templates",)),
    ("آیا افزونه باشگاه مشتریان فعال است", ("list_business_plugins",)),
    ("تنظیمات مالیات مودیان", ("get_tax_settings",)),
    ("لیست محصولات و کالاها", ("search_products",)),
    ("یک کالای جدید با بارکد و انبار پیش‌فرض اضافه کن", ("create_product",)),
    ("قیمت کالای پیچ را ویرایش کن", ("update_product",)),
    ("موجودی کیف پول کسب‌وکار", ("get_wallet_overview",)),
    ("سرفصل حساب‌های کل", ("list_accounts",)),
    ("یه فاکتور برای علی بزن", ("create_invoice", "list_currencies")),
    ("حواله ورود انبار بزن", ("create_warehouse_document", "list_warehouses")),
    ("یک چک دریافتی ثبت کن", ("create_check",)),
    ("اتوماسیون جدید بساز", ("create_workflow", "get_workflow_design_rules")),
)


def _legacy_gold() -> List[GoldQuery]:
    out: List[GoldQuery] = []
    for i, (query, required) in enumerate(_LEGACY_CASES, start=1):
        writes = {
            "create_person",
            "create_invoice",
            "create_product",
            "update_product",
            "create_warehouse_document",
            "create_check",
            "create_workflow",
        }
        intent = INTENT_WRITE if any(t in writes for t in required) else INTENT_READ
        out.append(
            _g(
                f"legacy-{i:02d}",
                query,
                required,
                capability="",
                intent=intent,
                category="legacy",
                difficulty="medium",
                source="legacy",
            )
        )
    return out


def _invoice_queries() -> List[GoldQuery]:
    rows: List[GoldQuery] = []
    reads = [
        ("فاکتورهای فروش این ماه را نشان بده", "easy", ""),
        ("لیست فاکتورهای علی رضایی را بیاور", "easy", ""),
        ("صورتحساب‌های خرید هفته پیش کجاست", "medium", "synonyms"),
        ("فاکتور شماره ۱۲۳ را پیدا کن", "easy", ""),
        ("فاکتورهای تسویه‌نشده این ماه", "medium", ""),
        ("invoice list for last month", "medium", "english"),
        ("فروش‌های ثبت‌شده امروز را لیست کن", "medium", "synonyms"),
        ("فاکتور علی را پیدا کن", "easy", ""),
        ("همه فاکتورهای برگشتی را نشان بده", "hard", "similar_tools"),
        ("صورتحساب فروش فروردین را باز کن", "medium", "persian_accounting"),
    ]
    for i, (q, diff, hard) in enumerate(reads, start=1):
        rows.append(
            _g(
                f"inv-search-{i:02d}",
                q,
                ("search_invoices",),
                acceptable=("get_invoice_details", "get_invoices_count", "query_business_data", "get_sales_report"),
                capability="financial.invoice",
                category="invoice",
                difficulty=diff,
                hard_case=hard,
            )
        )
    details = [
        ("فاکتور شماره ۱۲۳ را کامل نشان بده", "easy"),
        ("جزئیات فاکتور علی رضایی که هفته پیش ثبت شده را بیار", "medium"),
        ("اقلام و مالیات این فاکتور چیست؟", "medium"),
        ("فاکتور ۱۴۰۳-۱۲ را با ردیف‌ها باز کن", "medium"),
        ("جزئیات invoice 88 را بده", "medium"),
    ]
    for i, (q, diff) in enumerate(details, start=1):
        rows.append(
            _g(
                f"inv-detail-{i:02d}",
                q,
                ("get_invoice_details",),
                acceptable=("search_invoices", "query_business_data"),
                capability="financial.invoice",
                category="invoice",
                difficulty=diff,
            )
        )
    rows.extend([
        _g("inv-count-01", "چند فاکتور فروش این ماه ثبت شده؟", ("get_invoices_count",),
           acceptable=("search_invoices", "get_sales_report"), capability="financial.invoice",
           category="invoice", difficulty="easy"),
        _g("inv-create-01", "یه فاکتور فروش برای علی رضایی بزن", ("create_invoice",),
           acceptable=("search_persons", "search_products", "list_currencies"),
           capability="financial.invoice", intent=INTENT_WRITE, category="invoice", difficulty="easy"),
        _g("inv-create-02", "فاکتور خرید جدید برای تامین‌کننده میلاد ثبت کن", ("create_invoice",),
           acceptable=("search_persons", "search_products"),
           capability="financial.invoice", intent=INTENT_WRITE, category="invoice", difficulty="medium"),
        _g("inv-create-03", "بزن فاکتور خدمات پشتیبانی سازمانی برای رضا", ("create_invoice",),
           acceptable=("search_persons", "search_products", "list_currencies"),
           capability="financial.invoice", intent=INTENT_WRITE, category="invoice", difficulty="medium"),
        _g("inv-update-01", "مبلغ فاکتور ۱۲۳ را ویرایش کن", ("update_invoice",),
           acceptable=("get_invoice_details", "search_invoices"),
           capability="financial.invoice", intent=INTENT_WRITE, category="invoice", difficulty="easy"),
        _g("inv-update-02", "تخفیف فاکتور علی را اصلاح کن", ("update_invoice",),
           acceptable=("search_invoices", "get_invoice_details"),
           capability="financial.invoice", intent=INTENT_WRITE, category="invoice", difficulty="medium"),
        _g("inv-delete-01", "این فاکتور را حذف کن", ("delete_invoice",),
           acceptable=("search_invoices",),
           capability="financial.invoice", intent=INTENT_DELETE, category="invoice", difficulty="easy"),
        _g("inv-delete-02", "فاکتور شماره ۸۸ را پاک کن", ("delete_invoice",),
           acceptable=("search_invoices", "get_invoice_details"),
           capability="financial.invoice", intent=INTENT_DELETE, category="invoice", difficulty="medium"),
    ])
    persons = ("علی", "رضا محمدی", "زهرا احمدی", "شرکت پارس")
    for i, name in enumerate(persons, start=1):
        rows.append(
            _g(
                f"inv-person-{i:02d}",
                f"فاکتورهای {name} را نشان بده",
                ("search_invoices",),
                acceptable=("search_persons", "get_invoice_details"),
                capability="financial.invoice",
                category="invoice",
                difficulty="easy",
            )
        )
    return rows


def _report_queries() -> List[GoldQuery]:
    rows = [
        _g("rep-sales-01", "گزارش فروش بده", ("get_sales_report",),
           acceptable=("get_report", "search_invoices", "list_available_reports"),
           capability="reports.sales", category="reports", difficulty="easy"),
        _g("rep-sales-02", "فروش این ماه را گزارش کن", ("get_sales_report",),
           acceptable=("get_report", "get_invoices_count"),
           capability="reports.sales", category="sales", difficulty="easy"),
        _g("rep-sales-03", "میزان فروش ماهانه چقدر بوده؟", ("get_sales_report",),
           acceptable=("get_report", "get_financial_summary"),
           capability="reports.sales", category="sales", difficulty="medium"),
        _g("rep-sales-04", "sales report for this month", ("get_sales_report",),
           acceptable=("get_report",), capability="reports.sales",
           category="reports", difficulty="medium", hard_case="english"),
        _g("rep-sales-05", "خلاصه فروش خرداد را بده", ("get_sales_report",),
           acceptable=("get_report",), capability="reports.sales",
           category="reports", difficulty="medium", hard_case="persian_accounting"),
        _g("rep-buy-01", "گزارش خرید ماه گذشته", ("get_purchase_report",),
           acceptable=("get_report", "search_invoices"),
           capability="reports.purchases", category="purchase", difficulty="easy"),
        _g("rep-buy-02", "خرید این ماه چقدر بوده", ("get_purchase_report",),
           acceptable=("get_report",), capability="reports.purchases",
           category="purchase", difficulty="easy"),
        _g("rep-deb-01", "گزارش بدهکاران", ("get_debtors_report",),
           acceptable=("get_report",), capability="reports.receivables",
           category="reports", difficulty="easy"),
        _g("rep-deb-02", "لیست مشتریانی که بدهکارند", ("get_debtors_report",),
           acceptable=("search_persons", "get_person_balance"),
           capability="reports.receivables", category="customer", difficulty="medium"),
        _g("rep-deb-03", "سن بدهی بدهکاران را نشان بده", ("get_debtors_report",),
           acceptable=("get_report",), capability="reports.receivables",
           category="reports", difficulty="medium", hard_case="persian_accounting"),
        _g("rep-crd-01", "گزارش بستانکاران", ("get_creditors_report",),
           acceptable=("get_report",), capability="reports.payables",
           category="reports", difficulty="easy"),
        _g("rep-crd-02", "لیست بستانکاران", ("get_creditors_report",),
           acceptable=("get_report", "search_persons"),
           capability="reports.payables", category="reports", difficulty="easy"),
        _g("rep-fin-01", "خلاصه وضعیت مالی کسب‌وکار", ("get_financial_summary",),
           acceptable=("get_report", "get_business_dashboard"),
           capability="reports.financial", category="accounting", difficulty="medium"),
        _g("rep-cash-01", "گزارش جریان وجوه نقد", ("get_cash_flow",),
           acceptable=("get_report",), capability="reports.cashflow",
           category="accounting", difficulty="medium"),
        _g("rep-tb-01", "تراز آزمایشی فروردین", ("get_report",),
           acceptable=("list_available_reports", "list_accounts"),
           capability="reports.overview", category="accounting", difficulty="medium",
           hard_case="persian_accounting"),
        _g("rep-pl-01", "گزارش سود و زیان", ("get_report",),
           acceptable=("get_financial_summary", "list_available_reports"),
           capability="reports.overview", category="accounting", difficulty="easy"),
        _g("rep-bs-01", "ترازنامه بده", ("get_report",),
           acceptable=("get_financial_summary",), capability="reports.overview",
           category="accounting", difficulty="medium"),
        _g("rep-list-01", "چه گزارش‌هایی داری؟", ("list_available_reports",),
           acceptable=("get_report",), capability="reports.overview",
           category="reports", difficulty="easy"),
        _g("rep-dash-01", "داشبورد کسب‌وکار را نشان بده", ("get_business_dashboard",),
           acceptable=("get_financial_summary", "get_report"),
           capability="reports.overview", category="reports", difficulty="medium"),
        _g("rep-inv-01", "گزارش ارزش موجودی کالا", ("get_inventory_valuation",),
           acceptable=("get_inventory_status", "get_warehouse_report"),
           capability="reports.inventory", category="inventory", difficulty="medium"),
        _g("rep-wh-01", "گزارش انبار مرکزی", ("get_warehouse_report",),
           acceptable=("get_inventory_status", "list_warehouses"),
           capability="reports.inventory", category="inventory", difficulty="medium"),
        _g("rep-tpl-01", "قالب چاپ فاکتور", ("list_report_templates",),
           acceptable=("get_report_template",), capability="reports.templates",
           category="reports", difficulty="medium"),
    ]
    months = ("فروردین", "اردیبهشت", "خرداد", "تیر", "مرداد", "شهریور")
    for i, month in enumerate(months, start=1):
        rows.append(
            _g(
                f"rep-sales-m{i:02d}",
                f"گزارش فروش {month} را بده",
                ("get_sales_report",),
                acceptable=("get_report", "resolve_date_range"),
                capability="reports.sales",
                category="sales",
                difficulty="easy",
            )
        )
    return rows


def _people_queries() -> List[GoldQuery]:
    rows = [
        _g("ppl-01", "لیست مشتریان", ("search_persons",),
           acceptable=("query_business_data",), capability="people.person",
           category="customer", difficulty="easy"),
        _g("ppl-02", "مشتری علی رضایی را پیدا کن", ("search_persons",),
           acceptable=("get_customer_info",), capability="people.person",
           category="customer", difficulty="easy"),
        _g("ppl-03", "طرف حساب زهرا را باز کن", ("search_persons",),
           acceptable=("get_customer_info", "get_person_balance"),
           capability="people.person", category="customer", difficulty="medium",
           hard_case="synonyms"),
        _g("ppl-04", "کارت مشتری رضا محمدی", ("get_customer_info",),
           acceptable=("search_persons", "get_person_balance"),
           capability="people.person", category="customer", difficulty="medium"),
        _g("ppl-05", "مانده حساب علی چقدر است", ("get_person_balance",),
           acceptable=("search_persons", "get_customer_info"),
           capability="people.person", category="customer", difficulty="medium"),
        _g("ppl-06", "گردش حساب این شخص را نشان بده", ("get_person_transactions",),
           acceptable=("search_persons", "search_receipts_payments"),
           capability="financial.payment", category="customer", difficulty="hard",
           hard_case="ambiguous"),
        _g("ppl-07", "یک مشتری به نام نرگس اضافه کن", ("create_person",),
           acceptable=("list_person_groups",), capability="people.person",
           intent=INTENT_WRITE, category="customer", difficulty="easy"),
        _g("ppl-08", "شخص جدید تامین‌کننده سیمان ثبت کن", ("create_person",),
           acceptable=("list_person_groups",), capability="people.person",
           intent=INTENT_WRITE, category="customer", difficulty="medium"),
        _g("ppl-09", "این شخص را حذف کن", ("delete_person",),
           acceptable=("search_persons",), capability="people.person",
           intent=INTENT_DELETE, category="customer", difficulty="easy"),
        _g("ppl-10", "گروه اشخاص را لیست کن", ("list_person_groups",),
           acceptable=("search_persons",), capability="people.person",
           category="customer", difficulty="easy"),
        _g("ppl-11", "find customer named Ali", ("search_persons",),
           acceptable=("get_customer_info",), capability="people.person",
           category="customer", difficulty="medium", hard_case="english"),
        _g("ppl-12", "اعتبار این مشتری چقدر است", ("get_person_credit",),
           acceptable=("get_customer_info", "get_business_credit_settings"),
           capability="financial.credit", category="customer", difficulty="hard"),
    ]
    for i, name in enumerate(("مینا", "حسام", "شرکت نور"), start=1):
        rows.append(
            _g(
                f"ppl-var-{i:02d}",
                f"مشتری {name} را پیدا کن",
                ("search_persons",),
                acceptable=("get_customer_info",),
                capability="people.person",
                category="customer",
                difficulty="easy",
            )
        )
    return rows


def _inventory_queries() -> List[GoldQuery]:
    return [
        _g("invt-01", "لیست محصولات و کالاها", ("search_products",),
           acceptable=("query_business_data",), capability="inventory.product",
           category="inventory", difficulty="easy"),
        _g("invt-02", "کالای پیچ را پیدا کن", ("search_products",),
           acceptable=("get_product_info",), capability="inventory.product",
           category="inventory", difficulty="easy"),
        _g("invt-03", "موجودی انبار چقدر است", ("get_inventory_status",),
           acceptable=("get_warehouse_stock_summary", "get_product_kardex"),
           capability="inventory.stock", category="inventory", difficulty="easy"),
        _g("invt-04", "کالاهای کم‌موجود را نشان بده", ("get_inventory_status",),
           acceptable=("get_warehouse_stock_summary",), capability="inventory.stock",
           category="inventory", difficulty="medium"),
        _g("invt-05", "کاردکس کالای پیچ", ("get_product_kardex",),
           acceptable=("get_inventory_status", "get_product_info"),
           capability="inventory.stock", category="inventory", difficulty="easy"),
        _g("invt-06", "اطلاعات کالای روغن را بده", ("get_product_info",),
           acceptable=("search_products",), capability="inventory.product",
           category="inventory", difficulty="easy"),
        _g("invt-07", "یک کالای جدید با بارکد اضافه کن", ("create_product",),
           acceptable=("search_categories", "list_warehouses"),
           capability="inventory.product", intent=INTENT_WRITE, category="inventory",
           difficulty="easy"),
        _g("invt-08", "قیمت کالای پیچ را ویرایش کن", ("update_product",),
           acceptable=("search_products", "get_product_info"),
           capability="inventory.product", intent=INTENT_WRITE, category="inventory",
           difficulty="easy"),
        _g("invt-09", "لیست انبارها", ("list_warehouses",),
           acceptable=("get_warehouse_stock_summary",), capability="inventory.warehouse",
           category="inventory", difficulty="easy"),
        _g("invt-10", "حواله ورود انبار بزن", ("create_warehouse_document",),
           acceptable=("list_warehouses", "search_products"),
           capability="inventory.warehouse", intent=INTENT_WRITE, category="inventory",
           difficulty="medium"),
        _g("invt-11", "اسناد انبار این هفته را نشان بده", ("search_warehouse_documents",),
           acceptable=("get_warehouse_document_details",), capability="inventory.warehouse",
           category="inventory", difficulty="medium"),
        _g("invt-12", "جزئیات حواله انبار ۱۲ را باز کن", ("get_warehouse_document_details",),
           acceptable=("search_warehouse_documents",), capability="inventory.warehouse",
           category="inventory", difficulty="medium"),
        _g("invt-13", "صورت مواد این محصول چیست", ("get_bom_details",),
           acceptable=("list_boms", "get_product_info"), capability="inventory.bom",
           category="inventory", difficulty="hard"),
        _g("invt-14", "لیست BOMها", ("list_boms",),
           acceptable=("get_bom_details",), capability="inventory.bom",
           category="inventory", difficulty="medium"),
        _g("invt-15", "اسناد تولید را لیست کن", ("search_production_documents",),
           acceptable=("search_warehouse_documents",), capability="inventory.production",
           category="inventory", difficulty="hard"),
        _g("invt-16", "دسته‌بندی کالاها", ("search_categories",),
           acceptable=("search_products",), capability="inventory.product",
           category="inventory", difficulty="easy"),
        _g("invt-17", "لیست قیمت عمده", ("list_price_lists",),
           acceptable=("list_price_list_items",), capability="inventory.product",
           category="inventory", difficulty="medium"),
        _g("invt-18", "موجودی انبار مرکزی به تفکیک کالا", ("get_warehouse_stock_summary",),
           acceptable=("get_inventory_status", "list_warehouses"),
           capability="inventory.stock", category="inventory", difficulty="medium"),
        _g("invt-19", "stock level of screws", ("get_inventory_status",),
           acceptable=("search_products", "get_product_kardex"),
           capability="inventory.stock", category="inventory", difficulty="hard",
           hard_case="english"),
        _g("invt-20", "سریال کالاهای گارانتی‌دار", ("search_product_instances",),
           acceptable=("search_warranty_codes", "search_products"),
           capability="inventory.stock", category="inventory", difficulty="hard"),
    ]


def _accounting_queries() -> List[GoldQuery]:
    return [
        _g("acc-01", "سرفصل حساب‌های کل", ("list_accounts",),
           acceptable=("get_account",), capability="financial.account",
           category="accounting", difficulty="easy"),
        _g("acc-02", "حساب بانک ملت را نشان بده", ("get_account",),
           acceptable=("list_accounts", "list_bank_accounts"),
           capability="financial.account", category="accounting", difficulty="medium"),
        _g("acc-03", "لیست حساب‌های بانکی", ("list_bank_accounts",),
           acceptable=("list_accounts",), capability="financial.account",
           category="accounting", difficulty="easy"),
        _g("acc-04", "اسناد حسابداری این ماه", ("search_documents",),
           acceptable=("get_document_details", "query_business_data"),
           capability="financial.document", category="accounting", difficulty="medium"),
        _g("acc-05", "جزئیات سند ۱۲۴ را باز کن", ("get_document_details",),
           acceptable=("search_documents",), capability="financial.document",
           category="accounting", difficulty="medium"),
        _g("acc-06", "سال مالی جاری کدام است", ("get_current_fiscal_year",),
           acceptable=("list_fiscal_years",), capability="financial.fiscal",
           category="accounting", difficulty="easy"),
        _g("acc-07", "لیست سال‌های مالی", ("list_fiscal_years",),
           acceptable=("get_current_fiscal_year",), capability="financial.fiscal",
           category="accounting", difficulty="easy"),
        _g("acc-08", "مانده افتتاحیه حساب‌ها", ("get_opening_balance",),
           acceptable=("list_accounts",), capability="financial.account",
           category="accounting", difficulty="hard"),
        _g("acc-09", "صندوق‌ها را لیست کن", ("list_cash_registers",),
           acceptable=("list_petty_cash", "list_accounts"),
           capability="financial.account", category="accounting", difficulty="medium"),
        _g("acc-10", "تنخواه را نشان بده", ("list_petty_cash",),
           acceptable=("list_cash_registers",), capability="financial.account",
           category="accounting", difficulty="medium", hard_case="persian_accounting"),
        _g("acc-11", "یک هزینه ثبت کن", ("create_expense_income",),
           acceptable=("list_accounts",), capability="financial.expense",
           intent=INTENT_WRITE, category="accounting", difficulty="easy"),
        _g("acc-12", "هزینه‌های این ماه را لیست کن", ("search_expense_income",),
           acceptable=("create_expense_income", "get_report"),
           capability="financial.expense", category="accounting", difficulty="medium"),
        _g("acc-13", "یک دریافت از علی ثبت کن", ("create_receipt_payment",),
           acceptable=("list_bank_accounts", "search_persons"),
           capability="financial.payment", intent=INTENT_WRITE, category="accounting",
           difficulty="medium"),
        _g("acc-14", "لیست دریافت و پرداخت‌ها", ("search_receipts_payments",),
           acceptable=("get_person_transactions",), capability="financial.payment",
           category="accounting", difficulty="easy"),
        _g("acc-15", "یک چک دریافتی ثبت کن", ("create_check",),
           acceptable=("search_persons", "search_checks"),
           capability="financial.check", intent=INTENT_WRITE, category="accounting",
           difficulty="easy"),
        _g("acc-16", "چک‌های در جریان", ("search_checks",),
           acceptable=("get_check_details",), capability="financial.check",
           category="accounting", difficulty="easy"),
        _g("acc-17", "جزئیات چک ۸۸", ("get_check_details",),
           acceptable=("search_checks",), capability="financial.check",
           category="accounting", difficulty="medium"),
        _g("acc-18", "این چک را حذف کن", ("delete_check",),
           acceptable=("search_checks",), capability="financial.check",
           intent=INTENT_DELETE, category="accounting", difficulty="easy"),
        _g("acc-19", "انتقال بین حساب‌ها ثبت کن", ("create_transfer",),
           acceptable=("list_bank_accounts",), capability="financial.transfer",
           intent=INTENT_WRITE, category="accounting", difficulty="medium"),
        _g("acc-20", "لیست انتقال‌های بانکی", ("search_transfers",),
           acceptable=("create_transfer",), capability="financial.transfer",
           category="accounting", difficulty="medium"),
        _g("acc-21", "لیست ارزها", ("list_currencies",),
           acceptable=("list_currency_rates",), capability="financial.currency",
           category="accounting", difficulty="easy"),
        _g("acc-22", "نرخ دلار را بگیر", ("resolve_currency_rate",),
           acceptable=("list_currency_rates",), capability="financial.currency",
           category="accounting", difficulty="medium"),
        _g("acc-23", "سرفصل جدید بساز", ("create_account",),
           acceptable=("list_accounts",), capability="financial.account",
           intent=INTENT_WRITE, category="accounting", difficulty="medium"),
        _g("acc-24", "coding حساب‌ها را نشان بده", ("list_accounts",),
           acceptable=("get_account",), capability="financial.account",
           category="accounting", difficulty="hard", hard_case="english"),
    ]


def _wallet_memory_workflow() -> List[GoldQuery]:
    return [
        _g("wal-01", "موجودی کیف پول کسب‌وکار", ("get_wallet_overview",),
           acceptable=("get_wallet_metrics", "list_wallet_transactions"),
           capability="financial.wallet", category="wallet", difficulty="easy"),
        _g("wal-02", "تراکنش‌های کیف پول", ("list_wallet_transactions",),
           acceptable=("get_wallet_overview",), capability="financial.wallet",
           category="wallet", difficulty="easy"),
        _g("wal-03", "متریک کیف پول را بده", ("get_wallet_metrics",),
           acceptable=("get_wallet_overview",), capability="financial.wallet",
           category="wallet", difficulty="medium"),
        _g("wal-04", "wallet balance", ("get_wallet_overview",),
           acceptable=("get_wallet_metrics",), capability="financial.wallet",
           category="wallet", difficulty="medium", hard_case="english"),
        _g("wal-05", "کیف پول چقدر شارژ دارد", ("get_wallet_overview",),
           acceptable=("list_wallet_transactions",), capability="financial.wallet",
           category="wallet", difficulty="easy", hard_case="synonyms"),
        _g("mem-01", "چی درباره من می‌دانی؟", ("read_memory",),
           acceptable=("list_session_todos",), capability="agent.memory",
           category="memory", difficulty="easy"),
        _g("mem-02", "یادت باشه گزارش‌ها را به تومان بدهی", ("upsert_memory_entry",),
           acceptable=("read_memory",), capability="agent.memory",
           intent=INTENT_WRITE, category="memory", difficulty="easy"),
        _g("mem-03", "به خاطر بسپار نام من علی است", ("upsert_memory_entry",),
           acceptable=("read_memory",), capability="agent.memory",
           intent=INTENT_WRITE, category="memory", difficulty="easy"),
        _g("mem-04", "این مورد را از حافظه حذف کن", ("delete_memory_entry",),
           acceptable=("read_memory",), capability="agent.memory",
           intent=INTENT_DELETE, category="memory", difficulty="easy"),
        _g("mem-05", "فراموش کن که همیشه دلار بدهی", ("delete_memory_entry",),
           acceptable=("read_memory",), capability="agent.memory",
           intent=INTENT_DELETE, category="memory", difficulty="medium"),
        _g("mem-06", "remember this: invoices in toman", ("upsert_memory_entry",),
           acceptable=("read_memory",), capability="agent.memory",
           intent=INTENT_WRITE, category="memory", difficulty="medium", hard_case="english"),
        _g("wf-01", "لیست گردش‌کارهای اتوماسیون", ("list_workflows",),
           acceptable=("get_workflow",), capability="automation.workflow",
           category="workflow", difficulty="easy"),
        _g("wf-02", "اتوماسیون جدید بساز", ("create_workflow",),
           acceptable=("get_workflow_design_rules", "list_workflow_builtin_nodes"),
           capability="automation.workflow", intent=INTENT_WRITE, category="workflow",
           difficulty="easy"),
        _g("wf-03", "این گردش‌کار را اجرا کن", ("execute_workflow",),
           acceptable=("list_workflows", "poll_workflow_execution"),
           capability="automation.workflow", intent=INTENT_EXECUTE, category="workflow",
           difficulty="easy"),
        _g("wf-04", "حذف اتوماسیون حقوق", ("delete_workflow",),
           acceptable=("list_workflows",), capability="automation.workflow",
           intent=INTENT_DELETE, category="workflow", difficulty="medium"),
        _g("wf-05", "اجراهای workflow را نشان بده", ("list_workflow_executions",),
           acceptable=("poll_workflow_execution", "get_workflow_execution_debug"),
           capability="automation.workflow", category="workflow", difficulty="medium"),
        _g("wf-06", "قوانین طراحی اتوماسیون چیست", ("get_workflow_design_rules",),
           acceptable=("get_workflow_component_schema",), capability="automation.workflow",
           category="workflow", difficulty="medium"),
        _g("wf-07", "کاتالوگ اکشن‌های گردش‌کار", ("list_workflow_action_catalog",),
           acceptable=("list_workflow_trigger_catalog",), capability="automation.workflow",
           category="workflow", difficulty="hard"),
        _g("wf-08", "پیش‌نویس گردش‌کار را اعتبارسنجی کن", ("validate_workflow_draft",),
           acceptable=("get_workflow_design_rules",), capability="automation.workflow",
           category="workflow", difficulty="hard"),
        _g("wf-09", "اتوماسیون را تست کن", ("test_workflow",),
           acceptable=("execute_workflow", "validate_workflow_draft"),
           capability="automation.workflow", intent=INTENT_EXECUTE, category="workflow",
           difficulty="hard"),
        _g("wf-10", "جزئیات گردش‌کار ۱۲", ("get_workflow",),
           acceptable=("list_workflows",), capability="automation.workflow",
           category="workflow", difficulty="medium"),
    ]


def _crm_tax_integration() -> List[GoldQuery]:
    return [
        _g("crm-01", "سرنخ‌های این هفته را لیست کن", ("search_leads",),
           acceptable=("get_lead_details", "get_lead_funnel_report"),
           capability="crm.lead", category="CRM", difficulty="easy"),
        _g("crm-02", "یک سرنخ جدید برای شرکت آفتاب بساز", ("create_lead",),
           acceptable=("search_leads",), capability="crm.lead",
           intent=INTENT_WRITE, category="CRM", difficulty="easy"),
        _g("crm-03", "معاملات باز را نشان بده", ("search_deals",),
           acceptable=("get_deal_details", "get_pipeline_report"),
           capability="crm.deal", category="CRM", difficulty="easy"),
        _g("crm-04", "جزئیات این معامله", ("get_deal_details",),
           acceptable=("search_deals",), capability="crm.deal",
           category="CRM", difficulty="medium"),
        _g("crm-05", "قیف فروش سرنخ‌ها", ("get_lead_funnel_report",),
           acceptable=("get_pipeline_report", "search_leads"),
           capability="reports.crm", category="CRM", difficulty="medium"),
        _g("crm-06", "گزارش پایپلاین", ("get_pipeline_report",),
           acceptable=("get_crm_summary", "search_deals"),
           capability="reports.crm", category="CRM", difficulty="medium"),
        _g("crm-07", "خلاصه CRM", ("get_crm_summary",),
           acceptable=("search_leads", "search_deals"),
           capability="crm.summary", category="CRM", difficulty="easy"),
        _g("crm-08", "فعالیت‌های CRM امروز", ("search_activities",),
           acceptable=("get_crm_summary",), capability="crm.activity",
           category="CRM", difficulty="medium"),
        _g("club-01", "امتیاز باشگاه مشتریان چقدر است", ("get_customer_club_settings",),
           acceptable=("get_customer_club_rfm_summary", "list_customer_club_ledger"),
           capability="customer_club.loyalty", category="CRM", difficulty="easy"),
        _g("club-02", "سطح‌های باشگاه مشتریان", ("list_customer_club_tiers",),
           acceptable=("get_customer_club_settings",), capability="customer_club.loyalty",
           category="CRM", difficulty="medium"),
        _g("tax-01", "تنظیمات مالیات مودیان", ("get_tax_settings",),
           acceptable=("search_tax_workspace",), capability="tax.moadian",
           category="support", difficulty="easy"),
        _g("tax-02", "کارپوشه مودیان را جستجو کن", ("search_tax_workspace",),
           acceptable=("get_tax_settings", "get_tax_data_quality"),
           capability="tax.moadian", category="support", difficulty="medium"),
        _g("tax-03", "کیفیت داده مالیاتی", ("get_tax_data_quality",),
           acceptable=("get_tax_settings",), capability="tax.moadian",
           category="support", difficulty="hard"),
        _g("bas-01", "وضعیت سینک باسلام چطور است", ("get_basalam_overview",),
           acceptable=("list_basalam_dead_letter", "list_basalam_synced_invoices"),
           capability="integration.basalam", category="support", difficulty="easy"),
        _g("bas-02", "صف خطای باسلام", ("list_basalam_dead_letter",),
           acceptable=("get_basalam_overview",), capability="integration.basalam",
           category="support", difficulty="medium"),
        _g("woo-01", "سفارش‌های ووکامرس را نشان بده", ("list_woocommerce_orders",),
           acceptable=("list_woocommerce_products",), capability="integration.woocommerce",
           category="support", difficulty="easy"),
        _g("woo-02", "محصولات ووکامرس", ("list_woocommerce_products",),
           acceptable=("list_woocommerce_orders",), capability="integration.woocommerce",
           category="support", difficulty="easy"),
        _g("con-01", "کانکتور قیمت را صدا بزن", ("invoke_business_connector",),
           acceptable=(), capability="integration.connector",
           intent=INTENT_EXECUTE, category="support", difficulty="medium"),
        _g("plug-01", "آیا افزونه باشگاه مشتریان فعال است", ("list_business_plugins",),
           acceptable=("list_marketplace_plugins",), capability="platform.marketplace",
           category="support", difficulty="medium"),
        _g("plug-02", "افزونه‌های فروشگاه را نشان بده", ("list_marketplace_plugins",),
           acceptable=("list_business_plugins",), capability="platform.marketplace",
           category="support", difficulty="medium"),
    ]


def _hard_and_edge() -> List[GoldQuery]:
    rows = [
        _g("hard-short-01", "فاکتور", ("search_invoices",),
           acceptable=("get_invoice_details", "get_sales_report", "create_invoice"),
           capability="financial.invoice", category="invoice", difficulty="ambiguous",
           hard_case="short"),
        _g("hard-short-02", "موجودی", ("get_inventory_status",),
           acceptable=("get_product_kardex", "search_products", "get_wallet_overview"),
           capability="inventory.stock", category="inventory", difficulty="ambiguous",
           hard_case="short"),
        _g("hard-short-03", "گزارش", ("get_report",),
           acceptable=("list_available_reports", "get_sales_report", "get_financial_summary"),
           capability="reports.overview", category="reports", difficulty="ambiguous",
           hard_case="short"),
        _g("hard-short-04", "مشتری", ("search_persons",),
           acceptable=("get_customer_info", "create_person"),
           capability="people.person", category="customer", difficulty="ambiguous",
           hard_case="short"),
        _g("hard-short-05", "فروش", ("get_sales_report",),
           acceptable=("search_invoices", "get_report"),
           capability="reports.sales", category="sales", difficulty="ambiguous",
           hard_case="short"),
        _g("hard-sim-01", "گزارش فروش یا فاکتورهای فروش؟ هر دو را بده",
           ("get_sales_report", "search_invoices"),
           acceptable=("get_report",), capability="reports.sales",
           category="reports", difficulty="hard", hard_case="similar_tools",
           require_all=True),
        _g("hard-sim-02", "جزئیات فاکتور را می‌خواهم نه لیست فاکتورها",
           ("get_invoice_details",),
           acceptable=("search_invoices",), capability="financial.invoice",
           category="invoice", difficulty="hard", hard_case="similar_tools"),
        _g("hard-sim-03", "کاردکس می‌خواهم نه فقط موجودی لحظه‌ای",
           ("get_product_kardex",),
           acceptable=("get_inventory_status",), capability="inventory.stock",
           category="inventory", difficulty="hard", hard_case="similar_tools"),
        _g("hard-typo-01", "فاکور فروش این ماه", ("search_invoices",),
           acceptable=("get_sales_report",), capability="financial.invoice",
           category="invoice", difficulty="hard", hard_case="typos"),
        _g("hard-typo-02", "گزرش فروش", ("get_sales_report",),
           acceptable=("get_report",), capability="reports.sales",
           category="reports", difficulty="hard", hard_case="typos"),
        _g("hard-typo-03", "موجودی انبار", ("get_inventory_status",),
           acceptable=("get_warehouse_stock_summary",), capability="inventory.stock",
           category="inventory", difficulty="easy", hard_case="typos"),
        _g("hard-typo-04", "بدهکارن را لیست کن", ("get_debtors_report",),
           acceptable=("get_report",), capability="reports.receivables",
           category="reports", difficulty="hard", hard_case="typos"),
        _g("hard-typo-05", "اتوماسیونو لیست کن", ("list_workflows",),
           acceptable=("get_workflow",), capability="automation.workflow",
           category="workflow", difficulty="hard", hard_case="typos"),
        _g("hard-syn-01", "صورتحساب علی را باز کن", ("search_invoices",),
           acceptable=("get_invoice_details",), capability="financial.invoice",
           category="invoice", difficulty="medium", hard_case="synonyms"),
        _g("hard-syn-02", "طرف‌حساب‌ها را نشان بده", ("search_persons",),
           acceptable=("get_customer_info",), capability="people.person",
           category="customer", difficulty="medium", hard_case="synonyms"),
        _g("hard-syn-03", "خروجی اکسل فاکتورهای این ماه", ("export_business_data",),
           acceptable=("search_invoices",), capability="reports.export",
           intent=INTENT_EXPORT, category="reports", difficulty="medium",
           hard_case="synonyms"),
        _g("hard-en-01", "show purchase invoices", ("search_invoices",),
           acceptable=("get_purchase_report",), capability="financial.invoice",
           category="purchase", difficulty="hard", hard_case="english"),
        _g("hard-en-02", "debtors aging report", ("get_debtors_report",),
           acceptable=("get_report",), capability="reports.receivables",
           category="reports", difficulty="hard", hard_case="english"),
        _g("hard-en-03", "create a new customer named Sara", ("create_person",),
           acceptable=("search_persons",), capability="people.person",
           intent=INTENT_WRITE, category="customer", difficulty="medium",
           hard_case="english"),
        _g("hard-long-01",
           "لطفاً وضعیت فروش این ماه را با جزئیات بررسی کن و بگو کدام کالاها بیشتر فروخته شده‌اند و موجودی همان کالاها در انبار مرکزی چقدر است",
           ("get_sales_report", "get_inventory_status"),
           acceptable=("search_invoices", "search_products", "get_product_kardex"),
           capability="reports.sales", category="reports", difficulty="hard",
           hard_case="long", require_all=True),
        _g("hard-long-02",
           "می‌خواهم یک مشتری جدید به نام کامران ثبت کنم بعد برایش فاکتور فروش خدمات پشتیبانی بزنم و در نهایت از حساب بانک ملت تسویه کنم",
           ("create_person", "create_invoice", "create_receipt_payment"),
           acceptable=("search_persons", "search_products", "list_bank_accounts"),
           capability="financial.invoice", intent=INTENT_WRITE, category="invoice",
           difficulty="hard", hard_case="multi-intent", require_all=True),
        _g("hard-multi-01", "گزارش فروش، موجودی انبار و بدهکاران را با هم بده",
           ("get_sales_report", "get_inventory_status", "get_debtors_report"),
           acceptable=("get_report",), capability="reports.overview",
           category="reports", difficulty="hard", hard_case="multi-intent",
           require_all=True),
        _g("hard-multi-02", "هم فاکتورهای امروز را لیست کن هم چک‌های در جریان را",
           ("search_invoices", "search_checks"),
           acceptable=("get_invoice_details", "get_check_details"),
           capability="financial.invoice", category="accounting", difficulty="hard",
           hard_case="multi-intent", require_all=True),
        _g("hard-amb-01", "این را حذف کن", ("delete_invoice",),
           acceptable=("delete_person", "delete_memory_entry", "delete_workflow"),
           capability="financial.invoice", intent=INTENT_DELETE, category="invoice",
           difficulty="ambiguous", hard_case="ambiguous"),
        _g("hard-amb-02", "ثبتش کن", ("create_invoice",),
           acceptable=("create_person", "create_product", "create_receipt_payment"),
           capability="financial.invoice", intent=INTENT_WRITE, category="invoice",
           difficulty="ambiguous", hard_case="ambiguous"),
        _g("hard-gen-01", "یک گزارش کلی از اوضاع بده", ("get_business_dashboard",),
           acceptable=("get_financial_summary", "get_report", "get_sales_report"),
           capability="reports.overview", category="reports", difficulty="ambiguous",
           hard_case="generic"),
        _g("hard-gen-02", "وضعیت کسب‌وکار چطوره", ("get_business_dashboard",),
           acceptable=("get_financial_summary", "get_business_info"),
           capability="reports.overview", category="reports", difficulty="ambiguous",
           hard_case="generic"),
        _g("hard-conv-01", "صف خطا چطور شد", ("list_basalam_dead_letter",),
           acceptable=("get_basalam_overview",), capability="integration.basalam",
           category="support", difficulty="hard", hard_case="conversational",
           history=({"role": "user", "content": "وضعیت سینک باسلام را بررسی کن"},)),
        _g("hard-conv-02", "جزئیاتش را هم بده", ("get_invoice_details",),
           acceptable=("search_invoices",), capability="financial.invoice",
           category="invoice", difficulty="hard", hard_case="conversational",
           history=({"role": "user", "content": "فاکتورهای فروش علی را نشان بده"},)),
        _g("hard-conv-03", "انجامش بده", ("create_person",),
           acceptable=("search_persons",), capability="people.person",
           intent=INTENT_WRITE, category="customer", difficulty="hard",
           hard_case="conversational",
           history=({"role": "user", "content": "یک مشتری جدید به نام علی اضافه کن"},)),
        _g("hard-conv-04", "موجودی همان کالا چقدر است", ("get_inventory_status",),
           acceptable=("get_product_kardex", "get_product_info"),
           capability="inventory.stock", category="inventory", difficulty="hard",
           hard_case="conversational",
           history=({"role": "user", "content": "کالای پیچ را پیدا کن"},)),
        _g("exp-01", "خروجی اکسل فاکتورهای این ماه", ("export_business_data",),
           acceptable=("search_invoices",), capability="reports.export",
           intent=INTENT_EXPORT, category="reports", difficulty="easy"),
        _g("exp-02", "دانلود لیست مشتریان", ("export_business_data",),
           acceptable=("search_persons",), capability="reports.export",
           intent=INTENT_EXPORT, category="customer", difficulty="medium"),
        _g("exp-03", "export products to excel", ("export_business_data",),
           acceptable=("search_products",), capability="reports.export",
           intent=INTENT_EXPORT, category="inventory", difficulty="medium",
           hard_case="english"),
        _g("q-01", "موجودی و فاکتور را با فیلتر پیشرفته بده", ("query_business_data",),
           acceptable=("search_invoices", "get_inventory_status", "list_queryable_fields"),
           capability="query.entity", category="accounting", difficulty="hard",
           hard_case="generic"),
        _g("q-02", "بازه تاریخ هفته پیش را حساب کن", ("resolve_date_range",),
           acceptable=("search_invoices",), capability="query.meta",
           category="accounting", difficulty="medium"),
        _g("hs-01", "راهنمای hscript", ("hscript_language_guide",),
           acceptable=("hscript_search_docs",), capability="platform.hscript",
           category="support", difficulty="medium"),
        _g("hs-02", "مستندات اچ‌اسکریپت را جستجو کن", ("hscript_search_docs",),
           acceptable=("hscript_retrieve_docs", "hscript_read_doc"),
           capability="platform.hscript", category="support", difficulty="medium"),
        _g("plat-01", "اطلاعات این کسب‌وکار", ("get_business_info",),
           acceptable=("list_my_businesses",), capability="platform.settings",
           category="support", difficulty="medium"),
        _g("plat-02", "اعلان‌های من", ("list_user_notifications",),
           acceptable=("list_announcements",), capability="platform.notifications",
           category="support", difficulty="medium"),
        _g("plat-03", "کاربران این کسب‌وکار", ("list_business_users",),
           acceptable=("get_business_info",), capability="platform.settings",
           category="support", difficulty="medium"),
    ]
    # realistic paraphrases to reach coverage without inventing new tools
    paraphrases = [
        ("فاکتور فروش شماره ۴۵ را نشان بده", "get_invoice_details", "search_invoices", "invoice", "financial.invoice"),
        ("صورتحساب ۱۲۲ را باز کن", "get_invoice_details", "search_invoices", "invoice", "financial.invoice"),
        ("فاکتورهای امروز چند تا است", "get_invoices_count", "search_invoices", "invoice", "financial.invoice"),
        ("گزارش فروش هفته اخیر", "get_sales_report", "get_report", "sales", "reports.sales"),
        ("میزان فروش دیروز", "get_sales_report", "search_invoices", "sales", "reports.sales"),
        ("خریدهای این هفته چقدر شده", "get_purchase_report", "search_invoices", "purchase", "reports.purchases"),
        ("چه کسانی از ما طلبکارند", "get_creditors_report", "search_persons", "reports", "reports.payables"),
        ("چه کسانی به ما بدهکارند", "get_debtors_report", "search_persons", "reports", "reports.receivables"),
        ("کالای روغن موجودی دارد؟", "get_inventory_status", "search_products", "inventory", "inventory.stock"),
        ("گردش کالای روغن", "get_product_kardex", "get_inventory_status", "inventory", "inventory.stock"),
        ("لیست کالاهای دسته غذایی", "search_products", "search_categories", "inventory", "inventory.product"),
        ("مشتری جدید شرکتی ثبت کن", "create_person", "list_person_groups", "customer", "people.person"),
        ("ویرایش نام مشتری علی", "update_person", "search_persons", "customer", "people.person"),
        ("سند حسابداری ۸۰۰ را باز کن", "get_document_details", "search_documents", "accounting", "financial.document"),
        ("هزینه اجاره را ویرایش کن", "update_expense_income", "search_expense_income", "accounting", "financial.expense"),
        ("پرداخت به تامین‌کننده را ویرایش کن", "update_receipt_payment", "search_receipts_payments", "accounting", "financial.payment"),
        ("چک را ویرایش کن", "update_check", "search_checks", "accounting", "financial.check"),
        ("کیف پول چقدر مانده دارد", "get_wallet_overview", "list_wallet_transactions", "wallet", "financial.wallet"),
        ("یادت باشه ارز پیش‌فرض ریال است", "upsert_memory_entry", "read_memory", "memory", "agent.memory"),
        ("گردش‌کار حقوق را باز کن", "get_workflow", "list_workflows", "workflow", "automation.workflow"),
        ("سرنخ شرکت پارس", "search_leads", "get_lead_details", "CRM", "crm.lead"),
        ("جزئیات سرنخ ۱۲", "get_lead_details", "search_leads", "CRM", "crm.lead"),
        ("باسلام چه محصولاتی تداخل دارند", "list_basalam_product_conflicts", "get_basalam_overview", "support", "integration.basalam"),
        ("فاکتورهای سینک‌شده باسلام", "list_basalam_synced_invoices", "get_basalam_overview", "support", "integration.basalam"),
        ("درگاه‌های پرداخت را لیست کن", "list_payment_gateways", "list_bank_accounts", "accounting", "financial.payment"),
        ("اقساط اعتبار را نشان بده", "list_credit_installment_plans", "get_business_credit_settings", "accounting", "financial.credit"),
        ("تسهیلات وام را لیست کن", "list_loan_facilities", "get_loan_facility", "accounting", "financial.loan"),
        ("جزئیات این وام", "get_loan_facility", "list_loan_facilities", "accounting", "financial.loan"),
        ("لاگ فعالیت سیستم", "search_activity_logs", "search_activities", "support", "platform.audit"),
        ("اعلانات سامانه", "list_announcements", "list_user_notifications", "support", "platform.notifications"),
    ]
    write_set = {
        "create_person", "update_person", "update_expense_income",
        "update_receipt_payment", "update_check", "upsert_memory_entry",
    }
    for i, (query, primary, extra, cat, cap) in enumerate(paraphrases, start=1):
        intent = INTENT_WRITE if primary in write_set else INTENT_READ
        rows.append(
            _g(
                f"para-{i:02d}",
                query,
                (primary,),
                acceptable=(extra,),
                capability=cap,
                intent=intent,
                category=cat,
                difficulty="medium",
            )
        )
    return rows


def _no_match_queries() -> List[GoldQuery]:
    texts = [
        "هوا امروز چطوره؟",
        "چه رنگی بپوشم",
        "یک جوک بگو",
        "ساعت چند است",
        "سلام خوبی؟",
        "thank you",
        "ok",
        "شعر حافظ بخوان",
        "پایتخت فرانسه کجاست",
        "دستور پخت قیمه",
        "نتیجه فوتبال دیشب",
        "چطور وزن کم کنم",
        "بهترین فیلم ۲۰۲۴",
        "هوای تهران فردا",
        "یک داستان کوتاه بگو",
        "صبح بخیر فقط خواستم سلام کنم",
        "این برنامه را دوست دارم",
        "کمکم کن حال بگیرم",
        "random chitchat about the weather",
        "آیا انسان به مریخ رفته؟",
    ]
    rows = []
    for i, text in enumerate(texts, start=1):
        rows.append(
            _g(
                f"none-{i:02d}",
                text,
                (),
                capability="",
                intent=INTENT_NONE,
                category="none",
                difficulty="easy",
                hard_case="no_match",
                no_match=True,
            )
        )
    return rows


def _expansion_queries() -> List[GoldQuery]:
    """Controlled extra paraphrases so the set can actually measure recall."""
    specs: List[Tuple[str, str, str, str, str, str, str]] = [
        ("سلام فاکتورهای فروش امروز را نشان بده", "search_invoices", "get_invoices_count", "invoice", "financial.invoice", "read", "easy"),
        ("فاکتور برگشت از فروش را پیدا کن", "search_invoices", "get_invoice_details", "invoice", "financial.invoice", "read", "medium"),
        ("فاکتور خرید شماره ۹۰ را کامل باز کن", "get_invoice_details", "search_invoices", "purchase", "financial.invoice", "read", "easy"),
        ("یه فاکتور فروش نقدی برای مینا بزن", "create_invoice", "search_persons", "invoice", "financial.invoice", "write", "easy"),
        ("فاکتور علی را بروزرسانی کن", "update_invoice", "search_invoices", "invoice", "financial.invoice", "write", "medium"),
        ("این فاکتور اشتباه را حذف کن", "delete_invoice", "search_invoices", "invoice", "financial.invoice", "delete", "easy"),
        ("گزارش فروش سال جاری", "get_sales_report", "get_report", "sales", "reports.sales", "read", "easy"),
        ("فروش به تفکیک کالا", "get_sales_report", "search_products", "sales", "reports.sales", "read", "medium"),
        ("گزارش خرید از تامین‌کننده‌ها", "get_purchase_report", "search_persons", "purchase", "reports.purchases", "read", "medium"),
        ("بدهکاران بالای ده میلیون", "get_debtors_report", "search_persons", "reports", "reports.receivables", "read", "medium"),
        ("سود و زیان سه ماهه", "get_report", "get_financial_summary", "accounting", "reports.overview", "read", "medium"),
        ("دفتر کل حساب بانک", "get_report", "get_account", "accounting", "reports.overview", "read", "hard"),
        ("جریان نقدی این فصل", "get_cash_flow", "get_financial_summary", "accounting", "reports.cashflow", "read", "medium"),
        ("ارزش موجودی انبار به ریال", "get_inventory_valuation", "get_inventory_status", "inventory", "reports.inventory", "read", "medium"),
        ("مشتری حقیقی جدید به نام سارا بساز", "create_person", "list_person_groups", "customer", "people.person", "write", "easy"),
        ("شماره تماس مشتری رضا را عوض کن", "update_person", "search_persons", "customer", "people.person", "write", "medium"),
        ("شخص تکراری را حذف کن", "delete_person", "search_persons", "customer", "people.person", "delete", "medium"),
        ("کارت مشتری شرکت پارس", "get_customer_info", "search_persons", "customer", "people.person", "read", "easy"),
        ("مانده تامین‌کننده سیمان", "get_person_balance", "search_persons", "customer", "people.person", "read", "medium"),
        ("کالای جدید روغن موتور ثبت کن", "create_product", "search_categories", "inventory", "inventory.product", "write", "easy"),
        ("بارکد کالا را ویرایش کن", "update_product", "search_products", "inventory", "inventory.product", "write", "easy"),
        ("ویژگی رنگ کالا را اضافه کن", "create_product_attribute", "list_product_attributes", "inventory", "inventory.product", "write", "hard"),
        ("لیست ویژگی‌های کالا", "list_product_attributes", "get_product_attribute", "inventory", "inventory.product", "read", "medium"),
        ("حواله خروج انبار بزن", "create_warehouse_document", "list_warehouses", "inventory", "inventory.warehouse", "write", "medium"),
        ("جانمایی انبار را نشان بده", "list_warehouse_placements", "list_warehouse_locations", "inventory", "inventory.warehouse", "read", "hard"),
        ("محل‌های انبار", "list_warehouse_locations", "list_warehouses", "inventory", "inventory.warehouse", "read", "medium"),
        ("سرفصل حساب بانک را ویرایش کن", "update_account", "list_accounts", "accounting", "financial.account", "write", "medium"),
        ("این سرفصل را حذف کن", "delete_account", "list_accounts", "accounting", "financial.account", "delete", "medium"),
        ("هزینه اینترنت را حذف کن", "delete_expense_income", "search_expense_income", "accounting", "financial.expense", "delete", "medium"),
        ("این دریافت را حذف کن", "delete_receipt_payment", "search_receipts_payments", "accounting", "financial.payment", "delete", "medium"),
        ("انتقال بانکی را حذف کن", "delete_transfer", "search_transfers", "accounting", "financial.transfer", "delete", "medium"),
        ("نرخ‌های ارز را لیست کن", "list_currency_rates", "list_currencies", "accounting", "financial.currency", "read", "easy"),
        ("شرح‌های پرتکرار اسناد", "list_frequent_descriptions", "search_documents", "accounting", "financial.document", "read", "hard"),
        ("شماره‌گذاری اسناد چطور تنظیم شده", "get_document_numbering_settings", "search_documents", "support", "platform.settings", "read", "hard"),
        ("یادت باشه همیشه فاکتور را ریالی بدهی", "upsert_memory_entry", "read_memory", "memory", "agent.memory", "write", "easy"),
        ("چی از ترجیحات من در حافظه داری", "read_memory", "list_session_todos", "memory", "agent.memory", "read", "medium"),
        ("این گردش‌کار را به‌روز کن", "update_workflow", "get_workflow", "workflow", "automation.workflow", "write", "medium"),
        ("نتیجه اجرای workflow را بگیر", "poll_workflow_execution", "list_workflow_executions", "workflow", "automation.workflow", "read", "hard"),
        ("دیباگ اجرای اتوماسیون", "get_workflow_execution_debug", "list_workflow_executions", "workflow", "automation.workflow", "read", "hard"),
        ("نودهای آماده گردش‌کار", "list_workflow_builtin_nodes", "list_workflow_action_catalog", "workflow", "automation.workflow", "read", "hard"),
        ("تریگرهای اتوماسیون را لیست کن", "list_workflow_trigger_catalog", "list_workflow_action_catalog", "workflow", "automation.workflow", "read", "hard"),
        ("این اتوماسیون را حذف کن", "delete_workflow", "list_workflows", "workflow", "automation.workflow", "delete", "easy"),
        ("فعالیت باشگاه مشتریان در دفتر امتیاز", "list_customer_club_ledger", "get_customer_club_settings", "CRM", "customer_club.loyalty", "read", "medium"),
        ("امتیاز باشگاه را کم و زیاد کن", "adjust_customer_club_points", "list_customer_club_ledger", "CRM", "customer_club.loyalty", "write", "hard"),
        ("تنظیمات باشگاه را عوض کن", "update_customer_club_settings", "get_customer_club_settings", "CRM", "customer_club.loyalty", "write", "medium"),
        ("RFM باشگاه را دوباره حساب کن", "recalculate_customer_club_rfm", "get_customer_club_rfm_summary", "CRM", "customer_club.loyalty", "write", "hard"),
        ("خلاصه RFM مشتریان", "get_customer_club_rfm_summary", "search_customer_club_rfm_persons", "CRM", "customer_club.loyalty", "read", "medium"),
        ("اسکریپت حسابیکس را اعتبارسنجی کن", "hscript_validate_script", "hscript_language_guide", "support", "platform.hscript", "read", "hard"),
        ("پیش‌نمایش hscript", "hscript_run_preview", "hscript_validate_script", "support", "platform.hscript", "read", "hard"),
        ("کسب‌وکارهای من را لیست کن", "list_my_businesses", "get_business_info", "support", "platform.settings", "read", "easy"),
        ("کدهای گارانتی را جستجو کن", "search_warranty_codes", "search_product_instances", "inventory", "misc.general", "read", "hard"),
        ("سفارش‌های تعمیر", "search_repair_orders", "get_repair_order_details", "support", "misc.general", "read", "hard"),
        ("پروژه‌ها را لیست کن", "search_projects", "get_project_summary", "support", "misc.general", "read", "medium"),
        ("مسیرهای توزیع", "list_distribution_routes", "search_persons", "support", "misc.general", "read", "hard"),
        ("فیلدهای قابل پرس‌وجو برای فاکتور", "list_queryable_fields", "query_business_data", "accounting", "query.meta", "read", "hard"),
        ("چند موجودیت را یکجا query کن", "batch_query_business_data", "query_business_data", "accounting", "query.entity", "read", "hard"),
        ("قالب گزارش پیش‌فرض را عوض کن", "set_default_report_template", "list_report_templates", "reports", "reports.templates", "write", "hard"),
        ("قالب گزارش را منتشر کن", "publish_report_template", "list_report_templates", "reports", "reports.templates", "write", "hard"),
        ("اقلام لیست قیمت ۱۲", "list_price_list_items", "list_price_lists", "inventory", "inventory.product", "read", "medium"),
        ("این ویژگی کالا را حذف کن", "delete_product_attribute", "list_product_attributes", "inventory", "inventory.product", "delete", "hard"),
        ("خروجی اکسل گزارش فروش", "export_business_data", "get_sales_report", "reports", "reports.export", "export", "medium"),
        ("فاکور های فروش علی", "search_invoices", "get_invoice_details", "invoice", "financial.invoice", "read", "hard"),
        ("گزارش فروشو بده", "get_sales_report", "get_report", "sales", "reports.sales", "read", "hard"),
        ("موجودی انبار چقده", "get_inventory_status", "get_warehouse_stock_summary", "inventory", "inventory.stock", "read", "hard"),
        ("لیست مشتریا", "search_persons", "get_customer_info", "customer", "people.person", "read", "hard"),
        ("بدهکارا کیان", "get_debtors_report", "search_persons", "reports", "reports.receivables", "read", "hard"),
        ("یه چک بزن", "create_check", "search_checks", "accounting", "financial.check", "write", "medium"),
        ("اتوماسیونا چیا هستن", "list_workflows", "get_workflow", "workflow", "automation.workflow", "read", "hard"),
        ("please list unpaid invoices", "search_invoices", "get_invoices_count", "invoice", "financial.invoice", "read", "hard"),
        ("inventory kardex for oil", "get_product_kardex", "get_inventory_status", "inventory", "inventory.stock", "read", "hard"),
        ("create purchase invoice for supplier", "create_invoice", "search_persons", "purchase", "financial.invoice", "write", "medium"),
        ("show woocommerce products", "list_woocommerce_products", "list_woocommerce_orders", "support", "integration.woocommerce", "read", "easy"),
        ("basalam sync status", "get_basalam_overview", "list_basalam_dead_letter", "support", "integration.basalam", "read", "easy"),
        ("tax settings moadian", "get_tax_settings", "search_tax_workspace", "support", "tax.moadian", "read", "medium"),
        ("trial balance farvardin", "get_report", "list_available_reports", "accounting", "reports.overview", "read", "hard"),
        ("remember I prefer toman", "upsert_memory_entry", "read_memory", "memory", "agent.memory", "write", "easy"),
        ("forget my previous currency preference", "delete_memory_entry", "read_memory", "memory", "agent.memory", "delete", "medium"),
        ("run this workflow now", "execute_workflow", "list_workflows", "workflow", "automation.workflow", "execute", "easy"),
        ("how much did we sell last week", "get_sales_report", "search_invoices", "sales", "reports.sales", "read", "medium"),
        ("who owes us money", "get_debtors_report", "search_persons", "reports", "reports.receivables", "read", "medium"),
        ("add product with barcode 123", "create_product", "search_products", "inventory", "inventory.product", "write", "easy"),
        ("chart of accounts", "list_accounts", "get_account", "accounting", "financial.account", "read", "medium"),
        ("customer groups", "list_person_groups", "search_persons", "customer", "people.person", "read", "easy"),
        ("fiscal years", "list_fiscal_years", "get_current_fiscal_year", "accounting", "financial.fiscal", "read", "easy"),
        ("payment gateways", "list_payment_gateways", "list_bank_accounts", "accounting", "financial.payment", "read", "easy"),
        ("connector call", "invoke_business_connector", "get_business_info", "support", "integration.connector", "execute", "hard"),
        ("marketplace plugins", "list_marketplace_plugins", "list_business_plugins", "support", "platform.marketplace", "read", "easy"),
        ("business users", "list_business_users", "get_business_info", "support", "platform.settings", "read", "easy"),
        ("activity log search", "search_activity_logs", "search_activities", "support", "platform.audit", "read", "medium"),
        ("checks in process", "search_checks", "get_check_details", "accounting", "financial.check", "read", "easy"),
        ("expense list this month", "search_expense_income", "create_expense_income", "accounting", "financial.expense", "read", "easy"),
        ("leads this month", "search_leads", "get_lead_funnel_report", "CRM", "crm.lead", "read", "easy"),
        ("open deals", "search_deals", "get_pipeline_report", "CRM", "crm.deal", "read", "easy"),
        ("available reports catalog", "list_available_reports", "get_report", "reports", "reports.overview", "read", "easy"),
        ("wallet metrics please", "get_wallet_metrics", "get_wallet_overview", "wallet", "financial.wallet", "read", "medium"),
        ("what do you remember about me", "read_memory", "upsert_memory_entry", "memory", "agent.memory", "read", "easy"),
        ("test this automation", "test_workflow", "execute_workflow", "workflow", "automation.workflow", "execute", "medium"),
        ("bom list", "list_boms", "get_bom_details", "inventory", "inventory.bom", "read", "medium"),
        ("bank accounts", "list_bank_accounts", "list_accounts", "accounting", "financial.account", "read", "easy"),
        ("currencies", "list_currencies", "list_currency_rates", "accounting", "financial.currency", "read", "easy"),
        ("product info oil", "get_product_info", "search_products", "inventory", "inventory.product", "read", "easy"),
        ("warehouse report", "get_warehouse_report", "get_inventory_status", "inventory", "reports.inventory", "read", "easy"),
        ("financial summary", "get_financial_summary", "get_business_dashboard", "accounting", "reports.financial", "read", "easy"),
        ("business dashboard", "get_business_dashboard", "get_financial_summary", "reports", "reports.overview", "read", "easy"),
        ("crm summary", "get_crm_summary", "search_leads", "CRM", "crm.summary", "read", "easy"),
        ("deal 5 details", "get_deal_details", "search_deals", "CRM", "crm.deal", "read", "easy"),
        ("basalam dead letter", "list_basalam_dead_letter", "get_basalam_overview", "support", "integration.basalam", "read", "easy"),
        ("hscript docs search", "hscript_search_docs", "hscript_language_guide", "support", "platform.hscript", "read", "easy"),
        ("export excel of persons", "export_business_data", "search_persons", "customer", "reports.export", "export", "easy"),
        ("delete this check", "delete_check", "search_checks", "accounting", "financial.check", "delete", "easy"),
        ("create expense for rent", "create_expense_income", "list_accounts", "accounting", "financial.expense", "write", "easy"),
        ("create receipt from customer", "create_receipt_payment", "list_bank_accounts", "accounting", "financial.payment", "write", "easy"),
        ("create bank transfer", "create_transfer", "list_bank_accounts", "accounting", "financial.transfer", "write", "easy"),
        ("create lead company aftab", "create_lead", "search_leads", "CRM", "crm.lead", "write", "easy"),
        ("لیست فاکتور", "search_invoices", "get_invoice_details", "invoice", "financial.invoice", "read", "ambiguous"),
        ("گزارش فروش", "get_sales_report", "get_report", "reports", "reports.sales", "read", "ambiguous"),
        ("کاردکس", "get_product_kardex", "get_inventory_status", "inventory", "inventory.stock", "read", "ambiguous"),
        ("بدهکاران", "get_debtors_report", "get_report", "reports", "reports.receivables", "read", "ambiguous"),
        ("اتوماسیون", "list_workflows", "create_workflow", "workflow", "automation.workflow", "read", "ambiguous"),
        ("کیف پول", "get_wallet_overview", "list_wallet_transactions", "wallet", "financial.wallet", "read", "ambiguous"),
        ("مودیان", "get_tax_settings", "search_tax_workspace", "support", "tax.moadian", "read", "ambiguous"),
        ("باسلام", "get_basalam_overview", "list_basalam_dead_letter", "support", "integration.basalam", "read", "ambiguous"),
        ("باشگاه", "get_customer_club_settings", "list_customer_club_tiers", "CRM", "customer_club.loyalty", "read", "ambiguous"),
        ("سرفصل", "list_accounts", "get_account", "accounting", "financial.account", "read", "ambiguous"),
        ("please list unpaid sales invoices this month", "search_invoices", "get_sales_report", "invoice", "financial.invoice", "read", "medium"),
        ("show me cash flow and debtors together", "get_cash_flow", "get_debtors_report", "accounting", "reports.cashflow", "read", "hard"),
        ("ثبت هزینه آب و برق", "create_expense_income", "list_accounts", "accounting", "financial.expense", "write", "easy"),
        ("ویرایش چک برگشتی", "update_check", "search_checks", "accounting", "financial.check", "write", "medium"),
        ("لیست صندوق‌های فروشگاهی", "list_cash_registers", "list_petty_cash", "accounting", "financial.account", "read", "medium"),
        ("تنخواه گردان را نشان بده", "list_petty_cash", "list_cash_registers", "accounting", "financial.account", "read", "medium"),
        ("سال مالی جاری را بگو", "get_current_fiscal_year", "list_fiscal_years", "accounting", "financial.fiscal", "read", "easy"),
        ("جزئیات قالب چاپ فاکتور", "get_report_template", "list_report_templates", "reports", "reports.templates", "read", "medium"),
        ("کاتالوگ محدوده قالب", "get_report_template_scope_catalog", "get_report_template", "reports", "reports.templates", "read", "hard"),
        ("اسکیمای کامپوننت workflow", "get_workflow_component_schema", "get_workflow_design_rules", "workflow", "automation.workflow", "read", "hard"),
        ("اعتبارسنجی پیش‌نویس گردش‌کار", "validate_workflow_draft", "get_workflow_design_rules", "workflow", "automation.workflow", "read", "medium"),
        ("خلاصه پروژه ساختمانی", "get_project_summary", "search_projects", "support", "misc.general", "read", "medium"),
        ("جزئیات سفارش تعمیر ۱۲", "get_repair_order_details", "search_repair_orders", "support", "misc.general", "read", "hard"),
        ("اسناد تولید این ماه", "search_production_documents", "search_warehouse_documents", "inventory", "inventory.production", "read", "hard"),
        ("سریال کالاها", "search_product_instances", "search_products", "inventory", "inventory.stock", "read", "hard"),
        ("ویژگی کالا را ویرایش کن", "update_product_attribute", "get_product_attribute", "inventory", "inventory.product", "write", "hard"),
        ("جزئیات ویژگی کالا", "get_product_attribute", "list_product_attributes", "inventory", "inventory.product", "read", "hard"),
        ("تنظیمات اعتبار مشتریان", "get_business_credit_settings", "get_person_credit", "accounting", "financial.credit", "read", "hard"),
        ("اقساط اعتبار", "list_credit_installment_plans", "get_business_credit_settings", "accounting", "financial.credit", "read", "hard"),
        ("جزئیات تسهیلات وام", "get_loan_facility", "list_loan_facilities", "accounting", "financial.loan", "read", "medium"),
        ("لیست تسهیلات", "list_loan_facilities", "get_loan_facility", "accounting", "financial.loan", "read", "medium"),
        ("لاگ اعلان‌های کسب‌وکار", "list_business_notification_logs", "list_user_notifications", "support", "platform.notifications", "read", "hard"),
        ("قالب پیامک اعلان", "list_business_notification_templates", "list_business_notification_logs", "support", "platform.notifications", "read", "hard"),
        ("اعلانات من", "list_user_notifications", "list_announcements", "support", "platform.notifications", "read", "easy"),
        ("مستند hscript را بخوان", "hscript_read_doc", "hscript_search_docs", "support", "platform.hscript", "read", "medium"),
        ("بازیابی مستندات hscript", "hscript_retrieve_docs", "hscript_search_docs", "support", "platform.hscript", "read", "medium"),
        ("اسکریپت را اصلاح کن", "hscript_fix_script", "hscript_validate_script", "support", "platform.hscript", "write", "hard"),
        ("پرس‌وجوی پیشرفته فاکتور و موجودی", "query_business_data", "batch_query_business_data", "accounting", "query.entity", "read", "hard"),
        ("بازه تاریخ ماه گذشته را دربیار", "resolve_date_range", "search_invoices", "accounting", "query.meta", "read", "medium"),
        ("فاکتورهای سینک شده باسلام", "list_basalam_synced_invoices", "get_basalam_overview", "support", "integration.basalam", "read", "medium"),
        ("تداخل محصولات باسلام", "list_basalam_product_conflicts", "get_basalam_overview", "support", "integration.basalam", "read", "medium"),
        ("سفارش‌های ووکامرس امروز", "list_woocommerce_orders", "list_woocommerce_products", "support", "integration.woocommerce", "read", "easy"),
        ("افزونه فعال کسب‌وکار", "list_business_plugins", "list_marketplace_plugins", "support", "platform.marketplace", "read", "medium"),
        ("اطلاعات کسب‌وکار نشست", "get_business_info", "list_my_businesses", "support", "platform.settings", "read", "medium"),
        ("تنظیمات فروش سریع", "get_quick_sales_settings", "search_invoices", "invoice", "platform.settings", "read", "hard"),
        ("مشتریان باشگاه RFM", "search_customer_club_rfm_persons", "get_customer_club_rfm_summary", "CRM", "customer_club.loyalty", "read", "hard"),
        ("سطح‌های باشگاه", "list_customer_club_tiers", "get_customer_club_settings", "CRM", "customer_club.loyalty", "read", "medium"),
        ("فعالیت‌های CRM دیروز", "search_activities", "get_crm_summary", "CRM", "crm.activity", "read", "easy"),
        ("گزارش قیف سرنخ", "get_lead_funnel_report", "search_leads", "CRM", "reports.crm", "read", "medium"),
        ("گزارش پایپ‌لاین معاملات", "get_pipeline_report", "search_deals", "CRM", "reports.crm", "read", "medium"),
        ("جزئیات سرنخ ۱۴", "get_lead_details", "search_leads", "CRM", "crm.lead", "read", "easy"),
        ("کیفیت داده مودیان", "get_tax_data_quality", "get_tax_settings", "support", "tax.moadian", "read", "medium"),
        ("کارپوشه را باز کن", "search_tax_workspace", "get_tax_settings", "support", "tax.moadian", "read", "medium"),
        ("موجودی انبار مرکزی خلاصه", "get_warehouse_stock_summary", "get_inventory_status", "inventory", "inventory.stock", "read", "easy"),
        ("لیست قیمت‌ها", "list_price_lists", "list_price_list_items", "inventory", "inventory.product", "read", "easy"),
        ("دسته‌بندی کالا", "search_categories", "search_products", "inventory", "inventory.product", "read", "easy"),
        ("اسناد انبار امروز", "search_warehouse_documents", "get_warehouse_document_details", "inventory", "inventory.warehouse", "read", "easy"),
        ("انتقال‌های این هفته", "search_transfers", "create_transfer", "accounting", "financial.transfer", "read", "easy"),
        ("گردش حساب مشتری از اول ماه", "get_person_transactions", "search_receipts_payments", "customer", "financial.payment", "read", "medium"),
        ("اعتبار این مشتری", "get_person_credit", "get_customer_info", "customer", "financial.credit", "read", "hard"),
        ("مانده افتتاحیه حساب‌ها را بده", "get_opening_balance", "list_accounts", "accounting", "financial.account", "read", "medium"),
        ("نرخ ارز را resolve کن", "resolve_currency_rate", "list_currency_rates", "accounting", "financial.currency", "read", "medium"),
        ("ویرایش انتقال بین حساب", "update_transfer", "search_transfers", "accounting", "financial.transfer", "write", "medium"),
        ("ویرایش دریافت از علی", "update_receipt_payment", "search_receipts_payments", "accounting", "financial.payment", "write", "medium"),
        ("دانلود اکسل کالاها", "export_business_data", "search_products", "inventory", "reports.export", "export", "medium"),
        ("بستانکاران را نشان بده", "get_creditors_report", "get_report", "reports", "reports.payables", "read", "easy"),
        ("گزارش انبار", "get_warehouse_report", "get_inventory_status", "inventory", "reports.inventory", "read", "easy"),
        ("داشبورد", "get_business_dashboard", "get_financial_summary", "reports", "reports.overview", "read", "ambiguous"),
        ("چک", "search_checks", "get_check_details", "accounting", "financial.check", "read", "ambiguous"),
        ("انبار", "get_inventory_status", "list_warehouses", "inventory", "inventory.stock", "read", "ambiguous"),
        ("هزینه", "search_expense_income", "create_expense_income", "accounting", "financial.expense", "read", "ambiguous"),
    ]
    intent_map = {
        "read": INTENT_READ,
        "write": INTENT_WRITE,
        "delete": INTENT_DELETE,
        "export": INTENT_EXPORT,
        "execute": INTENT_EXECUTE,
    }
    rows: List[GoldQuery] = []
    for i, (query, primary, extra, cat, cap, intent, diff) in enumerate(specs, start=1):
        hard = ""
        if query.isascii() and any(ch.isalpha() for ch in query):
            hard = "english"
        elif diff == "ambiguous":
            hard = "short" if len(query) < 16 else "ambiguous"
        elif diff == "hard" and len(query) < 22:
            hard = "typos"
        rows.append(
            _g(
                f"exp-{i:03d}",
                query,
                (primary,),
                acceptable=(extra,),
                capability=cap,
                intent=intent_map[intent],
                category=cat,
                difficulty=diff,
                hard_case=hard,
            )
        )
    conv = [
        ("همان فاکتور را حذف کن", "delete_invoice", "search_invoices", "invoice", "financial.invoice", INTENT_DELETE,
         ({"role": "user", "content": "فاکتور شماره ۱۲۳ را نشان بده"},)),
        ("برای همان مشتری فاکتور بزن", "create_invoice", "search_persons", "invoice", "financial.invoice", INTENT_WRITE,
         ({"role": "user", "content": "مشتری علی رضایی را پیدا کن"},)),
        ("کاردکس همان کالا را هم بده", "get_product_kardex", "get_inventory_status", "inventory", "inventory.stock", INTENT_READ,
         ({"role": "user", "content": "موجودی کالای پیچ چقدر است"},)),
        ("گزارش بدهکاران را هم اضافه کن", "get_debtors_report", "get_sales_report", "reports", "reports.receivables", INTENT_READ,
         ({"role": "user", "content": "گزارش فروش این ماه را بده"},)),
        ("کیف پول را هم چک کن", "get_wallet_overview", "get_financial_summary", "wallet", "financial.wallet", INTENT_READ,
         ({"role": "user", "content": "خلاصه وضعیت مالی کسب‌وکار"},)),
        ("اتوماسیون را اجرا کن", "execute_workflow", "list_workflows", "workflow", "automation.workflow", INTENT_EXECUTE,
         ({"role": "user", "content": "لیست گردش‌کارهای اتوماسیون"},)),
        ("از حافظه بگو چی ثبت کردم", "read_memory", "upsert_memory_entry", "memory", "agent.memory", INTENT_READ,
         ({"role": "user", "content": "یادت باشه گزارش‌ها را به تومان بدهی"},)),
        ("صف خطا بعد از باسلام", "list_basalam_dead_letter", "get_basalam_overview", "support", "integration.basalam", INTENT_READ,
         ({"role": "user", "content": "وضعیت سینک باسلام چطور است"},)),
        ("جزئیات همان چک", "get_check_details", "search_checks", "accounting", "financial.check", INTENT_READ,
         ({"role": "user", "content": "چک‌های در جریان"},)),
        ("همین شخص را حذف کن", "delete_person", "search_persons", "customer", "people.person", INTENT_DELETE,
         ({"role": "user", "content": "مشتری علی را پیدا کن"},)),
    ]
    for i, (query, primary, extra, cat, cap, intent, hist) in enumerate(conv, start=1):
        rows.append(
            _g(
                f"convx-{i:02d}",
                query,
                (primary,),
                acceptable=(extra,),
                capability=cap,
                intent=intent,
                category=cat,
                difficulty="hard",
                hard_case="conversational",
                history=hist,
            )
        )
    none_extra = [
        "امروز حوصله کار ندارم",
        "یک معما بگو",
        "رنگ مورد علاقه‌ات چیست",
        "آیا ربات هستی",
        "good morning nothing else",
        "فقط خواستم خداحافظی کنم",
        "یه آهنگ پیشنهاد بده",
        "هوای شمال چطوره",
        "چرا آسمان آبی است",
        "کمک کن اسم برای گربه انتخاب کنم",
    ]
    for i, text in enumerate(none_extra, start=21):
        rows.append(
            _g(
                f"none-{i:02d}",
                text,
                (),
                intent=INTENT_NONE,
                category="none",
                difficulty="easy",
                hard_case="no_match",
                no_match=True,
            )
        )
    return rows


def load_gold_queries() -> List[GoldQuery]:
    rows: List[GoldQuery] = []
    rows.extend(_legacy_gold())
    rows.extend(_invoice_queries())
    rows.extend(_report_queries())
    rows.extend(_people_queries())
    rows.extend(_inventory_queries())
    rows.extend(_accounting_queries())
    rows.extend(_wallet_memory_workflow())
    rows.extend(_crm_tax_integration())
    rows.extend(_hard_and_edge())
    rows.extend(_expansion_queries())
    rows.extend(_no_match_queries())
    seen = set()
    unique: List[GoldQuery] = []
    for row in rows:
        if row.id in seen:
            raise ValueError(f"duplicate gold id: {row.id}")
        seen.add(row.id)
        unique.append(row)
    return unique


def gold_stats(rows: Optional[List[GoldQuery]] = None) -> Dict[str, Any]:
    rows = rows if rows is not None else load_gold_queries()
    tools = set()
    caps = set()
    cats = set()
    for row in rows:
        tools.update(row.primary_expected_tools)
        tools.update(row.acceptable_tools)
        if row.required_capability:
            caps.add(row.required_capability)
        if row.category:
            cats.add(row.category)
    return {
        "dataset_version": GOLD_DATASET_VERSION,
        "tool_catalog_version": TOOL_CATALOG_VERSION,
        "queries": len(rows),
        "match_queries": sum(1 for row in rows if not row.no_match),
        "no_match_queries": sum(1 for row in rows if row.no_match),
        "tools_covered": len(tools),
        "capabilities_covered": len(caps),
        "categories": sorted(cats),
        "write_queries": sum(1 for row in rows if row.intent == INTENT_WRITE),
        "destructive_queries": sum(1 for row in rows if row.intent == INTENT_DELETE),
        "report_queries": sum(1 for row in rows if row.category in {"reports", "sales", "purchase"}),
        "memory_queries": sum(1 for row in rows if row.category == "memory"),
        "hard_queries": sum(1 for row in rows if row.difficulty in {"hard", "ambiguous"}),
        "legacy_queries": sum(1 for row in rows if row.source == "legacy"),
    }
