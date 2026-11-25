"""سازمان، سهمیه، صف و مجوز رکورد. سند حسابداری ساخته نمی‌شود."""
from __future__ import annotations

from datetime import date, datetime, time
from typing import Any

from sqlalchemy.exc import IntegrityError
from sqlalchemy import and_, func, or_
from sqlalchemy.orm import Session

from adapters.db.models.business_crm_settings import BusinessCrmSettings
from adapters.db.models.business_permission import BusinessPermission
from adapters.db.models.crm import (
    CrmLeadQueue,
    CrmLeadQueueMember,
    CrmManagerLink,
    CrmOrganization,
    CrmOrganizationContact,
    CrmProcessStage,
    CrmQuota,
    CrmRecordAcl,
    Deal,
    Lead,
)
from adapters.db.models.person import Person
from app.core.responses import ApiError
from app.services.crm_enterprise import (
    OPEN_FORECAST_CATEGORIES,
    descendant_ids,
    effective_forecast,
    manager_link_creates_cycle,
    person_belongs_to_organization,
    quota_progress,
    record_access,
)


def _commit(db: Session, code: str, message: str) -> None:
    try:
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        raise ApiError(code, message, http_status=400) from exc


def _person(db: Session, business_id: int, person_id: int) -> Person:
    row = db.query(Person).filter(Person.id == person_id, Person.business_id == business_id).first()
    if row is None:
        raise ApiError("CRM_PERSON_NOT_IN_BUSINESS", "شخص در این کسب‌وکار نیست.", http_status=400)
    return row


def _member(db: Session, business_id: int, user_id: int) -> None:
    row = db.query(BusinessPermission.id).filter(
        BusinessPermission.business_id == business_id, BusinessPermission.user_id == user_id
    ).first()
    if row is None:
        raise ApiError("CRM_USER_NOT_IN_BUSINESS", "کاربر عضو این کسب‌وکار نیست.", http_status=400)


def _settings(db: Session, business_id: int) -> BusinessCrmSettings:
    row = db.query(BusinessCrmSettings).filter(BusinessCrmSettings.business_id == business_id).first()
    if row is None:
        row = BusinessCrmSettings(business_id=business_id, record_acl_enabled=False)
        db.add(row)
        db.flush()
    return row


def create_organization(db: Session, business_id: int, name: str, billing_person_id: int, contact_ids: list[int]) -> CrmOrganization:
    _person(db, business_id, billing_person_id)
    cleaned = []
    for person_id in [billing_person_id, *contact_ids]:
        if person_id in cleaned:
            continue
        _person(db, business_id, int(person_id))
        cleaned.append(int(person_id))
    org = CrmOrganization(business_id=business_id, name=name.strip(), billing_person_id=int(billing_person_id))
    db.add(org)
    db.flush()
    for person_id in cleaned:
        db.add(CrmOrganizationContact(organization_id=org.id, person_id=person_id))
    _commit(db, "CRM_ORGANIZATION_EXISTS", "سازمانی با این نام وجود دارد.")
    db.refresh(org)
    return org


def _organization_payload(db: Session, business_id: int, org: CrmOrganization, names: dict[int, str] | None = None) -> dict[str, Any]:
    contacts = [int(item.person_id) for item in org.contacts]
    if names is None:
        ids = set(contacts) | {int(org.billing_person_id)}
        names = {}
        if ids:
            for person in db.query(Person).filter(Person.business_id == business_id, Person.id.in_(ids)).all():
                names[int(person.id)] = (person.alias_name or "").strip() or f"#{person.id}"
    billing_id = int(org.billing_person_id)
    return {
        "id": org.id,
        "name": org.name,
        "billing_person_id": billing_id,
        "billing_person_name": names.get(billing_id),
        "contact_ids": contacts,
        "contacts": [
            {"id": person_id, "name": names.get(person_id) or f"#{person_id}"}
            for person_id in contacts
            if person_id != billing_id
        ],
    }


def list_organizations(db: Session, business_id: int) -> list[dict[str, Any]]:
    rows = db.query(CrmOrganization).filter(CrmOrganization.business_id == business_id).order_by(CrmOrganization.name).all()
    person_ids = {int(org.billing_person_id) for org in rows}
    for org in rows:
        person_ids.update(int(item.person_id) for item in org.contacts)
    names: dict[int, str] = {}
    if person_ids:
        for person in db.query(Person).filter(Person.business_id == business_id, Person.id.in_(person_ids)).all():
            names[int(person.id)] = (person.alias_name or "").strip() or f"#{person.id}"
    return [_organization_payload(db, business_id, org, names) for org in rows]


def update_organization_contacts(
    db: Session,
    business_id: int,
    organization_id: int,
    contact_ids: list[int],
) -> dict[str, Any]:
    """مخاطبان را جایگزین می‌کند و شخص صورتحساب را همیشه در فهرست نگه می‌دارد."""
    org = _organization(db, business_id, organization_id)
    wanted: list[int] = []
    for person_id in [int(org.billing_person_id), *[int(item) for item in contact_ids]]:
        if person_id in wanted:
            continue
        _person(db, business_id, person_id)
        wanted.append(person_id)
    existing = {int(item.person_id): item for item in list(org.contacts)}
    removed = [person_id for person_id in existing if person_id not in wanted]
    if removed:
        linked = (
            db.query(Deal.id)
            .filter(
                Deal.business_id == business_id,
                Deal.organization_id == org.id,
                Deal.person_id.in_(removed),
            )
            .first()
        )
        if linked is not None:
            raise ApiError(
                "CRM_ORG_CONTACT_IN_USE",
                "این مخاطب هنوز روی یک فرصت همین سازمان است. اول سازمان فرصت را عوض کنید.",
                http_status=400,
            )
    for person_id in removed:
        db.delete(existing[person_id])
    for person_id in wanted:
        if person_id not in existing:
            db.add(CrmOrganizationContact(organization_id=org.id, person_id=person_id))
    db.commit()
    db.refresh(org)
    return _organization_payload(db, business_id, org)


def delete_organization(db: Session, business_id: int, organization_id: int) -> None:
    org = _organization(db, business_id, organization_id)
    used_by_deal = db.query(Deal.id).filter(Deal.business_id == business_id, Deal.organization_id == org.id).first()
    used_by_lead = db.query(Lead.id).filter(Lead.business_id == business_id, Lead.organization_id == org.id).first()
    if used_by_deal is not None or used_by_lead is not None:
        raise ApiError(
            "CRM_ORG_IN_USE",
            "این سازمان هنوز به یک سرنخ یا فرصت وصل است. اول آن اتصال را بردارید.",
            http_status=400,
        )
    db.delete(org)
    db.commit()


def _organization(db: Session, business_id: int, organization_id: int) -> CrmOrganization:
    row = db.query(CrmOrganization).filter(CrmOrganization.id == organization_id, CrmOrganization.business_id == business_id).first()
    if row is None:
        raise ApiError("NOT_FOUND", "سازمان یافت نشد.", http_status=404)
    return row


def change_deal_person(db: Session, business_id: int, deal: Deal, person_id: int) -> None:
    """شخص فرصت را عوض می‌کند. اگر سازمان وصل باشد، شخص جدید باید عضو همان سازمان باشد."""
    if int(person_id) == int(deal.person_id):
        return
    if db.query(Person.id).filter(Person.id == int(person_id), Person.business_id == business_id).first() is None:
        raise ApiError("CRM_PERSON_NOT_IN_BUSINESS", "شخص در این کسب‌وکار نیست.", http_status=400)
    if deal.organization_id:
        org = db.query(CrmOrganization).filter(
            CrmOrganization.id == deal.organization_id, CrmOrganization.business_id == business_id
        ).first()
        if org is not None:
            contacts = {int(item.person_id) for item in org.contacts}
            if not person_belongs_to_organization(org.billing_person_id, contacts, int(person_id)):
                raise ApiError(
                    "CRM_ORG_PERSON_MISMATCH",
                    "شخص فرصت باید شخص صورتحساب یا یکی از مخاطبان سازمان باشد.",
                    http_status=400,
                )
    deal.person_id = int(person_id)


def _organization_matches_person(org: CrmOrganization, person_id: int) -> bool:
    contacts = {int(item.person_id) for item in org.contacts}
    return person_belongs_to_organization(org.billing_person_id, contacts, person_id)


def link_converted_person_to_lead_organization(db: Session, business_id: int, lead: Lead, person_id: int, deal: Deal | None = None) -> None:
    """تبدیل سرنخ، شخص جدید را مخاطب همان سازمان می‌کند و فرصت تازه‌ساخته را به آن وصل می‌کند."""
    if not lead.organization_id:
        return
    org = db.query(CrmOrganization).filter(
        CrmOrganization.id == lead.organization_id, CrmOrganization.business_id == business_id
    ).first()
    if org is None:
        lead.organization_id = None
        return
    if not _organization_matches_person(org, int(person_id)):
        db.add(CrmOrganizationContact(organization_id=org.id, person_id=int(person_id)))
        db.flush()
    if deal is not None:
        deal.organization_id = org.id


def attach_organization_to_deal(
    db: Session, business_id: int, deal_id: int, organization_id: int | None, ctx: Any = None
) -> Deal:
    deal = db.query(Deal).filter(Deal.id == deal_id, Deal.business_id == business_id).first()
    if deal is None:
        raise ApiError("NOT_FOUND", "فرصت فروش یافت نشد.", http_status=404)
    if ctx is not None:
        assert_can_view_record(db, business_id, ctx, "deal", deal, write=True)
    if organization_id is None:
        deal.organization_id = None
    else:
        org = _organization(db, business_id, organization_id)
        if not _organization_matches_person(org, int(deal.person_id)):
            raise ApiError("CRM_ORG_PERSON_MISMATCH", "شخص فرصت باید شخص صورتحساب یا یکی از مخاطبان سازمان باشد.", http_status=400)
        deal.organization_id = org.id
    db.commit()
    db.refresh(deal)
    return deal


def attach_organization_to_lead(
    db: Session, business_id: int, lead_id: int, organization_id: int | None, ctx: Any = None
) -> Lead:
    lead = db.query(Lead).filter(Lead.id == lead_id, Lead.business_id == business_id).first()
    if lead is None:
        raise ApiError("NOT_FOUND", "سرنخ یافت نشد.", http_status=404)
    if ctx is not None:
        assert_can_view_record(db, business_id, ctx, "lead", lead, write=True)
    if organization_id is None:
        lead.organization_id = None
    else:
        org = _organization(db, business_id, organization_id)
        if lead.person_id is not None and not _organization_matches_person(org, int(lead.person_id)):
            raise ApiError("CRM_ORG_PERSON_MISMATCH", "شخص سرنخ باید شخص صورتحساب یا یکی از مخاطبان سازمان باشد.", http_status=400)
        lead.organization_id = org.id
    db.commit()
    db.refresh(lead)
    return lead


def set_forecast_category(db: Session, business_id: int, deal_id: int, category: str | None, ctx: Any = None) -> Deal:
    deal = db.query(Deal).filter(Deal.id == deal_id, Deal.business_id == business_id).first()
    if deal is None:
        raise ApiError("NOT_FOUND", "فرصت فروش یافت نشد.", http_status=404)
    if ctx is not None:
        assert_can_view_record(db, business_id, ctx, "deal", deal, write=True)
    if category is not None and category not in OPEN_FORECAST_CATEGORIES:
        raise ApiError("CRM_FORECAST_CATEGORY_INVALID", "دسته پیش‌بینی باید pipeline، best_case یا commit باشد.", http_status=400)
    deal.forecast_category = category
    db.commit()
    db.refresh(deal)
    return deal


def create_quota(db: Session, business_id: int, user_id: int, period_start: date, period_end: date, amount: float, currency_id: int) -> CrmQuota:
    if period_end < period_start:
        raise ApiError("CRM_QUOTA_PERIOD_INVALID", "پایان دوره نباید پیش از شروع باشد.", http_status=400)
    if amount < 0:
        raise ApiError("CRM_QUOTA_AMOUNT_INVALID", "مبلغ سهمیه منفی نیست.", http_status=400)
    _member(db, business_id, user_id)
    from app.services.crm_guards import assert_currency_enabled_for_business

    assert_currency_enabled_for_business(db, business_id, currency_id)
    row = CrmQuota(
        business_id=business_id,
        user_id=user_id,
        period_start=period_start,
        period_end=period_end,
        amount=amount,
        currency_id=currency_id,
    )
    db.add(row)
    _commit(db, "CRM_QUOTA_EXISTS", "برای این کاربر، شروع دوره و ارز سهمیه ثبت شده است.")
    db.refresh(row)
    return row


def _won_amount(db: Session, business_id: int, user_id: int, currency_id: int, period_start: date, period_end: date) -> float:
    start = datetime.combine(period_start, time.min)
    end = datetime.combine(period_end, time.max)
    total = (
        db.query(func.coalesce(func.sum(Deal.amount), 0))
        .join(CrmProcessStage, CrmProcessStage.id == Deal.stage_id)
        .filter(
            Deal.business_id == business_id,
            Deal.assigned_to_user_id == user_id,
            Deal.currency_id == currency_id,
            Deal.closed_at.isnot(None),
            Deal.closed_at >= start,
            Deal.closed_at <= end,
            CrmProcessStage.is_win.is_(True),
        )
        .scalar()
    )
    return float(total or 0)


def list_quotas(db: Session, business_id: int) -> list[dict[str, Any]]:
    rows = db.query(CrmQuota).filter(CrmQuota.business_id == business_id).order_by(CrmQuota.period_start.desc()).all()
    items = []
    for row in rows:
        won = _won_amount(db, business_id, row.user_id, row.currency_id, row.period_start, row.period_end)
        items.append(
            {
                "id": row.id,
                "user_id": row.user_id,
                "period_start": row.period_start.isoformat(),
                "period_end": row.period_end.isoformat(),
                "currency_id": row.currency_id,
                **quota_progress(row.amount, won),
            }
        )
    return items


def delete_quota(db: Session, business_id: int, quota_id: int) -> None:
    row = db.query(CrmQuota).filter(CrmQuota.id == quota_id, CrmQuota.business_id == business_id).first()
    if row is None:
        raise ApiError("NOT_FOUND", "سهمیه یافت نشد.", http_status=404)
    db.delete(row)
    db.commit()


def set_manager(db: Session, business_id: int, manager_user_id: int, member_user_id: int) -> CrmManagerLink:
    _member(db, business_id, manager_user_id)
    _member(db, business_id, member_user_id)
    links = [
        (int(row.manager_user_id), int(row.member_user_id))
        for row in db.query(CrmManagerLink).filter(CrmManagerLink.business_id == business_id).all()
        if int(row.member_user_id) != int(member_user_id)
    ]
    if manager_link_creates_cycle(links, manager_user_id, member_user_id):
        raise ApiError("CRM_MANAGER_CYCLE", "این ارتباط مدیر چرخه می‌سازد.", http_status=400)
    row = db.query(CrmManagerLink).filter(CrmManagerLink.business_id == business_id, CrmManagerLink.member_user_id == member_user_id).first()
    if row is None:
        row = CrmManagerLink(business_id=business_id, manager_user_id=manager_user_id, member_user_id=member_user_id)
        db.add(row)
    else:
        row.manager_user_id = manager_user_id
    db.commit()
    db.refresh(row)
    return row


def list_manager_links(db: Session, business_id: int) -> list[dict[str, Any]]:
    rows = db.query(CrmManagerLink).filter(CrmManagerLink.business_id == business_id).order_by(CrmManagerLink.id).all()
    return [
        {"id": row.id, "manager_user_id": row.manager_user_id, "member_user_id": row.member_user_id}
        for row in rows
    ]


def delete_manager_link(db: Session, business_id: int, link_id: int) -> None:
    row = db.query(CrmManagerLink).filter(CrmManagerLink.id == link_id, CrmManagerLink.business_id == business_id).first()
    if row is None:
        raise ApiError("NOT_FOUND", "ارتباط مدیر یافت نشد.", http_status=404)
    db.delete(row)
    db.commit()


def manager_rollup(db: Session, business_id: int, manager_user_id: int, ctx: Any | None = None) -> dict[str, Any]:
    _member(db, business_id, manager_user_id)
    links = [
        (int(row.manager_user_id), int(row.member_user_id))
        for row in db.query(CrmManagerLink).filter(CrmManagerLink.business_id == business_id).all()
    ]
    if ctx is not None and not _sees_all(ctx, business_id):
        viewer = int(ctx.get_user_id())
        if viewer != int(manager_user_id) and int(manager_user_id) not in descendant_ids(links, viewer):
            raise ApiError("NOT_FOUND", "جمع این مدیر در دسترس نیست.", http_status=404)
    team = [manager_user_id, *descendant_ids(links, manager_user_id)]
    deals = (
        db.query(Deal.currency_id, func.coalesce(func.sum(Deal.amount), 0), func.count(Deal.id))
        .filter(Deal.business_id == business_id, Deal.closed_at.is_(None), Deal.assigned_to_user_id.in_(team))
        .group_by(Deal.currency_id)
        .all()
    )
    return {
        "manager_user_id": manager_user_id,
        "team_user_ids": team,
        "open_by_currency": [
            {"currency_id": row[0], "amount": float(row[1] or 0), "deal_count": int(row[2] or 0)}
            for row in deals
        ],
    }


def create_queue(db: Session, business_id: int, name: str, member_ids: list[int]) -> CrmLeadQueue:
    queue = CrmLeadQueue(business_id=business_id, name=name.strip())
    db.add(queue)
    db.flush()
    seen = set()
    for user_id in member_ids:
        if int(user_id) in seen:
            continue
        _member(db, business_id, int(user_id))
        seen.add(int(user_id))
        db.add(CrmLeadQueueMember(queue_id=queue.id, user_id=int(user_id)))
    _commit(db, "CRM_QUEUE_EXISTS", "صفی با این نام وجود دارد.")
    db.refresh(queue)
    return queue


def list_queues(db: Session, business_id: int) -> list[dict[str, Any]]:
    rows = db.query(CrmLeadQueue).filter(CrmLeadQueue.business_id == business_id).order_by(CrmLeadQueue.name).all()
    return [{"id": row.id, "name": row.name, "member_ids": [int(item.user_id) for item in row.members]} for row in rows]


def delete_queue(db: Session, business_id: int, queue_id: int) -> None:
    queue = db.query(CrmLeadQueue).filter(CrmLeadQueue.id == queue_id, CrmLeadQueue.business_id == business_id).first()
    if queue is None:
        raise ApiError("NOT_FOUND", "صف یافت نشد.", http_status=404)
    in_use = db.query(Lead.id).filter(Lead.business_id == business_id, Lead.queue_id == queue.id).first()
    if in_use is not None:
        raise ApiError(
            "CRM_QUEUE_IN_USE",
            "هنوز سرنخی در این صف است. اول سرنخ را از صف بردارید.",
            http_status=400,
        )
    db.delete(queue)
    db.commit()


def claim_lead(db: Session, business_id: int, lead_id: int, user_id: int) -> Lead:
    _member(db, business_id, user_id)
    lead = db.query(Lead).filter(Lead.id == lead_id, Lead.business_id == business_id).first()
    if lead is None or lead.queue_id is None:
        raise ApiError("CRM_QUEUE_LEAD_NOT_FOUND", "این سرنخ در صفی نیست.", http_status=404)
    actor = acl_actor(db, user_id)
    if record_acl_enforced(db, business_id, actor):
        try:
            assert_can_view_record(db, business_id, actor, "lead", lead, write=False)
        except ApiError:
            raise ApiError("CRM_QUEUE_LEAD_NOT_FOUND", "این سرنخ در صفی نیست.", http_status=404) from None
    member = db.query(CrmLeadQueueMember.id).filter(
        CrmLeadQueueMember.queue_id == lead.queue_id, CrmLeadQueueMember.user_id == user_id
    ).first()
    if member is None:
        raise ApiError("CRM_QUEUE_FORBIDDEN", "عضو این صف نیستید.", http_status=403)
    if lead.assigned_to_user_id not in (None, user_id):
        raise ApiError("CRM_QUEUE_ALREADY_CLAIMED", "این سرنخ را شخص دیگری برداشته است.", http_status=409)
    lead.assigned_to_user_id = user_id
    db.commit()
    db.refresh(lead)
    return lead


def assign_lead_queue(db: Session, business_id: int, lead_id: int, queue_id: int | None, ctx: Any = None) -> Lead:
    lead = db.query(Lead).filter(Lead.id == lead_id, Lead.business_id == business_id).first()
    if lead is None:
        raise ApiError("NOT_FOUND", "سرنخ یافت نشد.", http_status=404)
    if ctx is not None:
        assert_can_view_record(db, business_id, ctx, "lead", lead, write=True)
    if queue_id is not None:
        queue = db.query(CrmLeadQueue).filter(CrmLeadQueue.id == queue_id, CrmLeadQueue.business_id == business_id).first()
        if queue is None:
            raise ApiError("NOT_FOUND", "صف یافت نشد.", http_status=404)
        lead.queue_id = queue.id
        lead.assigned_to_user_id = None
    else:
        lead.queue_id = None
    db.commit()
    db.refresh(lead)
    return lead


def grant_record_access(db: Session, business_id: int, entity_type: str, entity_id: int, user_id: int, access: str, ctx: Any = None) -> CrmRecordAcl:
    if entity_type not in {"lead", "deal"} or access not in {"view", "edit"}:
        raise ApiError("CRM_ACL_INVALID", "نوع رکورد یا سطح دسترسی نامعتبر است.", http_status=400)
    _member(db, business_id, user_id)
    model = Lead if entity_type == "lead" else Deal
    target = db.query(model).filter(model.id == entity_id, model.business_id == business_id).first()
    if target is None:
        raise ApiError("NOT_FOUND", "رکورد یافت نشد.", http_status=404)
    if ctx is not None:
        assert_can_view_record(db, business_id, ctx, entity_type, target, write=True)
    row = db.query(CrmRecordAcl).filter(
        CrmRecordAcl.business_id == business_id,
        CrmRecordAcl.entity_type == entity_type,
        CrmRecordAcl.entity_id == entity_id,
        CrmRecordAcl.user_id == user_id,
    ).first()
    if row is None:
        row = CrmRecordAcl(business_id=business_id, entity_type=entity_type, entity_id=entity_id, user_id=user_id, access=access)
        db.add(row)
    else:
        row.access = access
    db.commit()
    db.refresh(row)
    return row


def list_record_access(db: Session, business_id: int, ctx: Any = None) -> list[dict[str, Any]]:
    rows = (
        db.query(CrmRecordAcl)
        .filter(CrmRecordAcl.business_id == business_id)
        .order_by(CrmRecordAcl.id.desc())
        .limit(100)
        .all()
    )
    if ctx is not None and record_acl_enforced(db, business_id, ctx):
        lead_ids = [int(row.entity_id) for row in rows if row.entity_type == "lead"]
        deal_ids = [int(row.entity_id) for row in rows if row.entity_type == "deal"]
        visible_leads = {
            int(item[0]) for item in restrict_visibility_query(
                db.query(Lead.id).filter(Lead.business_id == business_id, Lead.id.in_(lead_ids or [0])),
                db, business_id, ctx, Lead, "lead",
            ).all()
        } if lead_ids else set()
        visible_deals = {
            int(item[0]) for item in restrict_visibility_query(
                db.query(Deal.id).filter(Deal.business_id == business_id, Deal.id.in_(deal_ids or [0])),
                db, business_id, ctx, Deal, "deal",
            ).all()
        } if deal_ids else set()
        rows = [
            row for row in rows
            if (row.entity_type == "lead" and int(row.entity_id) in visible_leads)
            or (row.entity_type == "deal" and int(row.entity_id) in visible_deals)
        ]
    lead_ids = [int(row.entity_id) for row in rows if row.entity_type == "lead"]
    deal_ids = [int(row.entity_id) for row in rows if row.entity_type == "deal"]
    lead_labels: dict[int, str] = {}
    deal_labels: dict[int, str] = {}
    if lead_ids:
        for lead in db.query(Lead.id, Lead.name, Lead.code).filter(Lead.business_id == business_id, Lead.id.in_(lead_ids)).all():
            lead_labels[int(lead.id)] = (lead.name or "").strip() or str(lead.code or lead.id)
    if deal_ids:
        for deal in db.query(Deal.id, Deal.title, Deal.code).filter(Deal.business_id == business_id, Deal.id.in_(deal_ids)).all():
            deal_labels[int(deal.id)] = (deal.title or "").strip() or str(deal.code or deal.id)
    items = []
    for row in rows:
        entity_id = int(row.entity_id)
        label = lead_labels.get(entity_id) if row.entity_type == "lead" else deal_labels.get(entity_id)
        items.append(
            {
                "id": row.id,
                "entity_type": row.entity_type,
                "entity_id": entity_id,
                "entity_label": label or f"#{entity_id}",
                "user_id": row.user_id,
                "access": row.access,
            }
        )
    return items


def revoke_record_access(db: Session, business_id: int, acl_id: int, ctx: Any = None) -> None:
    row = db.query(CrmRecordAcl).filter(CrmRecordAcl.id == acl_id, CrmRecordAcl.business_id == business_id).first()
    if row is None:
        raise ApiError("NOT_FOUND", "دسترسی رکورد یافت نشد.", http_status=404)
    if ctx is not None:
        model = Lead if row.entity_type == "lead" else Deal
        target = db.query(model).filter(model.id == row.entity_id, model.business_id == business_id).first()
        if target is None:
            raise ApiError("NOT_FOUND", "دسترسی رکورد یافت نشد.", http_status=404)
        assert_can_view_record(db, business_id, ctx, row.entity_type, target, write=True)
    db.delete(row)
    db.commit()


def set_record_acl_enabled(db: Session, business_id: int, enabled: bool) -> bool:
    row = _settings(db, business_id)
    row.record_acl_enabled = bool(enabled)
    db.commit()
    return bool(row.record_acl_enabled)


class _AclActor:
    """نمای حداقلی کاربر برای همان قواعد دیدن رکورد، وقتی فقط شناسه کاربر در دست است."""

    def __init__(self, db: Session, user_id: int) -> None:
        from adapters.db.models.user import User

        self.db = db
        self._user_id = int(user_id)
        user = db.get(User, self._user_id)
        permissions = user.app_permissions if user is not None and isinstance(user.app_permissions, dict) else {}
        self._super = bool(permissions.get("superadmin"))

    def get_user_id(self) -> int:
        return self._user_id

    def is_superadmin(self) -> bool:
        return self._super

    def is_business_owner(self, business_id: int) -> bool:
        from adapters.db.models.business import Business

        business = self.db.get(Business, business_id)
        return bool(business and int(business.owner_id) == self._user_id)


def acl_actor(db: Session, user_id: int) -> _AclActor:
    return _AclActor(db, user_id)


def record_acl_enforced(db: Session, business_id: int, ctx: Any) -> bool:
    if _sees_all(ctx, business_id):
        return False
    settings = db.query(BusinessCrmSettings).filter(BusinessCrmSettings.business_id == business_id).first()
    return bool(settings and settings.record_acl_enabled)


def _sees_all(ctx: Any, business_id: int) -> bool:
    if ctx.is_superadmin():
        return True
    return bool(ctx.is_business_owner(business_id))


def _viewer_context(db: Session, business_id: int, user_id: int, entity_type: str, row: Any) -> dict[str, Any]:
    settings = db.query(BusinessCrmSettings).filter(BusinessCrmSettings.business_id == business_id).first()
    enforced = bool(settings and settings.record_acl_enabled)
    links = [
        (int(item.manager_user_id), int(item.member_user_id))
        for item in db.query(CrmManagerLink).filter(CrmManagerLink.business_id == business_id).all()
    ]
    reports = set(descendant_ids(links, user_id))
    acl = db.query(CrmRecordAcl.access).filter(
        CrmRecordAcl.business_id == business_id,
        CrmRecordAcl.entity_type == entity_type,
        CrmRecordAcl.entity_id == row.id,
        CrmRecordAcl.user_id == user_id,
    ).first()
    queue_member = False
    if entity_type == "lead" and row.queue_id:
        queue_member = db.query(CrmLeadQueueMember.id).filter(
            CrmLeadQueueMember.queue_id == row.queue_id, CrmLeadQueueMember.user_id == user_id
        ).first() is not None
    return {
        "enforced": enforced,
        "acl_access": acl[0] if acl else None,
        "manages_assignee": row.assigned_to_user_id in reports,
        "queue_member": queue_member,
    }


def guard_record(db: Session, business_id: int, ctx: Any, entity_type: str, row: Any, *, write: bool = False) -> None:
    """همان کنترل دسترسی رکورد، با خطای متنی برای ابزارهایی که ApiError را به کاربر نشان نمی‌دهند."""
    try:
        assert_can_view_record(db, business_id, ctx, entity_type, row, write=write)
    except ApiError as exc:
        raise ValueError(exc.message) from exc


def assert_activity_access(db: Session, business_id: int, ctx: Any, activity: Any, *, write: bool = False) -> None:
    """فعالیت وصل به سرنخ یا فرصت پنهان، همان خطای دیدن آن رکورد را می‌دهد."""
    _assert_activity_link(db, business_id, ctx, "lead", getattr(activity, "lead_id", None), write=write)
    _assert_activity_link(db, business_id, ctx, "deal", getattr(activity, "deal_id", None), write=write)


def guard_activity(db: Session, business_id: int, ctx: Any, activity: Any, *, write: bool = False) -> None:
    try:
        assert_activity_access(db, business_id, ctx, activity, write=write)
    except ApiError as exc:
        raise ValueError(exc.message) from exc


def _assert_activity_link(db: Session, business_id: int, ctx: Any, entity_type: str, row_id: int | None, *, write: bool) -> None:
    if not row_id:
        return
    model = Lead if entity_type == "lead" else Deal
    row = db.query(model).filter(and_(model.id == int(row_id), model.business_id == business_id)).first()
    if row is None:
        if record_acl_enforced(db, business_id, ctx):
            raise ApiError("NOT_FOUND", "رکورد یافت نشد.", http_status=404)
        return
    assert_can_view_record(db, business_id, ctx, entity_type, row, write=write)


def restrict_activity_query(query, db: Session, business_id: int, ctx: Any, activity_model):
    if not record_acl_enforced(db, business_id, ctx):
        return query
    from sqlalchemy.orm import aliased

    lead_alias = aliased(Lead)
    deal_alias = aliased(Deal)
    visible_leads = restrict_visibility_query(
        db.query(lead_alias.id).filter(lead_alias.business_id == business_id),
        db, business_id, ctx, lead_alias, "lead",
    )
    visible_deals = restrict_visibility_query(
        db.query(deal_alias.id).filter(deal_alias.business_id == business_id),
        db, business_id, ctx, deal_alias, "deal",
    )
    return query.filter(
        or_(activity_model.lead_id.is_(None), activity_model.lead_id.in_(visible_leads)),
        or_(activity_model.deal_id.is_(None), activity_model.deal_id.in_(visible_deals)),
    )


def assert_can_view_record(db: Session, business_id: int, ctx: Any, entity_type: str, row: Any, *, write: bool = False) -> None:
    if _sees_all(ctx, business_id):
        return
    user_id = int(ctx.get_user_id())
    context = _viewer_context(db, business_id, user_id, entity_type, row)
    access = record_access(
        enforced=context["enforced"],
        is_owner=False,
        user_id=user_id,
        assigned_to=row.assigned_to_user_id,
        created_by=row.created_by_user_id,
        acl_access=context["acl_access"],
        manages_assignee=context["manages_assignee"],
        queue_member=context["queue_member"],
    )
    if access == "none":
        raise ApiError("NOT_FOUND", "رکورد یافت نشد.", http_status=404)
    if write and access != "edit":
        raise ApiError("CRM_RECORD_FORBIDDEN", "مجوز ویرایش این رکورد را ندارید.", http_status=403)


def restrict_visibility_query(query, db: Session, business_id: int, ctx: Any, model, entity_type: str):
    if _sees_all(ctx, business_id):
        return query
    settings = db.query(BusinessCrmSettings).filter(BusinessCrmSettings.business_id == business_id).first()
    if settings is None or not settings.record_acl_enabled:
        return query
    user_id = int(ctx.get_user_id())
    links = [
        (int(item.manager_user_id), int(item.member_user_id))
        for item in db.query(CrmManagerLink).filter(CrmManagerLink.business_id == business_id).all()
    ]
    reports = descendant_ids(links, user_id)
    clauses = [
        model.assigned_to_user_id == user_id,
        model.created_by_user_id == user_id,
        model.id.in_(
            db.query(CrmRecordAcl.entity_id).filter(
                CrmRecordAcl.business_id == business_id,
                CrmRecordAcl.entity_type == entity_type,
                CrmRecordAcl.user_id == user_id,
            )
        ),
    ]
    if reports:
        clauses.append(model.assigned_to_user_id.in_(reports))
    if entity_type == "lead":
        queue_ids = [
            int(row.queue_id)
            for row in db.query(CrmLeadQueueMember.queue_id).join(CrmLeadQueue, CrmLeadQueue.id == CrmLeadQueueMember.queue_id).filter(
                CrmLeadQueue.business_id == business_id, CrmLeadQueueMember.user_id == user_id
            ).all()
        ]
        if queue_ids:
            clauses.append(and_(model.queue_id.in_(queue_ids), model.assigned_to_user_id.is_(None)))
    return query.filter(or_(*clauses))
