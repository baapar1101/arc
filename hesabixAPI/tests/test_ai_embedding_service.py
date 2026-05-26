"""تست embedding و شباهت کسینوسی."""
from __future__ import annotations

from app.services.ai.ai_embedding_service import cosine_similarity, split_text_chunks


def test_cosine_similarity_identical():
    v = [1.0, 0.0, 0.5]
    assert cosine_similarity(v, v) == 1.0


def test_split_text_chunks_overlap():
    text = "a" * 2000 + "\n\n" + "b" * 2000
    parts = split_text_chunks(text, chunk_size=500, overlap=50)
    assert len(parts) >= 2
