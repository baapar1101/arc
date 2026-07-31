# noqa: D100
"""سرویس دید ۳۶۰ درجه مشتری: تجمیع اطلاعات شخص، معاملات، فعالیت‌ها، وظایف، اسناد و برچسب‌ها."""
from __future__ import annotations

from datetime import datetime
from typing import Any, Dict, List, Optional

from sqlalchemy import and_, or_
from sqlalchemy.orm import Session, selectinload

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
from app.core.responses import ApiError


def _iso(dt: Optional[datetime]) -> Optional[str]:
    return dt.isoformat() if dt else None


def _full_name(user) -> Optional[str]:
    if not user:
        return None
    return f"{user.first_name or ''} {user.last_name or ''}".strip() or None


def get_customer_360(db: Session, business_id: int, person_id: int) -> Dict[str, Any]:
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

    # معاملات باز/بسته
    deals = (
        db.query(Deal)
        .options(selectinload(Deal.stage), selectinload(Deal.assigned_to))
        .filter(Deal.business_id == business_id, Deal.person_id == person_id)
        .order_by(Deal.created_at.desc())
        .all()
    )
    open_deals: List[Dict[str, Any]] = []
    closed_deals: List[Dict[str, Any]] = []
    for d in deals:
        item = {
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
        (closed_deals if d.closed_at else open_deals).append(item)

    # فعالیت‌های اخیر
    activities = (
        db.query(CrmActivity)
        .options(selectinload(CrmActivity.created_by), selectinload(CrmActivity.assigned_to))
        .filter(CrmActivity.business_id == business_id, CrmActivity.person_id == person_id)
        .order_by(CrmActivity.activity_date.desc())
        .limit(30)
        .all()
    )
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
    tasks_open_rows = (
        db.query(CrmActivity)
        .options(selectinload(CrmActivity.assigned_to))
        .filter(
            CrmActivity.business_id == business_id,
            CrmActivity.person_id == person_id,
            CrmActivity.is_task.is_(True),
            CrmActivity.status == "open",
        )
        .order_by(CrmActivity.due_at.asc().nullslast())
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
        db.query(Lead)
        .filter(Lead.business_id == business_id, Lead.person_id == person_id)
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

    # یادداشت‌های متصل از طریق سرنخ
    notes: List[Dict[str, Any]] = []
    if lead_ids:
        note_rows = (
            db.query(CrmNote)
            .filter(
                CrmNote.business_id == business_id,
                CrmNote.lead_id.in_(lead_ids),
                CrmNote.deleted_at.is_(None),
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
            }
            for n in note_rows
        ]

    # اسناد اخیر (فاکتورها) از طریق خطوط سند
    doc_rows = (
        db.query(Document)
        .join(DocumentLine, DocumentLine.document_id == Document.id)
        .filter(Document.business_id == business_id, DocumentLine.person_id == person_id)
        .order_by(Document.document_date.desc(), Document.id.desc())
        .distinct()
        .limit(20)
        .all()
    )
    documents = [
        {
            "id": d.id,
            "code": d.code,
            "document_type": d.document_type,
            "document_date": d.document_date.isoformat() if d.document_date else None,
            "is_proforma": bool(d.is_proforma),
            "description": d.description,
        }
        for d in doc_rows
    ]

    # برچسب‌ها از معاملات متصل
    deal_ids = [d.id for d in deals]
    tags: List[Dict[str, Any]] = []
    if deal_ids:
        tag_rows = (
            db.query(CrmTag)
            .join(CrmDealTagLink, CrmDealTagLink.tag_id == CrmTag.id)
            .filter(CrmDealTagLink.deal_id.in_(deal_ids), CrmTag.business_id == business_id)
            .distinct()
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
        timeline.append(
            {"type": "note", "date": n["occurs_on"], "title": n["title"] or "یادداشت", "ref_id": n["id"]}
        )
    for doc in documents:
        timeline.append(
            {"type": "document", "date": doc["document_date"], "title": doc["code"], "ref_id": doc["id"]}
        )
    timeline.sort(key=lambda x: (x.get("date") or ""), reverse=True)

    # خلاصه آماری
    total_won = sum(d["amount"] for d in closed_deals)
    summary = {
        "open_deals_count": len(open_deals),
        "closed_deals_count": len(closed_deals),
        "open_deals_amount": sum(d["amount"] for d in open_deals),
        "closed_deals_amount": total_won,
        "open_tasks_count": len(tasks_open),
        "activities_count": len(recent_activities),
    }

    return {
        "person": core,
        "social_contacts": social_contacts,
        "summary": summary,
        "open_deals": open_deals,
        "closed_deals": closed_deals,
        "recent_activities": recent_activities,
        "tasks_open": tasks_open,
        "converted_leads": converted_leads,
        "notes": notes,
        "documents": documents,
        "tags": tags,
        "timeline": timeline,
    }
