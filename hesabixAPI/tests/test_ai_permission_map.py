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
