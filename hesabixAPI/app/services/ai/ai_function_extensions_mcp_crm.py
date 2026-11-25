"""MCP-facing CRM lifecycle tools built on CRM domain models and services."""
from __future__ import annotations

import logging
from datetime import datetime, date
from typing import Any, Dict, TYPE_CHECKING

logger = logging.getLogger(__name__)

from app.services.ai.function_registry import AIRole, AIFunction

if TYPE_CHECKING:
    from app.services.ai.function_registry import AIFunctionRegistry


_ROLES = {AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN}
_DATE = {"type": "string", "format": "date"}
_DATETIME = {"type": "string", "format": "date-time"}


def _schema(properties: Dict[str, Any], required: list[str]) -> Dict[str, Any]:
    return {"type": "object", "properties": properties, "required": required, "additionalProperties": False}


def _log_crm_change(db: Any, business_id: int, entity_type: str, entity_id: int, field_name: str, old_value: Any, new_value: Any, user_id: int) -> None:
    from adapters.db.models.crm import CrmChangeHistory

    old_text = str(old_value)[:4000] if old_value is not None else ""
    new_text = str(new_value)[:4000] if new_value is not None else ""
    if old_text != new_text:
        db.add(CrmChangeHistory(
            business_id=business_id,
            entity_type=entity_type,
            entity_id=entity_id,
            field_name=field_name,
            old_value=old_text,
            new_value=new_text,
            changed_by_user_id=user_id,
        ))


def _ensure_business_member(db: Any, business_id: int, user_id: int | None) -> None:
    if user_id is None:
        return
    from adapters.db.models.business import Business
    from adapters.db.repositories.business_permission_repo import BusinessPermissionRepository
    from app.core.business_membership import membership_is_active

    business = db.query(Business).filter(Business.id == business_id).first()
    if business and int(business.owner_id) == int(user_id):
        return
    membership = BusinessPermissionRepository(db).get_by_user_and_business(int(user_id), business_id)
    if not membership or not membership_is_active(membership):
        raise ValueError("کاربر مسئول عضو فعال این کسب‌وکار نیست")


def _crm_deal_result(db, business_id: int, deal: Any) -> Dict[str, Any]:
    from app.services import crm_tag_service

    tags = crm_tag_service.get_deal_tags(db, business_id, int(deal.id))
    return {
        "id": deal.id,
        "business_id": deal.business_id,
        "code": deal.code,
        "person_id": deal.person_id,
        "person_name": deal.person.alias_name if deal.person else None,
        "process_definition_id": deal.process_definition_id,
        "stage_id": deal.stage_id,
        "stage_name": deal.stage.name if deal.stage else None,
        "title": deal.title,
        "amount": float(deal.amount),
        "currency_id": deal.currency_id,
        "probability_percent": deal.probability_percent,
        "expected_close_date": deal.expected_close_date.isoformat() if deal.expected_close_date else None,
        "next_follow_up_at": deal.next_follow_up_at.isoformat() if deal.next_follow_up_at else None,
        "closed_at": deal.closed_at.isoformat() if deal.closed_at else None,
        "document_id": deal.document_id,
        "assigned_to_user_id": deal.assigned_to_user_id,
        "description": deal.description,
        "won_reason_code": deal.won_reason_code,
        "lost_reason_code": deal.lost_reason_code,
        "competitor_name": deal.competitor_name,
        "stage_entered_at": deal.stage_entered_at.isoformat() if deal.stage_entered_at else None,
        "organization_id": deal.organization_id,
        "organization_name": deal.organization.name if deal.organization else None,
        "tags": tags,
        "created_at": deal.created_at.isoformat() if deal.created_at else None,
        "updated_at": deal.updated_at.isoformat() if deal.updated_at else None,
        "created_by_user_id": deal.created_by_user_id,
    }


def _crm_activity_result(activity: Any) -> Dict[str, Any]:
    return {
        "id": activity.id,
        "business_id": activity.business_id,
        "person_id": activity.person_id,
        "person_name": activity.person.alias_name if activity.person else None,
        "lead_id": activity.lead_id,
        "lead_name": activity.lead.name if activity.lead else None,
        "code": activity.code,
        "activity_type": activity.activity_type,
        "subject": activity.subject,
        "description": activity.description,
        "activity_date": activity.activity_date.isoformat() if activity.activity_date else None,
        "deal_id": activity.deal_id,
        "deal_title": activity.deal.title if activity.deal else None,
        "deal_code": activity.deal.code if activity.deal else None,
        "is_task": bool(activity.is_task),
        "due_at": activity.due_at.isoformat() if activity.due_at else None,
        "status": activity.status,
        "completed_at": activity.completed_at.isoformat() if activity.completed_at else None,
        "assigned_to_user_id": activity.assigned_to_user_id,
        "outcome": activity.outcome,
        "priority": activity.priority,
        "created_by_user_id": activity.created_by_user_id,
        "created_at": activity.created_at.isoformat() if activity.created_at else None,
        "updated_at": activity.updated_at.isoformat() if activity.updated_at else None,
    }


def _crm_lead_result(db: Any, business_id: int, lead: Any) -> Dict[str, Any]:
    from app.services import crm_tag_service

    return {
        "id": lead.id,
        "business_id": lead.business_id,
        "code": lead.code,
        "process_definition_id": lead.process_definition_id,
        "stage_id": lead.stage_id,
        "stage_name": lead.stage.name if lead.stage else None,
        "name": lead.name,
        "company_name": lead.company_name,
        "source_code": lead.source_code,
        "mobile": lead.mobile,
        "email": lead.email,
        "description": lead.description,
        "assigned_to_user_id": lead.assigned_to_user_id,
        "next_follow_up_at": lead.next_follow_up_at.isoformat() if lead.next_follow_up_at else None,
        "person_id": lead.person_id,
        "organization_id": lead.organization_id,
        "organization_name": lead.organization.name if lead.organization else None,
        "converted_at": lead.converted_at.isoformat() if lead.converted_at else None,
        "tags": crm_tag_service.get_lead_tags(db, business_id, int(lead.id)),
        "created_at": lead.created_at.isoformat() if lead.created_at else None,
    }


def register_mcp_crm_functions(registry: "AIFunctionRegistry") -> None:
    # LEAD UPDATE / DELETE / CONVERT
    def update_lead(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from adapters.db.models.crm import CrmProcessStage, Lead
        from adapters.api.v1.schema_models.crm import LeadUpdate
        from app.services import crm_custom_field_service, crm_tag_service

        db = context["db"]
        business_id = int(context["business_id"])
        ctx = context["user_context"]
        lead_id = int(args["lead_id"])
        body = LeadUpdate(**{k: v for k, v in args.items() if k not in {"lead_id", "business_id"}})
        lead = db.query(Lead).filter(Lead.id == lead_id, Lead.business_id == business_id).first()
        if not lead:
            raise ValueError("سرنخ در کسب‌وکار متصل پیدا نشد")
        from app.services.crm_enterprise_service import guard_record
        guard_record(db, business_id, ctx, "lead", lead, write=True)
        _ensure_business_member(db, business_id, body.assigned_to_user_id)
        if body.code is not None and str(body.code).strip():
            code = str(body.code).strip()
            if db.query(Lead.id).filter(Lead.business_id == business_id, Lead.code == code, Lead.id != lead_id).first():
                raise ValueError("کد سرنخ تکراری است")
        merged_custom_fields = None
        if body.custom_fields is not None:
            merged_custom_fields = crm_custom_field_service.validate_and_merge_custom_values(
                db, business_id, "lead", lead.extra_info, body.custom_fields
            )
        if body.tag_ids is not None:
            crm_tag_service.set_lead_tags(db, business_id, lead_id, body.tag_ids)
        if body.stage_id is not None:
            stage = db.query(CrmProcessStage).filter(
                CrmProcessStage.id == body.stage_id,
                CrmProcessStage.process_definition_id == lead.process_definition_id,
            ).first()
            if not stage:
                raise ValueError("مرحله در فرایند این سرنخ پیدا نشد")
            _log_crm_change(db, business_id, "lead", lead_id, "stage_id", str(lead.stage_id), stage.name, ctx.get_user_id())
            old_stage_id = lead.stage_id
            lead.stage_id = body.stage_id
            try:
                from app.services.workflow.workflow_trigger_service import trigger_lead_stage_changed
                trigger_lead_stage_changed(db, business_id, lead_id=lead_id, old_stage_id=old_stage_id, new_stage_id=body.stage_id, user_id=ctx.get_user_id())
            except Exception:
                pass
        if body.code is not None and str(body.code).strip():
            lead.code = str(body.code).strip()
        if body.clear_next_follow_up and body.next_follow_up_at is not None:
            raise ValueError("هم‌زمان نمی‌توان پیگیری را تنظیم و پاک کرد")
        for field in ("source_code", "name", "company_name", "mobile", "email", "description", "next_follow_up_at", "extra_info"):
            value = getattr(body, field, None)
            if value is None:
                continue
            if field in {"source_code", "company_name", "mobile", "email", "description"}:
                value = str(value).strip() or None
            setattr(lead, field, value)
        if body.clear_next_follow_up:
            lead.next_follow_up_at = None
        if body.clear_assigned_to and body.assigned_to_user_id is not None:
            raise ValueError("هم‌زمان نمی‌توان مسئول را تنظیم و پاک کرد")
        if body.clear_assigned_to or body.assigned_to_user_id is not None:
            old_assignee = lead.assigned_to_user_id
            new_assignee = None if body.clear_assigned_to else body.assigned_to_user_id
            lead.assigned_to_user_id = new_assignee
            if old_assignee != new_assignee:
                try:
                    from app.services.workflow.workflow_trigger_service import trigger_lead_assigned
                    trigger_lead_assigned(db, business_id, lead_id=lead_id, old_assigned_to_user_id=old_assignee, new_assigned_to_user_id=new_assignee, user_id=ctx.get_user_id())
                except Exception:
                    logger.exception("mcp trigger_lead_assigned failed lead_id=%s", lead_id)
        if merged_custom_fields is not None:
            lead.extra_info = merged_custom_fields
        db.commit()
        db.refresh(lead)
        return _crm_lead_result(db, business_id, lead)

    lead_update_props = {
        "stage_id": {"type": ["integer", "null"], "minimum": 1},
        "code": {"type": ["string", "null"], "maxLength": 50},
        "source_code": {"type": ["string", "null"], "maxLength": 50},
        "name": {"type": ["string", "null"], "minLength": 1, "maxLength": 255},
        "company_name": {"type": ["string", "null"], "maxLength": 255},
        "mobile": {"type": ["string", "null"], "maxLength": 20},
        "email": {"type": ["string", "null"], "maxLength": 255},
        "description": {"type": ["string", "null"]},
        "assigned_to_user_id": {"type": ["integer", "null"], "minimum": 1},
        "clear_assigned_to": {"type": "boolean", "description": "برداشتن مسئول. همراه assigned_to_user_id نفرستید."},
        "next_follow_up_at": {"anyOf": [_DATETIME, {"type": "null"}]},
        "clear_next_follow_up": {"type": "boolean", "description": "پاک کردن پیگیری. همراه next_follow_up_at نفرستید."},
        "extra_info": {"type": ["object", "null"]},
        "custom_fields": {"type": ["object", "null"]},
        "tag_ids": {"type": ["array", "null"], "items": {"type": "integer", "minimum": 1}},
    }
    registry.register(AIFunction(
        name="update_lead", description="ویرایش سرنخ و انتقال آن در مراحل همان فرایند؛ شناسه و مرحله را از ابزارهای جستجو بگیر. نیازمند تأیید است.",
        parameters_schema=_schema({"lead_id": {"type": "integer", "minimum": 1}, **lead_update_props}, ["lead_id"]),
        handler=update_lead, allowed_roles=_ROLES, required_permissions=["crm.write"], category="crm",
        requires_approval=True, risk_level="medium", is_readonly=False,
    ))

    def delete_lead(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from adapters.db.models.crm import Lead
        db = context["db"]
        business_id = int(context["business_id"])
        lead_id = int(args["lead_id"])
        lead = db.query(Lead).filter(Lead.id == lead_id, Lead.business_id == business_id).first()
        if not lead:
            raise ValueError("سرنخ در کسب‌وکار متصل پیدا نشد")
        from app.services.crm_enterprise_service import guard_record
        guard_record(db, business_id, context["user_context"], "lead", lead, write=True)
        db.delete(lead)
        db.commit()
        return {"lead_id": lead_id, "deleted": True}

    registry.register(AIFunction(
        name="delete_lead", description="حذف سرنخ CRM؛ اطلاعات وابسته تابع قیدهای دامنه و پایگاه‌داده است. نیازمند تأیید صریح است.",
        parameters_schema=_schema({"lead_id": {"type": "integer", "minimum": 1}}, ["lead_id"]),
        handler=delete_lead, allowed_roles=_ROLES, required_permissions=["crm.write"], category="crm",
        requires_approval=True, risk_level="high", is_readonly=False,
    ))

    def convert_lead_to_customer(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from datetime import datetime
        from datetime import date as date_cls
        from adapters.db.models.crm import CrmProcessDefinition, CrmProcessStage, Deal, Lead
        from adapters.db.models.person import PersonType
        from adapters.api.v1.schema_models.crm import LeadConvertRequest
        from adapters.api.v1.schema_models.person import PersonCreateRequest
        from app.services.person_service import create_person
        from app.services.document_numbering_service import generate_document_code

        db = context["db"]
        business_id = int(context["business_id"])
        ctx = context["user_context"]
        lead_id = int(args["lead_id"])
        body = LeadConvertRequest(**{k: v for k, v in args.items() if k not in {"lead_id", "business_id"}})
        lead = db.query(Lead).filter(Lead.id == lead_id, Lead.business_id == business_id).with_for_update().first()
        if not lead:
            raise ValueError("سرنخ در کسب‌وکار متصل پیدا نشد")
        from app.services.crm_enterprise_service import guard_record
        guard_record(db, business_id, ctx, "lead", lead, write=True)
        if lead.person_id is not None:
            raise ValueError("این سرنخ قبلاً به مشتری تبدیل شده است")
        deal_option = body.create_deal
        if deal_option:
            process = db.query(CrmProcessDefinition).filter(
                CrmProcessDefinition.id == deal_option.process_definition_id,
                CrmProcessDefinition.business_id == business_id,
                CrmProcessDefinition.process_type == "sales_pipeline",
            ).first()
            if not process:
                raise ValueError("فرایند پایپلاین فروش در کسب‌وکار متصل پیدا نشد")
            stage = db.query(CrmProcessStage).filter(
                CrmProcessStage.id == deal_option.stage_id,
                CrmProcessStage.process_definition_id == process.id,
            ).first()
            if not stage:
                raise ValueError("مرحلهٔ پایپلاین فروش پیدا نشد")
            _ensure_business_member(db, business_id, deal_option.assigned_to_user_id or lead.assigned_to_user_id)
        alias = (lead.name or lead.company_name or "مشتری بدون نام").strip() or "مشتری بدون نام"
        person_payload = PersonCreateRequest(
            alias_name=alias[:255], first_name=lead.name, company_name=lead.company_name,
            mobile=lead.mobile, email=lead.email, person_types=[PersonType.CUSTOMER],
        )
        # Keep customer creation, lead linkage and optional deal in one transaction.
        result = create_person(db, business_id, person_payload, commit=False)
        person = result.get("data") if isinstance(result, dict) else None
        if not isinstance(person, dict) or not person.get("id"):
            raise ValueError("ساخت مشتری از سرنخ انجام نشد")
        lead.person_id = int(person["id"])
        lead.converted_at = datetime.utcnow()
        deal_result = None
        if deal_option:
            deal_code = generate_document_code(db, business_id, "crm_deal", date_cls.today())
            deal = Deal(
                business_id=business_id, person_id=int(person["id"]), code=deal_code,
                process_definition_id=deal_option.process_definition_id, stage_id=deal_option.stage_id,
                title=deal_option.title, amount=deal_option.amount, currency_id=deal_option.currency_id,
                probability_percent=deal_option.probability_percent,
                expected_close_date=deal_option.expected_close_date,
                assigned_to_user_id=deal_option.assigned_to_user_id or lead.assigned_to_user_id,
                description=deal_option.description, stage_entered_at=datetime.utcnow(),
                created_by_user_id=ctx.get_user_id(),
            )
            db.add(deal)
            db.flush()
            db.refresh(deal)
        from app.services.crm_enterprise_service import link_converted_person_to_lead_organization

        link_converted_person_to_lead_organization(db, business_id, lead, int(person["id"]), deal if deal_option else None)
        if deal_option:
            db.refresh(deal)
            deal_result = _crm_deal_result(db, business_id, deal)
        db.commit()
        db.refresh(lead)
        try:
            from app.services.person_service import invalidate_persons_cache
            invalidate_persons_cache(business_id, fiscal_year_id=None)
        except Exception:
            pass
        try:
            from app.services.workflow.workflow_trigger_service import trigger_person_created
            trigger_person_created(
                db=db, business_id=business_id, person_id=int(person["id"]),
                person_types=[PersonType.CUSTOMER.value], user_id=ctx.get_user_id(),
            )
        except Exception:
            pass
        try:
            from app.services.workflow.workflow_trigger_service import trigger_lead_converted
            trigger_lead_converted(db, business_id, lead_id=lead_id, person_id=lead.person_id, user_id=ctx.get_user_id())
        except Exception:
            pass
        result = {"lead": _crm_lead_result(db, business_id, lead), "person": person}
        if deal_result:
            result["deal"] = deal_result
        return result

    registry.register(AIFunction(
        name="convert_lead_to_customer", description="تبدیل سرنخ تبدیل‌نشده به مشتری؛ در صورت نیاز می‌توان هم‌زمان فرصت فروش را ساخت. پیش از اجرا نبودن مشتری تکراری و فرایند/مرحله را بررسی کن. نیازمند تأیید است.",
        parameters_schema=_schema({
            "lead_id": {"type": "integer", "minimum": 1},
            "create_deal": {"anyOf": [
                {"type": "null"},
                {"type": "object", "properties": {
                    "process_definition_id": {"type": "integer", "minimum": 1},
                    "stage_id": {"type": "integer", "minimum": 1},
                    "title": {"type": "string", "minLength": 1, "maxLength": 255},
                    "amount": {"type": "number", "minimum": 0},
                    "currency_id": {"type": ["integer", "null"], "minimum": 1},
                    "probability_percent": {"type": ["integer", "null"], "minimum": 0, "maximum": 100},
                    "expected_close_date": {"anyOf": [_DATE, {"type": "null"}]},
                    "assigned_to_user_id": {"type": ["integer", "null"], "minimum": 1},
                    "description": {"type": ["string", "null"]},
                }, "required": ["process_definition_id", "stage_id", "title", "amount"], "additionalProperties": False},
            ]},
        }, ["lead_id"]),
        handler=convert_lead_to_customer, allowed_roles=_ROLES, required_permissions=["crm.write"], category="crm",
        requires_approval=True, risk_level="high", is_readonly=False,
    ))

    # DEAL CREATE
    def create_deal(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from adapters.db.models.crm import CrmProcessDefinition, CrmProcessStage, Deal
        from adapters.db.models.person import Person
        from adapters.api.v1.schema_models.crm import DealCreate
        from app.services import crm_custom_field_service, crm_tag_service
        from app.services.document_numbering_service import generate_document_code

        db = context["db"]
        business_id = int(context["business_id"])
        ctx = context["user_context"]
        body = DealCreate(**{k: v for k, v in args.items() if k != "business_id"})
        person = db.query(Person).filter(Person.id == body.person_id, Person.business_id == business_id).first()
        process = db.query(CrmProcessDefinition).filter(
            CrmProcessDefinition.id == body.process_definition_id,
            CrmProcessDefinition.business_id == business_id,
        ).first()
        stage = db.query(CrmProcessStage).filter(
            CrmProcessStage.id == body.stage_id,
            CrmProcessStage.process_definition_id == body.process_definition_id,
        ).first()
        if not person or not process or not stage:
            raise ValueError("شخص، فرایند یا مرحله در کسب‌وکار متصل پیدا نشد")
        _ensure_business_member(db, business_id, body.assigned_to_user_id)
        code = str(body.code or "").strip() or generate_document_code(db, business_id, "crm_deal", date.today())
        if db.query(Deal.id).filter(Deal.business_id == business_id, Deal.code == code).first():
            raise ValueError("کد فرصت فروش تکراری است")
        extra = crm_custom_field_service.validate_and_merge_custom_values(
            db, business_id, "deal", body.extra_info, body.custom_fields
        )
        deal = Deal(
            business_id=business_id, person_id=body.person_id, code=code,
            process_definition_id=body.process_definition_id, stage_id=body.stage_id,
            title=body.title, amount=body.amount, currency_id=body.currency_id,
            probability_percent=body.probability_percent, expected_close_date=body.expected_close_date,
            next_follow_up_at=body.next_follow_up_at, assigned_to_user_id=body.assigned_to_user_id,
            description=body.description, extra_info=extra, stage_entered_at=datetime.utcnow(),
            created_by_user_id=ctx.get_user_id(),
        )
        db.add(deal)
        db.flush()
        if body.tag_ids is not None:
            crm_tag_service.set_deal_tags(db, business_id, deal.id, body.tag_ids)
        db.commit()
        db.refresh(deal)
        try:
            from app.services.workflow.workflow_trigger_service import trigger_deal_created
            trigger_deal_created(
                db, business_id, deal_id=deal.id, process_definition_id=deal.process_definition_id,
                stage_id=deal.stage_id, person_id=deal.person_id, title=deal.title,
                amount=float(deal.amount), user_id=ctx.get_user_id(),
            )
        except Exception:
            pass
        return _crm_deal_result(db, business_id, deal)

    deal_create_schema = _schema({
        "person_id": {"type": "integer", "minimum": 1},
        "process_definition_id": {"type": "integer", "minimum": 1},
        "stage_id": {"type": "integer", "minimum": 1},
        "title": {"type": "string", "minLength": 1, "maxLength": 255},
        "amount": {"type": "number", "minimum": 0},
        "code": {"type": ["string", "null"], "maxLength": 50},
        "currency_id": {"type": ["integer", "null"], "minimum": 1},
        "probability_percent": {"type": ["integer", "null"], "minimum": 0, "maximum": 100},
        "expected_close_date": {"anyOf": [_DATE, {"type": "null"}]},
        "next_follow_up_at": {"anyOf": [_DATETIME, {"type": "null"}]},
        "assigned_to_user_id": {"type": ["integer", "null"], "minimum": 1},
        "description": {"type": ["string", "null"]},
        "extra_info": {"type": ["object", "null"]},
        "custom_fields": {"type": ["object", "null"]},
        "tag_ids": {"type": ["array", "null"], "items": {"type": "integer", "minimum": 1}},
    }, ["person_id", "process_definition_id", "stage_id", "title", "amount"])
    registry.register(AIFunction(
        name="create_deal", description="ایجاد فرصت فروش CRM؛ person_id، pipeline و stage را از ابزارهای جستجو بگیر. نیازمند تأیید است.",
        parameters_schema=deal_create_schema, handler=create_deal, allowed_roles=_ROLES,
        required_permissions=["crm.write"], category="crm", requires_approval=True,
        risk_level="medium", is_readonly=False,
    ))

    # DEAL UPDATE
    def update_deal(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from adapters.db.models.crm import CrmProcessStage, Deal
        from adapters.api.v1.schema_models.crm import DealUpdate
        from app.services import crm_custom_field_service, crm_tag_service, crm_close_reason_service

        db = context["db"]
        business_id = int(context["business_id"])
        ctx = context["user_context"]
        deal_id = int(args["deal_id"])
        body = DealUpdate(**{k: v for k, v in args.items() if k not in {"deal_id", "business_id"}})
        deal = db.query(Deal).filter(Deal.id == deal_id, Deal.business_id == business_id).first()
        if not deal:
            raise ValueError("فرصت فروش در کسب‌وکار متصل پیدا نشد")
        from app.services.crm_enterprise_service import guard_record
        guard_record(db, business_id, ctx, "deal", deal, write=True)
        _ensure_business_member(db, business_id, body.assigned_to_user_id)
        if body.document_id is not None:
            from adapters.db.models.document import Document
            if not db.query(Document.id).filter(
                Document.id == body.document_id, Document.business_id == business_id
            ).first():
                raise ValueError("سند متصل به این فرصت در کسب‌وکار جاری پیدا نشد")
        if body.code is not None and str(body.code).strip():
            code = str(body.code).strip()
            if db.query(Deal.id).filter(Deal.business_id == business_id, Deal.code == code, Deal.id != deal_id).first():
                raise ValueError("کد فرصت فروش تکراری است")
        merged_custom_fields = None
        if body.custom_fields is not None:
            merged_custom_fields = crm_custom_field_service.validate_and_merge_custom_values(
                db, business_id, "deal", deal.extra_info, body.custom_fields
            )
        if body.tag_ids is not None:
            crm_tag_service.set_deal_tags(db, business_id, deal_id, body.tag_ids)
        old_assignee = deal.assigned_to_user_id
        old_amount = str(deal.amount)
        if body.stage_id is not None:
            stage = db.query(CrmProcessStage).filter(
                CrmProcessStage.id == body.stage_id,
                CrmProcessStage.process_definition_id == deal.process_definition_id,
            ).first()
            if not stage:
                raise ValueError("مرحله در فرایند این فرصت پیدا نشد")
            if body.stage_id != deal.stage_id:
                if stage.is_win:
                    reason = body.won_reason_code or deal.won_reason_code
                    if not reason or not crm_close_reason_service.is_valid_reason_code(db, business_id, "won", reason):
                        raise ValueError("برای انتقال به مرحلهٔ برد، دلیل برد معتبر لازم است")
                    deal.won_reason_code = reason
                if stage.is_lost:
                    reason = body.lost_reason_code or deal.lost_reason_code
                    if not reason or not crm_close_reason_service.is_valid_reason_code(db, business_id, "lost", reason):
                        raise ValueError("برای انتقال به مرحلهٔ باخت، دلیل باخت معتبر لازم است")
                    deal.lost_reason_code = reason
                _log_crm_change(db, business_id, "deal", deal_id, "stage_id", str(deal.stage_id), stage.name, ctx.get_user_id())
                old_stage_id = deal.stage_id
                deal.stage_entered_at = datetime.utcnow()
                deal.stage_id = body.stage_id
                try:
                    from app.services.workflow.workflow_trigger_service import trigger_deal_stage_changed
                    trigger_deal_stage_changed(db, business_id, deal_id=deal_id, old_stage_id=old_stage_id, new_stage_id=body.stage_id, user_id=ctx.get_user_id())
                except Exception:
                    pass
        if body.person_id is not None and int(body.person_id) != int(deal.person_id):
            from app.core.responses import ApiError
            from app.services.crm_enterprise_service import change_deal_person

            old_person_id = deal.person_id
            try:
                change_deal_person(db, business_id, deal, int(body.person_id))
            except ApiError as exc:
                raise ValueError(exc.message) from exc
            _log_crm_change(db, business_id, "deal", deal_id, "person_id", str(old_person_id), str(body.person_id), ctx.get_user_id())
        if body.clear_next_follow_up and body.next_follow_up_at is not None:
            raise ValueError("هم‌زمان نمی‌توان پیگیری را تنظیم و پاک کرد")
        if body.clear_expected_close_date and body.expected_close_date is not None:
            raise ValueError("هم‌زمان نمی‌توان تاریخ پیش‌بینی را تنظیم و پاک کرد")
        if body.code is not None and str(body.code).strip():
            deal.code = str(body.code).strip()
        for field in ("title", "amount", "currency_id", "probability_percent", "expected_close_date", "next_follow_up_at", "document_id", "description", "extra_info", "won_reason_code", "lost_reason_code", "competitor_name"):
            value = getattr(body, field, None)
            if value is not None:
                setattr(deal, field, value)
        if body.clear_next_follow_up:
            deal.next_follow_up_at = None
        if body.clear_expected_close_date:
            deal.expected_close_date = None
        if body.amount is not None:
            _log_crm_change(db, business_id, "deal", deal_id, "amount", old_amount, str(body.amount), ctx.get_user_id())
        if body.assigned_to_user_id is not None:
            deal.assigned_to_user_id = body.assigned_to_user_id
            if body.assigned_to_user_id != old_assignee:
                try:
                    from app.services.workflow.workflow_trigger_service import trigger_deal_assigned
                    trigger_deal_assigned(db, business_id, deal_id=deal_id, old_assigned_to_user_id=old_assignee, new_assigned_to_user_id=body.assigned_to_user_id, user_id=ctx.get_user_id())
                except Exception:
                    pass
        if merged_custom_fields is not None:
            deal.extra_info = merged_custom_fields
        if body.closed_at is not None:
            deal.closed_at = body.closed_at
            try:
                from app.services.crm_automation_service import cancel_sequence_enrollments
                cancel_sequence_enrollments(db, business_id, entity_type="deal", entity_id=deal_id, reason="deal_closed", when="close")
            except Exception:
                logger.exception("sequence stop on mcp deal close failed deal_id=%s", deal_id)
            try:
                from app.services.workflow.workflow_trigger_service import trigger_deal_closed
                stage = db.query(CrmProcessStage).filter(CrmProcessStage.id == deal.stage_id).first()
                trigger_deal_closed(db, business_id, deal_id=deal_id, amount=float(deal.amount), is_win=bool(stage and stage.is_win), document_id=deal.document_id, user_id=ctx.get_user_id(), is_lost=bool(stage and stage.is_lost))
            except Exception:
                pass
        db.commit()
        db.refresh(deal)
        return _crm_deal_result(db, business_id, deal)

    deal_update_props = {k: v for k, v in deal_create_schema["properties"].items() if k not in {"person_id", "process_definition_id", "amount"}}
    deal_update_props.update({
        "code": {"type": ["string", "null"], "maxLength": 50},
        "document_id": {"type": ["integer", "null"], "minimum": 1},
        "closed_at": {"anyOf": [_DATETIME, {"type": "null"}]},
        "won_reason_code": {"type": ["string", "null"], "maxLength": 50},
        "lost_reason_code": {"type": ["string", "null"], "maxLength": 50},
        "competitor_name": {"type": ["string", "null"], "maxLength": 255},
        "tag_ids": {"type": ["array", "null"], "items": {"type": "integer", "minimum": 1}},
    })
    # Keep schema aligned with the public DealUpdate Pydantic contract.
    deal_update_props["amount"] = {"type": ["number", "null"], "minimum": 0}
    deal_update_props["person_id"] = {"type": ["integer", "null"], "minimum": 1}
    deal_update_props["clear_next_follow_up"] = {"type": "boolean", "description": "پاک کردن پیگیری. همراه next_follow_up_at نفرستید."}
    deal_update_props["clear_expected_close_date"] = {"type": "boolean", "description": "پاک کردن تاریخ پیش‌بینی بسته شدن. همراه expected_close_date نفرستید."}
    registry.register(AIFunction(
        name="update_deal", description="ویرایش فرصت یا انتقال مرحلهٔ CRM؛ برای مرحلهٔ برد/باخت دلیل معتبر لازم است. عوض کردن شخص، اگر سازمان وصل باشد، فقط به صورتحساب یا مخاطب همان سازمان مجاز است. نیازمند تأیید است.",
        parameters_schema=_schema({"deal_id": {"type": "integer", "minimum": 1}, **deal_update_props}, ["deal_id"]),
        handler=update_deal, allowed_roles=_ROLES, required_permissions=["crm.write"], category="crm",
        requires_approval=True, risk_level="high", is_readonly=False,
    ))

    def set_crm_organization(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from app.core.responses import ApiError
        from app.services.crm_enterprise_service import attach_organization_to_deal, attach_organization_to_lead

        db = context["db"]
        business_id = int(context["business_id"])
        ctx = context["user_context"]
        entity_type = str(args["entity_type"])
        entity_id = int(args["entity_id"])
        organization_id = args.get("organization_id")
        organization_id = int(organization_id) if organization_id is not None else None
        try:
            if entity_type == "lead":
                lead = attach_organization_to_lead(db, business_id, entity_id, organization_id, ctx)
                return _crm_lead_result(db, business_id, lead)
            if entity_type == "deal":
                deal = attach_organization_to_deal(db, business_id, entity_id, organization_id, ctx)
                return _crm_deal_result(db, business_id, deal)
        except ApiError as exc:
            raise ValueError(exc.message) from exc
        raise ValueError("entity_type باید lead یا deal باشد")

    registry.register(AIFunction(
        name="set_crm_organization",
        description="وصل یا قطع سازمان روی سرنخ یا فرصت. organization_id خالی اتصال را برمی‌دارد. سرنخ بدون مشتری به هر سازمان همین کسب‌وکار وصل می‌شود؛ اگر شخص دارد، یا فرصت، شخص باید صورتحساب یا مخاطب همان سازمان باشد. نیازمند تأیید است.",
        parameters_schema=_schema({
            "entity_type": {"type": "string", "enum": ["lead", "deal"]},
            "entity_id": {"type": "integer", "minimum": 1},
            "organization_id": {"type": ["integer", "null"], "minimum": 1},
        }, ["entity_type", "entity_id", "organization_id"]),
        handler=set_crm_organization, allowed_roles=_ROLES, required_permissions=["crm.write"], category="crm",
        requires_approval=True, risk_level="medium", is_readonly=False,
    ))

    def delete_deal(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from adapters.db.models.crm import Deal
        db = context["db"]
        business_id = int(context["business_id"])
        deal_id = int(args["deal_id"])
        deal = db.query(Deal).filter(Deal.id == deal_id, Deal.business_id == business_id).first()
        if not deal:
            raise ValueError("فرصت فروش در کسب‌وکار متصل پیدا نشد")
        from app.services.crm_enterprise_service import guard_record
        guard_record(db, business_id, context["user_context"], "deal", deal, write=True)
        db.delete(deal)
        db.commit()
        return {"deal_id": deal_id, "deleted": True}

    registry.register(AIFunction(
        name="delete_deal", description="حذف فرصت فروش CRM؛ حذف ممکن است فعالیت‌های مرتبط را طبق قواعد پایگاه‌داده تغییر دهد. نیازمند تأیید صریح است.",
        parameters_schema=_schema({"deal_id": {"type": "integer", "minimum": 1}}, ["deal_id"]),
        handler=delete_deal, allowed_roles=_ROLES, required_permissions=["crm.write"], category="crm",
        requires_approval=True, risk_level="high", is_readonly=False,
    ))

    # DEAL LINES: replacement follows the same service and validation as the API.
    def replace_deal_lines(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from app.services import crm_deal_line_service
        from adapters.api.v1.schema_models.crm import CrmDealLinesReplaceRequest

        db = context["db"]
        business_id = int(context["business_id"])
        deal_id = int(args["deal_id"])
        from adapters.db.models.crm import Deal
        from app.services.crm_enterprise_service import guard_record
        deal = db.query(Deal).filter(Deal.id == deal_id, Deal.business_id == business_id).first()
        if deal is None:
            raise ValueError("فرصت فروش در کسب‌وکار متصل پیدا نشد")
        guard_record(db, business_id, context["user_context"], "deal", deal, write=True)
        body = CrmDealLinesReplaceRequest(lines=args.get("lines", []))
        result = crm_deal_line_service.replace_lines(
            db, business_id, deal_id,
            [line.model_dump() for line in body.lines],
        )
        db.commit()
        return {"deal_id": deal_id, **result}

    registry.register(AIFunction(
        name="replace_deal_lines",
        description="تمام خطوط فرصت فروش را جایگزین و مبلغ فرصت را از روی خطوط بازمحاسبه می‌کند؛ هر خط باید کالا یا شرح داشته باشد. نیازمند تأیید است.",
        parameters_schema=_schema({
            "deal_id": {"type": "integer", "minimum": 1},
            "lines": {"type": "array", "maxItems": 200, "items": {"type": "object", "properties": {
                "product_id": {"type": ["integer", "null"], "minimum": 1},
                "description": {"type": ["string", "null"], "maxLength": 500},
                "quantity": {"type": "number", "exclusiveMinimum": 0},
                "unit_price": {"type": "number", "minimum": 0},
                "discount_percent": {"type": "number", "minimum": 0, "maximum": 100},
                "sort_order": {"type": "integer", "minimum": 0},
            }, "required": ["quantity"], "additionalProperties": False}},
        }, ["deal_id", "lines"]),
        handler=replace_deal_lines, allowed_roles=_ROLES, required_permissions=["crm.write"], category="crm",
        requires_approval=True, risk_level="high", is_readonly=False,
    ))

    def convert_deal_to_invoice(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from decimal import Decimal
        from sqlalchemy.orm import selectinload
        from adapters.db.models.crm import Deal
        from adapters.db.models.business import Business
        from adapters.api.v1.schema_models.crm import CrmDealConvertToInvoiceRequest
        from app.core.business_calendar import business_today
        db = context["db"]
        business_id = int(context["business_id"])
        deal_id = int(args["deal_id"])
        body = CrmDealConvertToInvoiceRequest(**{
            key: value for key, value in args.items() if key not in {"deal_id", "business_id"}
        })
        deal = db.query(Deal).options(
            selectinload(Deal.lines), selectinload(Deal.stage),
        ).filter(Deal.id == deal_id, Deal.business_id == business_id).first()
        if not deal:
            raise ValueError("فرصت فروش در کسب‌وکار متصل پیدا نشد")
        from app.services.crm_enterprise_service import guard_record
        guard_record(db, business_id, context["user_context"], "deal", deal)
        if deal.document_id:
            raise ValueError("برای این فرصت فروش قبلاً فاکتور صادر شده است")

        business = db.query(Business).filter(Business.id == business_id).first()
        currency_id = deal.currency_id or (business.default_currency_id if business else None)
        if not currency_id:
            raise ValueError("ارز فرصت یا ارز پیش‌فرض کسب‌وکار تنظیم نشده است")

        lines = []
        for line in sorted(deal.lines, key=lambda item: (item.sort_order or 0, item.id)):
            if not line.product_id:
                continue
            quantity = Decimal(str(line.quantity or 0))
            unit_price = Decimal(str(line.unit_price or 0))
            discount = quantity * unit_price * Decimal(str(line.discount_percent or 0)) / Decimal(100)
            line_total = Decimal(str(line.line_total if line.line_total is not None else quantity * unit_price - discount))
            extra = {"unit_price": float(unit_price), "line_discount": float(discount), "line_total": float(line_total)}
            if body.warehouse_id:
                extra["warehouse_id"] = int(body.warehouse_id)
            lines.append({
                "product_id": int(line.product_id), "quantity": float(quantity),
                "description": line.description, "extra_info": extra,
            })
        if not lines:
            raise ValueError("برای صدور فاکتور حداقل یک خط دارای کالا لازم است")

        return {
            "posted": False,
            "reason": "assistant_cannot_post_accounting_document",
            "message": "دستیار سند حسابداری صادر نمی‌کند. پیش‌فاکتور یا فاکتور را از صفحه فرصت فروش ثبت کنید.",
            "preview": {
                "deal_id": deal_id,
                "person_id": int(deal.person_id),
                "currency_id": int(currency_id),
                "document_date": business_today(business_id).isoformat(),
                "is_proforma": bool(body.is_proforma),
                "line_count": len(lines),
            },
        }

    registry.register(AIFunction(
        name="convert_deal_to_invoice",
        description="پیش‌نمایش تبدیل فرصت به فاکتور را برمی‌گرداند و هیچ سند حسابداری صادر نمی‌کند. ثبت فاکتور فقط از صفحه فرصت فروش انجام می‌شود.",
        parameters_schema=_schema({
            "deal_id": {"type": "integer", "minimum": 1},
            "is_proforma": {"type": "boolean"}, "close_as_won": {"type": "boolean"},
            "won_reason_code": {"type": ["string", "null"], "maxLength": 50},
            "warehouse_id": {"type": ["integer", "null"], "minimum": 1},
        }, ["deal_id"]),
        handler=convert_deal_to_invoice, allowed_roles=_ROLES, required_permissions=["crm.view"], category="crm",
        requires_approval=False, risk_level="safe", is_readonly=True,
    ))

    def get_crm_person_financial_summary(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from app.services.crm_intelligence_service import person_financial_answer

        return person_financial_answer(
            context["db"], int(context["business_id"]), int(args["person_id"]), context.get("user_context")
        )

    registry.register(AIFunction(
        name="get_crm_person_financial_summary",
        description="خلاصه فقط‌خواندنی مانده، فروش، برگشت، حاشیه، اسناد باز و اقدام بعدی یک شخص. سند حسابداری نمی‌سازد و فیلدهای خارج از فهرست مجاز را برنمی‌گرداند.",
        parameters_schema=_schema({"person_id": {"type": "integer", "minimum": 1}}, ["person_id"]),
        handler=get_crm_person_financial_summary, allowed_roles=_ROLES, required_permissions=["crm.view"], category="crm",
        requires_approval=False, risk_level="safe", is_readonly=True,
    ))

    def get_crm_manager_rollup(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from app.services.crm_enterprise_service import manager_rollup
        from app.core.responses import ApiError

        try:
            return manager_rollup(context["db"], int(context["business_id"]), int(args["manager_user_id"]), context["user_context"])
        except ApiError as exc:
            raise ValueError(exc.message) from exc

    registry.register(AIFunction(
        name="get_crm_manager_rollup",
        description="جمع فرصت‌های باز مدیر و زیرمجموعه را به تفکیک ارز برمی‌گرداند. ارزها با هم جمع نمی‌شوند و سند حسابداری ساخته نمی‌شود.",
        parameters_schema=_schema({"manager_user_id": {"type": "integer", "minimum": 1}}, ["manager_user_id"]),
        handler=get_crm_manager_rollup, allowed_roles=_ROLES, required_permissions=["crm.view"], category="crm",
        requires_approval=False, risk_level="safe", is_readonly=True,
    ))

    def list_crm_quotas(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from app.services.crm_enterprise_service import list_quotas

        return {"items": list_quotas(context["db"], int(context["business_id"]))}

    registry.register(AIFunction(
        name="list_crm_quotas",
        description="سهمیه‌های فروش و درصد تحقق از فرصت‌های برده‌شده همان ارز را فقط‌خواندنی برمی‌گرداند.",
        parameters_schema=_schema({}, []),
        handler=list_crm_quotas, allowed_roles=_ROLES, required_permissions=["crm.view"], category="crm",
        requires_approval=False, risk_level="safe", is_readonly=True,
    ))

    def get_crm_next_action(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from adapters.db.models.crm import Deal, Lead
        from adapters.db.models.person import Person
        from app.services.crm_next_action_service import next_action_for_deal, next_action_for_lead, next_action_for_person

        db, business_id = context["db"], int(context["business_id"])
        entity_type = args.get("entity_type")
        entity_id = int(args["entity_id"])
        from app.services.crm_enterprise_service import guard_record
        if entity_type == "lead":
            row = db.query(Lead).filter(Lead.id == entity_id, Lead.business_id == business_id).first()
            if row is not None:
                guard_record(db, business_id, context["user_context"], "lead", row)
            action = next_action_for_lead(db, business_id, row) if row else None
        elif entity_type == "deal":
            row = db.query(Deal).filter(Deal.id == entity_id, Deal.business_id == business_id).first()
            if row is not None:
                guard_record(db, business_id, context["user_context"], "deal", row)
            action = next_action_for_deal(db, business_id, row) if row else None
        elif entity_type == "person":
            row = db.query(Person.id).filter(Person.id == entity_id, Person.business_id == business_id).first()
            action = next_action_for_person(db, business_id, entity_id, ctx=context.get("user_context")) if row else None
        else:
            raise ValueError("entity_type باید lead، deal یا person باشد")
        if row is None:
            raise ValueError("رکورد در کسب‌وکار متصل پیدا نشد")
        if not action:
            return {"next_action": None}
        return {"next_action": {"code": action.get("code"), "title": action.get("title"), "reason": action.get("reason")}}

    registry.register(AIFunction(
        name="get_crm_next_action",
        description="اقدام بعدی قاعده‌مند یک سرنخ، فرصت یا شخص را همراه با دلیل برمی‌گرداند. فقط خواندنی است.",
        parameters_schema=_schema({
            "entity_type": {"type": "string", "enum": ["lead", "deal", "person"]},
            "entity_id": {"type": "integer", "minimum": 1},
        }, ["entity_type", "entity_id"]),
        handler=get_crm_next_action, allowed_roles=_ROLES, required_permissions=["crm.view"], category="crm",
        requires_approval=False, risk_level="safe", is_readonly=True,
    ))

    def preview_crm_task_from_text(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from datetime import datetime
        from app.services.crm_assistant import parse_task_sentence

        draft = parse_task_sentence(str(args.get("text") or ""), datetime.utcnow())
        draft["created"] = False
        return draft

    registry.register(AIFunction(
        name="preview_crm_task_from_text",
        description="جمله فارسی را به پیش‌نویس وظیفه تبدیل می‌کند و هیچ رکوردی نمی‌سازد. برای ثبت، پس از تأیید کاربر از create_crm_task_from_text استفاده کن.",
        parameters_schema=_schema({"text": {"type": "string", "minLength": 1, "maxLength": 1000}}, ["text"]),
        handler=preview_crm_task_from_text, allowed_roles=_ROLES, required_permissions=["crm.view"], category="crm",
        requires_approval=False, risk_level="safe", is_readonly=True,
    ))

    def create_crm_task_from_text(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from datetime import datetime
        from adapters.db.models.crm import CrmActivity, Deal, Lead
        from adapters.db.models.person import Person
        from app.services.crm_assistant import parse_task_sentence
        from app.services.document_numbering_service import generate_document_code

        draft = parse_task_sentence(str(args.get("text") or ""), datetime.utcnow())
        if args.get("confirmed") is not True:
            return {"created": False, "draft": draft, "reason": "confirmation_required"}
        if not draft.get("due_at"):
            raise ValueError("جمله باید موعد داشته باشد، مثل امروز، فردا یا ۳ روز")
        db, business_id = context["db"], int(context["business_id"])
        ctx = context["user_context"]
        person_id = args.get("person_id")
        lead_id = args.get("lead_id")
        deal_id = args.get("deal_id")
        if not any((person_id, lead_id, deal_id)):
            raise ValueError("یکی از person_id، lead_id یا deal_id لازم است")
        if lead_id:
            lead = db.query(Lead).filter(Lead.id == int(lead_id), Lead.business_id == business_id).first()
            if lead is None:
                raise ValueError("سرنخ در کسب‌وکار متصل پیدا نشد")
            from app.services.crm_enterprise_service import guard_record
            guard_record(db, business_id, ctx, "lead", lead, write=True)
            person_id = person_id or lead.person_id
        if person_id and not db.query(Person.id).filter(Person.id == int(person_id), Person.business_id == business_id).first():
            raise ValueError("شخص در کسب‌وکار متصل پیدا نشد")
        if deal_id:
            linked_deal = db.query(Deal).filter(Deal.id == int(deal_id), Deal.business_id == business_id).first()
            if linked_deal is None:
                raise ValueError("فرصت در کسب‌وکار متصل پیدا نشد")
            from app.services.crm_enterprise_service import guard_record
            guard_record(db, business_id, ctx, "deal", linked_deal, write=True)
        now = datetime.utcnow()
        activity = CrmActivity(
            business_id=business_id,
            person_id=int(person_id) if person_id else None,
            lead_id=int(lead_id) if lead_id else None,
            deal_id=int(deal_id) if deal_id else None,
            code=generate_document_code(db, business_id, "crm_activity", now.date()),
            activity_type="task",
            subject=draft["subject"],
            description=str(args.get("text") or "")[:4000],
            activity_date=now,
            is_task=True,
            due_at=datetime.fromisoformat(str(draft["due_at"])),
            status="open",
            priority="normal",
            created_by_user_id=ctx.get_user_id(),
        )
        db.add(activity)
        db.commit()
        db.refresh(activity)
        try:
            from app.services.workflow.workflow_trigger_service import trigger_crm_activity_created
            trigger_crm_activity_created(db, business_id, activity.id, user_id=ctx.get_user_id())
        except Exception:
            logger.exception("crm.activity.created trigger failed activity_id=%s", activity.id)
        return {"created": True, "activity_id": activity.id, "subject": activity.subject, "due_at": draft["due_at"], "posted_document": False}

    registry.register(AIFunction(
        name="create_crm_task_from_text",
        description="وظیفه CRM را از جمله فارسی می‌سازد، فقط وقتی confirmed=true باشد و کاربر ابزار را تأیید کرده باشد. سند حسابداری نمی‌سازد.",
        parameters_schema=_schema({
            "text": {"type": "string", "minLength": 1, "maxLength": 1000},
            "confirmed": {"type": "boolean"},
            "person_id": {"type": ["integer", "null"], "minimum": 1},
            "lead_id": {"type": ["integer", "null"], "minimum": 1},
            "deal_id": {"type": ["integer", "null"], "minimum": 1},
        }, ["text", "confirmed"]),
        handler=create_crm_task_from_text, allowed_roles=_ROLES, required_permissions=["crm.write"], category="crm",
        requires_approval=True, risk_level="medium", is_readonly=False,
    ))

    # ACTIVITY CREATE
    def create_activity(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from adapters.db.models.crm import CrmActivity, Deal, Lead
        from adapters.db.models.person import Person
        from adapters.api.v1.schema_models.crm import CrmActivityCreate
        from app.services import crm_custom_field_service
        from app.services.document_numbering_service import generate_document_code

        db = context["db"]
        business_id = int(context["business_id"])
        ctx = context["user_context"]
        body = CrmActivityCreate(**{k: v for k, v in args.items() if k != "business_id"})
        lead = None
        if body.lead_id:
            lead = db.query(Lead).filter(Lead.id == body.lead_id, Lead.business_id == business_id).first()
            if not lead:
                raise ValueError("سرنخ در کسب‌وکار متصل پیدا نشد")
            from app.services.crm_enterprise_service import guard_record
            guard_record(db, business_id, ctx, "lead", lead, write=True)
        person_id = body.person_id or (lead.person_id if lead else None)
        if person_id and not db.query(Person.id).filter(Person.id == person_id, Person.business_id == business_id).first():
            raise ValueError("شخص در کسب‌وکار متصل پیدا نشد")
        if body.deal_id:
            linked_deal = db.query(Deal).filter(Deal.id == body.deal_id, Deal.business_id == business_id).first()
            if linked_deal is None:
                raise ValueError("فرصت در کسب‌وکار متصل پیدا نشد")
            from app.services.crm_enterprise_service import guard_record
            guard_record(db, business_id, ctx, "deal", linked_deal, write=True)
        _ensure_business_member(db, business_id, body.assigned_to_user_id)
        code = str(body.code or "").strip() or generate_document_code(db, business_id, "crm_activity", body.activity_date.date())
        if db.query(CrmActivity.id).filter(CrmActivity.business_id == business_id, CrmActivity.code == code).first():
            raise ValueError("کد فعالیت CRM تکراری است")
        extra = crm_custom_field_service.validate_and_merge_custom_values(db, business_id, "activity", body.extra_info, body.custom_fields)
        status = body.status or "open"
        if status not in {"open", "done", "cancelled"}:
            raise ValueError("وضعیت فعالیت باید open، done یا cancelled باشد")
        activity = CrmActivity(
            business_id=business_id, person_id=person_id, lead_id=body.lead_id, code=code,
            activity_type=body.activity_type, subject=body.subject, description=body.description,
            activity_date=body.activity_date, deal_id=body.deal_id, is_task=body.is_task,
            due_at=body.due_at, status=status, completed_at=datetime.utcnow() if status == "done" else None,
            assigned_to_user_id=body.assigned_to_user_id, outcome=body.outcome,
            priority=body.priority or "normal", created_by_user_id=ctx.get_user_id(), extra_info=extra,
        )
        db.add(activity)
        if lead and not body.is_task:
            now = datetime.utcnow()
            lead.first_touched_at = lead.first_touched_at or now
            lead.last_activity_at = now
        db.commit()
        db.refresh(activity)
        try:
            from app.services.workflow.workflow_trigger_service import trigger_crm_activity_created
            trigger_crm_activity_created(db, business_id, activity.id, user_id=ctx.get_user_id())
        except Exception:
            pass
        return _crm_activity_result(activity)

    activity_create_props = {
        "person_id": {"type": ["integer", "null"], "minimum": 1},
        "lead_id": {"type": ["integer", "null"], "minimum": 1},
        "code": {"type": ["string", "null"], "maxLength": 50},
        "activity_type": {"type": "string", "maxLength": 50},
        "subject": {"type": ["string", "null"], "maxLength": 255},
        "description": {"type": ["string", "null"]},
        "activity_date": _DATETIME,
        "deal_id": {"type": ["integer", "null"], "minimum": 1},
        "extra_info": {"type": ["object", "null"]},
        "is_task": {"type": "boolean"}, "due_at": {"anyOf": [_DATETIME, {"type": "null"}]},
        "status": {"type": ["string", "null"], "enum": ["open", "done", "cancelled", None]},
        "assigned_to_user_id": {"type": ["integer", "null"], "minimum": 1},
        "outcome": {"type": ["string", "null"], "maxLength": 100},
        "priority": {"type": ["string", "null"], "enum": ["low", "normal", "high", "urgent", None]},
        "custom_fields": {"type": ["object", "null"]},
    }
    registry.register(AIFunction(
        name="create_crm_activity", description="ثبت فعالیت یا وظیفهٔ CRM. یکی از person_id یا lead_id لازم است؛ اگر lead به مشتری تبدیل شده، person_id را هم مشخص کن. نیازمند تأیید است.",
        parameters_schema=_schema(activity_create_props, ["activity_type", "activity_date"]),
        handler=create_activity, allowed_roles=_ROLES, required_permissions=["crm.write"], category="crm",
        requires_approval=True, risk_level="medium", is_readonly=False,
    ))

    # ACTIVITY UPDATE
    def update_activity(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from adapters.db.models.crm import CrmActivity, Deal
        from adapters.api.v1.schema_models.crm import CrmActivityUpdate
        from app.services import crm_custom_field_service

        db = context["db"]
        business_id = int(context["business_id"])
        ctx = context["user_context"]
        activity_id = int(args["activity_id"])
        body = CrmActivityUpdate(**{k: v for k, v in args.items() if k not in {"activity_id", "business_id"}})
        activity = db.query(CrmActivity).filter(CrmActivity.id == activity_id, CrmActivity.business_id == business_id).first()
        if not activity:
            raise ValueError("فعالیت در کسب‌وکار متصل پیدا نشد")
        from app.services.crm_enterprise_service import guard_activity, guard_record
        guard_activity(db, business_id, ctx, activity, write=True)
        if body.deal_id is not None and body.deal_id != activity.deal_id:
            linked_deal = db.query(Deal).filter(Deal.id == body.deal_id, Deal.business_id == business_id).first()
            if linked_deal is None:
                raise ValueError("فرصت در کسب‌وکار متصل پیدا نشد")
            guard_record(db, business_id, ctx, "deal", linked_deal, write=True)
        if body.code is not None and str(body.code).strip():
            code = str(body.code).strip()
            if db.query(CrmActivity.id).filter(CrmActivity.business_id == business_id, CrmActivity.code == code, CrmActivity.id != activity_id).first():
                raise ValueError("کد فعالیت CRM تکراری است")
            activity.code = code
        _ensure_business_member(db, business_id, body.assigned_to_user_id)
        if body.clear_deal:
            activity.deal_id = None
        for field in ("activity_type", "subject", "description", "activity_date", "deal_id", "extra_info", "is_task", "due_at", "assigned_to_user_id", "outcome", "priority"):
            if field == "deal_id" and body.clear_deal:
                continue
            value = getattr(body, field, None)
            if value is not None:
                setattr(activity, field, value)
        if body.status is not None:
            if body.status not in {"open", "done", "cancelled"}:
                raise ValueError("وضعیت فعالیت باید open، done یا cancelled باشد")
            activity.status = body.status
            activity.completed_at = datetime.utcnow() if body.status == "done" else None
        if body.custom_fields is not None:
            activity.extra_info = crm_custom_field_service.validate_and_merge_custom_values(db, business_id, "activity", activity.extra_info, body.custom_fields)
        db.commit()
        db.refresh(activity)
        return _crm_activity_result(activity)

    activity_update_props = {k: v for k, v in activity_create_props.items() if k not in {"person_id", "lead_id"}}
    activity_update_props["clear_deal"] = {"type": "boolean"}
    registry.register(AIFunction(
        name="update_crm_activity", description="ویرایش فعالیت یا وظیفهٔ CRM. برای تغییر وضعیت فقط open، done یا cancelled را بفرست. برای برداشتن فرصت، clear_deal را true بفرست. نیازمند تأیید است.",
        parameters_schema=_schema({"activity_id": {"type": "integer", "minimum": 1}, **activity_update_props}, ["activity_id"]),
        handler=update_activity, allowed_roles=_ROLES, required_permissions=["crm.write"], category="crm",
        requires_approval=True, risk_level="medium", is_readonly=False,
    ))

    def delete_activity(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from adapters.db.models.crm import CrmActivity
        db = context["db"]
        business_id = int(context["business_id"])
        activity_id = int(args["activity_id"])
        activity = db.query(CrmActivity).filter(CrmActivity.id == activity_id, CrmActivity.business_id == business_id).first()
        if not activity:
            raise ValueError("فعالیت در کسب‌وکار متصل پیدا نشد")
        from app.services.crm_enterprise_service import guard_activity
        guard_activity(db, business_id, context["user_context"], activity, write=True)
        db.delete(activity)
        db.commit()
        return {"activity_id": activity_id, "deleted": True}

    registry.register(AIFunction(
        name="delete_crm_activity", description="حذف فعالیت CRM؛ این عملیات سابقهٔ فعالیت را پاک می‌کند و نیازمند تأیید صریح است.",
        parameters_schema=_schema({"activity_id": {"type": "integer", "minimum": 1}}, ["activity_id"]),
        handler=delete_activity, allowed_roles=_ROLES, required_permissions=["crm.write"], category="crm",
        requires_approval=True, risk_level="high", is_readonly=False,
    ))

    # CRM AUTOMATION SEQUENCES
    def _sequence_result(sequence: Any) -> Dict[str, Any]:
        return {
            "id": sequence.id,
            "business_id": sequence.business_id,
            "name": sequence.name,
            "description": sequence.description,
            "is_active": bool(sequence.is_active),
            "sms_daily_cap": sequence.sms_daily_cap,
            "stop_on_reply": bool(sequence.stop_on_reply),
            "stop_on_close": bool(sequence.stop_on_close),
            "created_at": sequence.created_at.isoformat() if sequence.created_at else None,
            "updated_at": sequence.updated_at.isoformat() if sequence.updated_at else None,
            "created_by_user_id": sequence.created_by_user_id,
            "steps": [{
                "id": step.id, "step_order": step.step_order,
                "delay_hours": step.delay_hours, "action_type": step.action_type,
                "action_config": step.action_config,
            } for step in sorted(sequence.steps, key=lambda item: item.step_order)],
        }

    step_config_properties = {
        "due_in_hours": {"type": "integer", "minimum": 1, "maximum": 8760},
        "subject": {"type": "string", "maxLength": 255},
        "description": {"type": "string", "maxLength": 4000},
        "priority": {"type": "string", "enum": ["low", "normal", "high", "urgent"]},
        "message": {"type": "string", "maxLength": 2000},
        "text": {"type": "string", "maxLength": 2000},
        "title": {"type": "string", "maxLength": 255},
        "stage_id": {"type": "integer", "minimum": 1},
        "won_reason_code": {"type": "string", "maxLength": 50},
        "lost_reason_code": {"type": "string", "maxLength": 50},
    }
    step_schema = {"type": "object", "properties": {
        "step_order": {"type": "integer", "minimum": 0},
        "delay_hours": {"type": "integer", "minimum": 0, "maximum": 8760},
        "action_type": {"type": "string", "enum": ["create_task", "send_sms", "notify_assignee", "update_lead_stage", "update_deal_stage"]},
        "action_config": {"type": ["object", "null"], "properties": step_config_properties, "additionalProperties": False},
    }, "required": ["step_order", "action_type"], "additionalProperties": False}

    def _parse_sequence_steps(values: Any, db: Any, business_id: int) -> list[Any]:
        from adapters.db.models.crm import CrmProcessDefinition, CrmProcessStage
        from adapters.api.v1.schema_models.crm import CrmSequenceStepInput
        from sqlalchemy import and_

        if values is None:
            return []
        if len(values) > 50:
            raise ValueError("هر توالی حداکثر ۵۰ گام می‌تواند داشته باشد")
        steps = [CrmSequenceStepInput(**item) for item in values]
        orders = [step.step_order for step in steps]
        if len(orders) != len(set(orders)):
            raise ValueError("step_order گام‌های توالی باید یکتا باشد")
        allowed_config = {
            "create_task": {"due_in_hours", "subject", "description", "priority"},
            "send_sms": {"message", "text"},
            "notify_assignee": {"title", "message"},
            "update_lead_stage": {"stage_id"},
            "update_deal_stage": {"stage_id", "won_reason_code", "lost_reason_code"},
        }
        for step in steps:
            config = step.action_config or {}
            if set(config) - allowed_config[step.action_type]:
                raise ValueError(f"action_config برای {step.action_type} فیلد نامعتبر دارد")
            if step.action_type == "send_sms" and not (config.get("message") or config.get("text")):
                raise ValueError("گام send_sms به message یا text نیاز دارد")
            if step.action_type in {"update_lead_stage", "update_deal_stage"} and not config.get("stage_id"):
                raise ValueError("گام تغییر مرحله به stage_id نیاز دارد")
            if step.action_type in {"update_lead_stage", "update_deal_stage"}:
                expected_process_type = "lead_funnel" if step.action_type == "update_lead_stage" else "sales_pipeline"
                valid_stage = db.query(CrmProcessStage.id).join(
                    CrmProcessDefinition, CrmProcessDefinition.id == CrmProcessStage.process_definition_id,
                ).filter(and_(
                    CrmProcessStage.id == int(config["stage_id"]),
                    CrmProcessDefinition.business_id == business_id,
                    CrmProcessDefinition.process_type == expected_process_type,
                )).first()
                if not valid_stage:
                    raise ValueError(f"stage_id برای {step.action_type} باید به فرایند همین کسب‌وکار تعلق داشته باشد")
            if config.get("priority") and config["priority"] not in {"low", "normal", "high", "urgent"}:
                raise ValueError("اولویت create_task نامعتبر است")
        return steps

    def list_crm_sequences(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from adapters.db.models.crm import CrmSequence
        from sqlalchemy.orm import selectinload

        db, business_id = context["db"], int(context["business_id"])
        limit = min(max(int(args.get("limit", 50)), 1), 100)
        offset = max(int(args.get("offset", 0)), 0)
        query = db.query(CrmSequence).options(selectinload(CrmSequence.steps)).filter(CrmSequence.business_id == business_id)
        total = query.count()
        rows = query.order_by(CrmSequence.created_at.desc()).offset(offset).limit(limit).all()
        return {"items": [_sequence_result(row) for row in rows], "total": total, "limit": limit, "offset": offset}

    registry.register(AIFunction(
        name="list_crm_sequences", description="توالی‌های خودکار CRM کسب‌وکار متصل را صفحه‌بندی‌شده می‌خواند.",
        parameters_schema=_schema({"limit": {"type": "integer", "minimum": 1, "maximum": 100}, "offset": {"type": "integer", "minimum": 0}}, []),
        handler=list_crm_sequences, allowed_roles=_ROLES, required_permissions=["crm.view"], category="crm",
    ))

    def get_crm_sequence(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from adapters.db.models.crm import CrmSequence
        from sqlalchemy.orm import selectinload
        sequence = context["db"].query(CrmSequence).options(selectinload(CrmSequence.steps)).filter(
            CrmSequence.id == int(args["sequence_id"]), CrmSequence.business_id == int(context["business_id"]),
        ).first()
        if not sequence:
            raise ValueError("توالی در کسب‌وکار متصل پیدا نشد")
        return _sequence_result(sequence)

    registry.register(AIFunction(
        name="get_crm_sequence", description="جزئیات و گام‌های توالی CRM را می‌خواند.",
        parameters_schema=_schema({"sequence_id": {"type": "integer", "minimum": 1}}, ["sequence_id"]),
        handler=get_crm_sequence, allowed_roles=_ROLES, required_permissions=["crm.view"], category="crm",
    ))

    def create_crm_sequence(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from adapters.db.models.crm import CrmSequence, CrmSequenceStep
        from adapters.api.v1.schema_models.crm import CrmSequenceCreate

        db, business_id = context["db"], int(context["business_id"])
        body = CrmSequenceCreate(**{key: value for key, value in args.items() if key != "business_id"})
        steps = _parse_sequence_steps(args.get("steps") or [], db, business_id)
        sequence = CrmSequence(
            business_id=business_id, name=body.name, description=body.description,
            is_active=body.is_active, sms_daily_cap=body.sms_daily_cap or None,
            stop_on_reply=body.stop_on_reply, stop_on_close=body.stop_on_close,
            created_by_user_id=context["user_context"].get_user_id(),
        )
        db.add(sequence)
        db.flush()
        for step in steps:
            db.add(CrmSequenceStep(
                sequence_id=sequence.id, step_order=step.step_order,
                delay_hours=step.delay_hours, action_type=step.action_type,
                action_config=step.action_config,
            ))
        db.commit()
        db.refresh(sequence)
        return _sequence_result(sequence)

    sequence_fields = {
        "name": {"type": "string", "minLength": 1, "maxLength": 255},
        "description": {"type": ["string", "null"]},
        "is_active": {"type": "boolean"},
        "sms_daily_cap": {"type": ["integer", "null"], "minimum": 0, "maximum": 10000},
        "stop_on_reply": {"type": "boolean"},
        "stop_on_close": {"type": "boolean"},
        "steps": {"type": "array", "maxItems": 50, "items": step_schema},
    }
    registry.register(AIFunction(
        name="create_crm_sequence",
        description="تعریف توالی CRM. گام send_sms پیامک می‌فرستد و گام‌های مرحله وضعیت سرنخ/فرصت را تغییر می‌دهند؛ پیش از ذخیره اثرها را بررسی و تأیید بگیر.",
        parameters_schema=_schema(sequence_fields, ["name"]), handler=create_crm_sequence,
        allowed_roles=_ROLES, required_permissions=["crm.write"], category="crm",
        requires_approval=True, risk_level="high", is_readonly=False,
    ))

    def update_crm_sequence(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from adapters.db.models.crm import CrmSequence, CrmSequenceStep
        from adapters.api.v1.schema_models.crm import CrmSequenceUpdate
        from sqlalchemy.orm import selectinload

        db, business_id = context["db"], int(context["business_id"])
        sequence_id = int(args["sequence_id"])
        body = CrmSequenceUpdate(**{key: value for key, value in args.items() if key not in {"sequence_id", "business_id"}})
        sequence = db.query(CrmSequence).options(selectinload(CrmSequence.steps)).filter(
            CrmSequence.id == sequence_id, CrmSequence.business_id == business_id,
        ).with_for_update().first()
        if not sequence:
            raise ValueError("توالی در کسب‌وکار متصل پیدا نشد")
        steps = _parse_sequence_steps(args["steps"], db, business_id) if body.steps is not None else None
        if body.name is not None:
            sequence.name = body.name
        if body.description is not None:
            sequence.description = body.description
        if body.is_active is not None:
            sequence.is_active = body.is_active
        if body.clear_sms_daily_cap:
            sequence.sms_daily_cap = None
        elif body.sms_daily_cap is not None:
            sequence.sms_daily_cap = body.sms_daily_cap or None
        if body.stop_on_reply is not None:
            sequence.stop_on_reply = body.stop_on_reply
        if body.stop_on_close is not None:
            sequence.stop_on_close = body.stop_on_close
        if steps is not None:
            db.query(CrmSequenceStep).filter(CrmSequenceStep.sequence_id == sequence_id).delete(synchronize_session=False)
            for step in steps:
                db.add(CrmSequenceStep(
                    sequence_id=sequence_id, step_order=step.step_order,
                    delay_hours=step.delay_hours, action_type=step.action_type,
                    action_config=step.action_config,
                ))
        db.commit()
        db.expire(sequence, ["steps"])
        return _sequence_result(sequence)

    registry.register(AIFunction(
        name="update_crm_sequence", description="ویرایش توالی؛ ارسال پیامک یا تغییر مرحله در گام‌ها نیازمند تأیید است.",
        parameters_schema=_schema({"sequence_id": {"type": "integer", "minimum": 1}, **sequence_fields}, ["sequence_id"]),
        handler=update_crm_sequence, allowed_roles=_ROLES, required_permissions=["crm.write"], category="crm",
        requires_approval=True, risk_level="high", is_readonly=False,
    ))

    def delete_crm_sequence(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from adapters.db.models.crm import CrmSequence
        db, business_id = context["db"], int(context["business_id"])
        sequence_id = int(args["sequence_id"])
        sequence = db.query(CrmSequence).filter(CrmSequence.id == sequence_id, CrmSequence.business_id == business_id).first()
        if not sequence:
            raise ValueError("توالی در کسب‌وکار متصل پیدا نشد")
        db.delete(sequence)
        db.commit()
        return {"sequence_id": sequence_id, "deleted": True}

    registry.register(AIFunction(
        name="delete_crm_sequence", description="حذف توالی خودکار CRM و گام‌های آن؛ نیازمند تأیید صریح است.",
        parameters_schema=_schema({"sequence_id": {"type": "integer", "minimum": 1}}, ["sequence_id"]),
        handler=delete_crm_sequence, allowed_roles=_ROLES, required_permissions=["crm.write"], category="crm",
        requires_approval=True, risk_level="high", is_readonly=False,
    ))

    def enroll_crm_sequence(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from app.services.crm_automation_service import enroll_in_sequence
        db, business_id = context["db"], int(context["business_id"])
        from adapters.db.models.crm import Deal, Lead
        from app.services.crm_enterprise_service import guard_record
        entity_type = args["entity_type"]
        model = Lead if entity_type == "lead" else Deal
        target = db.query(model).filter(model.id == int(args["entity_id"]), model.business_id == business_id).first()
        if target is None:
            raise ValueError("رکورد در کسب‌وکار متصل پیدا نشد")
        guard_record(db, business_id, context["user_context"], entity_type, target, write=True)
        enrollment = enroll_in_sequence(
            db, business_id, int(args["sequence_id"]), entity_type, int(args["entity_id"]),
        )
        db.commit()
        db.refresh(enrollment)
        return {
            "id": enrollment.id, "sequence_id": enrollment.sequence_id,
            "entity_type": enrollment.entity_type, "entity_id": enrollment.entity_id,
            "status": enrollment.status, "current_step_order": enrollment.current_step_order,
            "next_run_at": enrollment.next_run_at.isoformat() if enrollment.next_run_at else None,
        }

    registry.register(AIFunction(
        name="enroll_crm_sequence", description="سرنخ یا فرصت را در توالی فعال CRM ثبت می‌کند؛ گام‌های زمان‌بندی‌شده ممکن است پیامک یا تغییر وضعیت ایجاد کنند. نیازمند تأیید صریح است.",
        parameters_schema=_schema({"sequence_id": {"type": "integer", "minimum": 1}, "entity_type": {"type": "string", "enum": ["lead", "deal"]}, "entity_id": {"type": "integer", "minimum": 1}}, ["sequence_id", "entity_type", "entity_id"]),
        handler=enroll_crm_sequence, allowed_roles=_ROLES, required_permissions=["crm.write"], category="crm",
        requires_approval=True, risk_level="high", is_readonly=False,
    ))

    # BUSINESS AUTOMATION SETTINGS
    def _automation_settings_result(settings: Any) -> Dict[str, Any]:
        return {
            "business_id": settings.business_id,
            "lead_sla_hours": settings.lead_sla_hours,
            "auto_assign_enabled": bool(settings.auto_assign_enabled),
            "auto_assign_user_ids": settings.auto_assign_user_ids or [],
            "auto_assign_cursor": settings.auto_assign_cursor,
            "follow_up_notify_enabled": bool(settings.follow_up_notify_enabled),
            "stale_deal_days": settings.stale_deal_days,
            "score_rules": settings.score_rules,
            "record_acl_enabled": bool(getattr(settings, "record_acl_enabled", False)),
        }

    def get_crm_automation_settings(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from app.services.crm_chat_service import get_or_create_crm_settings
        settings = get_or_create_crm_settings(context["db"], int(context["business_id"]))
        return _automation_settings_result(settings)

    registry.register(AIFunction(
        name="get_crm_automation_settings", description="تنظیمات SLA، تخصیص خودکار، یادآوری و امتیازدهی CRM را می‌خواند.",
        parameters_schema=_schema({}, []), handler=get_crm_automation_settings,
        allowed_roles=_ROLES, required_permissions=["crm.view"], category="crm",
    ))

    score_rule_schema = {"type": ["object", "null"], "properties": {
        "has_mobile": {"type": "integer", "minimum": -1000, "maximum": 1000},
        "has_email": {"type": "integer", "minimum": -1000, "maximum": 1000},
        "has_company": {"type": "integer", "minimum": -1000, "maximum": 1000},
        "stage_multiplier": {"type": "integer", "minimum": -1000, "maximum": 1000},
        "source_weights": {"type": ["object", "null"], "additionalProperties": {"type": "integer", "minimum": -1000, "maximum": 1000}},
    }, "additionalProperties": False}

    def update_crm_automation_settings(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from datetime import datetime
        from adapters.api.v1.schema_models.crm import CrmAutomationSettingsUpdate
        from app.services.crm_chat_service import get_or_create_crm_settings

        db, business_id = context["db"], int(context["business_id"])
        body = CrmAutomationSettingsUpdate(**{key: value for key, value in args.items() if key != "business_id"})
        user_ids = list(dict.fromkeys(body.auto_assign_user_ids or [])) if body.auto_assign_user_ids is not None else None
        if user_ids is not None:
            if len(user_ids) > 100:
                raise ValueError("حداکثر ۱۰۰ عضو را برای تخصیص خودکار مشخص کن")
            for user_id in user_ids:
                _ensure_business_member(db, business_id, user_id)
        if body.score_rules is not None:
            allowed_keys = {"has_mobile", "has_email", "has_company", "stage_multiplier", "source_weights"}
            if set(body.score_rules) - allowed_keys:
                raise ValueError("score_rules شامل کلید ناشناخته است")
            source_weights = body.score_rules.get("source_weights")
            if source_weights is not None:
                if not isinstance(source_weights, dict) or len(source_weights) > 200:
                    raise ValueError("source_weights باید یک شیء با حداکثر ۲۰۰ منبع باشد")
                for key, value in source_weights.items():
                    if not isinstance(key, str) or len(key) > 50 or isinstance(value, bool) or not isinstance(value, int) or not -1000 <= value <= 1000:
                        raise ValueError("هر وزن منبع باید عدد صحیح بین -۱۰۰۰ تا ۱۰۰۰ باشد")
            for key in allowed_keys - {"source_weights"}:
                value = body.score_rules.get(key)
                if value is not None and (isinstance(value, bool) or not isinstance(value, int) or not -1000 <= value <= 1000):
                    raise ValueError(f"{key} باید عدد صحیح بین -۱۰۰۰ تا ۱۰۰۰ باشد")

        settings = get_or_create_crm_settings(db, business_id)
        if body.lead_sla_hours is not None:
            settings.lead_sla_hours = body.lead_sla_hours
        if body.auto_assign_enabled is not None:
            settings.auto_assign_enabled = body.auto_assign_enabled
        if user_ids is not None:
            settings.auto_assign_user_ids = user_ids
        if body.follow_up_notify_enabled is not None:
            settings.follow_up_notify_enabled = body.follow_up_notify_enabled
        if body.stale_deal_days is not None:
            settings.stale_deal_days = body.stale_deal_days
        if body.score_rules is not None:
            settings.score_rules = body.score_rules
        settings.updated_at = datetime.utcnow()
        db.commit()
        db.refresh(settings)
        return _automation_settings_result(settings)

    registry.register(AIFunction(
        name="update_crm_automation_settings",
        description="به‌روزرسانی SLA، اعضای مجاز تخصیص خودکار، اعلان‌های پیگیری، تشخیص فرصت راکد و قواعد امتیازدهی؛ تغییر بر رفتار خودکار CRM اثر می‌گذارد و نیازمند تأیید است.",
        parameters_schema=_schema({
            "lead_sla_hours": {"type": ["integer", "null"], "minimum": 0},
            "auto_assign_enabled": {"type": ["boolean", "null"]},
            "auto_assign_user_ids": {"type": ["array", "null"], "maxItems": 100, "items": {"type": "integer", "minimum": 1}},
            "follow_up_notify_enabled": {"type": ["boolean", "null"]},
            "stale_deal_days": {"type": ["integer", "null"], "minimum": 0},
            "score_rules": score_rule_schema,
        }, []), handler=update_crm_automation_settings,
        allowed_roles=_ROLES, required_permissions=["crm.write"], category="crm",
        requires_approval=True, risk_level="high", is_readonly=False,
    ))
