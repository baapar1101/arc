"""Schema Loading — independent of Tool Discovery.

Discovery chooses names. This module builds/caches JSON schemas for those names.

Schema cache is not an authorization cache.
"""
from __future__ import annotations

import copy
import json
import threading
from dataclasses import dataclass, field
from typing import (
    AbstractSet,
    Any,
    Dict,
    List,
    Optional,
    Protocol,
    Sequence,
    Tuple,
)

from app.services.ai.ai_context_budget import estimate_text_tokens


class SchemaSource(Protocol):
    def schema_version_for(self, name: str) -> str: ...

    def build_openai_tool_definition(self, name: str) -> Optional[Dict[str, Any]]: ...


@dataclass
class SchemaRoundStats:
    iteration: int = 0
    initial_schema_count: int = 0
    initial_schema_tokens: int = 0
    new_schema_count: int = 0
    new_schema_tokens: int = 0
    repeated_schema_count: int = 0
    repeated_schema_tokens: int = 0
    wire_schema_count: int = 0
    wire_schema_tokens: int = 0
    construction_hits: int = 0
    construction_misses: int = 0

    def to_dict(self) -> Dict[str, int]:
        return {
            "iteration": self.iteration,
            "initial_schema_count": self.initial_schema_count,
            "initial_schema_tokens": self.initial_schema_tokens,
            "new_schema_count": self.new_schema_count,
            "new_schema_tokens": self.new_schema_tokens,
            "repeated_schema_count": self.repeated_schema_count,
            "repeated_schema_tokens": self.repeated_schema_tokens,
            "wire_schema_count": self.wire_schema_count,
            "wire_schema_tokens": self.wire_schema_tokens,
            "construction_hits": self.construction_hits,
            "construction_misses": self.construction_misses,
        }


@dataclass
class ToolContextState:
    """Per-agent-run loaded schemas. Not an authorization set."""

    loaded_versions: Dict[str, str] = field(default_factory=dict)
    payloads: Dict[str, Dict[str, Any]] = field(default_factory=dict)
    order: List[str] = field(default_factory=list)
    available_authorized: Tuple[str, ...] = ()
    rounds: List[SchemaRoundStats] = field(default_factory=list)
    construction_hits: int = 0
    construction_misses: int = 0

    @property
    def loaded_tools(self) -> Tuple[str, ...]:
        return tuple(self.order)

    def offered_names(self) -> AbstractSet[str]:
        return set(self.order)


@dataclass(frozen=True)
class SchemaLoadResult:
    definitions: Tuple[Dict[str, Any], ...]
    newly_loaded: Tuple[str, ...]
    reused: Tuple[str, ...]
    skipped_unauthorized: Tuple[str, ...]
    stats: SchemaRoundStats
    state: ToolContextState

    def names(self) -> List[str]:
        return [
            (item.get("function") or {}).get("name")
            for item in self.definitions
            if (item.get("function") or {}).get("name")
        ]


class ToolSchemaCache:
    """Process-wide construction cache. Keyed by (name, schema_version).

    Cached payload is never treated as authorized.
    """

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._store: Dict[Tuple[str, str], Dict[str, Any]] = {}
        self.hits = 0
        self.misses = 0

    def get(self, name: str, version: str) -> Optional[Dict[str, Any]]:
        with self._lock:
            payload = self._store.get((name, version))
            if payload is None:
                self.misses += 1
                return None
            self.hits += 1
            return copy.deepcopy(payload)

    def put(self, name: str, version: str, definition: Dict[str, Any]) -> Dict[str, Any]:
        cloned = copy.deepcopy(definition)
        with self._lock:
            self._store[(name, version)] = cloned
        return copy.deepcopy(cloned)

    def invalidate(self, name: str, version: Optional[str] = None) -> None:
        with self._lock:
            if version is None:
                for key in [k for k in self._store if k[0] == name]:
                    del self._store[key]
            else:
                self._store.pop((name, version), None)

    def clear(self) -> None:
        with self._lock:
            self._store.clear()
            self.hits = 0
            self.misses = 0

    def size(self) -> int:
        with self._lock:
            return len(self._store)


_CACHE = ToolSchemaCache()


def get_schema_cache() -> ToolSchemaCache:
    return _CACHE


def reset_schema_cache_for_tests() -> None:
    _CACHE.clear()


def estimate_schema_tokens(definition: Optional[Dict[str, Any]]) -> int:
    if not definition:
        return 0
    text = json.dumps(definition, ensure_ascii=False, separators=(",", ":"))
    return estimate_text_tokens(None, text)


def estimate_schemas_tokens(definitions: Sequence[Dict[str, Any]]) -> int:
    return sum(estimate_schema_tokens(item) for item in definitions)


class RegistrySchemaSource:
    """Live registry adapter. Import is lazy so unit tests need not load Registry."""

    def __init__(self, registry: Any = None) -> None:
        self._registry = registry

    def _reg(self) -> Any:
        if self._registry is not None:
            return self._registry
        from app.services.ai.function_registry import registry

        return registry

    def schema_version_for(self, name: str) -> str:
        return str(self._reg().schema_version_for(name) or "1")

    def build_openai_tool_definition(self, name: str) -> Optional[Dict[str, Any]]:
        return self._reg().build_openai_tool_definition(name)


def load_tool_schemas(
    requested_names: Sequence[str],
    *,
    authorized_names: AbstractSet[str],
    source: SchemaSource,
    state: Optional[ToolContextState] = None,
    max_total: Optional[int] = None,
    iteration: int = 0,
) -> SchemaLoadResult:
    """Load JSON schemas for requested names.

    Authorization is checked on every call. Cache hit does not grant access.
    Already-loaded names with the same schema_version are reused (dedup).
    Version change forces rebuild. State is append-only for still-authorized tools.
    """
    ctx = state or ToolContextState()
    authorized = {n for n in authorized_names if n}
    ctx.available_authorized = tuple(sorted(authorized))
    requested = [n for n in requested_names if n]
    skipped: List[str] = []
    newly: List[str] = []
    reused: List[str] = []
    hits = 0
    misses = 0

    def _can_add() -> bool:
        if max_total is None:
            return True
        return len(ctx.order) < int(max_total)

    for name in requested:
        if name not in authorized:
            skipped.append(name)
            continue
        version = str(source.schema_version_for(name) or "1")
        loaded_ver = ctx.loaded_versions.get(name)
        if loaded_ver == version and name in ctx.payloads:
            reused.append(name)
            continue
        if not _can_add() and name not in ctx.payloads:
            continue
        cached = _CACHE.get(name, version)
        if cached is not None:
            payload = cached
            hits += 1
        else:
            built = source.build_openai_tool_definition(name)
            if not built:
                skipped.append(name)
                continue
            payload = _CACHE.put(name, version, built)
            misses += 1
        ctx.payloads[name] = payload
        ctx.loaded_versions[name] = version
        if name not in ctx.order:
            ctx.order.append(name)
        newly.append(name)

    wire_names = [n for n in ctx.order if n in authorized]
    definitions = tuple(
        copy.deepcopy(ctx.payloads[n]) for n in wire_names if n in ctx.payloads
    )
    new_set = set(newly)
    new_defs = [ctx.payloads[n] for n in newly if n in ctx.payloads]
    repeated_defs = [
        ctx.payloads[n] for n in wire_names if n not in new_set and n in ctx.payloads
    ]
    is_first = not ctx.rounds
    new_tokens = estimate_schemas_tokens(new_defs)
    repeated_tokens = estimate_schemas_tokens(repeated_defs)
    wire_tokens = estimate_schemas_tokens(definitions)
    stats = SchemaRoundStats(
        iteration=iteration,
        initial_schema_count=0,
        initial_schema_tokens=0,
        new_schema_count=len(newly),
        new_schema_tokens=new_tokens,
        repeated_schema_count=len(repeated_defs),
        repeated_schema_tokens=repeated_tokens,
        wire_schema_count=len(definitions),
        wire_schema_tokens=wire_tokens,
        construction_hits=hits,
        construction_misses=misses,
    )
    if is_first:
        stats.initial_schema_count = len(definitions)
        stats.initial_schema_tokens = wire_tokens
    else:
        stats.initial_schema_count = ctx.rounds[0].initial_schema_count
        stats.initial_schema_tokens = ctx.rounds[0].initial_schema_tokens
    ctx.construction_hits += hits
    ctx.construction_misses += misses
    ctx.rounds.append(stats)
    return SchemaLoadResult(
        definitions=definitions,
        newly_loaded=tuple(newly),
        reused=tuple(reused),
        skipped_unauthorized=tuple(skipped),
        stats=stats,
        state=ctx,
    )


def hydrate_state_from_definitions(
    definitions: Sequence[Dict[str, Any]],
    *,
    source: Optional[SchemaSource] = None,
    state: Optional[ToolContextState] = None,
) -> ToolContextState:
    """When a caller already has schemas (keep path), record them as loaded."""
    ctx = state or ToolContextState()
    src = source
    for item in definitions:
        name = (item.get("function") or {}).get("name")
        if not name:
            continue
        version = str(src.schema_version_for(name) or "1") if src else "1"
        ctx.payloads[name] = copy.deepcopy(dict(item))
        ctx.loaded_versions[name] = version
        if name not in ctx.order:
            ctx.order.append(name)
        _CACHE.put(name, version, dict(item))
    return ctx


def record_wire_repeat(state: ToolContextState, *, iteration: int) -> SchemaRoundStats:
    """Same loaded schemas sent again on the wire (typical agent iteration)."""
    defs = [state.payloads[n] for n in state.order if n in state.payloads]
    wire_tokens = estimate_schemas_tokens(defs)
    initial_count = state.rounds[0].initial_schema_count if state.rounds else len(defs)
    initial_tokens = state.rounds[0].initial_schema_tokens if state.rounds else wire_tokens
    stats = SchemaRoundStats(
        iteration=iteration,
        initial_schema_count=initial_count,
        initial_schema_tokens=initial_tokens,
        new_schema_count=0,
        new_schema_tokens=0,
        repeated_schema_count=len(defs),
        repeated_schema_tokens=wire_tokens,
        wire_schema_count=len(defs),
        wire_schema_tokens=wire_tokens,
        construction_hits=0,
        construction_misses=0,
    )
    state.rounds.append(stats)
    return stats


def schema_round_totals(state: ToolContextState) -> Dict[str, int]:
    """Aggregate construction vs wire schema tokens across agent iterations."""
    rounds = state.rounds
    if not rounds:
        return {
            "iterations": 0,
            "initial_schema_tokens": 0,
            "additional_schema_tokens": 0,
            "total_wire_schema_tokens": 0,
            "total_new_schema_tokens": 0,
            "construction_hits": state.construction_hits,
            "construction_misses": state.construction_misses,
        }
    additional = sum(r.new_schema_tokens for r in rounds[1:])
    wire_total = sum(r.wire_schema_tokens for r in rounds)
    return {
        "iterations": len(rounds),
        "initial_schema_tokens": rounds[0].initial_schema_tokens,
        "additional_schema_tokens": additional,
        "total_wire_schema_tokens": wire_total,
        "total_new_schema_tokens": sum(r.new_schema_tokens for r in rounds),
        "construction_hits": state.construction_hits,
        "construction_misses": state.construction_misses,
    }


def is_tool_schema_offered(offered_names: Optional[AbstractSet[str]], name: str) -> bool:
    """Execution guard: a tool call is allowed only if its schema was loaded.

    None means schema tracking has not started (legacy callers).
    An empty set means zero schemas were offered — reject every call.
    Cache membership is never consulted here.
    """
    if offered_names is None:
        return True
    return bool(name) and name in offered_names
