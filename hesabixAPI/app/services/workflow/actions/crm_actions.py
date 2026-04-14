"""
Actionهای مربوط به CRM (سرنخ، فرصت فروش، فعالیت)
"""

from typing import Any, Dict
from datetime import datetime, date
from decimal import Decimal
from app.services.workflow.action_registry import ActionHandler
from app.services.workflow.logging_decorators import log_action_execution


class CreateLeadAction(ActionHandler):
    """ایجاد سرنخ از داخل Workflow"""

    def get_metadata(self) -> Dict[str, Any]:
        return {
            "name": "ایجاد سرنخ",
            "description": "ایجاد یک سرنخ جدید در CRM",
            "config_schema": {
                "process_definition_id": {"type": "integer", "description": "شناسه فرایند فانل سرنخ", "required": True},
                "stage_id": {"type": "integer", "description": "شناسه مرحله", "required": True},
                "name": {"type": "string", "description": "نام سرنخ", "required": True},
                "company_name": {"type": "string", "description": "نام شرکت", "required": False},
                "mobile": {"type": "string", "description": "موبایل", "required": False},
                "email": {"type": "string", "description": "ایمیل", "required": False},
                "description": {"type": "string", "description": "توضیحات", "required": False},
                "source_code": {"type": "string", "description": "کد منبع سرنخ", "required": False},
                "assigned_to_user_id": {"type": "integer", "description": "تخصیص به کاربر", "required": False},
            },
        }

    @log_action_execution
    def execute(
        self,
        context: Dict[str, Any],
        config: Dict[str, Any],
        node_results: Dict[str, Any],
    ) -> Dict[str, Any]:
        from app.services.workflow.workflow_engine import WorkflowEngine
        from adapters.db.models.crm import Lead
        from app.services.document_numbering_service import generate_document_code

        db = context.get("db")
        business_id = context.get("business_id")
        user_id = context.get("user_id")
        if not db or business_id is None:
            return {"success": False, "error": "db or business_id missing in context"}
        user_id = user_id or 0

        process_definition_id = WorkflowEngine._resolve_value_static(config.get("process_definition_id"), context, node_results)
        stage_id = WorkflowEngine._resolve_value_static(config.get("stage_id"), context, node_results)
        name = WorkflowEngine._resolve_value_static(config.get("name"), context, node_results)
        if not process_definition_id or not stage_id or not name:
            return {"success": False, "error": "process_definition_id, stage_id and name are required"}
        process_definition_id = int(process_definition_id)
        stage_id = int(stage_id)
        name = str(name).strip()[:255]
        if not name:
            return {"success": False, "error": "name is required"}

        code_val = generate_document_code(db, business_id, "crm_lead", date.today())
        created_by = user_id
        if not created_by:
            from adapters.db.models.business import Business
            biz = db.query(Business).filter(Business.id == business_id).first()
            created_by = biz.owner_id if biz else None
        if not created_by:
            return {"success": False, "error": "user_id or business owner required to create lead"}
        lead = Lead(
            business_id=business_id,
            process_definition_id=process_definition_id,
            stage_id=stage_id,
            code=code_val,
            name=name,
            company_name=WorkflowEngine._resolve_value_static(config.get("company_name"), context, node_results) or None,
            mobile=WorkflowEngine._resolve_value_static(config.get("mobile"), context, node_results) or None,
            email=WorkflowEngine._resolve_value_static(config.get("email"), context, node_results) or None,
            description=WorkflowEngine._resolve_value_static(config.get("description"), context, node_results) or None,
            source_code=WorkflowEngine._resolve_value_static(config.get("source_code"), context, node_results) or None,
            assigned_to_user_id=WorkflowEngine._resolve_value_static(config.get("assigned_to_user_id"), context, node_results) or None,
            created_by_user_id=created_by,
        )
        db.add(lead)
        db.flush()
        db.refresh(lead)
        return {"success": True, "lead_id": lead.id, "code": lead.code}


class CreateDealAction(ActionHandler):
    """ایجاد فرصت فروش از داخل Workflow"""

    def get_metadata(self) -> Dict[str, Any]:
        return {
            "name": "ایجاد فرصت فروش",
            "description": "ایجاد یک فرصت فروش جدید در CRM",
            "config_schema": {
                "person_id": {"type": "integer", "description": "شناسه مشتری (شخص)", "required": True},
                "process_definition_id": {"type": "integer", "description": "شناسه فرایند پایپلاین", "required": True},
                "stage_id": {"type": "integer", "description": "شناسه مرحله", "required": True},
                "title": {"type": "string", "description": "عنوان فرصت", "required": True},
                "amount": {"type": "number", "description": "مبلغ", "required": True},
                "currency_id": {"type": "integer", "required": False},
                "probability_percent": {"type": "integer", "required": False},
                "description": {"type": "string", "required": False},
                "assigned_to_user_id": {"type": "integer", "required": False},
            },
        }

    @log_action_execution
    def execute(
        self,
        context: Dict[str, Any],
        config: Dict[str, Any],
        node_results: Dict[str, Any],
    ) -> Dict[str, Any]:
        from app.services.workflow.workflow_engine import WorkflowEngine
        from adapters.db.models.crm import Deal
        from app.services.document_numbering_service import generate_document_code

        db = context.get("db")
        business_id = context.get("business_id")
        user_id = context.get("user_id")
        if not db or business_id is None:
            return {"success": False, "error": "db or business_id missing in context"}
        user_id = user_id or 0

        person_id = WorkflowEngine._resolve_value_static(config.get("person_id"), context, node_results)
        process_definition_id = WorkflowEngine._resolve_value_static(config.get("process_definition_id"), context, node_results)
        stage_id = WorkflowEngine._resolve_value_static(config.get("stage_id"), context, node_results)
        title = WorkflowEngine._resolve_value_static(config.get("title"), context, node_results)
        amount = WorkflowEngine._resolve_value_static(config.get("amount"), context, node_results)
        if not all([person_id, process_definition_id, stage_id, title, amount is not None]):
            return {"success": False, "error": "person_id, process_definition_id, stage_id, title and amount are required"}
        person_id = int(person_id)
        process_definition_id = int(process_definition_id)
        stage_id = int(stage_id)
        title = str(title).strip()[:255]
        amount = float(amount)
        if amount < 0:
            return {"success": False, "error": "amount must be >= 0"}

        created_by = user_id
        if not created_by:
            from adapters.db.models.business import Business
            biz = db.query(Business).filter(Business.id == business_id).first()
            created_by = biz.owner_id if biz else None
        if not created_by:
            return {"success": False, "error": "user_id or business owner required to create deal"}
        code_val = generate_document_code(db, business_id, "crm_deal", date.today())
        deal = Deal(
            business_id=business_id,
            person_id=person_id,
            process_definition_id=process_definition_id,
            stage_id=stage_id,
            code=code_val,
            title=title,
            amount=amount,
            currency_id=WorkflowEngine._resolve_value_static(config.get("currency_id"), context, node_results) or None,
            probability_percent=WorkflowEngine._resolve_value_static(config.get("probability_percent"), context, node_results) or None,
            description=WorkflowEngine._resolve_value_static(config.get("description"), context, node_results) or None,
            assigned_to_user_id=WorkflowEngine._resolve_value_static(config.get("assigned_to_user_id"), context, node_results) or None,
            created_by_user_id=created_by,
        )
        db.add(deal)
        db.flush()
        db.refresh(deal)
        return {"success": True, "deal_id": deal.id, "code": deal.code}


class CreateCrmActivityAction(ActionHandler):
    """ثبت فعالیت CRM از داخل Workflow"""

    def get_metadata(self) -> Dict[str, Any]:
        return {
            "name": "ثبت فعالیت CRM",
            "description": "ثبت یک فعالیت (تماس، ایمیل، جلسه، یادداشت) برای یک مشتری",
            "config_schema": {
                "person_id": {"type": "integer", "description": "شناسه شخص (مشتری)", "required": True},
                "activity_type": {"type": "string", "description": "نوع: call | email | meeting | note", "required": True, "enum": ["call", "email", "meeting", "note"]},
                "subject": {"type": "string", "description": "موضوع", "required": False},
                "description": {"type": "string", "description": "شرح", "required": False},
                "activity_date": {"type": "string", "description": "تاریخ و زمان (ISO)", "required": False},
                "deal_id": {"type": "integer", "description": "شناسه فرصت فروش (اختیاری)", "required": False},
            },
        }

    @log_action_execution
    def execute(
        self,
        context: Dict[str, Any],
        config: Dict[str, Any],
        node_results: Dict[str, Any],
    ) -> Dict[str, Any]:
        from app.services.workflow.workflow_engine import WorkflowEngine
        from adapters.db.models.crm import CrmActivity
        from app.services.document_numbering_service import generate_document_code

        db = context.get("db")
        business_id = context.get("business_id")
        user_id = context.get("user_id")
        if not db or business_id is None:
            return {"success": False, "error": "db or business_id missing in context"}
        user_id = user_id or 0

        person_id = WorkflowEngine._resolve_value_static(config.get("person_id"), context, node_results)
        activity_type = WorkflowEngine._resolve_value_static(config.get("activity_type"), context, node_results) or "note"
        if activity_type not in ("call", "email", "meeting", "note"):
            activity_type = "note"
        if not person_id:
            return {"success": False, "error": "person_id is required"}
        person_id = int(person_id)

        activity_date_str = WorkflowEngine._resolve_value_static(config.get("activity_date"), context, node_results)
        if activity_date_str:
            try:
                activity_date = datetime.fromisoformat(str(activity_date_str).replace("Z", "+00:00"))
            except Exception:
                activity_date = datetime.utcnow()
        else:
            activity_date = datetime.utcnow()

        created_by = user_id
        if not created_by:
            from adapters.db.models.business import Business
            biz = db.query(Business).filter(Business.id == business_id).first()
            created_by = biz.owner_id if biz else None
        if not created_by:
            return {"success": False, "error": "user_id or business owner required to create activity"}
        code_val = generate_document_code(db, business_id, "crm_activity", activity_date.date())
        act = CrmActivity(
            business_id=business_id,
            person_id=person_id,
            code=code_val,
            activity_type=activity_type,
            subject=WorkflowEngine._resolve_value_static(config.get("subject"), context, node_results) or None,
            description=WorkflowEngine._resolve_value_static(config.get("description"), context, node_results) or None,
            activity_date=activity_date,
            deal_id=WorkflowEngine._resolve_value_static(config.get("deal_id"), context, node_results) or None,
            created_by_user_id=created_by,
        )
        db.add(act)
        db.flush()
        db.refresh(act)
        return {"success": True, "activity_id": act.id, "code": act.code}
