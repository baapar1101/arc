"""پیوند سند حسابداری به فرصت فروش، بدون ساخت موجودیت پیش‌فاکتور موازی."""
from __future__ import annotations

from typing import Any

from sqlalchemy.orm import Session

from adapters.db.models.crm import CrmDealDocument, Deal
from adapters.db.models.document import Document
from app.core.responses import ApiError
from app.services.crm_guards import assert_document_in_business

DOCUMENT_ROLES = ("proforma", "invoice", "receipt")


def link_deal_document(
    db: Session,
    business_id: int,
    deal: Deal,
    document_id: int,
    *,
    role: str | None = None,
    created_by_user_id: int | None = None,
) -> tuple[CrmDealDocument, bool]:
    assert_document_in_business(db, business_id, int(document_id))
    document = db.get(Document, int(document_id))
    if document is None or int(document.business_id) != int(business_id):
        raise ApiError("CRM_DOCUMENT_NOT_IN_BUSINESS", "سند متعلق به این کسب‌وکار نیست.", http_status=400)
    resolved = role or ("proforma" if document.is_proforma else "invoice")
    if resolved not in DOCUMENT_ROLES:
        raise ApiError("CRM_DEAL_DOCUMENT_ROLE_INVALID", "نقش سند نامعتبر است.", http_status=400)
    existing = (
        db.query(CrmDealDocument)
        .filter(
            CrmDealDocument.business_id == business_id,
            CrmDealDocument.deal_id == deal.id,
            CrmDealDocument.document_id == int(document_id),
        )
        .first()
    )
    created = existing is None
    row = existing or CrmDealDocument(
        business_id=business_id,
        deal_id=int(deal.id),
        document_id=int(document_id),
        role=resolved,
        created_by_user_id=created_by_user_id,
    )
    row.role = resolved
    if created:
        db.add(row)
    if resolved in ("proforma", "invoice"):
        deal.document_id = int(document_id)
    db.flush()
    return row, created


def deals_for_document(db: Session, business_id: int, document_id: int, ctx: Any) -> list[dict[str, Any]]:
    """فرصت‌هایی که این سند به آن‌ها وصل است. فرصت پنهان برنمی‌گردد."""
    from app.services.crm_enterprise_service import assert_can_view_record

    linked = (
        db.query(Deal)
        .join(CrmDealDocument, CrmDealDocument.deal_id == Deal.id)
        .filter(
            CrmDealDocument.business_id == business_id,
            CrmDealDocument.document_id == int(document_id),
            Deal.business_id == business_id,
        )
        .all()
    )
    by_id = {int(deal.id): deal for deal in linked}
    pointed = (
        db.query(Deal)
        .filter(Deal.business_id == business_id, Deal.document_id == int(document_id))
        .all()
    )
    for deal in pointed:
        by_id.setdefault(int(deal.id), deal)
    document = db.get(Document, int(document_id))
    extra = document.extra_info if document is not None and isinstance(document.extra_info, dict) else {}
    raw_deal_id = extra.get("crm_deal_id")
    try:
        extra_deal_id = int(raw_deal_id) if raw_deal_id is not None else None
    except (TypeError, ValueError):
        extra_deal_id = None
    if extra_deal_id and extra_deal_id not in by_id:
        extra_deal = (
            db.query(Deal)
            .filter(Deal.business_id == business_id, Deal.id == extra_deal_id)
            .first()
        )
        if extra_deal is not None:
            by_id[int(extra_deal.id)] = extra_deal
    items: list[dict[str, Any]] = []
    for deal in sorted(by_id.values(), key=lambda row: int(row.id)):
        try:
            assert_can_view_record(db, business_id, ctx, "deal", deal, write=False)
        except ApiError:
            continue
        items.append({"id": int(deal.id), "code": deal.code, "title": deal.title})
    return items


def list_deal_documents(db: Session, business_id: int, deal_id: int) -> list[dict[str, Any]]:
    rows = (
        db.query(CrmDealDocument, Document)
        .join(Document, Document.id == CrmDealDocument.document_id)
        .filter(CrmDealDocument.business_id == business_id, CrmDealDocument.deal_id == deal_id)
        .order_by(CrmDealDocument.id.asc())
        .all()
    )
    items: list[dict[str, Any]] = []
    for link, document in rows:
        items.append(
            {
                "id": int(link.id),
                "document_id": int(document.id),
                "code": document.code,
                "document_type": document.document_type,
                "is_proforma": bool(document.is_proforma),
                "role": link.role,
                "document_date": document.document_date.isoformat() if document.document_date else None,
            }
        )
    return items
