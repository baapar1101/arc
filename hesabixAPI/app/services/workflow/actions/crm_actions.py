"""
Actionهای مربوط به CRM (سرنخ، فرصت فروش، فعالیت)
"""

from typing import Any, Dict, Optional
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
        from app.services.workflow.dry_run import dry_run_skip
        from app.services.workflow.workflow_engine import WorkflowEngine
        from adapters.db.models.crm import Lead
        from app.services.document_numbering_service import generate_document_code

        sk = dry_run_skip(context, "ایجاد سرنخ")
        if sk is not None:
            return sk

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
        try:
            from app.services.workflow.workflow_trigger_service import trigger_lead_created

            trigger_lead_created(
                db,
                int(business_id),
                lead_id=lead.id,
                process_definition_id=lead.process_definition_id,
                stage_id=lead.stage_id,
                name=lead.name,
                user_id=int(created_by) if created_by else None,
            )
        except Exception:
            pass
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
        from app.services.workflow.dry_run import dry_run_skip
        from app.services.workflow.workflow_engine import WorkflowEngine
        from adapters.db.models.crm import Deal
        from app.services.document_numbering_service import generate_document_code

        sk = dry_run_skip(context, "ایجاد فرصت فروش")
        if sk is not None:
            return sk

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
        try:
            from app.services.workflow.workflow_trigger_service import trigger_deal_created

            trigger_deal_created(
                db,
                int(business_id),
                deal_id=deal.id,
                process_definition_id=deal.process_definition_id,
                stage_id=deal.stage_id,
                person_id=deal.person_id,
                title=deal.title,
                amount=float(deal.amount),
                user_id=int(created_by) if created_by else None,
            )
        except Exception:
            pass
        return {"success": True, "deal_id": deal.id, "code": deal.code}


class CreateCrmActivityAction(ActionHandler):
    """ثبت فعالیت CRM از داخل Workflow"""

    def get_metadata(self) -> Dict[str, Any]:
        return {
            "name": "ثبت فعالیت CRM",
            "description": "ثبت یک فعالیت (تماس، ایمیل، جلسه، یادداشت) برای یک مشتری",
            "config_schema": {
                "person_id": {"type": "integer", "description": "شناسه شخص (مشتری) — در صورت ثبت برای سرنخ خالی بگذارید", "required": False},
                "lead_id": {"type": "integer", "description": "شناسه سرنخ (فعالیت قبل از تبدیل به مشتری)", "required": False},
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
        from app.services.workflow.dry_run import dry_run_skip
        from app.services.workflow.workflow_engine import WorkflowEngine
        from adapters.db.models.crm import CrmActivity
        from app.services.document_numbering_service import generate_document_code

        sk = dry_run_skip(context, "ثبت فعالیت CRM")
        if sk is not None:
            return sk

        db = context.get("db")
        business_id = context.get("business_id")
        user_id = context.get("user_id")
        if not db or business_id is None:
            return {"success": False, "error": "db or business_id missing in context"}
        user_id = user_id or 0

        person_id = WorkflowEngine._resolve_value_static(config.get("person_id"), context, node_results)
        lead_id = WorkflowEngine._resolve_value_static(config.get("lead_id"), context, node_results)
        activity_type = WorkflowEngine._resolve_value_static(config.get("activity_type"), context, node_results) or "note"
        if activity_type not in ("call", "email", "meeting", "note"):
            activity_type = "note"
        person_id_int = int(person_id) if person_id else None
        lead_id_int = int(lead_id) if lead_id else None
        if not person_id_int and not lead_id_int:
            return {"success": False, "error": "person_id یا lead_id لازم است"}
        if lead_id_int:
            from adapters.db.models.crm import Lead

            lead = db.query(Lead).filter(Lead.id == lead_id_int, Lead.business_id == business_id).first()
            if not lead:
                return {"success": False, "error": "lead not found"}
            if lead.person_id and not person_id_int:
                person_id_int = int(lead.person_id)

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
        if person_id_int:
            from adapters.db.models.person import Person

            person = db.query(Person).filter(Person.id == person_id_int, Person.business_id == business_id).first()
            if not person:
                return {"success": False, "error": "person not found"}
        code_val = generate_document_code(db, business_id, "crm_activity", activity_date.date())
        act = CrmActivity(
            business_id=business_id,
            person_id=person_id_int,
            lead_id=lead_id_int,
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
        try:
            from app.services.workflow.workflow_trigger_service import trigger_crm_activity_created

            trigger_crm_activity_created(db, int(business_id), act.id, user_id=int(created_by) if created_by else None)
        except Exception:
            pass
        return {"success": True, "activity_id": act.id, "code": act.code}


class UpdateLeadAction(ActionHandler):
    """به‌روزرسانی سرنخ از ورک‌فلو"""

    def get_metadata(self) -> Dict[str, Any]:
        return {
            "name": "به‌روزرسانی سرنخ",
            "description": "تغییر مرحله، مسئول، پیگیری یا نام سرنخ",
            "config_schema": {
                "lead_id": {"type": "integer", "required": True},
                "stage_id": {"type": "integer", "required": False},
                "assigned_to_user_id": {"type": "integer", "required": False},
                "next_follow_up_at": {"type": "string", "description": "ISO datetime", "required": False},
                "name": {"type": "string", "required": False},
                "source_code": {"type": "string", "required": False},
            },
        }

    @log_action_execution
    def execute(
        self,
        context: Dict[str, Any],
        config: Dict[str, Any],
        node_results: Dict[str, Any],
    ) -> Dict[str, Any]:
        from app.services.workflow.dry_run import dry_run_skip
        from app.services.workflow.workflow_engine import WorkflowEngine
        from adapters.db.models.crm import Lead, CrmProcessStage

        sk = dry_run_skip(context, "به‌روزرسانی سرنخ")
        if sk is not None:
            return sk

        db = context.get("db")
        business_id = context.get("business_id")
        if not db or business_id is None:
            return {"success": False, "error": "db or business_id missing in context"}
        lead_id = WorkflowEngine._resolve_value_static(config.get("lead_id"), context, node_results)
        if not lead_id:
            return {"success": False, "error": "lead_id is required"}
        lead = db.query(Lead).filter(Lead.id == int(lead_id), Lead.business_id == business_id).first()
        if not lead:
            return {"success": False, "error": "lead not found"}
        old_stage_id = int(lead.stage_id)
        old_assigned_to_user_id = lead.assigned_to_user_id
        uid = context.get("user_id")
        if not uid:
            from adapters.db.models.business import Business

            biz = db.query(Business).filter(Business.id == business_id).first()
            uid = biz.owner_id if biz else None

        sid = WorkflowEngine._resolve_value_static(config.get("stage_id"), context, node_results)
        if sid is not None:
            new_sid = int(sid)
            st = (
                db.query(CrmProcessStage)
                .filter(
                    CrmProcessStage.id == new_sid,
                    CrmProcessStage.process_definition_id == lead.process_definition_id,
                )
                .first()
            )
            if not st:
                return {"success": False, "error": "invalid stage_id"}
            if new_sid != old_stage_id:
                lead.stage_id = new_sid
                db.flush()
                try:
                    from app.services.workflow.workflow_trigger_service import trigger_lead_stage_changed

                    trigger_lead_stage_changed(
                        db,
                        int(business_id),
                        lead_id=int(lead.id),
                        old_stage_id=old_stage_id,
                        new_stage_id=new_sid,
                        user_id=int(uid) if uid else None,
                    )
                except Exception:
                    pass
        aid = WorkflowEngine._resolve_value_static(config.get("assigned_to_user_id"), context, node_results)
        if aid is not None:
            new_assign = int(aid) if aid else None
            if new_assign != old_assigned_to_user_id:
                lead.assigned_to_user_id = new_assign
                db.flush()
                try:
                    from app.services.workflow.workflow_trigger_service import trigger_lead_assigned

                    trigger_lead_assigned(
                        db,
                        int(business_id),
                        lead_id=int(lead.id),
                        old_assigned_to_user_id=old_assigned_to_user_id,
                        new_assigned_to_user_id=new_assign,
                        user_id=int(uid) if uid else None,
                    )
                except Exception:
                    pass
        nfu = WorkflowEngine._resolve_value_static(config.get("next_follow_up_at"), context, node_results)
        if nfu:
            try:
                lead.next_follow_up_at = datetime.fromisoformat(str(nfu).replace("Z", "+00:00"))
            except Exception:
                pass
        nm = WorkflowEngine._resolve_value_static(config.get("name"), context, node_results)
        if nm is not None:
            lead.name = str(nm).strip()[:255]
        sc = WorkflowEngine._resolve_value_static(config.get("source_code"), context, node_results)
        if sc is not None:
            lead.source_code = str(sc) if sc else None
        db.flush()
        db.refresh(lead)
        return {"success": True, "lead_id": lead.id}


class UpdateDealAction(ActionHandler):
    """به‌روزرسانی فرصت فروش از ورک‌فلو"""

    def get_metadata(self) -> Dict[str, Any]:
        return {
            "name": "به‌روزرسانی فرصت فروش",
            "description": "تغییر مرحله، مسئول، مبلغ، احتمال، سند مرتبط",
            "config_schema": {
                "deal_id": {"type": "integer", "required": True},
                "stage_id": {"type": "integer", "required": False},
                "assigned_to_user_id": {"type": "integer", "required": False},
                "amount": {"type": "number", "required": False},
                "probability_percent": {"type": "integer", "required": False},
                "document_id": {"type": "integer", "required": False},
                "title": {"type": "string", "required": False},
                "closed_at": {
                    "type": "string",
                    "description": "تاریخ بستن معامله (ISO). در صورت ارسال، تریگر crm.deal.closed شلیک می‌شود.",
                    "required": False,
                },
            },
        }

    @log_action_execution
    def execute(
        self,
        context: Dict[str, Any],
        config: Dict[str, Any],
        node_results: Dict[str, Any],
    ) -> Dict[str, Any]:
        from app.services.workflow.dry_run import dry_run_skip
        from app.services.workflow.workflow_engine import WorkflowEngine
        from adapters.db.models.crm import Deal, CrmProcessStage

        sk = dry_run_skip(context, "به‌روزرسانی فرصت فروش")
        if sk is not None:
            return sk

        db = context.get("db")
        business_id = context.get("business_id")
        if not db or business_id is None:
            return {"success": False, "error": "db or business_id missing in context"}
        deal_id = WorkflowEngine._resolve_value_static(config.get("deal_id"), context, node_results)
        if not deal_id:
            return {"success": False, "error": "deal_id is required"}
        deal = db.query(Deal).filter(Deal.id == int(deal_id), Deal.business_id == business_id).first()
        if not deal:
            return {"success": False, "error": "deal not found"}
        old_stage_id = int(deal.stage_id)
        old_assigned_to_user_id = deal.assigned_to_user_id
        uid = context.get("user_id")
        if not uid:
            from adapters.db.models.business import Business

            biz = db.query(Business).filter(Business.id == business_id).first()
            uid = biz.owner_id if biz else None

        sid = WorkflowEngine._resolve_value_static(config.get("stage_id"), context, node_results)
        if sid is not None:
            new_sid = int(sid)
            st = (
                db.query(CrmProcessStage)
                .filter(
                    CrmProcessStage.id == new_sid,
                    CrmProcessStage.process_definition_id == deal.process_definition_id,
                )
                .first()
            )
            if not st:
                return {"success": False, "error": "invalid stage_id"}
            if new_sid != old_stage_id:
                deal.stage_id = new_sid
                db.flush()
                try:
                    from app.services.workflow.workflow_trigger_service import trigger_deal_stage_changed

                    trigger_deal_stage_changed(
                        db,
                        int(business_id),
                        deal_id=int(deal.id),
                        old_stage_id=old_stage_id,
                        new_stage_id=new_sid,
                        user_id=int(uid) if uid else None,
                    )
                except Exception:
                    pass
        aid = WorkflowEngine._resolve_value_static(config.get("assigned_to_user_id"), context, node_results)
        if aid is not None:
            new_assign = int(aid) if aid else None
            if new_assign != old_assigned_to_user_id:
                deal.assigned_to_user_id = new_assign
                db.flush()
                try:
                    from app.services.workflow.workflow_trigger_service import trigger_deal_assigned

                    trigger_deal_assigned(
                        db,
                        int(business_id),
                        deal_id=int(deal.id),
                        old_assigned_to_user_id=old_assigned_to_user_id,
                        new_assigned_to_user_id=new_assign,
                        user_id=int(uid) if uid else None,
                    )
                except Exception:
                    pass
        amt = WorkflowEngine._resolve_value_static(config.get("amount"), context, node_results)
        if amt is not None:
            deal.amount = float(amt)
        pr = WorkflowEngine._resolve_value_static(config.get("probability_percent"), context, node_results)
        if pr is not None:
            deal.probability_percent = int(pr) if pr is not None else None
        doc = WorkflowEngine._resolve_value_static(config.get("document_id"), context, node_results)
        if doc is not None:
            deal.document_id = int(doc) if doc else None
        ttl = WorkflowEngine._resolve_value_static(config.get("title"), context, node_results)
        if ttl is not None:
            deal.title = str(ttl).strip()[:255]

        closed_raw = WorkflowEngine._resolve_value_static(config.get("closed_at"), context, node_results)
        if closed_raw is not None and str(closed_raw).strip():
            try:
                deal.closed_at = datetime.fromisoformat(str(closed_raw).replace("Z", "+00:00"))
            except Exception:
                return {"success": False, "error": "invalid closed_at (use ISO datetime)"}
            db.flush()
            stg = (
                db.query(CrmProcessStage)
                .filter(
                    CrmProcessStage.id == deal.stage_id,
                    CrmProcessStage.process_definition_id == deal.process_definition_id,
                )
                .first()
            )
            is_win = bool(stg and stg.is_win)
            is_lost = bool(stg and stg.is_lost)
            try:
                from app.services.workflow.workflow_trigger_service import trigger_deal_closed

                trigger_deal_closed(
                    db,
                    int(business_id),
                    deal_id=int(deal.id),
                    amount=float(deal.amount),
                    is_win=is_win,
                    document_id=deal.document_id,
                    user_id=int(uid) if uid else None,
                    is_lost=is_lost,
                )
            except Exception:
                pass

        db.flush()
        db.refresh(deal)
        return {"success": True, "deal_id": deal.id}


class CrmLinkDealDocumentAction(ActionHandler):
    """اتصال سند حسابداری به فرصت فروش (مثلاً پس از صدور فاکتور)"""

    def get_metadata(self) -> Dict[str, Any]:
        return {
            "name": "لینک سند به فرصت فروش",
            "description": "تنظیم document_id روی یک فرصت فروش",
            "config_schema": {
                "deal_id": {"type": "integer", "required": True},
                "document_id": {"type": "integer", "required": True},
            },
        }

    @log_action_execution
    def execute(
        self,
        context: Dict[str, Any],
        config: Dict[str, Any],
        node_results: Dict[str, Any],
    ) -> Dict[str, Any]:
        from app.services.workflow.dry_run import dry_run_skip
        from app.services.workflow.workflow_engine import WorkflowEngine
        from adapters.db.models.crm import Deal

        sk = dry_run_skip(context, "لینک سند به فرصت")
        if sk is not None:
            return sk

        db = context.get("db")
        business_id = context.get("business_id")
        if not db or business_id is None:
            return {"success": False, "error": "db or business_id missing in context"}
        deal_id = WorkflowEngine._resolve_value_static(config.get("deal_id"), context, node_results)
        document_id = WorkflowEngine._resolve_value_static(config.get("document_id"), context, node_results)
        if not deal_id or not document_id:
            return {"success": False, "error": "deal_id and document_id are required"}
        deal = db.query(Deal).filter(Deal.id == int(deal_id), Deal.business_id == business_id).first()
        if not deal:
            return {"success": False, "error": "deal not found"}
        deal.document_id = int(document_id)
        db.flush()
        return {"success": True, "deal_id": deal.id, "document_id": int(document_id)}


class CrmWebChatSendMessageAction(ActionHandler):
    """ارسال پیام عامل در چت وب CRM (همان کانال پنل / ویجت)."""

    def get_metadata(self) -> Dict[str, Any]:
        return {
            "name": "ارسال پیام در چت وب CRM",
            "description": (
                "پیام متنی (یا فایل پیوست‌شده) را به عنوان عامل در همان مکالمه چت وب ارسال می‌کند؛ "
                "بازدیدکننده در ویجت آن را فوراً می‌بیند. پیش‌فرض: بدون شلیک ورک‌فلو روی «پاسخ عامل» تا از حلقه جلوگیری شود."
            ),
            "config_schema": {
                "conversation_id": {
                    "type": "integer",
                    "description": "شناسه مکالمه (مثلاً از نود تریگر: $trigger_node.conversation_id)",
                    "required": True,
                },
                "body": {
                    "type": "string",
                    "description": "متن پیام (برای پیام فقط‌فایل می‌تواند خالی باشد اگر file_storage_id باشد)",
                    "required": False,
                },
                "file_storage_id": {
                    "type": "string",
                    "description": "شناسه فایل پیوست (اختیاری، همان فضای فایل کسب‌وکار)",
                    "required": False,
                },
                "agent_user_id": {
                    "type": "integer",
                    "description": "کاربر ارسال‌کننده در سیستم؛ اگر خالی باشد از اجراکننده ورک‌فلو یا مالک کسب‌وکار استفاده می‌شود",
                    "required": False,
                },
                "fire_message_sent_workflow_trigger": {
                    "type": "boolean",
                    "description": "در صورت true تریگر crm.chat.message.sent هم اجرا می‌شود (احتیاط: حلقه ورک‌فلو)",
                    "default": False,
                    "required": False,
                },
                "mark_as_workflow_automation": {
                    "type": "boolean",
                    "description": "اگر fire_message_sent_workflow_trigger فعال باشد، automation_source=workflow به payload تریگر اضافه می‌شود",
                    "default": True,
                    "required": False,
                },
            },
        }

    @log_action_execution
    def execute(
        self,
        context: Dict[str, Any],
        config: Dict[str, Any],
        node_results: Dict[str, Any],
    ) -> Dict[str, Any]:
        from app.services.workflow.dry_run import dry_run_skip
        from app.services.workflow.workflow_engine import WorkflowEngine
        from app.services import crm_chat_service as chat_svc
        from app.services.async_isolated import run_coroutine_isolated
        from app.core.responses import ApiError
        from adapters.db.models.business import Business

        sk = dry_run_skip(context, "ارسال پیام چت وب CRM")
        if sk is not None:
            return sk

        db = context.get("db")
        business_id = context.get("business_id")
        if not db or business_id is None:
            return {"success": False, "error": "db or business_id missing in context"}

        conversation_id = WorkflowEngine._resolve_value_static(config.get("conversation_id"), context, node_results)
        if conversation_id is None:
            return {"success": False, "error": "conversation_id is required"}
        body_raw = WorkflowEngine._resolve_value_static(config.get("body"), context, node_results)
        body: Optional[str] = str(body_raw).strip() if body_raw is not None else None
        if body == "":
            body = None
        file_storage_id = WorkflowEngine._resolve_value_static(config.get("file_storage_id"), context, node_results)
        if file_storage_id is not None:
            file_storage_id = str(file_storage_id).strip() or None

        if not body and not file_storage_id:
            return {"success": False, "error": "body or file_storage_id is required"}

        agent_uid = WorkflowEngine._resolve_value_static(config.get("agent_user_id"), context, node_results)
        if agent_uid is not None:
            agent_uid = int(agent_uid)
        else:
            uid = context.get("user_id")
            if uid:
                agent_uid = int(uid)
            else:
                biz = db.query(Business).filter(Business.id == business_id).first()
                agent_uid = int(biz.owner_id) if biz and biz.owner_id else None
        if not agent_uid:
            return {"success": False, "error": "agent_user_id or business owner required"}

        fire_sent = bool(config.get("fire_message_sent_workflow_trigger", False))
        mark_auto = bool(config.get("mark_as_workflow_automation", True))
        automation_context: Optional[Dict[str, Any]] = None
        if fire_sent and mark_auto:
            automation_context = {
                "automation_source": "workflow",
                "workflow_id": context.get("workflow_id"),
                "workflow_execution_id": context.get("execution_id"),
            }

        async def _run() -> Dict[str, Any]:
            return await chat_svc.post_agent_message(
                db,
                business_id=int(business_id),
                conversation_id=int(conversation_id),
                body=body,
                user_id=int(agent_uid),
                file_storage_id=file_storage_id,
                fire_workflow_trigger_message_sent=fire_sent,
                automation_context=automation_context,
            )

        try:
            msg = run_coroutine_isolated(lambda: _run())
        except ApiError as e:
            detail = e.detail
            if isinstance(detail, dict):
                err = detail.get("error")
                if isinstance(err, dict):
                    return {"success": False, "error": err.get("message", str(err)), "code": err.get("code")}
            return {"success": False, "error": str(detail)}
        except Exception as ex:
            return {"success": False, "error": str(ex)}

        return {
            "success": True,
            "message": msg,
            "message_id": msg.get("id"),
            "conversation_id": int(conversation_id),
        }
