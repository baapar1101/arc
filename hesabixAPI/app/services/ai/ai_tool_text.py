"""Search-text normalization for tool retrieval (index terms, not ranking).

Reuses number normalization from SmartNormalizer. Does not change
`tokenize_query` in the Phase 6 ranker.
"""
from __future__ import annotations

import re
from typing import Tuple

from app.core.smart_normalizer import smart_normalize_numbers

ZWNJ = "\u200c"
ZWJ = "\u200d"
_ARABIC_YE_KE = str.maketrans({
    "ي": "ی",
    "ى": "ی",
    "ك": "ک",
})
_TOKEN = re.compile(r"[\w\u0600-\u06FF]+", re.UNICODE)


def normalize_search_text(text: str) -> str:
    """Stable Persian/English fold for index keys."""
    if not text:
        return ""
    blob = smart_normalize_numbers(str(text))
    blob = blob.replace(ZWNJ, " ").replace(ZWJ, " ")
    blob = blob.translate(_ARABIC_YE_KE)
    blob = blob.lower().replace("_", " ").replace("-", " ").replace(".", " ")
    parts = _TOKEN.findall(blob)
    return " ".join(parts)


def tokenize_search_text(text: str, *, min_len: int = 2) -> Tuple[str, ...]:
    norm = normalize_search_text(text)
    seen = []
    for token in norm.split():
        if len(token) < min_len:
            continue
        if token not in seen:
            seen.append(token)
    return tuple(seen)
