"""Platform support-desk MCP: isolation from business MCP, operator access, no write-scope split."""
from __future__ import annotations

import asyncio
from datetime import datetime, timedelta
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

import pytest

from app.core.responses import ApiError
from app.services.ai.ai_function_extensions_mcp_support import (
    HISTORY,
    REPLY,
    SEARCH,
    get_user_support_ticket_history_handler,
    reply_support_ticket_handler,
    search_support_tickets_handler,
)
from app.services.ai.ai_mcp_discovery import (
    AGENT_TOOL_NAME,
    mcp_support_visible_definitions,
    mcp_visible_definitions,
    support_tool_catalog,
)
from app.services.ai.ai_mcp_support_connections import (
    SUPPORT_MCP_BEARER_PREFIX,
    SUPPORT_MCP_KEY_TYPE,
    SUPPORT_MCP_READ_SCOPE,
    SUPPORT_MCP_WRITE_SCOPE,
    create_support_connection,
    list_support_connections,
    revoke_support_connection,
)
from app.services.ai.ai_mcp_support_service import (
    SERVER_NAME,
    handle_support_mcp_request,
    prepare_support_mcp_tool_arguments,
)
from app.services.ai.ai_tool_capability import resolve_tool_capability
from app.services.ai.ai_tool_catalog_quality import parse_registered_tool_fields
from app.services.ai.ai_tool_keys import TOOL_L10N_KEYS, TOOL_LABELS_FA
from app.services.ai.ai_tool_manifest import get_manifest_entry
from app.services.ai.ai_write_guard import is_write_function

SUPPORT_READ_TOOLS = (
    "search_support_tickets",
    "get_support_ticket",
    "list_support_ticket_messages",
    "list_support_ticket_events",
    "get_support_dashboard_stats",
    "list_overdue_support_tickets",
    "list_support_activity",
    "get_user_support_ticket_history",
    "list_support_operators",
    "list_support_categories",
    "list_support_priorities",
    "list_support_statuses",
    "list_support_response_templates",
)
SUPPORT_WRITE_TOOLS = (
    "reply_support_ticket",
    "add_support_internal_note",
    "assign_support_ticket",
    "update_support_ticket_status",
    "update_support_ticket_priority",
    "mark_support_ticket_read",
    "bulk_assign_support_tickets",
    "bulk_update_support_ticket_status",
)
SUPPORT_TOOLS = SUPPORT_READ_TOOLS + SUPPORT_WRITE_TOOLS


def _ctx(*, superadmin: bool = False, operator: bool = True, user_id: int = 9):
    ctx = MagicMock()
    ctx.business_id = None
    ctx.user = SimpleNamespace(id=user_id, first_name="اپراتور", last_name="تست", email="op@test.ir")
    ctx.mcp_scopes = {SUPPORT_MCP_READ_SCOPE, SUPPORT_MCP_WRITE_SCOPE}
    ctx.mcp_tool_permissions = None
    ctx.mcp_connection_id = 4
    ctx.mcp_channel = "support"
    ctx.get_user_id.return_value = user_id
    ctx.is_superadmin.return_value = superadmin
    ctx.can_access_support_operator.return_value = superadmin or operator
    ctx.has_app_permission.side_effect = lambda perm: superadmin or (operator and perm == "support_operator")
    ctx.is_business_owner.return_value = False
    ctx.can_access_business.return_value = False
    return ctx


def _rpc(method: str, params=None, req_id=1):
    return {"jsonrpc": "2.0", "id": req_id, "method": method, "params": params or {}}


def _run(ctx, body):
    return asyncio.run(handle_support_mcp_request(MagicMock(), ctx, body))


def _tool_names(definitions):
    return {str((item.get("function") or {}).get("name")) for item in definitions}


def test_support_tools_are_registered_with_strict_isolation_metadata():
    parsed = parse_registered_tool_fields()
    for name in SUPPORT_TOOLS:
        assert name in parsed, name
        fields = parsed[name]
        assert fields["required_permissions"] == ["support_operator"], name
        assert fields["business_context_required"] is False, name
        assert fields["category"] == "support", name
        if name in SUPPORT_READ_TOOLS:
            assert fields["is_readonly"] is True, name
            assert fields["requires_approval"] is False, name
        else:
            assert fields["is_readonly"] is False, name
            assert fields["requires_approval"] is True, name
    assert parsed["bulk_assign_support_tickets"]["risk_level"] == "high"
    assert parsed["bulk_update_support_ticket_status"]["risk_level"] == "high"
    assert SEARCH["additionalProperties"] is False
    assert "business_id" not in SEARCH["properties"]
    assert "user_id" not in SEARCH["properties"]
    assert HISTORY["required"] == ["ticket_user_id"]
    assert "user_id" not in HISTORY["properties"]
    assert REPLY["properties"]["content"]["maxLength"] == 8000
    assert SEARCH["properties"]["take"]["maximum"] == 50


def test_support_manifest_capability_and_write_classification():
    for name in SUPPORT_TOOLS:
        entry = get_manifest_entry(name)
        assert entry is not None, name
        assert entry.domains == ("support",)
        assert entry.capability == "platform.support"
        assert resolve_tool_capability(name, entry.domains) == "platform.support"
        assert name in TOOL_L10N_KEYS
        assert name in TOOL_LABELS_FA
        if name in SUPPORT_WRITE_TOOLS:
            assert entry.intent_write is True
            assert is_write_function(name) is True
        else:
            assert entry.intent_write is False
            assert is_write_function(name) is False
    assert get_manifest_entry("bulk_assign_support_tickets").always_confirm is True
    assert get_manifest_entry("bulk_update_support_ticket_status").always_confirm is True
    from app.services.ai.ai_function_extensions_mcp_support import BULK_ASSIGN

    assert BULK_ASSIGN["properties"]["ticket_ids"]["maxItems"] == 20


def test_business_mcp_excludes_support_tools_even_for_superadmin():
    ctx = _ctx(superadmin=True)
    ctx.business_id = 7
    ctx.can_access_business.return_value = True
    _registry, definitions = mcp_visible_definitions(MagicMock(), ctx, 7)
    names = _tool_names(definitions)
    assert names
    assert names.isdisjoint(SUPPORT_TOOLS)
    assert AGENT_TOOL_NAME not in names


def test_support_mcp_includes_all_tools_for_operator_and_superadmin():
    for ctx in (_ctx(operator=True, superadmin=False), _ctx(superadmin=True)):
        _registry, definitions = mcp_support_visible_definitions(MagicMock(), ctx)
        names = _tool_names(definitions)
        assert set(SUPPORT_TOOLS) <= names
        assert "search_invoices" not in names
        assert "create_invoice" not in names
        assert AGENT_TOOL_NAME not in names
        assert all(
            (fn := _registry.get_function(name))
            and fn.category == "support"
            and not fn.business_context_required
            for name in SUPPORT_TOOLS
        )


def test_support_mcp_hides_tools_from_regular_business_user():
    ctx = _ctx(operator=False, superadmin=False)
    ctx.business_id = 3
    ctx.can_access_business.return_value = True
    ctx.has_app_permission.return_value = False
    ctx.can_access_support_operator.return_value = False
    _registry, definitions = mcp_support_visible_definitions(MagicMock(), ctx)
    assert _tool_names(definitions).isdisjoint(SUPPORT_TOOLS)


def test_support_catalog_does_not_split_read_and_write():
    ctx = _ctx(operator=True)
    ctx.mcp_scopes = {SUPPORT_MCP_READ_SCOPE}
    catalog = support_tool_catalog(MagicMock(), ctx)
    names = {item["name"] for item in catalog}
    assert set(SUPPORT_TOOLS) <= names
    assert AGENT_TOOL_NAME not in names
    writes = [item for item in catalog if item["name"] in SUPPORT_WRITE_TOOLS]
    assert writes
    assert all(item["read_only"] is False for item in writes)
    assert all(item["capability"] == "platform.support" for item in catalog if item["name"] in SUPPORT_TOOLS)


def test_prepare_support_arguments_remap_customer_user_and_strip_identity():
    cleaned = prepare_support_mcp_tool_arguments(
        {
            "user_id": 44,
            "business_id": 99,
            "_approve_writes": True,
            "approve_writes": True,
            "confirmation_id": "x",
            "ticket_id": 12,
            "content": "پاسخ",
        }
    )
    assert cleaned["ticket_user_id"] == 44
    assert "user_id" not in cleaned
    assert "business_id" not in cleaned
    assert "_approve_writes" not in cleaned
    assert "approve_writes" not in cleaned
    assert "confirmation_id" not in cleaned
    assert cleaned["ticket_id"] == 12
    assert cleaned["content"] == "پاسخ"


def test_support_initialize_and_tools_list_include_writes_without_write_scope():
    ctx = _ctx(operator=True)
    ctx.mcp_scopes = {SUPPORT_MCP_READ_SCOPE}
    init = _run(ctx, _rpc("initialize", {"protocolVersion": "2025-11-25"}))
    assert init["result"]["serverInfo"]["name"] == SERVER_NAME
    listed = _run(ctx, _rpc("tools/list"))
    names = {tool["name"] for tool in listed["result"]["tools"]}
    assert set(SUPPORT_TOOLS) <= names
    assert AGENT_TOOL_NAME not in names
    resources = _run(ctx, _rpc("resources/list"))
    uris = {item["uri"] for item in resources["result"]["resources"]}
    assert uris == {"hesabix://support/inbox", "hesabix://mcp/capabilities"}


def test_support_tools_call_does_not_require_write_scope():
    ctx = _ctx(operator=True)
    ctx.mcp_scopes = {SUPPORT_MCP_READ_SCOPE}
    with patch("app.services.ai.ai_db_helpers.run_ai_registry_function", return_value={"id": 12, "ok": True}) as call:
        result = _run(
            ctx,
            _rpc(
                "tools/call",
                {"name": "reply_support_ticket", "arguments": {"ticket_id": 12, "content": "سلام"}},
            ),
        )
    assert result["result"]["isError"] is False
    call.assert_called_once()
    assert call.call_args.args[0] == "reply_support_ticket"
    assert call.call_args.args[1] == {"ticket_id": 12, "content": "سلام"}
    assert call.call_args.args[2]["business_id"] is None


def test_support_tools_call_rejects_business_tools():
    ctx = _ctx(superadmin=True)
    result = _run(ctx, _rpc("tools/call", {"name": "search_invoices", "arguments": {"search": "فاکتور"}}))
    assert result["error"]["code"] == -32602
    assert "not permitted" in result["error"]["message"]


def test_search_support_tickets_defaults_to_open_only():
    db = MagicMock()
    open_status = SimpleNamespace(id=2)
    db.query.return_value.filter.return_value.all.return_value = [open_status]
    ticket = SimpleNamespace(
        id=8,
        title="خطا",
        user_id=3,
        user=SimpleNamespace(id=3, first_name="علی", last_name="رضایی", email="hidden@x.ir"),
        category=SimpleNamespace(name="فنی"),
        priority=SimpleNamespace(name="بالا"),
        status=SimpleNamespace(name="باز", is_final=False),
        assigned_operator=None,
        sla_breached=False,
        first_response_due_at=None,
        resolution_due_at=None,
        last_message_at=None,
        created_at=None,
        updated_at=None,
    )
    ctx = {
        "db": db,
        "user_context": _ctx(operator=True),
        "business_id": None,
    }
    with patch(
        "adapters.db.repositories.support.ticket_repository.TicketRepository.get_operator_tickets",
        return_value=([ticket], 1),
    ) as search:
        payload = search_support_tickets_handler({}, ctx)
    query = search.call_args.args[0]
    assert query.filters
    assert any(item.property == "status_id" and item.operator == "in" and item.value == [2] for item in query.filters)
    assert "email" not in payload["items"][0]["user"]
    assert payload["items"][0]["id"] == 8


def test_history_handler_uses_ticket_user_id_not_operator_identity():
    ctx = {
        "db": MagicMock(),
        "user_context": _ctx(operator=True, user_id=9),
        "business_id": None,
    }
    with patch(
        "app.services.support.support_dashboard_service.SupportDashboardService.get_user_ticket_history",
        return_value=[{"id": 1}],
    ) as history:
        payload = get_user_support_ticket_history_handler({"ticket_user_id": 44, "take": 5}, ctx)
    history.assert_called_once()
    assert history.call_args.args[0] == 44
    assert payload["items"] == [{"id": 1}]


def test_reply_handler_sends_public_operator_reply():
    actor = _ctx(operator=True, user_id=9)
    ctx = {"db": MagicMock(), "user_context": actor, "business_id": None}
    with patch(
        "app.services.support.operator_ticket_actions.reply_as_operator",
        return_value={"id": 21, "is_internal": False},
    ) as reply:
        payload = reply_support_ticket_handler({"ticket_id": 12, "content": "پاسخ اپراتور"}, ctx)
    reply.assert_called_once()
    kwargs = reply.call_args.kwargs
    assert kwargs["ticket_id"] == 12
    assert kwargs["actor_id"] == 9
    assert kwargs["is_internal"] is False
    assert kwargs["content"] == "پاسخ اپراتور"
    assert payload["id"] == 21


def test_create_support_connection_grants_both_scopes_and_platform_prefix():
    db = MagicMock()
    query = MagicMock()
    query.filter.return_value = query
    query.count.return_value = 0
    db.query.return_value = query
    created = {}

    def add(row):
        created["row"] = row

    def refresh(row):
        row.id = 15
        if row.created_at is None:
            row.created_at = datetime.utcnow()

    db.add.side_effect = add
    db.refresh.side_effect = refresh
    ctx = _ctx(operator=True, user_id=9)
    with patch(
        "app.services.ai.ai_mcp_support_connections.generate_api_key",
        return_value=("mcp_sup_secret", "hash"),
    ):
        payload = create_support_connection(db, ctx, name="اتصال تست", resource="https://api.example/api/v1/ai/mcp/support")
    row = created["row"]
    assert row.key_type == SUPPORT_MCP_KEY_TYPE
    assert row.business_id is None
    assert row.mcp_tool_permissions is None
    assert SUPPORT_MCP_BEARER_PREFIX == "mcp_sup_"
    assert payload["token"].startswith(SUPPORT_MCP_BEARER_PREFIX)
    assert SUPPORT_MCP_READ_SCOPE in payload["scopes"]
    assert SUPPORT_MCP_WRITE_SCOPE in payload["scopes"]
    assert payload["channel"] == "support"
    assert payload["token_once"] is True


def test_operator_cannot_revoke_another_operators_support_connection():
    db = MagicMock()
    row = SimpleNamespace(
        id=3,
        user_id=99,
        name="دیگر",
        scopes='["ai:tools:read","ai:tools:write"]',
        created_at=datetime.utcnow(),
        expires_at=datetime.utcnow() + timedelta(days=10),
        last_used_at=None,
        revoked_at=None,
        key_type=SUPPORT_MCP_KEY_TYPE,
    )
    query = MagicMock()
    query.filter.return_value = query
    query.first.return_value = row
    db.query.return_value = query
    ctx = _ctx(operator=True, superadmin=False, user_id=9)
    with pytest.raises(ApiError) as exc:
        revoke_support_connection(db, ctx, 3)
    assert exc.value.code == "FORBIDDEN"


def test_superadmin_lists_all_support_connections():
    now = datetime.utcnow()
    rows = [
        SimpleNamespace(
            id=1,
            user_id=9,
            name="مال من",
            scopes='["ai:tools:read","ai:tools:write"]',
            created_at=now,
            expires_at=now + timedelta(days=10),
            last_used_at=None,
            revoked_at=None,
        ),
        SimpleNamespace(
            id=2,
            user_id=44,
            name="اپراتور دیگر",
            scopes='["ai:tools:read","ai:tools:write"]',
            created_at=now,
            expires_at=now + timedelta(days=10),
            last_used_at=None,
            revoked_at=None,
        ),
    ]
    db = MagicMock()
    query = MagicMock()
    query.filter.return_value = query
    query.order_by.return_value.all.return_value = rows
    db.query.side_effect = lambda model: query if model.__name__ == "ApiKey" else MagicMock(
        filter=lambda *a, **k: SimpleNamespace(all=lambda: [
            SimpleNamespace(id=9, first_name="اپراتور", last_name="یک", email="a@x.ir"),
            SimpleNamespace(id=44, first_name="اپراتور", last_name="دو", email="b@x.ir"),
        ])
    )
    items = list_support_connections(db, _ctx(superadmin=True, user_id=1))
    assert {item["id"] for item in items} == {1, 2}
    assert all(item["channel"] == "support" for item in items)
