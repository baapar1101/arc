"""
نگاشت permission ابزارهای AI به سکشن/اکشن واقعی UI (people.add، invoices.view، …).
"""
from __future__ import annotations

from typing import List, Optional, Sequence, Tuple

from app.core.auth_dependency import AuthContext

# کلید legacy «section.action» → لیست (section, action) قابل قبول
PERMISSION_ALIASES: dict[str, List[Tuple[str, str]]] = {
    # اشخاص
    "persons.read": [("people", "view"), ("people", "read")],
    "persons.write": [("people", "add"), ("people", "edit")],
    "people.read": [("people", "view"), ("people", "read")],
    "people.view": [("people", "view"), ("people", "read")],
    "people.write": [("people", "add"), ("people", "edit")],
    "people.delete": [("people", "delete")],
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
    "products.delete": [("products", "delete")],
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
    "cash_registers.delete": [("cash", "delete")],
    # انبار
    "warehouses.view": [("inventory", "read"), ("warehouses", "view")],
    "warehouses.write": [("inventory", "write"), ("warehouses", "add"), ("warehouses", "edit")],
    "warehouses.delete": [("inventory", "delete"), ("warehouses", "delete")],
    # حسابداری
    "accounting_documents.view": [("accounting_documents", "view")],
    "accounting_documents.write": [
        ("accounting_documents", "add"),
        ("accounting_documents", "edit"),
        ("accounting_documents", "draft"),
    ],
    "accounting_documents.delete": [("accounting_documents", "delete")],
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
    "bank_accounts.delete": [("bank_accounts", "delete")],
    "fiscal_years.view": [("fiscal_years", "view")],
    "fiscal_years.edit": [("fiscal_years", "edit"), ("fiscal_years", "add")],
    "fiscal_years.close": [("fiscal_years", "close")],
    "fiscal_years.rollback": [("fiscal_years", "rollback")],
    "loan_facilities.view": [("loan_facilities", "view")],
    "loan_facilities.write": [("loan_facilities", "add"), ("loan_facilities", "edit")],
    "loan_facilities.delete": [("loan_facilities", "delete")],
    "currency_revaluation.view": [("currency_revaluation", "view")],
    "currency_revaluation.write": [("currency_revaluation", "add"), ("currency_revaluation", "edit")],
    "currency_revaluation.delete": [("currency_revaluation", "delete")],
    "notifications.view": [("notifications", "view")],
    "notifications.write": [("notifications", "write")],
    "notifications.send": [("notifications", "send")],
    "goods_expense_income.view": [("goods_expense_income", "view")],
    "goods_expense_income.write": [("goods_expense_income", "add"), ("goods_expense_income", "edit")],
    "goods_expense_income.delete": [("goods_expense_income", "delete")],
    "goods_expense_income.post": [("goods_expense_income", "post")],
    "goods_expense_income.submit": [("goods_expense_income", "submit")],
    "goods_expense_income.allocate": [("goods_expense_income", "allocate")],
    "goods_expense_income.cancel": [("goods_expense_income", "cancel")],
    "inventory.write": [("inventory", "write"), ("products", "add"), ("products", "edit")],
    "categories.view": [("categories", "view")],
    "categories.write": [("categories", "add"), ("categories", "edit")],
    "categories.delete": [("categories", "delete")],
    "price_lists.view": [("price_lists", "view")],
    "price_lists.edit": [("price_lists", "edit"), ("price_lists", "add")],
    "price_lists.write": [("price_lists", "add"), ("price_lists", "edit")],
    "price_lists.delete": [("price_lists", "delete")],
    "opening_balance.view": [("opening_balance", "view")],
    "opening_balance.edit": [("opening_balance", "edit")],
    "petty_cash.view": [("petty_cash", "view")],
    "petty_cash.write": [("petty_cash", "add"), ("petty_cash", "edit")],
    "petty_cash.delete": [("petty_cash", "delete")],
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
    "customer_club.redeem": [("customer_club", "redeem")],
    "report_templates.view": [("report_templates", "view")],
    "report_templates.write": [("report_templates", "add"), ("report_templates", "edit")],
    "marketplace.view": [("marketplace", "view"), ("settings", "business")],
    "activity_logs.view": [("activity_logs", "view")],
    "settings.view": [("settings", "business"), ("settings", "view")],
    "settings.business": [("settings", "business")],
    "settings.join": [("settings", "join")],
    "telephony.view": [("telephony", "view")],
    "telephony.manage": [("telephony", "manage")],
    "telephony.click_to_call": [("telephony", "click_to_call"), ("telephony", "view")],
    "telephony.reports": [("telephony", "reports")],
    "telephony.supervise": [("telephony", "supervise"), ("telephony", "manage")],
    "telephony.view_all_calls": [("telephony", "view_all_calls"), ("telephony", "manage")],
    "telephony.listen_recordings": [("telephony", "listen_recordings"), ("telephony", "manage")],
    "telephony.live_monitor": [("telephony", "live_monitor"), ("telephony", "manage")],
    "telephony.control_calls": [("telephony", "control_calls"), ("telephony", "manage")],
    "barcode_labels.view": [("barcode_labels", "view")],
    "barcode_labels.design": [("barcode_labels", "design")],
    "barcode_labels.print": [("barcode_labels", "print")],
    "credit.view": [("credit", "view")],
    "credit.write": [("credit", "edit"), ("credit", "add"), ("credit", "view")],
    "projects.view": [("accounting_documents", "view")],
    "projects.write": [("accounting_documents", "add"), ("accounting_documents", "edit")],
    "projects.delete": [("accounting_documents", "delete")],
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
