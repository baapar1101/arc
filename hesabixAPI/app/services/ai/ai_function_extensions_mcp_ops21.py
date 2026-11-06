"""MCP leftovers: transfer details + CRM activity details."""
from __future__ import annotations

from sqlalchemy.orm import selectinload

from app.services.ai.ai_mcp_tool_util import mcp_bid, mcp_db, mcp_jsonable, mcp_run, mcp_schema

DOC_ID = mcp_schema({"document_id": {"type": "integer", "minimum": 1}}, ["document_id"])
ACTIVITY_ID = mcp_schema({"activity_id": {"type": "integer", "minimum": 1}}, ["activity_id"])


def _public_doc(data: dict) -> dict:
    out = mcp_jsonable(data)
    if isinstance(out, dict):
        out.pop("extra_info", None)
    return out


def get_transfer_handler(args, context):
    from app.services.transfer_service import get_transfer

    data = mcp_run(get_transfer, mcp_db(context), int(args["document_id"]))
    if not data or int(data.get("business_id") or 0) != mcp_bid(context):
        raise ValueError("سند انتقال در کسب‌وکار متصل یافت نشد")
    return _public_doc(data)


def get_crm_activity_handler(args, context):
    from adapters.db.models.crm import CrmActivity

    db = mcp_db(context)
    bid = mcp_bid(context)
    activity_id = int(args["activity_id"])
    activity = (
        db.query(CrmActivity)
        .options(
            selectinload(CrmActivity.lead),
            selectinload(CrmActivity.person),
            selectinload(CrmActivity.created_by),
            selectinload(CrmActivity.assigned_to),
        )
        .filter(CrmActivity.id == activity_id, CrmActivity.business_id == bid)
        .first()
    )
    if not activity:
        raise ValueError("فعالیت CRM در کسب‌وکار متصل یافت نشد")
    person = getattr(activity, "person", None)
    person_name = None
    if person is not None:
        person_name = getattr(person, "alias_name", None) or getattr(person, "company_name", None)
    assigned = getattr(activity, "assigned_to", None)
    created = getattr(activity, "created_by", None)
    return mcp_jsonable(
        {
            "id": activity.id,
            "person_id": activity.person_id,
            "person_name": person_name,
            "lead_id": activity.lead_id,
            "lead_name": activity.lead.name if getattr(activity, "lead", None) else None,
            "code": activity.code,
            "activity_type": activity.activity_type,
            "subject": activity.subject,
            "description": activity.description,
            "activity_date": activity.activity_date.isoformat() if activity.activity_date else None,
            "deal_id": activity.deal_id,
            "is_task": bool(activity.is_task),
            "due_at": activity.due_at.isoformat() if activity.due_at else None,
            "status": activity.status,
            "completed_at": activity.completed_at.isoformat() if activity.completed_at else None,
            "assigned_to_user_id": activity.assigned_to_user_id,
            "assigned_to_name": (
                f"{assigned.first_name or ''} {assigned.last_name or ''}".strip() if assigned else None
            ),
            "outcome": activity.outcome,
            "priority": activity.priority,
            "created_by_user_id": activity.created_by_user_id,
            "created_by_name": (
                f"{created.first_name or ''} {created.last_name or ''}".strip() if created else None
            ),
        }
    )


def register_mcp_ops21_functions(registry) -> None:
    from app.services.ai.function_registry import AIFunction, AIRole

    roles = {AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN}
    registry.register(
        AIFunction(
            name="get_transfer",
            description="جزئیات سند انتقال وجه بین صندوق/بانک/تنخواه کسب‌وکار متصل؛ extra_info برنمی‌گردد.",
            parameters_schema=DOC_ID,
            handler=get_transfer_handler,
            allowed_roles=roles,
            required_permissions=["transfers.view"],
            category="financial",
            is_readonly=True,
        )
    )
    registry.register(
        AIFunction(
            name="get_crm_activity",
            description="جزئیات یک فعالیت یا وظیفه CRM متعلق به کسب‌وکار متصل.",
            parameters_schema=ACTIVITY_ID,
            handler=get_crm_activity_handler,
            allowed_roles=roles,
            required_permissions=["crm.view"],
            category="crm",
            is_readonly=True,
        )
    )
