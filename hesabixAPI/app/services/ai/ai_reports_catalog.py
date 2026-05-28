"""
کاتالوگ گزارش‌های قابل فراخوانی از AI (فاز ۶).
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import List, Optional, Tuple


@dataclass(frozen=True)
class ReportDefinition:
    report_type: str
    label_fa: str
    category: str
    permissions: Tuple[str, ...]
    description: str = ""
    requires: Tuple[str, ...] = ()  # پارامترهای اجباری در get_report


# گزارش‌های legacy (فاز ۴) + گزارش‌های جدید (فاز ۶)
REPORT_DEFINITIONS: Tuple[ReportDefinition, ...] = (
    # --- مالی / اشخاص ---
    ReportDefinition("debtors", "بدهکاران", "financial", ("reports.read", "persons.read")),
    ReportDefinition("creditors", "بستانکاران", "financial", ("reports.read", "persons.read")),
    ReportDefinition("cash_flow", "جریان نقدی (دریافت/پرداخت)", "financial", ("reports.read",)),
    ReportDefinition("people_transactions", "گردش اشخاص", "financial", ("reports.read", "persons.read")),
    ReportDefinition("bank_accounts_turnover", "گردش حساب بانکی", "financial", ("reports.read", "bank_accounts.view")),
    ReportDefinition("cash_petty_turnover", "گردش صندوق/تنخواه", "financial", ("reports.read", "cash_registers.view")),
    # --- فروش و خرید ---
    ReportDefinition("sales_by_product", "فروش به تفکیک کالا", "sales", ("reports.read", "invoices.read")),
    ReportDefinition("sales", "فروش (همان sales_by_product)", "sales", ("reports.read", "invoices.read")),
    ReportDefinition("item_movements", "گردش کالا", "sales", ("reports.read", "inventory.read")),
    ReportDefinition("daily_sales", "فروش روزانه", "sales", ("reports.read", "invoices.read")),
    ReportDefinition("daily_purchases", "خرید روزانه", "sales", ("reports.read", "invoices.read")),
    ReportDefinition("monthly_sales", "فروش ماهانه", "sales", ("reports.read", "invoices.read")),
    ReportDefinition("top_customers", "مشتریان برتر", "sales", ("reports.read", "invoices.read")),
    ReportDefinition("top_suppliers", "تأمین‌کنندگان برتر", "sales", ("reports.read", "invoices.read")),
    ReportDefinition("materials_consumption", "مصرف مواد", "sales", ("reports.read",)),
    ReportDefinition("production", "گزارش تولید", "sales", ("reports.read",)),
    ReportDefinition("purchase", "خرید (خلاصه)", "sales", ("reports.read", "invoices.read")),
    # --- انبار ---
    ReportDefinition("inventory_valuation", "ارزش موجودی", "warehouse", ("reports.read", "inventory.read")),
    ReportDefinition("inventory_stock", "موجودی کالا", "warehouse", ("reports.read", "inventory.read")),
    ReportDefinition("inventory_kardex", "کاردکس موجودی", "warehouse", ("reports.read", "inventory.read")),
    ReportDefinition("warehouse_documents_summary", "خلاصه حواله انبار", "warehouse", ("reports.read", "warehouses.view")),
    ReportDefinition("slow_moving_items", "کالاهای کم‌گردش", "warehouse", ("reports.read", "inventory.read")),
    ReportDefinition("critical_stock", "موجودی بحرانی", "warehouse", ("reports.read", "inventory.read")),
    ReportDefinition("inter_warehouse_transfers", "انتقال بین انبار", "warehouse", ("reports.read", "warehouses.view")),
    ReportDefinition("adjustment_documents", "اسناد تعدیل", "warehouse", ("reports.read", "warehouses.view")),
    ReportDefinition("warehouse_performance", "عملکرد انبار", "warehouse", ("reports.read", "warehouses.view")),
    ReportDefinition("product_movement_history", "سابقه گردش کالا", "warehouse", ("reports.read", "inventory.read")),
    ReportDefinition("inventory_turnover", "گردش موجودی", "warehouse", ("reports.read", "inventory.read")),
    ReportDefinition("pending_documents", "اسناد معلق انبار", "warehouse", ("reports.read", "warehouses.view")),
    # --- حسابداری ---
    ReportDefinition("trial_balance", "تراز آزمایشی", "accounting", ("reports.read", "accounting_documents.view")),
    ReportDefinition(
        "general_ledger",
        "دفتر کل",
        "accounting",
        ("reports.read", "accounting_documents.view"),
        requires=("account_ids",),
    ),
    ReportDefinition("journal_ledger", "دفتر روزنامه", "accounting", ("reports.read", "accounting_documents.view")),
    ReportDefinition("pnl_period", "سود و زیان دوره‌ای", "accounting", ("reports.read", "accounting_documents.view")),
    ReportDefinition("pnl_cumulative", "سود و زیان تجمعی", "accounting", ("reports.read", "accounting_documents.view")),
    ReportDefinition("accounts_review", "مرور حساب‌ها", "accounting", ("reports.read", "accounting_documents.view")),
    # --- یکپارچه‌سازی / سایر ---
    ReportDefinition("distribution_dashboard", "داشبورد توزیع", "integration", ("reports.read", "distribution.view")),
    ReportDefinition("basalam_overview", "خلاصه باسلام", "integration", ("basalam.view",)),
    ReportDefinition("basalam_dead_letter", "صف خطای باسلام", "integration", ("basalam.view",)),
)

REPORT_TYPES: Tuple[str, ...] = tuple(d.report_type for d in REPORT_DEFINITIONS)

_REPORT_BY_TYPE = {d.report_type: d for d in REPORT_DEFINITIONS}


def get_report_definition(report_type: str) -> Optional[ReportDefinition]:
    return _REPORT_BY_TYPE.get((report_type or "").strip().lower())
