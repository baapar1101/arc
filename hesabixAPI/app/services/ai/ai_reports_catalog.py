"""
کاتالوگ گزارش‌های قابل فراخوانی از AI (فاز ۶ به بعد).

منبع تطبیق رابط کاربری: `hesabixUI/.../reports_page.dart`.
هر آیتم منوی گزارش یا اینجا یک `report_type` دارد، یا با `ui_key` به همان نوع نگاشت می‌شود.
گزارش‌های وابسته به افزونه فقط وقتی افزونه فعال است در فهرست ظاهر می‌شوند.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Optional, Tuple


@dataclass(frozen=True)
class ReportDefinition:
    report_type: str
    label_fa: str
    category: str
    permissions: Tuple[str, ...]
    description: str = ""
    requires: Tuple[str, ...] = ()
    plugin_code: Optional[str] = None
    ui_key: str = ""

    def resolved_ui_key(self) -> str:
        return (self.ui_key or self.report_type).strip()


# گزارش‌های legacy (فاز ۴) + گزارش‌های صفحهٔ گزارشات
REPORT_DEFINITIONS: Tuple[ReportDefinition, ...] = (
    # --- مالی / اشخاص ---
    ReportDefinition("debtors", "بدهکاران", "financial", ("reports.read", "persons.read"), ui_key="debtors"),
    ReportDefinition("creditors", "بستانکاران", "financial", ("reports.read", "persons.read"), ui_key="creditors"),
    ReportDefinition(
        "cash_flow",
        "گردش دریافت و پرداخت",
        "financial",
        ("reports.read",),
        description="جمع دریافت و پرداخت نقدی دوره؛ برای صورت جریان وجوه نقد از cash_flow_statement استفاده کنید.",
    ),
    ReportDefinition(
        "cash_flow_statement",
        "صورت جریان وجوه نقد",
        "accounting",
        ("reports.read", "accounting_documents.view"),
        description="صورت جریان وجوه نقد عملیاتی بر اساس حساب‌های نقد/بانک/تنخواه.",
        ui_key="cash_flow",
    ),
    ReportDefinition("people_transactions", "معین / گردش اشخاص (با ریز اقلام)", "financial", ("reports.read", "persons.read"), ui_key="people_transactions"),
    ReportDefinition("bank_accounts_turnover", "گردش حساب بانکی", "financial", ("reports.read", "bank_accounts.view"), ui_key="bank_accounts_turnover"),
    ReportDefinition("cash_petty_turnover", "گردش صندوق/تنخواه", "financial", ("reports.read", "cash_registers.view"), ui_key="cash_petty_turnover"),
    ReportDefinition(
        "installments",
        "اقساط فاکتور فروش",
        "financial",
        ("reports.read", "invoices.read"),
        description="سررسید و وضعیت اقساط فاکتورهای فروش. from_date/to_date روی تاریخ سررسید اعمال می‌شود.",
        ui_key="installments",
    ),
    ReportDefinition(
        "ar_aging",
        "سن بدهی مشتریان",
        "financial",
        ("reports.read", "persons.read"),
        description="تحلیل سررسید مطالبات (AR). as_of_date اختیاری است.",
        ui_key="ar_aging",
    ),
    ReportDefinition(
        "ap_aging",
        "سن بستانکاری تامین‌کنندگان",
        "financial",
        ("reports.read", "persons.read"),
        description="تحلیل سررسید بدهی‌ها (AP). as_of_date اختیاری است.",
        ui_key="ap_aging",
    ),
    ReportDefinition(
        "person_balances_by_currency",
        "مانده اشخاص به تفکیک ارز",
        "financial",
        ("reports.read", "persons.read"),
        description="مانده بومی هر ارز و معادل ارز پایه.",
        ui_key="person_balances_by_currency",
    ),
    ReportDefinition(
        "checks",
        "گزارش چک",
        "financial",
        ("reports.read", "checks.view"),
        description="فهرست صفحه‌بندی‌شده چک با فیلتر نوع، وضعیت و بازه سررسید.",
        ui_key="checks",
    ),
    # --- فروش و خرید ---
    ReportDefinition("sales_by_product", "فروش به تفکیک کالا", "sales", ("reports.read", "invoices.read"), ui_key="sales_by_product"),
    ReportDefinition("sales", "فروش (همان sales_by_product)", "sales", ("reports.read", "invoices.read")),
    ReportDefinition("item_movements", "گردش کالا", "sales", ("reports.read", "inventory.read"), ui_key="item_movements"),
    ReportDefinition("daily_sales", "فروش روزانه", "sales", ("reports.read", "invoices.read"), ui_key="daily_sales"),
    ReportDefinition("daily_purchases", "خرید روزانه", "sales", ("reports.read", "invoices.read"), ui_key="daily_purchases"),
    ReportDefinition("monthly_sales", "فروش ماهانه", "sales", ("reports.read", "invoices.read"), ui_key="monthly_sales"),
    ReportDefinition("top_customers", "مشتریان برتر", "sales", ("reports.read", "invoices.read"), ui_key="top_customers"),
    ReportDefinition("top_suppliers", "تأمین‌کنندگان برتر", "sales", ("reports.read", "invoices.read"), ui_key="top_suppliers"),
    ReportDefinition("materials_consumption", "مصرف مواد", "sales", ("reports.read",), ui_key="materials_consumption"),
    ReportDefinition("production", "گزارش تولید", "sales", ("reports.read",), ui_key="production_report"),
    ReportDefinition("purchase", "خرید (خلاصه)", "sales", ("reports.read", "invoices.read")),
    # --- انبار ---
    ReportDefinition("inventory_valuation", "ارزش موجودی", "warehouse", ("reports.read", "inventory.read"), ui_key="inventory_valuation"),
    ReportDefinition("inventory_stock", "موجودی کالا", "warehouse", ("reports.read", "inventory.read"), ui_key="inventory_stock"),
    ReportDefinition("inventory_kardex", "کاردکس موجودی", "warehouse", ("reports.read", "inventory.read"), ui_key="inventory_kardex"),
    ReportDefinition("warehouse_documents_summary", "خلاصه حواله انبار", "warehouse", ("reports.read", "warehouses.view"), ui_key="warehouse_documents_summary"),
    ReportDefinition("slow_moving_items", "کالاهای کم‌گردش", "warehouse", ("reports.read", "inventory.read"), ui_key="slow_moving_items"),
    ReportDefinition("critical_stock", "موجودی بحرانی", "warehouse", ("reports.read", "inventory.read"), ui_key="critical_stock"),
    ReportDefinition("inter_warehouse_transfers", "انتقال بین انبار", "warehouse", ("reports.read", "warehouses.view"), ui_key="inter_warehouse_transfers"),
    ReportDefinition("adjustment_documents", "اسناد تعدیل", "warehouse", ("reports.read", "warehouses.view"), ui_key="adjustment_documents"),
    ReportDefinition("warehouse_performance", "عملکرد انبار", "warehouse", ("reports.read", "warehouses.view"), ui_key="warehouse_performance"),
    ReportDefinition("product_movement_history", "سابقه گردش کالا", "warehouse", ("reports.read", "inventory.read"), ui_key="product_movement_history"),
    ReportDefinition("inventory_turnover", "گردش موجودی", "warehouse", ("reports.read", "inventory.read"), ui_key="inventory_turnover"),
    ReportDefinition("pending_documents", "اسناد معلق انبار", "warehouse", ("reports.read", "warehouses.view"), ui_key="pending_documents"),
    ReportDefinition(
        "stock_count",
        "گزارش انبارگردانی",
        "warehouse",
        ("reports.read", "warehouses.view"),
        description="حواله‌های تعدیل که از نتیجه انبارگردانی ساخته شده‌اند.",
        ui_key="stock_count",
    ),
    # --- حسابداری ---
    ReportDefinition(
        "kardex",
        "کاردکس اسناد",
        "accounting",
        ("reports.read", "accounting_documents.view"),
        description="ریز خطوط اسناد حسابداری (کاردکس). حداکثر ۲۰۰ ردیف در صفحه.",
        ui_key="kardex",
    ),
    ReportDefinition("trial_balance", "تراز آزمایشی", "accounting", ("reports.read", "accounting_documents.view"), ui_key="trial_balance"),
    ReportDefinition(
        "general_ledger",
        "دفتر کل",
        "accounting",
        ("reports.read", "accounting_documents.view"),
        requires=("account_ids",),
        ui_key="general_ledger",
    ),
    ReportDefinition("journal_ledger", "دفتر روزنامه", "accounting", ("reports.read", "accounting_documents.view"), ui_key="journal_ledger"),
    ReportDefinition("pnl_period", "سود و زیان دوره‌ای", "accounting", ("reports.read", "accounting_documents.view"), ui_key="pnl_period"),
    ReportDefinition("pnl_cumulative", "سود و زیان تجمعی", "accounting", ("reports.read", "accounting_documents.view"), ui_key="pnl_cumulative"),
    ReportDefinition("accounts_review", "مرور حساب‌ها", "accounting", ("reports.read", "accounting_documents.view"), ui_key="accounts_review"),
    ReportDefinition("balance_sheet", "ترازنامه", "accounting", ("reports.read", "accounting_documents.view"), ui_key="balance_sheet"),
    ReportDefinition(
        "financial_package",
        "بسته گزارش مالی",
        "accounting",
        ("reports.read", "accounting_documents.view"),
        description="تراز آزمایشی، سود و زیان دوره و ترازنامه با پارامترهای یکسان؛ خروجی JSON است نه فایل.",
        ui_key="financial_package",
    ),
    ReportDefinition(
        "fx_revaluation",
        "گزارش تسعیر ارز",
        "accounting",
        ("reports.read", "accounting_documents.view"),
        description="اسناد تسعیر پایان‌دوره و اثر سود و زیان تسعیر.",
        ui_key="fx_revaluation",
    ),
    ReportDefinition(
        "activity_logs",
        "گزارش فعالیت سیستم",
        "system",
        ("activity_logs.view",),
        description="لاگ فعالیت‌های کسب‌وکار با فیلتر دسته، موجودیت و بازه تاریخ.",
        ui_key="activity_logs",
    ),
    ReportDefinition(
        "hscript_reports",
        "گزارش‌ساز اسکریپتی",
        "system",
        ("reports.read",),
        description="فهرست گزارش‌های ذخیره‌شده HScript. ساخت و ویرایش اسکریپت با ابزارهای hscript_* انجام می‌شود.",
        ui_key="hscript_builder",
    ),
    # --- یکپارچه‌سازی / افزونه‌ها ---
    ReportDefinition(
        "distribution_dashboard",
        "داشبورد توزیع",
        "integration",
        ("reports.read", "distribution.view"),
        requires=("from_date", "to_date"),
        plugin_code="distribution",
        ui_key="distribution_dashboard",
    ),
    ReportDefinition(
        "basalam_overview",
        "خلاصه باسلام",
        "integration",
        ("basalam.view",),
        plugin_code="basalam_connector",
        ui_key="basalam_reports_overview",
    ),
    ReportDefinition(
        "basalam_synced_invoices",
        "فاکتورهای همگام باسلام",
        "integration",
        ("basalam.view",),
        plugin_code="basalam_connector",
        ui_key="basalam_reports_invoices",
    ),
    ReportDefinition(
        "basalam_dead_letter",
        "صف خطای باسلام",
        "integration",
        ("basalam.view",),
        plugin_code="basalam_connector",
        ui_key="basalam_reports_dlq",
    ),
    ReportDefinition(
        "basalam_product_conflicts",
        "تعارض کالای باسلام",
        "integration",
        ("basalam.view",),
        plugin_code="basalam_connector",
        ui_key="basalam_reports_conflicts",
    ),
    ReportDefinition(
        "woocommerce_overview",
        "خلاصه ووکامرس",
        "integration",
        ("woocommerce.view",),
        plugin_code="woocommerce_hesabix",
        ui_key="woo_reports_overview",
    ),
    ReportDefinition(
        "woocommerce_orders",
        "سفارش‌های اخیر ووکامرس",
        "integration",
        ("woocommerce.view",),
        plugin_code="woocommerce_hesabix",
        ui_key="woo_reports_orders",
    ),
    ReportDefinition(
        "woocommerce_catalog",
        "کاتالوگ ووکامرس",
        "integration",
        ("woocommerce.view",),
        plugin_code="woocommerce_hesabix",
        ui_key="woo_reports_catalog",
    ),
    ReportDefinition(
        "woocommerce_bridge",
        "سلامت پل ووکامرس",
        "integration",
        ("woocommerce.view",),
        plugin_code="woocommerce_hesabix",
        ui_key="woo_reports_bridge",
    ),
)

REPORT_TYPES: Tuple[str, ...] = tuple(d.report_type for d in REPORT_DEFINITIONS)

REPORT_CATEGORIES: Tuple[str, ...] = tuple(sorted({d.category for d in REPORT_DEFINITIONS}))

PLUGIN_GATED_REPORT_TYPES: Tuple[str, ...] = tuple(
    d.report_type for d in REPORT_DEFINITIONS if d.plugin_code
)

_REPORT_BY_TYPE = {d.report_type: d for d in REPORT_DEFINITIONS}

# کلیدهای صفحهٔ گزارشات که باید معادل MCP داشته باشند (به‌جز hscript که فهرست ذخیره است نه طراح).
UI_REPORT_KEYS: Tuple[str, ...] = tuple(
    sorted({d.resolved_ui_key() for d in REPORT_DEFINITIONS if d.resolved_ui_key()})
)

# کلیدهای منوی `reports_page.dart` — منبع تطبیق sprint 1.
UI_MENU_REPORT_KEYS: Tuple[str, ...] = (
    "kardex",
    "hscript_builder",
    "installments",
    "debtors",
    "creditors",
    "ar_aging",
    "ap_aging",
    "person_balances_by_currency",
    "people_transactions",
    "distribution_dashboard",
    "item_movements",
    "inventory_kardex",
    "inventory_stock",
    "stock_count",
    "sales_by_product",
    "warehouse_documents_summary",
    "slow_moving_items",
    "critical_stock",
    "inter_warehouse_transfers",
    "adjustment_documents",
    "warehouse_performance",
    "product_movement_history",
    "inventory_valuation",
    "pending_documents",
    "inventory_turnover",
    "bank_accounts_turnover",
    "cash_petty_turnover",
    "checks",
    "daily_sales",
    "monthly_sales",
    "top_customers",
    "daily_purchases",
    "top_suppliers",
    "materials_consumption",
    "production_report",
    "trial_balance",
    "balance_sheet",
    "financial_package",
    "general_ledger",
    "journal_ledger",
    "accounts_review",
    "cash_flow",
    "fx_revaluation",
    "pnl_period",
    "pnl_cumulative",
    "activity_logs",
    "basalam_reports_overview",
    "basalam_reports_invoices",
    "basalam_reports_dlq",
    "basalam_reports_conflicts",
    "woo_reports_overview",
    "woo_reports_orders",
    "woo_reports_catalog",
    "woo_reports_bridge",
)


def get_report_definition(report_type: str) -> Optional[ReportDefinition]:
    return _REPORT_BY_TYPE.get((report_type or "").strip().lower())


def report_definitions_for_ui_key(ui_key: str) -> Tuple[ReportDefinition, ...]:
    key = (ui_key or "").strip()
    if not key:
        return ()
    return tuple(d for d in REPORT_DEFINITIONS if d.resolved_ui_key() == key)
