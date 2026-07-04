from __future__ import annotations

import re
from typing import Any, Dict, List, Optional

from sqlalchemy.orm import Session
from sqlalchemy.orm.attributes import flag_modified

from adapters.db.models.document import Document
from app.services.invoice_service import INVOICE_LINK_RECEIPT_PAYMENT_IDS

_PERSIAN_DIGITS = "۰۱۲۳۴۵۶۷۸۹"
_ARABIC_DIGITS = "٠١٢٣٤٥٦٧٨٩"
_DIGIT_TRANSLATION = str.maketrans(
    _PERSIAN_DIGITS + _ARABIC_DIGITS,
    "0123456789" * 2,
)

_LEGACY_INVOICE_CODE_PATTERNS = (
    re.compile(
        r"فاکتور\s*(?:فروش|خرید|برگشت\s*از\s*فروش|برگشت\s*از\s*خرید)?\s*شماره\s*[:\s]*([\d,]+)",
        re.I,
    ),
    re.compile(
        r"تسویه\s*فاکتور\s*(?:فروش|خرید|برگشت\s*از\s*فروش|برگشت\s*از\s*خرید)?\s*([\d,]+)",
        re.I,
    ),
    re.compile(
        r"فاکتور\s*(?:فروش|خرید|برگشت\s*از\s*فروش|برگشت\s*از\s*خرید)?\s*([\d,]+)",
        re.I,
    ),
    re.compile(r"فاکتور\s*شماره\s*[:\s]*([\d,]+)", re.I),
    re.compile(r"تسویه\s*فاکتور\s*([\d,]+)", re.I),
    re.compile(r"فاکتور\s*([\d,]+)", re.I),
)

# Only these legacy types reference a specific invoice in row descriptions.
INVOICE_LINKED_RECEIPT_PAYMENT_TYPES = frozenset({"sell_receive", "buy_send"})


def _normalize_invoice_code_text(text: Any) -> str:
    raw = str(text or "")
    raw = raw.translate(_DIGIT_TRANSLATION)
    # Thousands separators (Persian comma, Arabic thousands, thin space, etc.)
    raw = re.sub(r"[\u066C\u060C\u200F\u200E\s٬،]", "", raw)
    return raw


def parse_legacy_invoice_code(text: Any) -> Optional[str]:
    """Extract legacy invoice code from Persian description text."""
    if not text:
        return None
    raw = _normalize_invoice_code_text(text)
    for pattern in _LEGACY_INVOICE_CODE_PATTERNS:
        match = pattern.search(raw)
        if match:
            return match.group(1).replace(",", "").strip()
    return None


def extract_linked_invoice_legacy_code(
    doc: Dict[str, Any],
    rows: List[Dict[str, Any]],
) -> Optional[str]:
    """Find referenced invoice code from receipt/payment document rows or header."""
    for row in rows:
        code = parse_legacy_invoice_code(row.get("des"))
        if code:
            return code
    return parse_legacy_invoice_code(doc.get("des"))


def apply_related_docs_to_link_map(
    link_map: Dict[str, str],
    invoice_code: Any,
    related_docs: List[Any],
) -> None:
    """Map receipt/payment codes to invoice code using API relatedDocs."""
    inv_code = str(invoice_code or "").strip()
    if not inv_code:
        return
    for rel in related_docs:
        if not isinstance(rel, dict):
            continue
        rel_type = str(rel.get("type") or "").strip()
        if rel_type not in INVOICE_LINKED_RECEIPT_PAYMENT_TYPES:
            continue
        rel_code = rel.get("code")
        if rel_code is None:
            continue
        link_map[str(rel_code).strip()] = inv_code


def resolve_linked_invoice_legacy_code(
    *,
    receipt_payment_code: Any,
    related_docs_link_map: Dict[str, str],
    doc: Dict[str, Any],
    rows: List[Dict[str, Any]],
) -> Optional[str]:
    """Prefer relatedDocs map; fall back to description parsing."""
    rp_code = str(receipt_payment_code or "").strip()
    if rp_code and related_docs_link_map.get(rp_code):
        return related_docs_link_map[rp_code]
    return extract_linked_invoice_legacy_code(doc, rows)


def append_receipt_payment_to_invoice(
    db: Session,
    invoice_id: int,
    receipt_payment_document_id: int,
) -> None:
    """Bidirectional link: add receipt/payment id to invoice.extra_info.links."""
    inv = db.query(Document).filter(Document.id == int(invoice_id)).first()
    if not inv:
        return
    extra = dict(inv.extra_info) if isinstance(inv.extra_info, dict) else {}
    links = dict(extra.get("links") or {})
    raw_ids = links.get(INVOICE_LINK_RECEIPT_PAYMENT_IDS) or []
    ids: List[int] = []
    for raw in raw_ids:
        try:
            ids.append(int(raw))
        except (TypeError, ValueError):
            continue
    rp_id = int(receipt_payment_document_id)
    if rp_id not in ids:
        ids.append(rp_id)
    links[INVOICE_LINK_RECEIPT_PAYMENT_IDS] = ids
    extra["links"] = links
    inv.extra_info = extra
    flag_modified(inv, "extra_info")
    db.add(inv)
