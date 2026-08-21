"""In-process tool-metadata embeddings.

Vectors are built from search_text / aliases / keywords / examples —
never from full JSON Schema.

Default backend is a deterministic hashed character-ngram (no live API).
Neural embeddings are opt-in when credentials exist; CI does not call them.

Semantic retrieval may improve discovery, but it can never authorize a tool.
"""
from __future__ import annotations

import hashlib
import math
import threading
from dataclasses import dataclass
from typing import Dict, Iterable, List, Optional, Sequence, Tuple

from app.services.ai.ai_embedding_service import cosine_similarity
from app.services.ai.ai_tool_manifest import get_manifest_entry, iter_manifest_names

EMBEDDING_MODEL_LOCAL = "charngram-hash-v1"
EMBEDDING_DIMENSION = 256
EMBEDDING_VERSION = "1"


def tool_metadata_text(name: str, description: str = "") -> str:
    entry = get_manifest_entry(name)
    if entry is None:
        return " ".join(part for part in (name, description) if part)
    return entry.search_text(name, description)


def hashed_ngram_vector(text: str, dim: int = EMBEDDING_DIMENSION) -> Tuple[float, ...]:
    vec = [0.0] * dim
    blob = (text or "").lower()
    if len(blob) < 3:
        blob = f"{blob}***"
    for i in range(len(blob) - 2):
        gram = blob[i : i + 3]
        digest = hashlib.blake2b(gram.encode("utf-8"), digest_size=8).digest()
        h = int.from_bytes(digest, "little")
        idx = h % dim
        sign = 1.0 if (h >> 7) & 1 else -1.0
        vec[idx] += sign
    norm = math.sqrt(sum(x * x for x in vec)) or 1.0
    return tuple(x / norm for x in vec)


def metadata_content_hash(text: str) -> str:
    return hashlib.sha256((text or "").encode("utf-8")).hexdigest()[:16]


@dataclass(frozen=True)
class EmbeddingRecord:
    name: str
    vector: Tuple[float, ...]
    content_hash: str
    model: str = EMBEDDING_MODEL_LOCAL
    dimension: int = EMBEDDING_DIMENSION
    embedding_version: str = EMBEDDING_VERSION


@dataclass(frozen=True)
class EmbeddingIndexMeta:
    embedding_model: str
    embedding_dimension: int
    metadata_version: str
    embedding_version: str
    size: int


class ToolEmbeddingIndex:
    """Process-local index. Query must pass an authorized name universe."""

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._records: Dict[str, EmbeddingRecord] = {}
        self._meta_version = ""

    def _rebuild_unlocked(self, names: Iterable[str]) -> None:
        records: Dict[str, EmbeddingRecord] = {}
        parts: List[str] = []
        for name in sorted(set(names)):
            text = tool_metadata_text(name)
            vec = hashed_ngram_vector(text)
            digest = metadata_content_hash(text)
            records[name] = EmbeddingRecord(
                name=name, vector=vec, content_hash=digest
            )
            parts.append(f"{name}:{digest}")
        self._records = records
        self._meta_version = hashlib.sha256(
            "|".join(parts).encode("utf-8")
        ).hexdigest()[:16]

    def ensure(self, names: Optional[Iterable[str]] = None) -> None:
        catalog = list(names) if names is not None else list(iter_manifest_names())
        with self._lock:
            if self._records and set(self._records) == set(catalog):
                return
            self._rebuild_unlocked(catalog)

    def invalidate_if_stale(self, name: str) -> None:
        text = tool_metadata_text(name)
        digest = metadata_content_hash(text)
        with self._lock:
            current = self._records.get(name)
            if current is None or current.content_hash != digest:
                self._rebuild_unlocked(list(self._records) or [name])

    def meta(self) -> EmbeddingIndexMeta:
        with self._lock:
            return EmbeddingIndexMeta(
                embedding_model=EMBEDDING_MODEL_LOCAL,
                embedding_dimension=EMBEDDING_DIMENSION,
                metadata_version=self._meta_version,
                embedding_version=EMBEDDING_VERSION,
                size=len(self._records),
            )

    def query(
        self,
        text: str,
        authorized_names: Iterable[str],
        *,
        limit: int = 32,
    ) -> List[Tuple[str, float]]:
        """Cosine search restricted to authorized names only."""
        allowed = {n for n in authorized_names if n}
        if not allowed or not (text or "").strip():
            return []
        self.ensure(list(allowed) if not self._records else None)
        qvec = hashed_ngram_vector(text)
        scored: List[Tuple[str, float]] = []
        with self._lock:
            for name in allowed:
                rec = self._records.get(name)
                if rec is None:
                    vec = hashed_ngram_vector(tool_metadata_text(name))
                else:
                    vec = rec.vector
                score = cosine_similarity(qvec, vec)
                if score > 0.02:
                    scored.append((name, float(score)))
        scored.sort(key=lambda item: (-item[1], item[0]))
        return scored[: max(1, int(limit))]


_INDEX = ToolEmbeddingIndex()


def get_tool_embedding_index() -> ToolEmbeddingIndex:
    return _INDEX


def reset_tool_embedding_index_for_tests() -> None:
    with _INDEX._lock:
        _INDEX._records = {}
        _INDEX._meta_version = ""
