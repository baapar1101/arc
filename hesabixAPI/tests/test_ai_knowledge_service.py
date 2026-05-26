"""تست جستجوی دانشنامه AI."""
from __future__ import annotations

from unittest.mock import MagicMock

from app.services.ai.ai_knowledge_service import _tokenize, search_documents


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
