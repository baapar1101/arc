"""Derived inverted / field indexes for tool candidate retrieval.

Registry/Manifest remain the source of truth. This module stores posting
lists only. Permissions are never encoded here.
"""
from __future__ import annotations

import hashlib
import threading
import time
from collections import defaultdict
from dataclasses import dataclass
from typing import Dict, FrozenSet, Iterable, Optional, Set, Tuple

from app.services.ai.ai_tool_manifest import get_manifest_entry, iter_manifest_names
from app.services.ai.ai_tool_spec import ToolManifestEntry
from app.services.ai.ai_tool_text import tokenize_search_text

INDEX_KIND = "inverted_keyword_v1"


@dataclass(frozen=True)
class ToolRetrievalRecord:
    name: str
    tokens: Tuple[str, ...]
    capability: str = ""
    domains: Tuple[str, ...] = ()
    namespace: str = ""
    enabled: bool = True
    deprecated: bool = False
    version: str = "1"
    schema_version: str = "1"
    search_text_hash: str = ""
    indexed_at: float = 0.0

    def is_searchable(self) -> bool:
        return bool(self.enabled) and not bool(self.deprecated)


@dataclass
class RetrievalIndexStats:
    tools: int = 0
    postings: int = 0
    capabilities: int = 0
    domains: int = 0
    namespaces: int = 0
    build_ms: float = 0.0
    memory_bytes_est: int = 0


class ToolRetrievalIndex:
    """In-process inverted index. Incremental upsert/remove. Not authorization."""

    def __init__(self) -> None:
        self._lock = threading.RLock()
        self._records: Dict[str, ToolRetrievalRecord] = {}
        self._postings: Dict[str, FrozenSet[str]] = {}
        self._by_capability: Dict[str, FrozenSet[str]] = {}
        self._by_domain: Dict[str, FrozenSet[str]] = {}
        self._by_namespace: Dict[str, FrozenSet[str]] = {}
        self._built_at: float = 0.0
        self._build_ms: float = 0.0

    def stats(self) -> RetrievalIndexStats:
        with self._lock:
            postings = sum(len(v) for v in self._postings.values())
            mem = postings * 48 + len(self._records) * 256
            return RetrievalIndexStats(
                tools=len(self._records),
                postings=len(self._postings),
                capabilities=len(self._by_capability),
                domains=len(self._by_domain),
                namespaces=len(self._by_namespace),
                build_ms=self._build_ms,
                memory_bytes_est=mem,
            )

    def get(self, name: str) -> Optional[ToolRetrievalRecord]:
        with self._lock:
            return self._records.get(name)

    def names(self) -> Set[str]:
        with self._lock:
            return set(self._records)

    def lookup_token(self, token: str) -> FrozenSet[str]:
        with self._lock:
            return self._postings.get(token, frozenset())

    def lookup_capability(self, capability: str) -> FrozenSet[str]:
        key = (capability or "").strip()
        with self._lock:
            return self._by_capability.get(key, frozenset())

    def lookup_domain(self, domain: str) -> FrozenSet[str]:
        key = (domain or "").strip()
        with self._lock:
            return self._by_domain.get(key, frozenset())

    def lookup_namespace(self, namespace: str) -> FrozenSet[str]:
        key = (namespace or "").strip()
        with self._lock:
            return self._by_namespace.get(key, frozenset())

    def rebuild_from_manifest(self, names: Optional[Iterable[str]] = None) -> RetrievalIndexStats:
        catalog = list(names) if names is not None else list(iter_manifest_names())
        return self.load_many((name, "") for name in catalog)

    def load_many(self, items: Iterable[tuple]) -> RetrievalIndexStats:
        """Bulk rebuild with mutable postings, then freeze. O(tokens) not O(N²)."""
        started = time.perf_counter()
        records: Dict[str, ToolRetrievalRecord] = {}
        postings: Dict[str, Set[str]] = defaultdict(set)
        by_cap: Dict[str, Set[str]] = defaultdict(set)
        by_domain: Dict[str, Set[str]] = defaultdict(set)
        by_ns: Dict[str, Set[str]] = defaultdict(set)
        for item in items:
            name = item[0]
            extra = item[1] if len(item) > 1 else ""
            rec = _make_record(name, extra_text=extra)
            records[rec.name] = rec
            if not rec.is_searchable():
                continue
            for token in rec.tokens:
                postings[token].add(rec.name)
            if rec.capability:
                by_cap[rec.capability].add(rec.name)
            for domain in rec.domains:
                by_domain[domain].add(rec.name)
            if rec.namespace:
                by_ns[rec.namespace].add(rec.name)
        with self._lock:
            self._records = records
            self._postings = {k: frozenset(v) for k, v in postings.items()}
            self._by_capability = {k: frozenset(v) for k, v in by_cap.items()}
            self._by_domain = {k: frozenset(v) for k, v in by_domain.items()}
            self._by_namespace = {k: frozenset(v) for k, v in by_ns.items()}
            self._built_at = time.time()
            self._build_ms = round((time.perf_counter() - started) * 1000.0, 3)
        return self.stats()

    def upsert(
        self,
        name: str,
        *,
        entry: Optional[ToolManifestEntry] = None,
        extra_text: str = "",
        enabled: Optional[bool] = None,
        deprecated: Optional[bool] = None,
        version: Optional[str] = None,
        schema_version: Optional[str] = None,
    ) -> ToolRetrievalRecord:
        with self._lock:
            return self._upsert_unlocked(
                name,
                entry=entry,
                extra_text=extra_text,
                enabled=enabled,
                deprecated=deprecated,
                version=version,
                schema_version=schema_version,
            )

    def remove(self, name: str) -> None:
        with self._lock:
            self._remove_unlocked(name)

    def disable(self, name: str) -> None:
        self._set_lifecycle(name, enabled=False, deprecated=None)

    def deprecate(self, name: str) -> None:
        self._set_lifecycle(name, enabled=None, deprecated=True)

    def enable(self, name: str) -> None:
        self._set_lifecycle(name, enabled=True, deprecated=False)

    def _set_lifecycle(
        self,
        name: str,
        *,
        enabled: Optional[bool],
        deprecated: Optional[bool],
    ) -> None:
        rec = self.get(name)
        if rec is None:
            return
        next_enabled = rec.enabled if enabled is None else bool(enabled)
        next_deprecated = rec.deprecated if deprecated is None else bool(deprecated)
        entry = get_manifest_entry(name)
        extra = ""
        if entry is None:
            extra = " ".join(rec.tokens)
            entry = ToolManifestEntry(
                domains=rec.domains,
                capability=rec.capability,
                namespace=rec.namespace,
                version=rec.version,
                schema_version=rec.schema_version,
            )
        self.upsert(
            name,
            entry=entry,
            extra_text=extra,
            enabled=next_enabled,
            deprecated=next_deprecated,
            version=rec.version,
            schema_version=rec.schema_version,
        )

    def is_stale(self, name: str, *, search_text: str, version: str, schema_version: str) -> bool:
        rec = self.get(name)
        if rec is None:
            return True
        digest = _hash_text(search_text)
        return (
            rec.search_text_hash != digest
            or rec.version != str(version)
            or rec.schema_version != str(schema_version)
        )

    def _clear_unlocked(self) -> None:
        self._records.clear()
        self._postings.clear()
        self._by_capability.clear()
        self._by_domain.clear()
        self._by_namespace.clear()

    def _remove_unlocked(self, name: str) -> None:
        rec = self._records.pop(name, None)
        if rec is None:
            return
        for token in rec.tokens:
            self._drop_from(self._postings, token, name)
        if rec.capability:
            self._drop_from(self._by_capability, rec.capability, name)
        for domain in rec.domains:
            self._drop_from(self._by_domain, domain, name)
        if rec.namespace:
            self._drop_from(self._by_namespace, rec.namespace, name)

    @staticmethod
    def _drop_from(mapping: Dict[str, FrozenSet[str]], key: str, name: str) -> None:
        bucket = mapping.get(key)
        if not bucket or name not in bucket:
            return
        updated = bucket - {name}
        if updated:
            mapping[key] = updated
        else:
            mapping.pop(key, None)

    @staticmethod
    def _add_to(mapping: Dict[str, FrozenSet[str]], key: str, name: str) -> None:
        mapping[key] = mapping.get(key, frozenset()) | {name}

    def _upsert_unlocked(
        self,
        name: str,
        *,
        entry: Optional[ToolManifestEntry] = None,
        extra_text: str = "",
        enabled: Optional[bool] = None,
        deprecated: Optional[bool] = None,
        version: Optional[str] = None,
        schema_version: Optional[str] = None,
    ) -> ToolRetrievalRecord:
        name = (name or "").strip()
        if not name:
            raise ValueError("tool name required")
        self._remove_unlocked(name)
        rec = _make_record(
            name,
            entry=entry,
            extra_text=extra_text,
            enabled=enabled,
            deprecated=deprecated,
            version=version,
            schema_version=schema_version,
        )
        self._records[name] = rec
        if rec.is_searchable():
            for token in rec.tokens:
                self._add_to(self._postings, token, name)
            if rec.capability:
                self._add_to(self._by_capability, rec.capability, name)
            for domain in rec.domains:
                self._add_to(self._by_domain, domain, name)
            if rec.namespace:
                self._add_to(self._by_namespace, rec.namespace, name)
        return rec


def _make_record(
    name: str,
    *,
    entry: Optional[ToolManifestEntry] = None,
    extra_text: str = "",
    enabled: Optional[bool] = None,
    deprecated: Optional[bool] = None,
    version: Optional[str] = None,
    schema_version: Optional[str] = None,
) -> ToolRetrievalRecord:
    resolved = entry if entry is not None else get_manifest_entry(name)
    text = _index_document(name, resolved, extra_text)
    tokens = tokenize_search_text(text)
    cap = (resolved.capability if resolved else "") or ""
    domains = tuple(resolved.domains) if resolved else ()
    ns = (resolved.namespace if resolved else "") or (cap.split(".")[0] if cap else "")
    return ToolRetrievalRecord(
        name=name,
        tokens=tokens,
        capability=cap,
        domains=domains,
        namespace=ns,
        enabled=resolved.enabled if enabled is None and resolved else (
            True if enabled is None else bool(enabled)
        ),
        deprecated=resolved.deprecated if deprecated is None and resolved else (
            False if deprecated is None else bool(deprecated)
        ),
        version=str(version or (resolved.version if resolved else "1") or "1"),
        schema_version=str(
            schema_version or (resolved.schema_version if resolved else "1") or "1"
        ),
        search_text_hash=_hash_text(text),
        indexed_at=time.time(),
    )


def _index_document(name: str, entry: Optional[ToolManifestEntry], extra_text: str) -> str:
    if entry is not None:
        base = entry.search_text(name, extra_text or "")
    else:
        base = " ".join(part for part in (name, extra_text) if part)
    return base


def _hash_text(text: str) -> str:
    return hashlib.sha256((text or "").encode("utf-8")).hexdigest()[:16]


_GLOBAL = ToolRetrievalIndex()
_ENSURED = False
_ENSURE_LOCK = threading.Lock()


def get_retrieval_index() -> ToolRetrievalIndex:
    global _ENSURED
    with _ENSURE_LOCK:
        if not _ENSURED:
            _GLOBAL.rebuild_from_manifest()
            _ENSURED = True
        return _GLOBAL


def reset_retrieval_index_for_tests() -> None:
    global _ENSURED
    with _ENSURE_LOCK:
        _GLOBAL._clear_unlocked()
        _GLOBAL._build_ms = 0.0
        _ENSURED = False
