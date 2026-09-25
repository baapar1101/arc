"""Phase 7 — progressive schema loading, independent of Discovery."""
from __future__ import annotations

import pytest

from app.services.ai.ai_tool_schema import (
    hydrate_state_from_definitions,
    is_tool_schema_offered,
    load_tool_schemas,
    record_wire_repeat,
    reset_schema_cache_for_tests,
    schema_round_totals,
)


class _FakeSource:
    def __init__(self) -> None:
        self.versions = {"alpha": "1", "bravo": "1", "charlie": "1", "delta": "1"}
        self.builds = 0

    def schema_version_for(self, name: str) -> str:
        return self.versions.get(name, "1")

    def build_openai_tool_definition(self, name: str):
        self.builds += 1
        return {
            "type": "function",
            "function": {
                "name": name,
                "description": f"tool {name}",
                "parameters": {"type": "object", "properties": {name: {"type": "string"}}},
            },
        }


@pytest.fixture(autouse=True)
def _reset_schema_cache():
    reset_schema_cache_for_tests()
    yield
    reset_schema_cache_for_tests()


def test_schema_generated_once_when_reloaded():
    source = _FakeSource()
    authorized = {"alpha", "bravo"}
    first = load_tool_schemas(["alpha"], authorized_names=authorized, source=source)
    second = load_tool_schemas(
        ["alpha"],
        authorized_names=authorized,
        source=source,
        state=first.state,
        iteration=1,
    )
    assert source.builds == 1
    assert second.newly_loaded == ()
    assert "alpha" in second.reused
    assert second.names() == ["alpha"]


def test_only_new_tool_is_constructed():
    source = _FakeSource()
    authorized = {"alpha", "bravo", "charlie", "delta"}
    first = load_tool_schemas(
        ["alpha", "bravo", "charlie"],
        authorized_names=authorized,
        source=source,
    )
    builds_after_first = source.builds
    second = load_tool_schemas(
        ["bravo", "charlie", "delta"],
        authorized_names=authorized,
        source=source,
        state=first.state,
        iteration=1,
    )
    assert second.newly_loaded == ("delta",)
    assert set(second.reused) >= {"bravo", "charlie"}
    assert source.builds == builds_after_first + 1
    assert second.names() == ["alpha", "bravo", "charlie", "delta"]


def test_schema_version_change_reloads():
    source = _FakeSource()
    authorized = {"alpha"}
    first = load_tool_schemas(["alpha"], authorized_names=authorized, source=source)
    source.versions["alpha"] = "2"
    second = load_tool_schemas(
        ["alpha"],
        authorized_names=authorized,
        source=source,
        state=first.state,
        iteration=1,
    )
    assert "alpha" in second.newly_loaded
    assert source.builds == 2
    assert first.state.loaded_versions["alpha"] == "2"


def test_cached_schema_is_not_authorization():
    source = _FakeSource()
    first = load_tool_schemas(
        ["alpha", "bravo"],
        authorized_names={"alpha", "bravo"},
        source=source,
    )
    denied = load_tool_schemas(
        ["alpha", "bravo"],
        authorized_names={"alpha"},
        source=source,
        state=first.state,
        iteration=1,
    )
    assert "bravo" in denied.skipped_unauthorized or "bravo" not in denied.names()
    assert "bravo" not in denied.names()
    assert "alpha" in denied.names()


def test_empty_discovery_loads_no_schemas():
    source = _FakeSource()
    result = load_tool_schemas([], authorized_names={"alpha"}, source=source)
    assert result.definitions == ()
    assert result.names() == []
    assert source.builds == 0


def test_hydrate_keep_path_records_loaded_tools():
    defs = [
        {
            "type": "function",
            "function": {"name": "alpha", "description": "a", "parameters": {}},
        }
    ]
    state = hydrate_state_from_definitions(defs)
    assert "alpha" in state.loaded_tools


def test_max_total_caps_progressive_initial_set():
    source = _FakeSource()
    result = load_tool_schemas(
        ["alpha", "bravo", "charlie", "delta"],
        authorized_names={"alpha", "bravo", "charlie", "delta"},
        source=source,
        max_total=2,
    )
    assert len(result.names()) == 2
    assert result.names() == ["alpha", "bravo"]


def test_process_cache_avoids_rebuild_across_states():
    source = _FakeSource()
    load_tool_schemas(["alpha"], authorized_names={"alpha"}, source=source)
    builds = source.builds
    load_tool_schemas(["alpha"], authorized_names={"alpha"}, source=source)
    assert source.builds == builds


def test_process_cache_hit_is_still_unauthorized_without_policy():
    source = _FakeSource()
    load_tool_schemas(["bravo"], authorized_names={"bravo"}, source=source)
    denied = load_tool_schemas(["bravo"], authorized_names={"alpha"}, source=source)
    assert "bravo" not in denied.names()
    assert "bravo" in denied.skipped_unauthorized


def test_record_wire_repeat_does_not_rebuild_schema():
    source = _FakeSource()
    first = load_tool_schemas(["alpha"], authorized_names={"alpha"}, source=source)
    builds = source.builds
    stats = record_wire_repeat(first.state, iteration=2)
    assert source.builds == builds
    assert stats.new_schema_count == 0
    assert stats.repeated_schema_count == 1
    totals = schema_round_totals(first.state)
    assert totals["iterations"] == 2
    assert totals["additional_schema_tokens"] == 0


def test_unoffered_tool_call_is_rejected():
    assert is_tool_schema_offered({"alpha"}, "alpha") is True
    assert is_tool_schema_offered({"alpha"}, "bravo") is False
    assert is_tool_schema_offered(set(), "alpha") is False
    assert is_tool_schema_offered(None, "bravo") is True


def test_empty_authorized_set_loads_nothing():
    source = _FakeSource()
    result = load_tool_schemas(["alpha"], authorized_names=set(), source=source)
    assert result.names() == []
    assert "alpha" in result.skipped_unauthorized
    assert source.builds == 0
