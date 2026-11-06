"""مدیریت اتصال MCP: فهرست، تغییر دسترسی، قطع grant و refresh."""
from __future__ import annotations

from datetime import datetime, timedelta
from types import SimpleNamespace
from unittest.mock import MagicMock

import pytest

from app.core.responses import ApiError
from app.services.ai.ai_mcp_connections import (
    access_scope_payload,
    apply_permissions_to_grant,
    clone_stored_tool_permissions,
    connection_status,
    keep_unrestricted_grant,
    mcp_client_kind,
    parse_tool_permissions,
    refresh_scope_payload,
    representative_rows,
    resolve_write_enabled,
    revoke_all_connections,
    serialize_connection,
    user_display_name,
)


def test_client_kind_from_oauth_metadata_url():
    assert mcp_client_kind(None, oauth=False) == "manual"
    assert mcp_client_kind("https://chatgpt.com/.well-known/oauth-client", oauth=True) == "chatgpt"
    assert mcp_client_kind("https://chat.openai.com/oauth", oauth=True) == "chatgpt"
    assert mcp_client_kind("https://claude.ai/oauth/callback", oauth=True) == "claude"
    assert mcp_client_kind("https://example.com/client", oauth=True) == "oauth"


def test_connection_status_and_display_name():
    now = datetime(2026, 11, 6, 12, 0, 0)
    row = SimpleNamespace(revoked_at=None, expires_at=now + timedelta(days=1))
    assert connection_status(row, membership_active=True, now=now) == "active"
    assert connection_status(row, membership_active=False, now=now) == "membership_inactive"
    row.revoked_at = now
    assert connection_status(row, membership_active=True, now=now) == "revoked"
    row.revoked_at = None
    row.expires_at = now - timedelta(minutes=1)
    assert connection_status(row, membership_active=True, now=now) == "expired"
    user = SimpleNamespace(first_name="علی", last_name="رضایی", email="a@b.ir", mobile=None)
    assert user_display_name(user) == "علی رضایی"


def test_representative_rows_keep_live_oauth_grant():
    now = datetime(2026, 11, 6, 12, 0, 0)
    old = SimpleNamespace(
        id=1,
        oauth_grant_id="g1",
        revoked_at=now,
        expires_at=now + timedelta(days=1),
        last_used_at=now - timedelta(hours=2),
        created_at=now - timedelta(days=1),
    )
    live = SimpleNamespace(
        id=2,
        oauth_grant_id="g1",
        revoked_at=None,
        expires_at=now + timedelta(days=10),
        last_used_at=now,
        created_at=now,
    )
    manual = SimpleNamespace(
        id=3,
        oauth_grant_id=None,
        revoked_at=None,
        expires_at=now + timedelta(days=1),
        last_used_at=None,
        created_at=now - timedelta(hours=1),
    )
    rows = representative_rows([old, live, manual], now=now)
    assert [row.id for row in rows] == [2, 3]


def test_parse_tool_permissions_rejects_agent_and_duplicates():
    assert parse_tool_permissions([]) == []
    assert parse_tool_permissions(["search_invoices", "get_invoice_details"]) == [
        "search_invoices",
        "get_invoice_details",
    ]
    with pytest.raises(ApiError) as duplicated:
        parse_tool_permissions(["search_invoices", "search_invoices"])
    assert duplicated.value.code == "MCP_INVALID_TOOL_PERMISSIONS"
    with pytest.raises(ApiError) as hidden:
        parse_tool_permissions(["ask_hesabix_agent"])
    assert hidden.value.code == "MCP_TOOL_NOT_PERMITTED"
    with pytest.raises(ApiError) as status_tool:
        parse_tool_permissions(["get_ai_mcp_plugin_status"])
    assert status_tool.value.code == "MCP_TOOL_NOT_PERMITTED"


def test_unrestricted_flag_cannot_widen_an_explicit_grant():
    assert keep_unrestricted_grant(True, True) is True
    assert keep_unrestricted_grant(True, False) is False
    assert keep_unrestricted_grant(False, True) is False
    assert clone_stored_tool_permissions(None) is None
    assert clone_stored_tool_permissions(["search_invoices"]) == ["search_invoices"]
    assert clone_stored_tool_permissions([]) == []
    assert clone_stored_tool_permissions("invalid") == []


def test_resolve_write_enabled_requires_explicit_read_only_cleanup():
    catalog = {
        "search_invoices": {"read_only": True},
        "create_invoice": {"read_only": False},
    }
    assert resolve_write_enabled(["search_invoices"], catalog, None) is False
    assert resolve_write_enabled(["create_invoice"], catalog, None) is True
    assert resolve_write_enabled(["create_invoice"], catalog, True) is True
    with pytest.raises(ApiError) as exc:
        resolve_write_enabled(["create_invoice"], catalog, False)
    assert exc.value.code == "MCP_WRITE_TOOLS_REQUIRE_WRITE_SCOPE"


def test_apply_permissions_updates_access_and_refresh_together():
    access = SimpleNamespace(
        id=11,
        oauth_grant_id="grant-1",
        mcp_tool_permissions=["search_invoices", "create_invoice"],
        scopes='["ai:tools:read","ai:tools:write"]',
        revoked_at=None,
    )
    refresh = SimpleNamespace(
        grant_id="grant-1",
        tool_permissions=["search_invoices", "create_invoice"],
        scopes=["ai:tools:read", "ai:tools:write", "offline_access"],
        revoked_at=None,
    )
    db = MagicMock()

    def query_side_effect(model):
        q = MagicMock()
        if model.__name__ == "ApiKey":
            q.filter.return_value.all.return_value = [access]
        else:
            q.filter.return_value.all.return_value = [refresh]
        return q

    db.query.side_effect = query_side_effect
    apply_permissions_to_grant(
        db,
        access,
        tool_permissions=["search_invoices"],
        enable_writes=False,
    )
    assert access.mcp_tool_permissions == ["search_invoices"]
    assert access.scopes == access_scope_payload(False)
    assert refresh.tool_permissions == ["search_invoices"]
    assert refresh.scopes == refresh_scope_payload(
        ["ai:tools:read", "ai:tools:write", "offline_access"],
        False,
    )
    assert "offline_access" in refresh.scopes
    assert "ai:tools:write" not in refresh.scopes

    apply_permissions_to_grant(
        db,
        access,
        tool_permissions=None,
        enable_writes=True,
    )
    assert access.mcp_tool_permissions is None
    assert refresh.tool_permissions is None
    assert "ai:tools:write" in refresh.scopes
    assert "offline_access" in refresh.scopes


def test_serialize_connection_reports_unrestricted_manual_grant():
    row = SimpleNamespace(
        id=9,
        name="اتصال MCP",
        business_id=4,
        user_id=2,
        oauth_grant_id=None,
        oauth_client_id=None,
        scopes='["ai:tools:read"]',
        mcp_tool_permissions=None,
        created_at=datetime(2026, 11, 1),
        expires_at=datetime(2026, 12, 1),
        last_used_at=None,
        revoked_at=None,
    )
    payload = serialize_connection(
        row,
        user=SimpleNamespace(first_name="سارا", last_name="", email="s@b.ir", mobile=None),
        client=None,
        membership_active=True,
        can_manage=True,
        now=datetime(2026, 11, 6),
    )
    assert payload["client_kind"] == "manual"
    assert payload["unrestricted_tools"] is True
    assert payload["write_enabled"] is False
    assert payload["status"] == "active"
    assert payload["user_name"] == "سارا"


def test_revoke_all_is_owner_only():
    ctx = MagicMock()
    ctx.is_business_owner.return_value = False
    ctx.get_user_id.return_value = 3
    with pytest.raises(ApiError) as exc:
        revoke_all_connections(MagicMock(), ctx, 8)
    assert exc.value.code == "MCP_REVOKE_ALL_OWNER_ONLY"
