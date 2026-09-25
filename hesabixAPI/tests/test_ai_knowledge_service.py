"""تست جستجوی دانشنامه AI."""
from __future__ import annotations

from unittest.mock import MagicMock

from app.services.ai.ai_knowledge_service import (
    _tokenize,
    document_to_dict,
    inspect_index_status,
    search_documents,
)


def test_tokenize_persian_and_latin():
    tokens = _tokenize("فروش ماه گذشته sales report")
    assert "فروش" in tokens
    assert "sales" in tokens


def test_search_documents_scores_overlap():
    db = MagicMock()
    doc1 = MagicMock()
    doc1.id = 1
    doc1.title = "سیاست تخفیف"
    doc1.content = "حداکثر تخفیف فاکتور ۱۰ درصد است"
    doc1.updated_at = None
    doc2 = MagicMock()
    doc2.id = 2
    doc2.title = "راهنما"
    doc2.content = "موجودی انبار"
    doc2.updated_at = None

    q = MagicMock()
    q.filter.return_value.order_by.return_value.limit.return_value.all.return_value = [doc1, doc2]
    db.query.return_value = q

    hits = search_documents(db, business_id=1, query="تخفیف فاکتور", limit=3)
    assert len(hits) >= 1
    assert hits[0]["id"] == 1
    assert hits[0]["score"] >= 1


def test_document_to_dict_includes_index_status():
    doc = MagicMock()
    doc.id = 7
    doc.business_id = 1
    doc.title = "سیاست"
    doc.source_filename = None
    doc.content = "متن"
    doc.created_at = None
    doc.updated_at = None
    payload = document_to_dict(
        doc,
        index_status={
            "index_status": "semantic",
            "chunk_count": 4,
            "embedded_count": 4,
        },
    )
    assert payload["index_status"] == "semantic"
    assert payload["chunk_count"] == 4


def test_inspect_index_status_keyword_when_no_embeddings():
    db = MagicMock()
    q = MagicMock()
    q.filter.return_value.all.return_value = [(None,), (None,)]
    db.query.return_value = q
    status = inspect_index_status(db, 3)
    assert status["index_status"] == "keyword"
    assert status["chunk_count"] == 2
    assert status["embedded_count"] == 0
