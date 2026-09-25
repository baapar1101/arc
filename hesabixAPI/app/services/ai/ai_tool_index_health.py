"""Index freshness and consistency — derived from Manifest, not permissions."""
from __future__ import annotations

import time
from typing import Iterable, Optional, Set, Tuple

from app.services.ai.ai_tool_manifest import get_manifest_entry
from app.services.ai.ai_tool_retrieval_index import ToolRetrievalIndex, get_retrieval_index
from app.services.ai.ai_tool_text import tokenize_search_text

FALLBACK_EMPTY = "empty"
FALLBACK_LOW = "low_candidate_quality"
FALLBACK_STALE = "stale_index"
FALLBACK_ERROR = "index_error"
FALLBACK_CONSISTENCY = "index_inconsistency"
FALLBACK_UNKNOWN = "unknown"
# Legacy aliases from Phase 12 — same canonical values after mapping.
FALLBACK_DISABLED = FALLBACK_ERROR
FALLBACK_NORMALIZATION = FALLBACK_ERROR
FALLBACK_EMPTY_INDEX = FALLBACK_EMPTY
FALLBACK_LOW_SIGNAL = FALLBACK_LOW

FALLBACK_REASONS = (
    FALLBACK_EMPTY,
    FALLBACK_LOW,
    FALLBACK_STALE,
    FALLBACK_ERROR,
    FALLBACK_CONSISTENCY,
    FALLBACK_UNKNOWN,
)

_REASON_ALIASES = {
    "empty_index": FALLBACK_EMPTY,
    "low_candidate_recall_signal": FALLBACK_LOW,
    "disabled_tool": FALLBACK_ERROR,
    "normalization": FALLBACK_ERROR,
}


def canonical_fallback_reason(reason: Optional[str]) -> str:
    raw = (reason or "").strip() or FALLBACK_UNKNOWN
    return _REASON_ALIASES.get(raw, raw if raw in FALLBACK_REASONS else FALLBACK_UNKNOWN)


def refresh_stale_authorized(
    authorized: Iterable[str],
    index: Optional[ToolRetrievalIndex] = None,
) -> Tuple[int, Optional[str]]:
    """Re-upsert stale manifest rows. Returns (refreshed_count, error_reason)."""
    store = index or get_retrieval_index()
    refreshed = 0
    try:
        for name in authorized:
            entry = get_manifest_entry(name)
            if entry is None:
                continue
            text = entry.search_text(name, "")
            if store.is_stale(
                name,
                search_text=text,
                version=entry.version,
                schema_version=entry.schema_version,
            ):
                store.upsert(name, entry=entry)
                refreshed += 1
        return refreshed, None
    except Exception:
        return refreshed, FALLBACK_STALE


def index_consistency_ok(
    authorized: Iterable[str],
    index: Optional[ToolRetrievalIndex] = None,
) -> bool:
    """True when every enabled manifest tool in the authorized set is indexed."""
    store = index or get_retrieval_index()
    for name in authorized:
        entry = get_manifest_entry(name)
        if entry is None or not entry.enabled or entry.deprecated:
            continue
        rec = store.get(name)
        if rec is None or not rec.is_searchable():
            return False
    return True


def disabled_authorized_in_index(
    authorized: Iterable[str],
    index: Optional[ToolRetrievalIndex] = None,
) -> Set[str]:
    store = index or get_retrieval_index()
    found: Set[str] = set()
    for name in authorized:
        rec = store.get(name)
        if rec is not None and not rec.is_searchable():
            found.add(name)
    return found


def last_refresh_epoch(index: Optional[ToolRetrievalIndex] = None) -> float:
    store = index or get_retrieval_index()
    return float(getattr(store, "_built_at", 0.0) or 0.0)


def normalization_blocked(query: Optional[str]) -> bool:
    text = (query or "").strip()
    if not text:
        return False
    return not tokenize_search_text(text)


def tool_index_health(index: Optional[ToolRetrievalIndex] = None) -> dict:
    """Manifest vs postings. Permissions are not stored here."""
    from app.services.ai.ai_tool_manifest import iter_manifest_names

    store = index or get_retrieval_index()
    active = 0
    indexed = 0
    stale = 0
    disabled = 0
    for name in iter_manifest_names():
        entry = get_manifest_entry(name)
        rec = store.get(name)
        enabled = bool(entry and entry.enabled and not entry.deprecated)
        if enabled:
            active += 1
        if rec is not None and rec.is_searchable():
            indexed += 1
        if rec is not None and not rec.is_searchable():
            disabled += 1
        if entry is None:
            continue
        text = entry.search_text(name, "")
        if store.is_stale(
            name,
            search_text=text,
            version=entry.version,
            schema_version=entry.schema_version,
        ):
            stale += 1
    healthy = stale == 0 and indexed >= active
    last = last_refresh_epoch(store)
    age = (time.time() - last) if last else None
    return {
        "active_tool_count": active,
        "indexed_tool_count": indexed,
        "stale_tool_count": stale,
        "disabled_tool_count": disabled,
        "last_refresh": last,
        "healthy": healthy,
        "active_tools": active,
        "indexed_tools": indexed,
        "stale_tools": stale,
        "disabled_tools": disabled,
        "index_refresh_age": None if age is None else round(age, 3),
        "index_health": "healthy" if healthy else "unhealthy",
    }
