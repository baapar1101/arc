"""Shared ticket dict serialization for user/operator APIs."""

from __future__ import annotations

from typing import Any, Dict, Optional

from sqlalchemy.orm import Session

from adapters.api.v1.support.schemas import TicketResponse
from adapters.db.models.support.ticket import Ticket
from app.services.support.ticket_engagement_service import engagement_fields


def attach_support_subscription(data: Dict[str, Any], db: Session, user_id: Optional[int]) -> None:
    """Attach submitter's active/grace support plan fields onto a ticket payload."""
    data["support_subscription"] = None
    data["is_priority_subscriber"] = False
    if not user_id:
        return
    try:
        from app.services.support.support_billing_settings import get_support_paid_priority_boost
        from app.services.support.support_entitlement_service import get_active_or_grace_subscription

        sub = get_active_or_grace_subscription(db, int(user_id))
        if not sub or not sub.plan:
            return
        plan = sub.plan
        data["support_subscription"] = {
            "status": sub.status,
            "ends_at": sub.ends_at.isoformat() if sub.ends_at else None,
            "plan_id": plan.id,
            "plan_name": plan.name,
            "plan_code": plan.code,
            "period_months": plan.period_months,
            "includes_priority_support": bool(plan.includes_priority_support),
            "priority_weight": int(plan.priority_weight or 0),
        }
        if get_support_paid_priority_boost(db) and sub.status == "active":
            data["is_priority_subscriber"] = bool(plan.includes_priority_support) or int(
                plan.priority_weight or 0
            ) > 0
    except Exception:
        data["support_subscription"] = None
        data["is_priority_subscriber"] = False


def ticket_response_dict(ticket: Ticket, db: Session) -> dict:
    """Full ticket payload (ORM relations + engagement fields)."""
    data = TicketResponse.from_orm(ticket).dict()
    data.update(engagement_fields(db, ticket))
    attach_support_subscription(data, db, ticket.user_id)
    return data


def ticket_to_dict(ticket: Ticket, db: Session) -> dict:
    data = {
        "id": ticket.id,
        "title": ticket.title,
        "description": ticket.description,
        "user_id": ticket.user_id,
        "category_id": ticket.category_id,
        "priority_id": ticket.priority_id,
        "status_id": ticket.status_id,
        "assigned_operator_id": ticket.assigned_operator_id,
        "is_internal": ticket.is_internal,
        "closed_at": ticket.closed_at,
        "created_at": ticket.created_at,
        "updated_at": ticket.updated_at,
        "last_message_at": ticket.last_message_at,
        "first_response_due_at": ticket.first_response_due_at,
        "resolution_due_at": ticket.resolution_due_at,
        "first_responded_at": ticket.first_responded_at,
        "sla_breached": ticket.sla_breached,
        "category": {
            "id": ticket.category.id,
            "name": ticket.category.name,
            "description": ticket.category.description,
            "is_active": ticket.category.is_active,
            "created_at": ticket.category.created_at,
            "updated_at": ticket.category.updated_at,
        }
        if ticket.category
        else None,
        "priority": {
            "id": ticket.priority.id,
            "name": ticket.priority.name,
            "description": ticket.priority.description,
            "color": ticket.priority.color,
            "order": ticket.priority.order,
            "created_at": ticket.priority.created_at,
            "updated_at": ticket.priority.updated_at,
        }
        if ticket.priority
        else None,
        "status": {
            "id": ticket.status.id,
            "name": ticket.status.name,
            "description": ticket.status.description,
            "color": ticket.status.color,
            "is_final": ticket.status.is_final,
            "created_at": ticket.status.created_at,
            "updated_at": ticket.status.updated_at,
        }
        if ticket.status
        else None,
    }
    if ticket.user:
        data["user"] = {
            "id": ticket.user.id,
            "first_name": ticket.user.first_name,
            "last_name": ticket.user.last_name,
            "email": ticket.user.email,
        }
    attach_support_subscription(data, db, ticket.user_id)
    if ticket.assigned_operator:
        data["assigned_operator"] = {
            "id": ticket.assigned_operator.id,
            "first_name": ticket.assigned_operator.first_name,
            "last_name": ticket.assigned_operator.last_name,
            "email": ticket.assigned_operator.email,
        }
    data.update(engagement_fields(db, ticket))
    return data
