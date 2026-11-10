"""اقدام بعدی قاعده‌مند برای سرنخ، فرصت و شخص.

اولویت: وظیفه عقب‌افتاده، پیگیری سررسیدشده، فاکتور باز، رکود فرصت، نقض SLA.
"""
from __future__ import annotations

import logging
from datetime import datetime, timedelta
from typing import Any

from sqlalchemy.orm import Session

from adapters.db.models.business_crm_settings import BusinessCrmSettings
from adapters.db.models.crm import CrmActivity, Deal, Lead

logger = logging.getLogger(__name__)


def _action(
    code: str,
    title: str,
    reason: str,
    *,
    entity_type: str,
    entity_id: int,
    lead_id: int | None = None,
    deal_id: int | None = None,
    person_id: int | None = None,
) -> dict[str, Any]:
    return {
        "code": code,
        "title": title,
        "reason": reason,
        "entity_type": entity_type,
        "entity_id": int(entity_id),
        "lead_id": lead_id,
        "deal_id": deal_id,
        "person_id": person_id,
    }


def _overdue_task(
    db: Session,
    business_id: int,
    *,
    lead_id: int | None = None,
    deal_id: int | None = None,
    person_id: int | None = None,
    now: datetime,
    ctx: Any | None = None,
) -> dict[str, Any] | None:
    query = db.query(CrmActivity).filter(
        CrmActivity.business_id == business_id,
        CrmActivity.is_task.is_(True),
        CrmActivity.status == "open",
        CrmActivity.due_at.isnot(None),
        CrmActivity.due_at < now,
    )
    if lead_id is not None:
        query = query.filter(CrmActivity.lead_id == lead_id)
    elif deal_id is not None:
        query = query.filter(CrmActivity.deal_id == deal_id)
    elif person_id is not None:
        query = query.filter(CrmActivity.person_id == person_id)
        if ctx is not None:
            from app.services.crm_enterprise_service import restrict_activity_query

            query = restrict_activity_query(query, db, business_id, ctx, CrmActivity)
    else:
        return None
    row = query.order_by(CrmActivity.due_at.asc()).first()
    if row is None:
        return None
    return _action(
        "overdue_task",
        "وظیفه عقب‌افتاده",
        row.subject or "یک وظیفه باز از سررسید گذشته است.",
        entity_type="activity",
        entity_id=int(row.id),
        lead_id=row.lead_id,
        deal_id=row.deal_id,
        person_id=row.person_id,
    )


def _open_invoice_action(db: Session, business_id: int, person_id: int) -> dict[str, Any] | None:
    """جدیدترین فاکتور فروش تسویه‌نشده در همان سقف ۱۰۰تایی دید ۳۶۰."""
    from adapters.db.models.document import Document
    from adapters.db.models.document_line import DocumentLine
    from app.services.invoice_service import batch_calculate_invoices_remaining

    id_rows = (
        db.query(Document.id)
        .join(DocumentLine, DocumentLine.document_id == Document.id)
        .filter(
            Document.business_id == business_id,
            DocumentLine.person_id == person_id,
            Document.document_type == "invoice_sales",
            Document.is_proforma.is_(False),
        )
        .group_by(Document.id, Document.document_date)
        .order_by(Document.document_date.desc(), Document.id.desc())
        .limit(100)
        .all()
    )
    doc_ids = [row[0] for row in id_rows]
    if not doc_ids:
        return None
    documents = db.query(Document).filter(Document.id.in_(doc_ids), Document.business_id == business_id).all()
    by_id = {int(document.id): document for document in documents}
    try:
        remaining_map = batch_calculate_invoices_remaining(db, business_id, list(by_id.values()))
    except Exception:
        logger.exception("crm next action remaining failed person_id=%s", person_id)
        return None
    for document_id in doc_ids:
        document = by_id.get(int(document_id))
        if document is None:
            continue
        info = remaining_map.get(int(document.id)) or {}
        remaining = float(info.get("remaining") or 0)
        if info.get("is_settled") or remaining <= 0.01:
            continue
        return _action(
            "open_invoice",
            "پیگیری وصول",
            f"فاکتور {document.code} مانده دارد.",
            entity_type="document",
            entity_id=int(document.id),
            person_id=person_id,
        )
    return None


def _invoice_from_financial(financial: dict[str, Any] | None, person_id: int) -> dict[str, Any] | None:
    if not financial or int(financial.get("open_invoices_count") or 0) <= 0:
        return None
    rows = financial.get("open_invoices") or []
    first = rows[0] if rows else None
    document_id = int(first["id"]) if isinstance(first, dict) and first.get("id") else person_id
    code = first.get("code") if isinstance(first, dict) else None
    reason = f"فاکتور {code} مانده دارد." if code else "فاکتور فروش تسویه‌نشده وجود دارد."
    return _action(
        "open_invoice",
        "پیگیری وصول",
        reason,
        entity_type="document",
        entity_id=document_id,
        person_id=person_id,
    )


def _stale_deal_action(db: Session, business_id: int, deal: Deal, now: datetime) -> dict[str, Any] | None:
    if deal.closed_at is not None or deal.stage_entered_at is None:
        return None
    settings = db.query(BusinessCrmSettings).filter(BusinessCrmSettings.business_id == business_id).first()
    days = int(settings.stale_deal_days) if settings is not None else 14
    if days <= 0:
        return None
    if deal.stage_entered_at > now - timedelta(days=days):
        return None
    return _action(
        "stale_deal",
        "فرصت راکد",
        f"این فرصت بیش از {days} روز در مرحله فعلی مانده است.",
        entity_type="deal",
        entity_id=int(deal.id),
        deal_id=int(deal.id),
        person_id=int(deal.person_id),
    )


def next_action_for_lead(db: Session, business_id: int, lead: Lead, now: datetime | None = None) -> dict[str, Any] | None:
    current = now or datetime.utcnow()
    overdue = _overdue_task(db, business_id, lead_id=int(lead.id), now=current)
    if overdue:
        return overdue
    if lead.next_follow_up_at is not None and lead.next_follow_up_at <= current:
        return _action(
            "follow_up_due",
            "پیگیری سررسیدشده",
            "زمان پیگیری بعدی این سرنخ رسیده است.",
            entity_type="lead",
            entity_id=int(lead.id),
            lead_id=int(lead.id),
        )
    if (
        lead.person_id is None
        and lead.first_touched_at is None
        and lead.sla_due_at is not None
        and lead.sla_due_at <= current
    ):
        return _action(
            "sla_breach",
            "نقض مهلت اولین تماس",
            "مهلت SLA این سرنخ گذشته و هنوز تماسی ثبت نشده است.",
            entity_type="lead",
            entity_id=int(lead.id),
            lead_id=int(lead.id),
        )
    return None


def next_action_for_deal(db: Session, business_id: int, deal: Deal, now: datetime | None = None) -> dict[str, Any] | None:
    current = now or datetime.utcnow()
    overdue = _overdue_task(db, business_id, deal_id=int(deal.id), now=current)
    if overdue:
        return overdue
    if deal.next_follow_up_at is not None and deal.next_follow_up_at <= current and deal.closed_at is None:
        return _action(
            "follow_up_due",
            "پیگیری سررسیدشده",
            "زمان پیگیری بعدی این فرصت رسیده است.",
            entity_type="deal",
            entity_id=int(deal.id),
            deal_id=int(deal.id),
            person_id=int(deal.person_id),
        )
    if deal.closed_at is None:
        invoice = _open_invoice_action(db, business_id, int(deal.person_id))
        if invoice:
            invoice["deal_id"] = int(deal.id)
            return invoice
        stale = _stale_deal_action(db, business_id, deal, current)
        if stale:
            return stale
    return None


def next_action_for_person(
    db: Session,
    business_id: int,
    person_id: int,
    *,
    financial: dict[str, Any] | None = None,
    now: datetime | None = None,
    ctx: Any | None = None,
) -> dict[str, Any] | None:
    current = now or datetime.utcnow()
    overdue = _overdue_task(db, business_id, person_id=person_id, now=current, ctx=ctx)
    if overdue:
        return overdue
    invoice = _invoice_from_financial(financial, person_id)
    if invoice:
        return invoice
    deal_query = db.query(Deal).filter(
        Deal.business_id == business_id, Deal.person_id == person_id, Deal.closed_at.is_(None)
    )
    if ctx is not None:
        from app.services.crm_enterprise_service import restrict_visibility_query

        deal_query = restrict_visibility_query(deal_query, db, business_id, ctx, Deal, "deal")
    deal = deal_query.order_by(Deal.stage_entered_at.asc().nullslast()).first()
    if deal is not None:
        return _stale_deal_action(db, business_id, deal, current)
    return None


def queue_suggestions(tasks: list[Any], leads: list[Any], deals: list[Any], now: datetime) -> list[dict[str, Any]]:
    suggestions: list[dict[str, Any]] = []
    for task in tasks:
        if task.due_at is not None and task.due_at < now:
            suggestions.append(
                _action(
                    "overdue_task",
                    "وظیفه عقب‌افتاده",
                    task.subject or "وظیفه از سررسید گذشته است.",
                    entity_type="activity",
                    entity_id=int(task.id),
                    lead_id=task.lead_id,
                    deal_id=task.deal_id,
                    person_id=task.person_id,
                )
            )
    for lead in leads:
        if lead.next_follow_up_at is not None and lead.next_follow_up_at <= now:
            suggestions.append(
                _action(
                    "follow_up_due",
                    "پیگیری سرنخ",
                    lead.name or "پیگیری این سرنخ رسیده است.",
                    entity_type="lead",
                    entity_id=int(lead.id),
                    lead_id=int(lead.id),
                )
            )
    for deal in deals:
        if deal.next_follow_up_at is not None and deal.next_follow_up_at <= now:
            suggestions.append(
                _action(
                    "follow_up_due",
                    "پیگیری فرصت",
                    deal.title or "پیگیری این فرصت رسیده است.",
                    entity_type="deal",
                    entity_id=int(deal.id),
                    deal_id=int(deal.id),
                    person_id=int(deal.person_id) if deal.person_id else None,
                )
            )
    return suggestions[:30]
