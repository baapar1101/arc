"""مسیرهای سازمان فروش CRM."""
from __future__ import annotations

from datetime import date
from typing import Any

from fastapi import APIRouter, Body, Depends, Path, Request
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import AuthContext, get_current_user
from app.core.permissions import require_business_access, require_business_permission_dep
from app.core.responses import success_response
from app.services import crm_enterprise_service as enterprise
from app.services.crm_enterprise import effective_forecast

router = APIRouter(prefix="/crm", tags=["CRM enterprise"])


class OrganizationCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=255)
    billing_person_id: int = Field(..., gt=0)
    contact_ids: list[int] = Field(default_factory=list)


class OrganizationContactsUpdate(BaseModel):
    contact_ids: list[int] = Field(default_factory=list)


class DealOrganizationUpdate(BaseModel):
    organization_id: int | None = None


class ForecastUpdate(BaseModel):
    forecast_category: str | None = None


class QuotaCreate(BaseModel):
    user_id: int = Field(..., gt=0)
    period_start: date
    period_end: date
    amount: float = Field(..., ge=0)
    currency_id: int = Field(..., gt=0)


class ManagerLinkCreate(BaseModel):
    manager_user_id: int = Field(..., gt=0)
    member_user_id: int = Field(..., gt=0)


class QueueCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=120)
    member_ids: list[int] = Field(default_factory=list)


class LeadQueueUpdate(BaseModel):
    queue_id: int | None = None


class RecordAclGrant(BaseModel):
    entity_type: str
    entity_id: int = Field(..., gt=0)
    user_id: int = Field(..., gt=0)
    access: str = "view"


class RecordAclToggle(BaseModel):
    enabled: bool


@router.get("/businesses/{business_id}/organizations")
@require_business_access("business_id")
async def list_organizations(
    request: Request,
    business_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "view")),
) -> dict[str, Any]:
    return success_response(data={"items": enterprise.list_organizations(db, business_id)}, request=request)


@router.post("/businesses/{business_id}/organizations")
@require_business_access("business_id")
async def create_organization(
    request: Request,
    business_id: int = Path(..., gt=0),
    body: OrganizationCreate = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "write")),
) -> dict[str, Any]:
    org = enterprise.create_organization(db, business_id, body.name, body.billing_person_id, body.contact_ids)
    return success_response(data={"id": org.id, "name": org.name, "billing_person_id": org.billing_person_id}, request=request)


@router.delete("/businesses/{business_id}/organizations/{organization_id}")
@require_business_access("business_id")
async def delete_organization(
    request: Request,
    business_id: int = Path(..., gt=0),
    organization_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "write")),
) -> dict[str, Any]:
    enterprise.delete_organization(db, business_id, organization_id)
    return success_response(data={"id": organization_id}, request=request)


@router.patch("/businesses/{business_id}/organizations/{organization_id}")
@require_business_access("business_id")
async def update_organization_contacts(
    request: Request,
    business_id: int = Path(..., gt=0),
    organization_id: int = Path(..., gt=0),
    body: OrganizationContactsUpdate = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "write")),
) -> dict[str, Any]:
    data = enterprise.update_organization_contacts(db, business_id, organization_id, body.contact_ids)
    return success_response(data=data, request=request)


@router.patch("/businesses/{business_id}/deals/{deal_id}/organization")
@require_business_access("business_id")
async def update_deal_organization(
    request: Request,
    business_id: int = Path(..., gt=0),
    deal_id: int = Path(..., gt=0),
    body: DealOrganizationUpdate = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "write")),
) -> dict[str, Any]:
    deal = enterprise.attach_organization_to_deal(db, business_id, deal_id, body.organization_id, ctx)
    return success_response(data={"id": deal.id, "organization_id": deal.organization_id, "organization_name": deal.organization.name if deal.organization else None}, request=request)


@router.patch("/businesses/{business_id}/leads/{lead_id}/organization")
@require_business_access("business_id")
async def update_lead_organization(
    request: Request,
    business_id: int = Path(..., gt=0),
    lead_id: int = Path(..., gt=0),
    body: DealOrganizationUpdate = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "write")),
) -> dict[str, Any]:
    lead = enterprise.attach_organization_to_lead(db, business_id, lead_id, body.organization_id, ctx)
    return success_response(
        data={"id": lead.id, "organization_id": lead.organization_id, "organization_name": lead.organization.name if lead.organization else None},
        request=request,
    )


@router.patch("/businesses/{business_id}/deals/{deal_id}/forecast")
@require_business_access("business_id")
async def update_deal_forecast(
    request: Request,
    business_id: int = Path(..., gt=0),
    deal_id: int = Path(..., gt=0),
    body: ForecastUpdate = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "write")),
) -> dict[str, Any]:
    deal = enterprise.set_forecast_category(db, business_id, deal_id, body.forecast_category, ctx)
    stage = deal.stage
    category = effective_forecast(
        closed=deal.closed_at is not None,
        is_win=bool(stage and stage.is_win),
        is_lost=bool(stage and stage.is_lost),
        probability=deal.probability_percent,
        override=deal.forecast_category,
    )
    return success_response(data={"id": deal.id, "forecast_category": category, "forecast_override": deal.forecast_category}, request=request)


@router.get("/businesses/{business_id}/quotas")
@require_business_access("business_id")
async def list_quotas(
    request: Request,
    business_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "view")),
) -> dict[str, Any]:
    return success_response(data={"items": enterprise.list_quotas(db, business_id)}, request=request)


@router.post("/businesses/{business_id}/quotas")
@require_business_access("business_id")
async def create_quota(
    request: Request,
    business_id: int = Path(..., gt=0),
    body: QuotaCreate = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "write")),
) -> dict[str, Any]:
    row = enterprise.create_quota(db, business_id, body.user_id, body.period_start, body.period_end, body.amount, body.currency_id)
    return success_response(data={"id": row.id}, request=request)


@router.delete("/businesses/{business_id}/quotas/{quota_id}")
@require_business_access("business_id")
async def delete_quota(
    request: Request,
    business_id: int = Path(..., gt=0),
    quota_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "write")),
) -> dict[str, Any]:
    enterprise.delete_quota(db, business_id, quota_id)
    return success_response(data={"id": quota_id}, request=request)


@router.get("/businesses/{business_id}/manager-links")
@require_business_access("business_id")
async def list_manager_links(
    request: Request,
    business_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "view")),
) -> dict[str, Any]:
    return success_response(data={"items": enterprise.list_manager_links(db, business_id)}, request=request)


@router.delete("/businesses/{business_id}/manager-links/{link_id}")
@require_business_access("business_id")
async def delete_manager_link(
    request: Request,
    business_id: int = Path(..., gt=0),
    link_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "write")),
) -> dict[str, Any]:
    enterprise.delete_manager_link(db, business_id, link_id)
    return success_response(data={"id": link_id}, request=request)


@router.post("/businesses/{business_id}/manager-links")
@require_business_access("business_id")
async def create_manager_link(
    request: Request,
    business_id: int = Path(..., gt=0),
    body: ManagerLinkCreate = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "write")),
) -> dict[str, Any]:
    row = enterprise.set_manager(db, business_id, body.manager_user_id, body.member_user_id)
    return success_response(data={"id": row.id, "manager_user_id": row.manager_user_id, "member_user_id": row.member_user_id}, request=request)


@router.get("/businesses/{business_id}/manager-rollup/{manager_user_id}")
@require_business_access("business_id")
async def get_manager_rollup(
    request: Request,
    business_id: int = Path(..., gt=0),
    manager_user_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "view")),
) -> dict[str, Any]:
    return success_response(data=enterprise.manager_rollup(db, business_id, manager_user_id, ctx), request=request)


@router.get("/businesses/{business_id}/lead-queues")
@require_business_access("business_id")
async def list_lead_queues(
    request: Request,
    business_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "view")),
) -> dict[str, Any]:
    return success_response(data={"items": enterprise.list_queues(db, business_id)}, request=request)


@router.delete("/businesses/{business_id}/lead-queues/{queue_id}")
@require_business_access("business_id")
async def delete_lead_queue(
    request: Request,
    business_id: int = Path(..., gt=0),
    queue_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "write")),
) -> dict[str, Any]:
    enterprise.delete_queue(db, business_id, queue_id)
    return success_response(data={"id": queue_id}, request=request)


@router.post("/businesses/{business_id}/lead-queues")
@require_business_access("business_id")
async def create_lead_queue(
    request: Request,
    business_id: int = Path(..., gt=0),
    body: QueueCreate = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "write")),
) -> dict[str, Any]:
    queue = enterprise.create_queue(db, business_id, body.name, body.member_ids)
    return success_response(data={"id": queue.id, "name": queue.name}, request=request)


@router.post("/businesses/{business_id}/leads/{lead_id}/claim")
@require_business_access("business_id")
async def claim_queued_lead(
    request: Request,
    business_id: int = Path(..., gt=0),
    lead_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "write")),
) -> dict[str, Any]:
    lead = enterprise.claim_lead(db, business_id, lead_id, int(ctx.get_user_id()))
    return success_response(data={"id": lead.id, "assigned_to_user_id": lead.assigned_to_user_id}, request=request)


@router.patch("/businesses/{business_id}/leads/{lead_id}/queue")
@require_business_access("business_id")
async def update_lead_queue(
    request: Request,
    business_id: int = Path(..., gt=0),
    lead_id: int = Path(..., gt=0),
    body: LeadQueueUpdate = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "write")),
) -> dict[str, Any]:
    lead = enterprise.assign_lead_queue(db, business_id, lead_id, body.queue_id, ctx)
    return success_response(data={"id": lead.id, "queue_id": lead.queue_id}, request=request)


@router.get("/businesses/{business_id}/record-acl")
@require_business_access("business_id")
async def list_record_acl(
    request: Request,
    business_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "view")),
) -> dict[str, Any]:
    return success_response(data={"items": enterprise.list_record_access(db, business_id, ctx)}, request=request)


@router.delete("/businesses/{business_id}/record-acl/{acl_id}")
@require_business_access("business_id")
async def revoke_record_acl(
    request: Request,
    business_id: int = Path(..., gt=0),
    acl_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "write")),
) -> dict[str, Any]:
    enterprise.revoke_record_access(db, business_id, acl_id, ctx)
    return success_response(data={"id": acl_id}, request=request)


@router.put("/businesses/{business_id}/record-acl")
@require_business_access("business_id")
async def grant_record_acl(
    request: Request,
    business_id: int = Path(..., gt=0),
    body: RecordAclGrant = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "write")),
) -> dict[str, Any]:
    row = enterprise.grant_record_access(db, business_id, body.entity_type, body.entity_id, body.user_id, body.access, ctx)
    return success_response(data={"id": row.id, "access": row.access}, request=request)


@router.put("/businesses/{business_id}/record-acl/enabled")
@require_business_access("business_id")
async def toggle_record_acl(
    request: Request,
    business_id: int = Path(..., gt=0),
    body: RecordAclToggle = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "write")),
) -> dict[str, Any]:
    enabled = enterprise.set_record_acl_enabled(db, business_id, body.enabled)
    return success_response(data={"enabled": enabled}, request=request)
