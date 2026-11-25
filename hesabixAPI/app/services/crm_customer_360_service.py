# noqa: D100
"""سرویس دید ۳۶۰ درجه مشتری: تجمیع اطلاعات شخص، معاملات، فعالیت‌ها، وظایف، اسناد و برچسب‌ها."""
from __future__ import annotations

import logging
from datetime import datetime
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)

from sqlalchemy import and_, func, or_
from sqlalchemy.orm import Session, joinedload, selectinload

from adapters.db.models.person import Person, PersonSocialContact
from adapters.db.models.crm import (
    Deal,
    CrmActivity,
    Lead,
    CrmNote,
    CrmTag,
    CrmDealTagLink,
)
from adapters.db.models.document import Document
from adapters.db.models.document_line import DocumentLine
from adapters.db.models.telephony import TelephonyCall
from app.core.responses import ApiError


def _iso(dt: Optional[datetime]) -> Optional[str]:
    return dt.isoformat() if dt else None


def _full_name(user) -> Optional[str]:
    if not user:
        return None
    return f"{user.first_name or ''} {user.last_name or ''}".strip() or None


_LIST_CAP = 50
_INVOICE_SCAN_CAP = 100


def _deal_brief(d: Deal) -> Dict[str, Any]:
    return {
        "id": d.id,
        "code": d.code,
        "title": d.title,
        "amount": float(d.amount or 0),
        "stage_id": d.stage_id,
        "stage_name": d.stage.name if d.stage else None,
        "closed_at": _iso(d.closed_at),
        "won_reason_code": d.won_reason_code,
        "lost_reason_code": d.lost_reason_code,
        "assigned_to_name": _full_name(d.assigned_to),
        "created_at": _iso(d.created_at),
    }


def _person_financial(db: Session, business_id: int, person_id: int) -> Dict[str, Any]:
    """مانده از همان تابع حسابداری شخص، به‌علاوه فاکتورهای فروش تسویه‌نشده."""
    from app.services.invoice_service import batch_calculate_invoices_remaining
    from app.services.person_service import calculate_person_balance_breakdown

    breakdown = calculate_person_balance_breakdown(db, person_id)
    invoice_filters = (
        Document.business_id == business_id,
        DocumentLine.person_id == person_id,
        Document.document_type == "invoice_sales",
        Document.is_proforma.is_(False),
    )
    invoice_total = (
        db.query(func.count(func.distinct(Document.id)))
        .join(DocumentLine, DocumentLine.document_id == Document.id)
        .filter(*invoice_filters)
        .scalar()
        or 0
    )
    id_rows = (
        db.query(Document.id)
        .join(DocumentLine, DocumentLine.document_id == Document.id)
        .filter(*invoice_filters)
        .group_by(Document.id, Document.document_date)
        .order_by(Document.document_date.desc(), Document.id.desc())
        .limit(_INVOICE_SCAN_CAP)
        .all()
    )
    doc_ids = [row[0] for row in id_rows]
    open_invoices: List[Dict[str, Any]] = []
    if doc_ids:
        docs = db.query(Document).filter(Document.id.in_(doc_ids), Document.business_id == business_id).all()
        by_id = {d.id: d for d in docs}
        remaining_map = batch_calculate_invoices_remaining(db, business_id, list(by_id.values()))
        for did in doc_ids:
            info = remaining_map.get(did) or {}
            remaining = float(info.get("remaining") or 0)
            if info.get("is_settled") or remaining <= 0.01:
                continue
            doc = by_id.get(did)
            if doc is None:
                continue
            open_invoices.append(
                {
                    "id": doc.id,
                    "code": doc.code,
                    "document_date": doc.document_date.isoformat() if doc.document_date else None,
                    "remaining": remaining,
                    "total_amount": float(info.get("total_amount") or 0),
                }
            )
    return {
        "balance": breakdown.get("balance", 0.0),
        "status": breakdown.get("status"),
        "total_debit": breakdown.get("total_debit", 0.0),
        "total_credit": breakdown.get("total_credit", 0.0),
        "open_invoices_count": len(open_invoices),
        "open_invoices": open_invoices[:8],
        "sales_invoice_count": int(invoice_total),
        "open_invoices_exact": int(invoice_total) <= _INVOICE_SCAN_CAP,
    }


def get_customer_360(db: Session, business_id: int, person_id: int, ctx: Any | None = None) -> Dict[str, Any]:
    """تجمیع دید کامل مشتری همراه با تایم‌لاین رویدادهای مرتب‌شده نزولی."""
    person = (
        db.query(Person)
        .options(selectinload(Person.social_contacts))
        .filter(and_(Person.id == person_id, Person.business_id == business_id))
        .first()
    )
    if not person:
        raise ApiError("NOT_FOUND", "شخص یافت نشد.", http_status=404)

    # اطلاعات پایه شخص
    core = {
        "id": person.id,
        "alias_name": person.alias_name,
        "first_name": person.first_name,
        "last_name": person.last_name,
        "company_name": person.company_name,
        "mobile": person.mobile,
        "phone": person.phone,
        "email": person.email,
        "city": person.city,
        "province": person.province,
        "address": person.address,
        "created_at": _iso(person.created_at),
    }
    social_contacts = [
        {
            "id": sc.id,
            "platform_key": sc.platform_key,
            "custom_label": sc.custom_label,
            "value": sc.value,
        }
        for sc in sorted(person.social_contacts, key=lambda x: x.sort_order or 0)
    ]

    def _visible(query, model, entity_type: str):
        if ctx is None:
            return query
        from app.services.crm_enterprise_service import restrict_visibility_query

        return restrict_visibility_query(query, db, business_id, ctx, model, entity_type)

    open_deals_count = (
        _visible(
            db.query(func.count(Deal.id)).filter(Deal.business_id == business_id, Deal.person_id == person_id, Deal.closed_at.is_(None)),
            Deal,
            "deal",
        ).scalar()
        or 0
    )
    closed_deals_count = (
        _visible(
            db.query(func.count(Deal.id)).filter(Deal.business_id == business_id, Deal.person_id == person_id, Deal.closed_at.isnot(None)),
            Deal,
            "deal",
        ).scalar()
        or 0
    )
    open_deals_amount = _visible(
        db.query(func.coalesce(func.sum(Deal.amount), 0)).filter(Deal.business_id == business_id, Deal.person_id == person_id, Deal.closed_at.is_(None)),
        Deal,
        "deal",
    ).scalar()
    closed_deals_amount = _visible(
        db.query(func.coalesce(func.sum(Deal.amount), 0)).filter(Deal.business_id == business_id, Deal.person_id == person_id, Deal.closed_at.isnot(None)),
        Deal,
        "deal",
    ).scalar()
    deal_query = _visible(
        db.query(Deal)
        .options(selectinload(Deal.stage), selectinload(Deal.assigned_to))
        .filter(Deal.business_id == business_id, Deal.person_id == person_id),
        Deal,
        "deal",
    )
    open_deals = [
        _deal_brief(d)
        for d in deal_query.filter(Deal.closed_at.is_(None)).order_by(Deal.created_at.desc()).limit(_LIST_CAP).all()
    ]
    closed_deals = [
        _deal_brief(d)
        for d in deal_query.filter(Deal.closed_at.isnot(None)).order_by(Deal.created_at.desc()).limit(_LIST_CAP).all()
    ]

    # فعالیت‌های اخیر
    activity_query = (
        db.query(CrmActivity)
        .options(selectinload(CrmActivity.created_by), selectinload(CrmActivity.assigned_to))
        .filter(CrmActivity.business_id == business_id, CrmActivity.person_id == person_id)
    )
    if ctx is not None:
        from sqlalchemy.orm import aliased
        from app.services.crm_enterprise_service import record_acl_enforced

        if record_acl_enforced(db, business_id, ctx):
            lead_alias = aliased(Lead)
            deal_alias = aliased(Deal)
            visible_lead_ids = _visible(
                db.query(lead_alias.id).filter(lead_alias.business_id == business_id), lead_alias, "lead"
            )
            visible_deal_ids = _visible(
                db.query(deal_alias.id).filter(deal_alias.business_id == business_id), deal_alias, "deal"
            )
            activity_query = activity_query.filter(
                or_(CrmActivity.lead_id.is_(None), CrmActivity.lead_id.in_(visible_lead_ids)),
                or_(CrmActivity.deal_id.is_(None), CrmActivity.deal_id.in_(visible_deal_ids)),
            )
    activities = activity_query.order_by(CrmActivity.activity_date.desc()).limit(30).all()
    recent_activities = [
        {
            "id": a.id,
            "activity_type": a.activity_type,
            "subject": a.subject,
            "description": a.description,
            "activity_date": _iso(a.activity_date),
            "is_task": bool(a.is_task),
            "status": a.status,
            "due_at": _iso(a.due_at),
            "outcome": a.outcome,
            "created_by_name": _full_name(a.created_by),
        }
        for a in activities
    ]

    # وظایف باز
    task_query = db.query(CrmActivity).filter(
        CrmActivity.business_id == business_id,
        CrmActivity.person_id == person_id,
        CrmActivity.is_task.is_(True),
        CrmActivity.status == "open",
    )
    if ctx is not None:
        from app.services.crm_enterprise_service import record_acl_enforced

        if record_acl_enforced(db, business_id, ctx):
            task_query = task_query.filter(
                or_(CrmActivity.lead_id.is_(None), CrmActivity.lead_id.in_(visible_lead_ids)),
                or_(CrmActivity.deal_id.is_(None), CrmActivity.deal_id.in_(visible_deal_ids)),
            )
    tasks_open_count = task_query.with_entities(func.count(CrmActivity.id)).scalar() or 0
    tasks_open_rows = (
        task_query.options(selectinload(CrmActivity.assigned_to))
        .order_by(CrmActivity.due_at.asc().nullslast())
        .limit(_LIST_CAP)
        .all()
    )
    tasks_open = [
        {
            "id": t.id,
            "subject": t.subject,
            "due_at": _iso(t.due_at),
            "priority": t.priority,
            "assigned_to_name": _full_name(t.assigned_to),
        }
        for t in tasks_open_rows
    ]

    # سرنخ‌هایی که به این شخص تبدیل شده‌اند
    leads = (
        _visible(db.query(Lead).filter(Lead.business_id == business_id, Lead.person_id == person_id), Lead, "lead")
        .order_by(Lead.created_at.desc())
        .all()
    )
    converted_leads = [
        {
            "id": l.id,
            "code": l.code,
            "name": l.name,
            "source_code": l.source_code,
            "converted_at": _iso(l.converted_at),
            "created_at": _iso(l.created_at),
        }
        for l in leads
    ]
    lead_ids = [l.id for l in leads]

    # یادداشت‌های شخص، فرصت‌های او، یا سرنخ‌های تبدیل‌شده
    deal_ids = _visible(db.query(Deal.id).filter(Deal.business_id == business_id, Deal.person_id == person_id), Deal, "deal")
    note_filters = [CrmNote.person_id == person_id, CrmNote.deal_id.in_(deal_ids)]
    if lead_ids:
        note_filters.append(CrmNote.lead_id.in_(lead_ids))
    note_rows = (
        db.query(CrmNote)
        .options(joinedload(CrmNote.deal), joinedload(CrmNote.lead))
        .filter(
            CrmNote.business_id == business_id,
            CrmNote.deleted_at.is_(None),
            or_(*note_filters),
        )
        .order_by(CrmNote.occurs_on.desc())
        .limit(30)
        .all()
    )
    notes = [
        {
            "id": n.id,
            "title": n.title,
            "body": n.body,
            "occurs_on": n.occurs_on.isoformat() if n.occurs_on else None,
            "lead_id": n.lead_id,
            "lead_name": n.lead.name if n.lead else None,
            "person_id": n.person_id,
            "deal_id": n.deal_id,
            "deal_title": n.deal.title if n.deal else None,
            "deal_code": n.deal.code if n.deal else None,
        }
        for n in note_rows
    ]

    # اسناد اخیر (فاکتورها) از طریق خطوط سند
    # توجه: Document.extra_info از نوع JSON است؛ DISTINCT روی کل ردیف در PostgreSQL خطا می‌دهد.
    doc_id_rows = (
        db.query(Document.id, Document.document_date)
        .join(DocumentLine, DocumentLine.document_id == Document.id)
        .filter(Document.business_id == business_id, DocumentLine.person_id == person_id)
        .group_by(Document.id, Document.document_date)
        .order_by(Document.document_date.desc(), Document.id.desc())
        .limit(20)
        .all()
    )
    doc_ids = [row[0] for row in doc_id_rows]
    documents: List[Dict[str, Any]] = []
    if doc_ids:
        doc_by_id = {
            d.id: d
            for d in db.query(Document).filter(Document.id.in_(doc_ids)).all()
        }
        for did in doc_ids:
            d = doc_by_id.get(did)
            if not d:
                continue
            documents.append(
                {
                    "id": d.id,
                    "code": d.code,
                    "document_type": d.document_type,
                    "document_date": d.document_date.isoformat() if d.document_date else None,
                    "is_proforma": bool(d.is_proforma),
                    "description": d.description,
                }
            )

    # تماس‌های تلفنی متصل به این شخص
    call_rows = (
        db.query(TelephonyCall)
        .filter(TelephonyCall.business_id == business_id, TelephonyCall.person_id == person_id)
        .order_by(TelephonyCall.started_at.desc())
        .limit(20)
        .all()
    )
    recent_calls: List[Dict[str, Any]] = []
    for c in call_rows:
        peer = (
            (c.from_number_normalized or c.from_number_raw)
            if c.direction == "inbound"
            else (c.to_number_normalized or c.to_number_raw)
        )
        recent_calls.append(
            {
                "id": c.id,
                "direction": c.direction,
                "status": c.status,
                "peer_number": peer,
                "extension": c.extension,
                "started_at": _iso(c.started_at),
                "duration_sec": c.duration_sec,
                "talk_sec": c.talk_sec,
                "recording_available": c.recording_status == "available",
            }
        )

    tag_id_rows = (
        db.query(CrmTag.id)
        .join(CrmDealTagLink, CrmDealTagLink.tag_id == CrmTag.id)
        .join(Deal, Deal.id == CrmDealTagLink.deal_id)
        .filter(Deal.business_id == business_id, Deal.person_id == person_id, CrmTag.business_id == business_id)
        .group_by(CrmTag.id)
        .all()
    )
    tag_ids = [row[0] for row in tag_id_rows]
    tags: List[Dict[str, Any]] = []
    if tag_ids:
        tag_rows = (
            db.query(CrmTag)
            .filter(CrmTag.id.in_(tag_ids))
            .order_by(CrmTag.sort_order.asc(), CrmTag.id.asc())
            .all()
        )
        tags = [{"id": t.id, "name": t.name, "color": t.color} for t in tag_rows]

    # تایم‌لاین رویدادهای ترکیبی مرتب‌شده نزولی بر اساس تاریخ
    timeline: List[Dict[str, Any]] = []
    for a in recent_activities:
        timeline.append(
            {
                "type": "task" if a["is_task"] else "activity",
                "date": a["activity_date"],
                "title": a["subject"] or a["activity_type"],
                "ref_id": a["id"],
            }
        )
    for d in open_deals + closed_deals:
        timeline.append(
            {"type": "deal", "date": d["created_at"], "title": d["title"], "ref_id": d["id"]}
        )
    for l in converted_leads:
        timeline.append(
            {"type": "lead", "date": l["created_at"], "title": l["name"], "ref_id": l["id"]}
        )
    for n in notes:
        context_bits = [bit for bit in (n.get("deal_title"), n.get("lead_name")) if bit]
        timeline.append(
            {
                "type": "note",
                "date": n["occurs_on"],
                "title": n["title"] or "یادداشت",
                "context": " · ".join(context_bits),
                "ref_id": n["id"],
            }
        )
    for doc in documents:
        timeline.append(
            {
                "type": "document",
                "date": doc["document_date"],
                "title": doc["code"],
                "document_type": doc["document_type"],
                "ref_id": doc["id"],
            }
        )
    for c in recent_calls:
        dir_fa = {"inbound": "ورودی", "outbound": "خروجی", "internal": "داخلی"}.get(c["direction"], c["direction"])
        timeline.append(
            {
                "type": "call",
                "date": c["started_at"],
                "title": f"تماس {dir_fa} {c.get('peer_number') or ''}".strip(),
                "ref_id": c["id"],
            }
        )
    timeline.sort(key=lambda x: (x.get("date") or ""), reverse=True)

    summary = {
        "open_deals_count": int(open_deals_count),
        "closed_deals_count": int(closed_deals_count),
        "open_deals_amount": float(open_deals_amount or 0),
        "closed_deals_amount": float(closed_deals_amount or 0),
        "open_tasks_count": int(tasks_open_count),
        "activities_count": len(recent_activities),
        "deals_list_truncated": int(open_deals_count) > len(open_deals) or int(closed_deals_count) > len(closed_deals),
    }

    financial = _person_financial(db, business_id, person_id)
    try:
        from app.services.crm_person_stats_service import build_person_commercial

        financial["commercial"] = build_person_commercial(db, business_id, person_id)
    except Exception:
        logger.exception("customer 360 commercial summary failed person_id=%s", person_id)
        financial["commercial"] = {"error": "commercial_unavailable"}
    from app.services.crm_next_action_service import next_action_for_person

    return {
        "person": core,
        "social_contacts": social_contacts,
        "summary": summary,
        "financial": financial,
        "next_action": next_action_for_person(db, business_id, person_id, financial=financial, ctx=ctx),
        "open_deals": open_deals,
        "closed_deals": closed_deals,
        "recent_activities": recent_activities,
        "tasks_open": tasks_open,
        "converted_leads": converted_leads,
        "notes": notes,
        "documents": documents,
        "recent_calls": recent_calls,
        "tags": tags,
        "timeline": timeline,
    }
