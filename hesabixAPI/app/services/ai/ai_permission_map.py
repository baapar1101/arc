"""
نگاشت permission ابزارهای AI به سکشن/اکشن واقعی UI (people.add، invoices.view، …).
"""
from __future__ import annotations

from typing import List, Optional, Sequence, Tuple

from app.core.auth_dependency import AuthContext

# کلید legacy «section.action» → لیست (section, action) قابل قبول
PERMISSION_ALIASES: dict[str, List[Tuple[str, str]]] = {
    # اشخاص
    "persons.read": [("people", "view")],
    "persons.write": [("people", "add"), ("people", "edit")],
    "people.read": [("people", "view")],
    "people.write": [("people", "add"), ("people", "edit")],
    # فاکتور
    "invoices.read": [("invoices", "view")],
    "invoices.write": [("invoices", "add"), ("invoices", "edit"), ("invoices", "draft")],
    # محصول / موجودی
    "inventory.read": [
        ("products", "view"),
        ("warehouses", "view"),
        ("warehouse_transfers", "view"),
        ("inventory", "read"),
        ("inventory", "view"),
    ],
    "products.read": [("products", "view")],
    "products.write": [("products", "add"), ("products", "edit")],
    # دریافت/پرداخت
    "receipts_payments.read": [("people_transactions", "view")],
    "receipts_payments.write": [
        ("people_transactions", "add"),
        ("people_transactions", "edit"),
        ("people_transactions", "draft"),
    ],
    # گزارش عمومی
    "reports.read": [
        ("invoices", "view"),
        ("people", "view"),
        ("products", "view"),
        ("accounting_documents", "view"),
        ("warehouse_transfers", "view"),
    ],
    "reports.view": [("reports", "view")],
    # صندوق
    "cash_registers.view": [("cash", "view")],
    "cash_registers.write": [("cash", "add"), ("cash", "edit")],
    # انبار
    "warehouses.view": [("inventory", "read"), ("warehouses", "view")],
    "warehouses.write": [("inventory", "write"), ("warehouses", "add"), ("warehouses", "edit")],
    "warehouses.delete": [("inventory", "delete")],
    # حسابداری
    "accounting_documents.view": [("accounting_documents", "view")],
    "accounting_documents.write": [
        ("accounting_documents", "add"),
        ("accounting_documents", "edit"),
        ("accounting_documents", "draft"),
    ],
    "expenses_income.view": [("expenses_income", "view")],
    "expenses_income.write": [
        ("expenses_income", "add"),
        ("expenses_income", "edit"),
        ("expenses_income", "draft"),
    ],
    "transfers.view": [("transfers", "view")],
    "transfers.write": [("transfers", "add"), ("transfers", "edit"), ("transfers", "draft")],
    "checks.view": [("checks", "view")],
    "checks.write": [("checks", "add"), ("checks", "edit")],
    "bank_accounts.view": [("bank_accounts", "view")],
    "bank_accounts.write": [("bank_accounts", "add"), ("bank_accounts", "edit")],
    "fiscal_years.view": [("fiscal_years", "view")],
    "categories.view": [("categories", "view")],
    "categories.write": [("categories", "add"), ("categories", "edit")],
    "price_lists.view": [("price_lists", "view")],
    "price_lists.edit": [("price_lists", "edit"), ("price_lists", "add")],
    "opening_balance.view": [("opening_balance", "view")],
    "opening_balance.edit": [("opening_balance", "edit")],
    "petty_cash.view": [("petty_cash", "view")],
    "petty_cash.write": [("petty_cash", "add"), ("petty_cash", "edit")],
    "crm.view": [("crm", "view")],
    "crm.write": [("crm", "add"), ("crm", "edit")],
    "workflows.view": [("workflows", "view")],
    "workflows.write": [("workflows", "add"), ("workflows", "edit")],
    "moadian.view": [("moadian", "view")],
    "moadian.operate": [("moadian", "operate")],
    "payroll.view": [("payroll", "view")],
    "payroll.manage": [("payroll", "manage")],
    "payroll.operate": [("payroll", "operate")],
    "payroll.approve": [("payroll", "approve")],
    "payroll.post": [("payroll", "post")],
    "fixed_assets.view": [("fixed_assets", "view")],
    "fixed_assets.manage": [("fixed_assets", "manage")],
    "fixed_assets.operate": [("fixed_assets", "operate")],
    "fixed_assets.post": [("fixed_assets", "post")],
    "repair_shop.read": [("repair_shop", "read")],
    "repair_shop.write": [("repair_shop", "write")],
    "repair_shop.manage": [("repair_shop", "manage")],
    "repair_shop.delete": [("repair_shop", "delete")],
    # Keep these aligned with adapters/api/v1/warranty.py.
    "warranty.read": [("warranty", "read")],
    "warranty.manage": [("warranty", "manage")],
    "warranty.write": [("warranty", "write")],
    "warranty.delete": [("warranty", "delete")],
    "distribution.view": [("distribution", "view")],
    "distribution.manage": [("distribution", "manage")],
    "distribution.operate": [("distribution", "operate"), ("distribution", "manage")],
    "distribution.settle": [("distribution", "settle"), ("distribution", "manage")],
    "distribution.approve_returns": [("distribution", "approve_returns"), ("distribution", "manage")],
    "distribution.reports_team": [("distribution", "reports_team")],
    "customer_club.view": [("customer_club", "view")],
    "customer_club.write": [
        ("customer_club", "edit"),
        ("customer_club", "manage"),
        ("customer_club", "adjust"),
    ],
    "report_templates.view": [("report_templates", "view")],
    "report_templates.write": [("report_templates", "add"), ("report_templates", "edit")],
    "marketplace.view": [("marketplace", "view"), ("settings", "business")],
    "activity_logs.view": [("activity_logs", "view")],
    "settings.view": [("settings", "business"), ("settings", "view")],
    "credit.view": [("credit", "view")],
    "woocommerce.view": [("woocommerce", "view"), ("marketplace", "view")],
    "basalam.view": [("basalam", "view"), ("marketplace", "view")],
    "wallet.view": [("wallet", "view"), ("settings", "business")],
}


def _resolve_targets(perm: str) -> List[Tuple[str, str]]:
    if perm in PERMISSION_ALIASES:
        return PERMISSION_ALIASES[perm]
    if "." in perm:
        section, action = perm.split(".", 1)
        return [(section, action)]
    return []


def has_ai_tool_permission(
    ctx: AuthContext,
    perm: str,
    *,
    business_id: Optional[int] = None,
) -> bool:
    """بررسی یک رشته permission ابزار AI."""
    if not perm:
        return True
    bid = business_id or ctx.business_id
    if ctx.is_superadmin():
        return True
    if bid and ctx.is_business_owner(bid):
        return True
    if "." not in perm:
        return bool(ctx.has_app_permission(perm))
    for section, action in _resolve_targets(perm):
        if ctx.has_business_permission(section, action):
            return True
    return False


def has_any_ai_tool_permission(
    ctx: AuthContext,
    perms: Optional[Sequence[str]],
    *,
    business_id: Optional[int] = None,
) -> bool:
    """اگر لیست خالی باشد مجاز است."""
    if not perms:
        return True
    return any(has_ai_tool_permission(ctx, p, business_id=business_id) for p in perms)
