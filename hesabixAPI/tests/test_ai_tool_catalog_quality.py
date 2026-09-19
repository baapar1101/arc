"""Phase 4 — catalog permission and metadata hardening."""
from __future__ import annotations

from types import SimpleNamespace

from app.services.ai.ai_permission_policy import (
    ALLOWED_EMPTY_PERMISSION_POLICIES,
    catalog_permission_allows,
    permission_policy_for_name,
)
from app.services.ai.ai_tool_capability import TOOL_CAPABILITIES, resolve_tool_capability
from app.services.ai.ai_tool_catalog_quality import (
    MUTATING_SIDE_EFFECTS,
    audit_catalog,
    catalog_completeness,
    parse_registered_tool_fields,
)
from app.services.ai.ai_tool_manifest import get_manifest_entry, iter_manifest_names
from app.services.ai.ai_tool_security import (
    QueryMutation,
    ToolSecurityClass,
    classify_query_mutation,
    classify_tool_security,
)


def test_manifest_and_registry_identities_match():
    parsed = parse_registered_tool_fields()
    manifested = set(iter_manifest_names())
    assert set(parsed) == manifested
    assert len(parsed) == 180
    assert len(parsed) == len(set(parsed))


def test_all_capabilities_are_granular_and_valid():
    for name in iter_manifest_names():
        entry = get_manifest_entry(name)
        assert entry is not None
        cap = resolve_tool_capability(name, entry.domains)
        assert cap == entry.capability
        assert cap in TOOL_CAPABILITIES
        assert "." in cap


def test_search_representation_exists_for_every_tool():
    parsed = parse_registered_tool_fields()
    for name in iter_manifest_names():
        entry = get_manifest_entry(name)
        assert entry is not None
        text = entry.search_text(name, parsed.get(name, {}).get("description") or "")
        assert name in text
        assert entry.capability in text


def test_mutating_tools_are_classified():
    parsed = parse_registered_tool_fields()
    for name, fields in parsed.items():
        entry = get_manifest_entry(name)
        assert entry is not None
        if fields.get("is_agent_internal"):
            continue
        if fields.get("is_readonly") is False or fields.get("requires_approval"):
            assert entry.side_effect in MUTATING_SIDE_EFFECTS or entry.intent_write, name
        if name.startswith("delete_"):
            assert entry.side_effect == "delete"


def test_upsert_memory_entry_is_write():
    entry = get_manifest_entry("upsert_memory_entry")
    assert entry is not None
    assert entry.side_effect == "write"
    assert entry.intent_write is True
    assert classify_tool_security("upsert_memory_entry") == ToolSecurityClass.WRITE
    assert classify_query_mutation("یادت باشه اسم من علی است") == QueryMutation.WRITE
    parsed = parse_registered_tool_fields()["upsert_memory_entry"]
    assert parsed["is_readonly"] is False


def test_critical_tools_have_permission_metadata():
    parsed = parse_registered_tool_fields()
    required = {
        "delete_invoice": ["invoices.write"],
        "create_invoice": ["invoices.write"],
        "export_business_data": ["reports.read"],
        "execute_workflow": ["workflows.write"],
        "invoke_business_connector": ["settings.view"],
        "get_wallet_overview": ["wallet.view"],
    }
    for name, expected in required.items():
        perms = parsed[name]["required_permissions"] or []
        assert perms, name
        for item in expected:
            assert item in perms


def test_empty_permission_is_explicit_policy_or_assigned():
    rows = audit_catalog()
    missing = [row["name"] for row in rows if row["permission_status"] == "missing"]
    assert missing == []
    empty_ok = [
        row for row in rows
        if not row["required_permissions"]
    ]
    for row in empty_ok:
        assert row["permission_policy"] in ALLOWED_EMPTY_PERMISSION_POLICIES


def test_unspecified_empty_permission_is_fail_closed():
    fn = SimpleNamespace(
        name="mystery_export",
        required_permissions=[],
        permission_policy="unspecified",
    )
    ctx = SimpleNamespace()
    assert catalog_permission_allows(fn, ctx, 1) is False
    fn.permission_policy = "handler"
    assert catalog_permission_allows(fn, ctx, 1) is True


def test_handler_and_self_scoped_policies():
    assert permission_policy_for_name("query_business_data") == "handler"
    assert permission_policy_for_name("upsert_memory_entry") == "self_scoped"
    assert permission_policy_for_name("spawn_subagent") == "agent_internal"
    assert permission_policy_for_name("get_business_info") == "user_context"


def test_catalog_completeness_gates():
    stats = catalog_completeness()
    assert stats["total"] == 180
    assert stats["missing_permissions"] == 0
    assert stats["missing_side_effect"] == 0
    assert stats["missing_domain"] == 0
    assert stats["missing_capability"] == 0
    assert stats["missing_search_text"] == 0
    assert stats["missing_description"] == 0
    assert stats["complete_metadata"] >= 40
