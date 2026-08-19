"""تضمین منبع حقیقت واحد Metadata ابزارها (Phase 1)."""
from __future__ import annotations

import re
from pathlib import Path
from types import SimpleNamespace

from app.services.ai.ai_execution_policy import HIGH_RISK_ALWAYS_APPROVE, is_high_risk_write
from app.services.ai.ai_tool_index import bind_manifest, get_tool_index
from app.services.ai.ai_tool_intent import (
    _CATEGORY_TOOLS,
    _CORE_TOOL_NAMES,
    _WRITE_TOOLS,
    select_tool_names,
)
from app.services.ai.ai_tool_manifest import get_manifest_entry, iter_manifest_names
from app.services.ai.ai_tool_rank import TOOL_ALIASES
from app.services.ai.ai_tool_spec import TOOL_DOMAINS
from app.services.ai.ai_write_guard import WRITE_FUNCTIONS, is_write_function

_AI_DIR = Path(__file__).resolve().parents[1] / "app" / "services" / "ai"
_NAME_RE = re.compile(r'AIFunction\s*\(\s*name\s*=\s*["\']([^"\']+)["\']')


def _registered_names_from_source() -> set[str]:
    names: set[str] = set()
    files = [_AI_DIR / "function_registry.py", *_AI_DIR.glob("ai_function_extensions*.py")]
    for path in files:
        names.update(_NAME_RE.findall(path.read_text(encoding="utf-8")))
    return names


def test_manifest_covers_every_registered_tool_name():
    registered = _registered_names_from_source()
    manifested = set(iter_manifest_names())
    assert registered == manifested
    assert len(registered) == 180


def test_every_manifest_domain_is_known():
    unknown = []
    for name in iter_manifest_names():
        entry = get_manifest_entry(name)
        assert entry is not None
        for domain in entry.domains:
            if domain not in TOOL_DOMAINS:
                unknown.append((name, domain))
        assert entry.capability
        assert entry.side_effect
    assert unknown == []


def test_index_matches_intent_exports():
    idx = get_tool_index()
    assert idx.core_names == _CORE_TOOL_NAMES
    assert idx.intent_write_names == _WRITE_TOOLS
    assert idx.category_tools == _CATEGORY_TOOLS
    assert "query_business_data" in idx.core_names
    assert "create_invoice" in idx.intent_write_names
    assert "search_invoices" in idx.category_tools["financial"]


def test_aliases_come_from_manifest():
    assert TOOL_ALIASES["create_invoice"] == ("فاکتور جدید", "ثبت فاکتور", "بزن فاکتور")
    entry = get_manifest_entry("create_invoice")
    assert entry is not None
    assert entry.aliases == TOOL_ALIASES["create_invoice"]
    assert entry.intent_write is True
    assert entry.side_effect == "write"


def test_delete_tools_have_delete_side_effect():
    entry = get_manifest_entry("delete_invoice")
    assert entry is not None
    assert entry.side_effect == "delete"
    assert entry.always_confirm is True
    assert "delete_invoice" in HIGH_RISK_ALWAYS_APPROVE


def test_write_fallback_set_is_manifest_derived():
    assert "create_invoice" in WRITE_FUNCTIONS
    assert "delete_invoice" in WRITE_FUNCTIONS
    assert "upsert_memory_entry" in WRITE_FUNCTIONS
    assert "update_user_memory" not in WRITE_FUNCTIONS
    assert is_write_function("create_invoice") is True


def test_bind_preserves_handler_security_flags():
    fn = SimpleNamespace(
        name="create_invoice",
        description="x",
        requires_approval=True,
        risk_level="medium",
        is_readonly=False,
        is_agent_internal=False,
        category="invoices",
    )
    bound = bind_manifest(fn)
    assert bound.requires_approval is True
    assert bound.risk_level == "medium"
    assert bound.is_readonly is False
    assert bound.intent_write is True
    assert bound.domains == ("financial",)
    assert "search_persons" in bound.companion_tools


def test_high_risk_uses_always_confirm_on_bound_function():
    delete_fn = bind_manifest(
        SimpleNamespace(
            name="delete_invoice",
            description="x",
            requires_approval=True,
            risk_level="high",
            is_readonly=False,
            is_agent_internal=False,
            category="invoices",
        )
    )
    create_fn = bind_manifest(
        SimpleNamespace(
            name="create_invoice",
            description="x",
            requires_approval=True,
            risk_level="medium",
            is_readonly=False,
            is_agent_internal=False,
            category="invoices",
        )
    )

    class _Reg:
        def __init__(self, fns):
            self._fns = fns

        def get_function(self, name):
            return self._fns.get(name)

    reg = _Reg({"delete_invoice": delete_fn, "create_invoice": create_fn})
    assert delete_fn.always_confirm is True
    assert is_high_risk_write("delete_invoice", reg) is True
    assert is_high_risk_write("create_invoice", reg) is False


def test_intent_still_selects_core_and_writes():
    selected = select_tool_names(
        {"query_business_data", "create_person", "search_invoices"},
        "یک مشتری به نام علی اضافه کن",
    )
    assert "create_person" in selected
    assert "query_business_data" in selected
