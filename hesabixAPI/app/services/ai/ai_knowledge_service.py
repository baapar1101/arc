"""
پایگاه دانش کسب‌وکار — جستجوی متنی (RAG lite) بدون وکتور.
"""
from __future__ import annotations

import re
from datetime import datetime
from typing import Any, Dict, List, Optional

from sqlalchemy.orm import Session

from adapters.db.models.ai_knowledge_document import AIKnowledgeDocument

MAX_DOC_CHARS = 100_000
MAX_CONTENT_IN_PROMPT = 8_000
TOP_K = 4
MIN_WORD_LEN = 2


def _tokenize(text: str) -> List[str]:
    if not text:
        return []
    parts = re.findall(r"[\w\u0600-\u06FF]+", text.lower())
    return [p for p in parts if len(p) >= MIN_WORD_LEN][:24]


def list_documents(db: Session, business_id: int, limit: int = 100) -> List[AIKnowledgeDocument]:
    return (
        db.query(AIKnowledgeDocument)
        .filter(
            AIKnowledgeDocument.business_id == business_id,
            AIKnowledgeDocument.is_active == True,  # noqa: E712
        )
        .order_by(AIKnowledgeDocument.updated_at.desc())
        .limit(limit)
        .all()
    )


def create_document(
    db: Session,
    business_id: int,
    user_id: int,
    title: str,
    content: str,
    source_filename: Optional[str] = None,
) -> AIKnowledgeDocument:
    body = (content or "").strip()[:MAX_DOC_CHARS]
    if not body:
        raise ValueError("محتوای سند خالی است")
    row = AIKnowledgeDocument(
        business_id=business_id,
        user_id=user_id,
        title=(title or "بدون عنوان")[:512],
        content=body,
        source_filename=source_filename,
        is_active=True,
    )
    db.add(row)
    db.commit()
    db.refresh(row)
    try:
        from app.services.ai.ai_embedding_service import index_document

        index_document(db, row)
    except Exception:
        pass
    return row


def delete_document(db: Session, document_id: int, business_id: int) -> bool:
    row = (
        db.query(AIKnowledgeDocument)
        .filter(
            AIKnowledgeDocument.id == document_id,
            AIKnowledgeDocument.business_id == business_id,
        )
        .first()
    )
    if not row:
        return False
    try:
        from app.services.ai.ai_embedding_service import delete_document_chunks

        delete_document_chunks(db, document_id)
    except Exception:
        pass
    db.delete(row)
    db.commit()
    return True


def document_to_dict(doc: AIKnowledgeDocument, include_content: bool = False) -> Dict[str, Any]:
    d: Dict[str, Any] = {
        "id": doc.id,
        "business_id": doc.business_id,
        "title": doc.title,
        "source_filename": doc.source_filename,
        "char_count": len(doc.content or ""),
        "created_at": doc.created_at.isoformat() if doc.created_at else None,
        "updated_at": doc.updated_at.isoformat() if doc.updated_at else None,
    }
    if include_content:
        d["content"] = doc.content
    return d


def search_documents(
    db: Session,
    business_id: int,
    query: str,
    limit: int = TOP_K,
) -> List[Dict[str, Any]]:
    """امتیازدهی ساده بر اساس هم‌پوشانی واژه‌ها."""
    tokens = _tokenize(query)
    if not tokens:
        return []

    docs = list_documents(db, business_id, limit=200)
    scored: List[tuple[int, AIKnowledgeDocument]] = []

    for doc in docs:
        haystack = f"{doc.title} {doc.content}".lower()
        score = sum(1 for t in tokens if t in haystack)
        if score > 0:
            scored.append((score, doc))

    scored.sort(key=lambda x: (-x[0], x[1].updated_at or datetime.min))

    results: List[Dict[str, Any]] = []
    for score, doc in scored[:limit]:
        excerpt = _best_excerpt(doc.content, tokens)
        results.append(
            {
                "id": doc.id,
                "title": doc.title,
                "score": score,
                "excerpt": excerpt,
            }
        )
    return results


def _best_excerpt(content: str, tokens: List[str], max_len: int = 1200) -> str:
    text = content or ""
    lower = text.lower()
    pos = -1
    for t in tokens:
        idx = lower.find(t)
        if idx >= 0 and (pos < 0 or idx < pos):
            pos = idx
    if pos < 0:
        return text[:max_len] + ("…" if len(text) > max_len else "")
    start = max(0, pos - 200)
    end = min(len(text), start + max_len)
    excerpt = text[start:end]
    if start > 0:
        excerpt = "…" + excerpt
    if end < len(text):
        excerpt = excerpt + "…"
    return excerpt


def hybrid_search(
    db: Session,
    business_id: int,
    query: str,
    limit: int = TOP_K,
) -> List[Dict[str, Any]]:
    """جستجوی معنایی با fallback واژه‌ای."""
    from app.services.ai.ai_embedding_service import semantic_search_chunks

    semantic = semantic_search_chunks(db, business_id, query, limit=limit)
    if semantic:
        return semantic

    keyword = search_documents(db, business_id, query, limit=limit)
    for hit in keyword:
        hit["search_mode"] = "keyword"
        hit.setdefault("document_id", hit.get("id"))
    return keyword


def format_knowledge_for_prompt(
    db: Session,
    business_id: int,
    user_query: Optional[str],
    max_chars: int = MAX_CONTENT_IN_PROMPT,
) -> str:
    if not user_query or not user_query.strip():
        return ""

    hits = hybrid_search(db, business_id, user_query, limit=TOP_K)
    if not hits:
        return ""

    lines = [
        "\n\n--- دانشنامه کسب‌وکار (مرتبط با پرسش؛ در صورت تعارض با داده زنده، داده سیستم را مقدم بدان) ---"
    ]
    used = 0
    for hit in hits:
        block = f"\n### {hit['title']}\n{hit['excerpt']}\n"
        if used + len(block) > max_chars:
            break
        lines.append(block)
        used += len(block)
    return "".join(lines)
