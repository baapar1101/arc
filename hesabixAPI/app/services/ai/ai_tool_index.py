"""ایندکس مشتق‌شده از Tool Manifest — منبع خواندن Intent / Alias / Write.

Registry هنگام register این ایندکس را روی AIFunction کپی می‌کند.
خود این ماژول Registry را import نمی‌کند.
"""
from __future__ import annotations

from dataclasses import dataclass, replace
from typing import Any, Dict, FrozenSet, Optional, Tuple

from app.services.ai.ai_tool_capability import (
    namespace_for_capability,
    resolve_tool_capability,
)
from app.services.ai.ai_tool_manifest import TOOL_MANIFEST, get_manifest_entry
from app.services.ai.ai_tool_spec import (
    REGISTRY_CATEGORY_TO_DOMAINS,
    TOOL_DOMAINS,
    ToolManifestEntry,
    infer_side_effect,
)


@dataclass(frozen=True)
class ToolIndex:
    category_tools: Dict[str, FrozenSet[str]]
    core_names: FrozenSet[str]
    intent_write_names: FrozenSet[str]
    always_confirm_names: FrozenSet[str]
    companions: Dict[str, FrozenSet[str]]
    aliases: Dict[str, Tuple[str, ...]]
    side_effects: Dict[str, str]
    capabilities: Dict[str, str]


_INDEX: Optional[ToolIndex] = None


def _build_index() -> ToolIndex:
    by_domain: Dict[str, set[str]] = {domain: set() for domain in sorted(TOOL_DOMAINS)}
    core: set[str] = set()
    writes: set[str] = set()
    confirm: set[str] = set()
    companions: Dict[str, FrozenSet[str]] = {}
    aliases: Dict[str, Tuple[str, ...]] = {}
    side_effects: Dict[str, str] = {}
    capabilities: Dict[str, str] = {}
    for name in TOOL_MANIFEST:
        entry = get_manifest_entry(name)
        if entry is None:
            continue
        for domain in entry.domains:
            if domain in by_domain:
                by_domain[domain].add(name)
        if entry.is_core:
            core.add(name)
        if entry.intent_write:
            writes.add(name)
        if entry.always_confirm:
            confirm.add(name)
        if entry.companion_tools:
            companions[name] = frozenset(entry.companion_tools)
        if entry.aliases:
            aliases[name] = entry.aliases
        side_effects[name] = entry.side_effect
        capabilities[name] = entry.capability
    return ToolIndex(
        category_tools={k: frozenset(v) for k, v in by_domain.items()},
        core_names=frozenset(core),
        intent_write_names=frozenset(writes),
        always_confirm_names=frozenset(confirm),
        companions=companions,
        aliases=aliases,
        side_effects=side_effects,
        capabilities=capabilities,
    )


def get_tool_index() -> ToolIndex:
    global _INDEX
    if _INDEX is None:
        _INDEX = _build_index()
    return _INDEX


def infer_manifest_entry(
    name: str,
    *,
    category: Optional[str] = None,
    requires_approval: bool = False,
    risk_level: str = "safe",
    is_agent_internal: bool = False,
) -> ToolManifestEntry:
    """Metadata حداقلی وقتی Tool در Manifest نیست — نباید مسیر عادی ثبت باشد."""
    domains = REGISTRY_CATEGORY_TO_DOMAINS.get(category or "", ("misc",))
    intent_write = bool(requires_approval) and not is_agent_internal
    always_confirm = (risk_level or "") == "high"
    capability = resolve_tool_capability(name, domains)
    return ToolManifestEntry(
        domains=domains,
        capability=capability,
        namespace=namespace_for_capability(capability),
        intent_write=intent_write,
        always_confirm=always_confirm,
        side_effect=infer_side_effect(
            name, intent_write=intent_write, always_confirm=always_confirm
        ),
        permission_policy="unspecified",
    )


def bind_manifest(func: Any) -> Any:
    """کپی Metadata Manifest روی AIFunction. فیلدهای امنیتی ثبت‌شده حفظ می‌شوند."""
    entry = get_manifest_entry(func.name)
    if entry is None:
        entry = infer_manifest_entry(
            func.name,
            category=getattr(func, "category", None),
            requires_approval=bool(getattr(func, "requires_approval", False)),
            risk_level=str(getattr(func, "risk_level", "safe") or "safe"),
            is_agent_internal=bool(getattr(func, "is_agent_internal", False)),
        )
    updates = {
        "domains": entry.domains,
        "capability": entry.capability,
        "namespace": entry.namespace,
        "aliases": entry.aliases,
        "keywords": entry.keywords,
        "examples": entry.examples,
        "companion_tools": entry.companion_tools,
        "is_core": entry.is_core,
        "intent_write": entry.intent_write,
        "always_confirm": entry.always_confirm or str(getattr(func, "risk_level", "")) == "high",
        "side_effect": entry.side_effect,
        "permission_policy": entry.permission_policy,
        "enabled": entry.enabled,
        "deprecated": entry.deprecated,
        "replacement": entry.replacement,
        "version": entry.version,
        "schema_version": entry.schema_version,
    }
    try:
        return replace(func, **updates)
    except TypeError:
        for key, value in updates.items():
            setattr(func, key, value)
        return func
