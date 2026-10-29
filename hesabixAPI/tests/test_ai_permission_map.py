"""تست نگاشت permission ابزارهای AI."""
from __future__ import annotations

from unittest.mock import MagicMock

from app.services.ai.ai_permission_map import has_ai_tool_permission, has_any_ai_tool_permission


def test_persons_write_maps_to_people_add():
    ctx = MagicMock()
    ctx.is_superadmin.return_value = False
    ctx.is_business_owner.return_value = False
    ctx.business_id = 1
    ctx.has_app_permission.return_value = False

    def _perm(section, action):
        return section == "people" and action == "add"

    ctx.has_business_permission.side_effect = _perm

    assert has_ai_tool_permission(ctx, "persons.write", business_id=1)


def test_invoices_read_maps_to_view():
    ctx = MagicMock()
    ctx.is_superadmin.return_value = False
    ctx.is_business_owner.return_value = False
    ctx.has_app_permission.return_value = False
    ctx.has_business_permission.side_effect = lambda s, a: s == "invoices" and a == "view"

    assert has_ai_tool_permission(ctx, "invoices.read", business_id=1)


def test_crm_write_maps_to_crm_add():
    ctx = MagicMock()
    ctx.is_superadmin.return_value = False
    ctx.is_business_owner.return_value = False
    ctx.has_app_permission.return_value = False
    ctx.has_business_permission.side_effect = lambda s, a: s == "crm" and a == "add"

    assert has_ai_tool_permission(ctx, "crm.write", business_id=1)


def test_empty_perms_allowed():
    ctx = MagicMock()
    assert has_any_ai_tool_permission(ctx, [])


def test_accounting_documents_delete_maps_to_delete():
    ctx = MagicMock()
    ctx.is_superadmin.return_value = False
    ctx.is_business_owner.return_value = False
    ctx.business_id = 1
    ctx.has_app_permission.return_value = False
    ctx.has_business_permission.side_effect = (
        lambda s, a: s == "accounting_documents" and a == "delete"
    )
    assert has_ai_tool_permission(ctx, "accounting_documents.delete", business_id=1)
    assert not has_ai_tool_permission(ctx, "accounting_documents.write", business_id=1)


def test_treasury_delete_permissions_map_to_ui_sections():
    ctx = MagicMock()
    ctx.is_superadmin.return_value = False
    ctx.is_business_owner.return_value = False
    ctx.business_id = 1
    ctx.has_app_permission.return_value = False

    ctx.has_business_permission.side_effect = lambda s, a: s == "bank_accounts" and a == "delete"
    assert has_ai_tool_permission(ctx, "bank_accounts.delete", business_id=1)
    assert not has_ai_tool_permission(ctx, "cash_registers.delete", business_id=1)

    ctx.has_business_permission.side_effect = lambda s, a: s == "cash" and a == "delete"
    assert has_ai_tool_permission(ctx, "cash_registers.delete", business_id=1)

    ctx.has_business_permission.side_effect = lambda s, a: s == "petty_cash" and a == "delete"
    assert has_ai_tool_permission(ctx, "petty_cash.delete", business_id=1)


def test_plugin_and_settings_permissions_map_to_ui_sections():
    ctx = MagicMock()
    ctx.is_superadmin.return_value = False
    ctx.is_business_owner.return_value = False
    ctx.business_id = 1
    ctx.has_app_permission.return_value = False

    ctx.has_business_permission.side_effect = lambda s, a: s == "fixed_assets" and a == "post"
    assert has_ai_tool_permission(ctx, "fixed_assets.post", business_id=1)
    assert not has_ai_tool_permission(ctx, "fixed_assets.manage", business_id=1)

    ctx.has_business_permission.side_effect = lambda s, a: s == "telephony" and a == "view"
    assert has_ai_tool_permission(ctx, "telephony.click_to_call", business_id=1)
    assert not has_ai_tool_permission(ctx, "telephony.manage", business_id=1)

    ctx.has_business_permission.side_effect = lambda s, a: s == "barcode_labels" and a == "design"
    assert has_ai_tool_permission(ctx, "barcode_labels.design", business_id=1)
    assert not has_ai_tool_permission(ctx, "barcode_labels.print", business_id=1)

    ctx.has_business_permission.side_effect = lambda s, a: s == "settings" and a == "business"
    assert has_ai_tool_permission(ctx, "settings.business", business_id=1)
    assert not has_ai_tool_permission(ctx, "settings.join", business_id=1)


def test_project_credit_and_person_group_permissions_map_to_ui_sections():
    ctx = MagicMock()
    ctx.is_superadmin.return_value = False
    ctx.is_business_owner.return_value = False
    ctx.business_id = 1
    ctx.has_app_permission.return_value = False

    ctx.has_business_permission.side_effect = (
        lambda s, a: s == "accounting_documents" and a == "add"
    )
    assert has_ai_tool_permission(ctx, "projects.write", business_id=1)
    assert not has_ai_tool_permission(ctx, "projects.delete", business_id=1)

    ctx.has_business_permission.side_effect = (
        lambda s, a: s == "accounting_documents" and a == "delete"
    )
    assert has_ai_tool_permission(ctx, "projects.delete", business_id=1)

    ctx.has_business_permission.side_effect = lambda s, a: s == "people" and a == "delete"
    assert has_ai_tool_permission(ctx, "people.delete", business_id=1)
    assert not has_ai_tool_permission(ctx, "persons.write", business_id=1)

    ctx.has_business_permission.side_effect = lambda s, a: s == "credit" and a == "view"
    assert has_ai_tool_permission(ctx, "credit.write", business_id=1)
    assert has_ai_tool_permission(ctx, "credit.view", business_id=1)


def test_catalog_permissions_map_to_ui_sections():
    ctx = MagicMock()
    ctx.is_superadmin.return_value = False
    ctx.is_business_owner.return_value = False
    ctx.business_id = 1
    ctx.has_app_permission.return_value = False

    ctx.has_business_permission.side_effect = lambda s, a: s == "products" and a == "delete"
    assert has_ai_tool_permission(ctx, "products.delete", business_id=1)
    assert not has_ai_tool_permission(ctx, "products.write", business_id=1)

    ctx.has_business_permission.side_effect = lambda s, a: s == "price_lists" and a == "add"
    assert has_ai_tool_permission(ctx, "price_lists.write", business_id=1)
    assert not has_ai_tool_permission(ctx, "price_lists.delete", business_id=1)

    ctx.has_business_permission.side_effect = lambda s, a: s == "categories" and a == "delete"
    assert has_ai_tool_permission(ctx, "categories.delete", business_id=1)
    assert not has_ai_tool_permission(ctx, "categories.write", business_id=1)


def test_remaining_domain_permissions_map_to_ui_sections():
    ctx = MagicMock()
    ctx.is_superadmin.return_value = False
    ctx.is_business_owner.return_value = False
    ctx.business_id = 1
    ctx.has_app_permission.return_value = False

    ctx.has_business_permission.side_effect = lambda s, a: s == "loan_facilities" and a == "add"
    assert has_ai_tool_permission(ctx, "loan_facilities.write", business_id=1)
    assert not has_ai_tool_permission(ctx, "loan_facilities.delete", business_id=1)

    ctx.has_business_permission.side_effect = lambda s, a: s == "fiscal_years" and a == "close"
    assert has_ai_tool_permission(ctx, "fiscal_years.close", business_id=1)
    assert not has_ai_tool_permission(ctx, "fiscal_years.edit", business_id=1)

    ctx.has_business_permission.side_effect = lambda s, a: s == "currency_revaluation" and a == "add"
    assert has_ai_tool_permission(ctx, "currency_revaluation.write", business_id=1)

    ctx.has_business_permission.side_effect = lambda s, a: s == "goods_expense_income" and a == "post"
    assert has_ai_tool_permission(ctx, "goods_expense_income.post", business_id=1)
    assert not has_ai_tool_permission(ctx, "goods_expense_income.write", business_id=1)

    ctx.has_business_permission.side_effect = lambda s, a: s == "notifications" and a == "send"
    assert has_ai_tool_permission(ctx, "notifications.send", business_id=1)
    assert not has_ai_tool_permission(ctx, "notifications.write", business_id=1)

    ctx.has_business_permission.side_effect = lambda s, a: s == "warehouses" and a == "delete"
    assert has_ai_tool_permission(ctx, "warehouses.delete", business_id=1)

    ctx.has_business_permission.side_effect = lambda s, a: s == "customer_club" and a == "redeem"
    assert has_ai_tool_permission(ctx, "customer_club.redeem", business_id=1)
