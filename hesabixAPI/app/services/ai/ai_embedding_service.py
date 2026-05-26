"""
سرویس embedding برای RAG معنایی (OpenAI-compatible API).
"""
from __future__ import annotations

import json
import logging
import math
import re
from typing import Any, Dict, List, Optional, Sequence, Tuple

from sqlalchemy import text
from sqlalchemy.orm import Session

from adapters.db.models.ai_knowledge_chunk import AIKnowledgeChunk
from adapters.db.models.ai_knowledge_document import AIKnowledgeDocument

logger = logging.getLogger(__name__)

CHUNK_SIZE = 1400
CHUNK_OVERLAP = 180
EMBEDDING_MODEL = "text-embedding-3-small"
MAX_CHUNKS_PER_DOC = 80
SEMANTIC_TOP_K = 5

_pgvector_available_cache: Optional[bool] = None


def _pgvector_available(db: Session) -> bool:
    global _pgvector_available_cache
    if _pgvector_available_cache is not None:
        return _pgvector_available_cache
    try:
        db.execute(text("SELECT embedding_vector FROM ai_knowledge_chunks LIMIT 0"))
        _pgvector_available_cache = True
    except Exception:
        _pgvector_available_cache = False
    return _pgvector_available_cache


def _vector_literal(vec: List[float]) -> str:
    return "[" + ",".join(f"{x:.8f}" for x in vec) + "]"


def split_text_chunks(text: str, chunk_size: int = CHUNK_SIZE, overlap: int = CHUNK_OVERLAP) -> List[str]:
    text = (text or "").strip()
    if not text:
        return []
    if len(text) <= chunk_size:
        return [text]

    paragraphs = re.split(r"\n{2,}", text)
    chunks: List[str] = []
    buf = ""

    def flush_buffer() -> None:
        nonlocal buf
        if not buf.strip():
            buf = ""
            return
        if len(buf) <= chunk_size:
            chunks.append(buf.strip())
            buf = ""
            return
        start = 0
        while start < len(buf):
            end = min(len(buf), start + chunk_size)
            piece = buf[start:end].strip()
            if piece:
                chunks.append(piece)
            if end >= len(buf):
                break
            start = max(0, end - overlap)
        buf = ""

    for para in paragraphs:
        p = para.strip()
        if not p:
            continue
        candidate = f"{buf}\n\n{p}".strip() if buf else p
        if len(candidate) <= chunk_size:
            buf = candidate
        else:
            flush_buffer()
            buf = p
    flush_buffer()
    return chunks[:MAX_CHUNKS_PER_DOC]


def cosine_similarity(a: Sequence[float], b: Sequence[float]) -> float:
    if not a or not b or len(a) != len(b):
        return 0.0
    dot = sum(x * y for x, y in zip(a, b))
    na = math.sqrt(sum(x * x for x in a))
    nb = math.sqrt(sum(y * y for y in b))
    if na == 0 or nb == 0:
        return 0.0
    return dot / (na * nb)


def _get_openai_client(api_key: str, api_base_url: Optional[str]):
    import openai

    return openai.OpenAI(api_key=api_key, base_url=api_base_url or None)


def embed_texts(
    texts: List[str],
    api_key: str,
    api_base_url: Optional[str] = None,
    model: str = EMBEDDING_MODEL,
) -> List[List[float]]:
    if not texts:
        return []
    client = _get_openai_client(api_key, api_base_url)
    # batch تا ۶۴ متن
    out: List[List[float]] = []
    batch_size = 32
    for i in range(0, len(texts), batch_size):
        batch = texts[i : i + batch_size]
        resp = client.embeddings.create(model=model, input=batch)
        sorted_data = sorted(resp.data, key=lambda d: d.index)
        out.extend([list(d.embedding) for d in sorted_data])
    return out


def get_ai_embedding_credentials(db: Session) -> Optional[Tuple[str, Optional[str]]]:
    """API key فعال از تنظیمات AI."""
    try:
        from adapters.db.repositories.ai_config_repository import AIConfigRepository
        from app.services.ai.encryption import decrypt_api_key

        repo = AIConfigRepository(db)
        config = repo.get_active_config()
        if not config or not config.is_active or not config.api_key:
            return None
        key = decrypt_api_key(config.api_key)
        if not key:
            return None
        return key, config.api_base_url
    except Exception as exc:
        logger.warning("embedding credentials unavailable: %s", exc)
        return None


def delete_document_chunks(db: Session, document_id: int) -> None:
    db.query(AIKnowledgeChunk).filter(AIKnowledgeChunk.document_id == document_id).delete()
    db.commit()


def index_document(db: Session, document: AIKnowledgeDocument) -> int:
    """تکه‌تکه و ذخیره embedding؛ در صورت نبود API فقط chunks بدون بردار."""
    delete_document_chunks(db, document.id)
    parts = split_text_chunks(document.content or "")
    if not parts:
        return 0

    embeddings: List[Optional[List[float]]] = [None] * len(parts)
    creds = get_ai_embedding_credentials(db)
    if creds:
        api_key, base_url = creds
        try:
            vectors = embed_texts(parts, api_key, base_url)
            for i, vec in enumerate(vectors):
                embeddings[i] = vec
        except Exception as exc:
            logger.warning("embedding index failed for doc %s: %s", document.id, exc)

    for idx, part in enumerate(parts):
        emb_json = None
        if embeddings[idx] is not None:
            emb_json = json.dumps(embeddings[idx])
        row = AIKnowledgeChunk(
            document_id=document.id,
            chunk_index=idx,
            content=part,
            embedding_json=emb_json,
        )
        db.add(row)
    db.flush()

    if creds and _pgvector_available(db):
        chunk_rows = (
            db.query(AIKnowledgeChunk)
            .filter(AIKnowledgeChunk.document_id == document.id)
            .order_by(AIKnowledgeChunk.chunk_index.asc())
            .all()
        )
        for i, chunk_row in enumerate(chunk_rows):
            vec = embeddings[i] if i < len(embeddings) else None
            if vec:
                try:
                    db.execute(
                        text(
                            "UPDATE ai_knowledge_chunks "
                            "SET embedding_vector = CAST(:vec AS vector) "
                            "WHERE id = :cid"
                        ),
                        {"vec": _vector_literal(vec), "cid": chunk_row.id},
                    )
                except Exception as exc:
                    logger.warning("pgvector store failed chunk %s: %s", chunk_row.id, exc)

    db.commit()
    return len(parts)


def reindex_business(db: Session, business_id: int) -> Dict[str, Any]:
    docs = (
        db.query(AIKnowledgeDocument)
        .filter(
            AIKnowledgeDocument.business_id == business_id,
            AIKnowledgeDocument.is_active == True,  # noqa: E712
        )
        .all()
    )
    total_chunks = 0
    for doc in docs:
        total_chunks += index_document(db, doc)
    return {"documents": len(docs), "chunks": total_chunks}


def _semantic_search_pgvector(
    db: Session,
    business_id: int,
    q_vec: List[float],
    limit: int,
) -> List[Dict[str, Any]]:
    try:
        rows = db.execute(
            text(
                """
                SELECT c.content, d.id AS doc_id, d.title,
                       1 - (c.embedding_vector <=> CAST(:qvec AS vector)) AS score
                FROM ai_knowledge_chunks c
                JOIN ai_knowledge_documents d ON d.id = c.document_id
                WHERE d.business_id = :bid
                  AND d.is_active = true
                  AND c.embedding_vector IS NOT NULL
                ORDER BY c.embedding_vector <=> CAST(:qvec AS vector)
                LIMIT :lim
                """
            ),
            {"qvec": _vector_literal(q_vec), "bid": business_id, "lim": limit},
        ).mappings().all()
    except Exception as exc:
        logger.warning("pgvector search failed: %s", exc)
        return []

    results: List[Dict[str, Any]] = []
    for row in rows:
        results.append(
            {
                "document_id": row["doc_id"],
                "title": row["title"],
                "score": round(float(row["score"] or 0), 4),
                "excerpt": (row["content"] or "")[:1200],
                "search_mode": "semantic_pgvector",
            }
        )
    return results


def semantic_search_chunks(
    db: Session,
    business_id: int,
    query: str,
    limit: int = SEMANTIC_TOP_K,
) -> List[Dict[str, Any]]:
    creds = get_ai_embedding_credentials(db)
    if not creds:
        return []
    api_key, base_url = creds
    try:
        q_vec = embed_texts([query.strip()], api_key, base_url)[0]
    except Exception as exc:
        logger.warning("query embedding failed: %s", exc)
        return []

    if _pgvector_available(db):
        pg_hits = _semantic_search_pgvector(db, business_id, q_vec, limit)
        if pg_hits:
            return pg_hits

    rows = (
        db.query(AIKnowledgeChunk, AIKnowledgeDocument)
        .join(AIKnowledgeDocument, AIKnowledgeDocument.id == AIKnowledgeChunk.document_id)
        .filter(
            AIKnowledgeDocument.business_id == business_id,
            AIKnowledgeDocument.is_active == True,  # noqa: E712
            AIKnowledgeChunk.embedding_json.isnot(None),
        )
        .all()
    )

    scored: List[Tuple[float, AIKnowledgeChunk, AIKnowledgeDocument]] = []
    for chunk, doc in rows:
        try:
            vec = json.loads(chunk.embedding_json or "[]")
        except json.JSONDecodeError:
            continue
        if not isinstance(vec, list):
            continue
        score = cosine_similarity(q_vec, vec)
        if score > 0.05:
            scored.append((score, chunk, doc))

    scored.sort(key=lambda x: -x[0])
    results: List[Dict[str, Any]] = []
    for score, chunk, doc in scored[:limit]:
        results.append(
            {
                "document_id": doc.id,
                "title": doc.title,
                "score": round(score, 4),
                "excerpt": chunk.content[:1200],
                "search_mode": "semantic",
            }
        )
    return results
