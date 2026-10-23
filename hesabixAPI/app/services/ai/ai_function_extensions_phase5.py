"""
ثبت functionهای فاز ۵ AI — writeهای تکمیلی، CRM، workflow، export.
"""
from __future__ import annotations

import base64
from datetime import date, datetime
from typing import Any, Dict, List, TYPE_CHECKING

from app.services.ai.function_registry import AIRole, AIFunction

if TYPE_CHECKING:
    from app.services.ai.function_registry import AIFunctionRegistry

_EXPORT_TYPES = [
    "persons",
    "invoices",
    "products",
    "expense_income",
    "documents",
    "checks",
]

_MAX_EXPORT_ROWS = 10_000


def register_phase5_business_functions(registry: "AIFunctionRegistry") -> None:
    from app.services.ai.ai_tool_payloads import (
        CREATE_EXPENSE_INCOME_DESCRIPTION,
        CREATE_EXPENSE_INCOME_PARAMETERS_SCHEMA,
        build_create_expense_income_payload,
    )

    # --- expense / income ---
    def create_expense_income_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from app.services.expense_income_service import create_expense_income

        db = context["db"]
        business_id = int(args.get("business_id") or context.get("business_id"))
        user_id = context["user_context"].get_user_id()
        body = build_create_expense_income_payload(
            args, db=db, business_id=business_id
        )
        return create_expense_income(db, business_id, user_id, body)

    registry.register(
        AIFunction(
            name="create_expense_income",
            description=CREATE_EXPENSE_INCOME_DESCRIPTION,
            parameters_schema=CREATE_EXPENSE_INCOME_PARAMETERS_SCHEMA,
            handler=create_expense_income_handler,
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["expenses_income.write"],
            category="financial",
            requires_approval=True,
            risk_level="high",
            is_readonly=False,
        )
    )

    # --- invoice update / delete ---
    def update_invoice_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from app.services.ai.ai_tool_payloads import build_update_invoice_payload
        from app.services.invoice_service import update_invoice

        db = context["db"]
        user_id = context["user_context"].get_user_id()
        invoice_id = int(args["invoice_id"])
        data = build_update_invoice_payload(args, db=db, invoice_id=invoice_id)
        return update_invoice(db, invoice_id, user_id, data)

    from app.services.ai.ai_tool_payloads import (
        UPDATE_INVOICE_DESCRIPTION,
        UPDATE_INVOICE_PARAMETERS_SCHEMA,
    )

    registry.register(
        AIFunction(
            name="update_invoice",
            description=UPDATE_INVOICE_DESCRIPTION,
            parameters_schema=UPDATE_INVOICE_PARAMETERS_SCHEMA,
            handler=update_invoice_handler,
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["invoices.write"],
            category="invoices",
            requires_approval=True,
            risk_level="high",
            is_readonly=False,
        )
    )

    def delete_invoice_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from app.services.invoice_service import delete_invoice

        db = context["db"]
        invoice_id = int(args["invoice_id"])
        ok = delete_invoice(db, invoice_id)
        return {"deleted": ok, "invoice_id": invoice_id}

    registry.register(
        AIFunction(
            name="delete_invoice",
            description="حذف فاکتور (سند). عملیات برگشت‌ناپذیر — نیاز به تأیید.",
            parameters_schema={
                "type": "object",
                "properties": {"invoice_id": {"type": "integer"}},
                "required": ["invoice_id"],
            },
            handler=delete_invoice_handler,
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["invoices.write"],
            category="invoices",
            requires_approval=True,
            risk_level="high",
            is_readonly=False,
        )
    )

    # --- Tax workspace (Moadian) ---
    def _get_tax_invoice(context: Dict[str, Any], invoice_id: Any):
        from adapters.db.models.document import Document
        from app.core.moadian_plugin_dependency import ensure_moadian_plugin_active

        business_id = int(context["business_id"])
        ensure_moadian_plugin_active(context["db"], business_id)
        try:
            document_id = int(invoice_id)
        except (TypeError, ValueError) as exc:
            raise ValueError("invoice_id باید شناسهٔ عددی باشد") from exc
        doc = context["db"].query(Document).filter(
            Document.id == document_id,
            Document.business_id == business_id,
        ).with_for_update().first()
        if not doc or doc.document_type not in {"invoice_sales", "invoice_sales_return"}:
            raise ValueError("فاکتور فروش در کسب‌وکار متصل پیدا نشد")
        if bool(getattr(doc, "is_proforma", False)):
            raise ValueError("پیش‌فاکتور را نمی‌توان به کارپوشهٔ مالیاتی افزود")
        return doc

    def add_invoice_to_tax_workspace_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from app.services.tax_reference_service import link_reference_invoice

        db = context["db"]
        business_id = int(context["business_id"])
        doc = _get_tax_invoice(context, args["invoice_id"])
        extra = dict(doc.extra_info or {})
        reference_id = args.get("reference_invoice_id")
        if doc.document_type == "invoice_sales_return" and not reference_id:
            raise ValueError("برای برگشت از فروش reference_invoice_id الزامی است")
        if reference_id is not None:
            linked = link_reference_invoice(db, business_id, doc, int(reference_id))
            extra = dict(doc.extra_info or {})
        else:
            linked = None
        extra["tax_workspace"] = True
        if not isinstance(extra.get("tax_status"), str) or not extra["tax_status"].strip():
            extra["tax_status"] = "not_sent"
        doc.extra_info = extra
        db.add(doc)
        db.flush()
        return {
            "invoice_id": doc.id,
            "tax_workspace": True,
            "tax_status": extra.get("tax_status"),
            "reference_invoice_id": extra.get("reference_invoice_id"),
            "reference_invoice_code": getattr(linked, "code", None),
        }

    registry.register(AIFunction(
        name="add_invoice_to_tax_workspace",
        description="افزودن فاکتور فروش یا برگشت فروش به کارپوشهٔ مالیاتی. برای برگشت، فاکتور فروش مرجع را با شناسهٔ جستجو‌شده مشخص کن.",
        parameters_schema={
            "type": "object",
            "properties": {
                "invoice_id": {"type": "integer", "minimum": 1},
                "reference_invoice_id": {"type": "integer", "minimum": 1},
            },
            "required": ["invoice_id"],
        },
        handler=add_invoice_to_tax_workspace_handler,
        allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
        required_permissions=["invoices.write"], category="tax",
        requires_approval=True, risk_level="medium", is_readonly=False,
    ))

    def remove_invoice_from_tax_workspace_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        doc = _get_tax_invoice(context, args["invoice_id"])
        extra = dict(doc.extra_info or {})
        status = extra.get("tax_status")
        if status in {"sent", "finalized"}:
            raise ValueError("فاکتور ارسال‌شده یا نهایی‌شده را نمی‌توان از کارپوشه حذف کرد")
        extra["tax_workspace"] = False
        extra["tax_status"] = status or "not_in_workspace"
        doc.extra_info = extra
        context["db"].add(doc)
        context["db"].flush()
        return {"invoice_id": doc.id, "tax_workspace": False, "tax_status": extra["tax_status"]}

    registry.register(AIFunction(
        name="remove_invoice_from_tax_workspace",
        description="حذف فاکتور فروش از کارپوشهٔ مالیاتی؛ فاکتور ارسال‌شده یا نهایی‌شده قابل حذف نیست. نیازمند تأیید است.",
        parameters_schema={"type": "object", "properties": {"invoice_id": {"type": "integer", "minimum": 1}}, "required": ["invoice_id"]},
        handler=remove_invoice_from_tax_workspace_handler,
        allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
        required_permissions=["invoices.write"], category="tax",
        requires_approval=True, risk_level="medium", is_readonly=False,
    ))

    def send_invoice_to_tax_system_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from app.services.tax_submission_service import send_document_to_tax_system, normalize_stored_tax_status, build_tax_failure_details

        db = context["db"]
        doc = _get_tax_invoice(context, args["invoice_id"])
        extra = dict(doc.extra_info or {})
        if not extra.get("tax_workspace"):
            raise ValueError("فاکتور ابتدا باید به کارپوشهٔ مالیاتی افزوده شود")
        status = extra.get("tax_status")
        if status in {"sent", "finalized"} or (
            normalize_stored_tax_status(extra) in {"sent", "finalized", "pending"} and extra.get("tax_tracking_code")
        ):
            raise ValueError("این فاکتور قبلاً ارسال شده است")
        if extra.get("tax_cancelled_in_modian"):
            raise ValueError("فاکتور در سامانهٔ مالیاتی ابطال شده و ارسال مجدد مجاز نیست")
        result = send_document_to_tax_system(db, doc)
        db.flush()
        after = dict(doc.extra_info or {})
        failed = after.get("tax_status") == "failed" or result.get("status") == "failed"
        return {
            "invoice_id": doc.id,
            "tax_status": after.get("tax_status"),
            "tax_tracking_code": after.get("tax_tracking_code"),
            "accepted": not failed,
            "error_message": result.get("error_message") or after.get("tax_error_message") if failed else None,
            "failure_details": build_tax_failure_details(after, result) if failed else None,
        }

    registry.register(AIFunction(
        name="send_invoice_to_tax_system",
        description="ارسال فاکتورِ موجود در کارپوشه به سامانهٔ مالیاتی. ارسال خارجی است، تکرار ارسال کنترل می‌شود و نتیجهٔ پذیرش/خطا برمی‌گردد؛ نیازمند تأیید صریح است.",
        parameters_schema={"type": "object", "properties": {"invoice_id": {"type": "integer", "minimum": 1}}, "required": ["invoice_id"]},
        handler=send_invoice_to_tax_system_handler,
        allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
        required_permissions=["invoices.write"], category="tax",
        requires_approval=True, risk_level="high", is_readonly=False,
    ))

    def cancel_invoice_in_tax_system_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from app.services.tax_reference_service import can_cancel_in_modian
        from app.services.tax_submission_service import cancel_document_in_tax_system, build_tax_status_fields_for_api

        db = context["db"]
        doc = _get_tax_invoice(context, args["invoice_id"])
        allowed, reason = can_cancel_in_modian(doc)
        if not allowed:
            raise ValueError(reason or "ابطال در وضعیت فعلی مجاز نیست")
        result = cancel_document_in_tax_system(db, doc)
        db.flush()
        extra = dict(doc.extra_info or {})
        return {
            "invoice_id": doc.id,
            "tax_status": extra.get("tax_status"),
            "tax_tracking_code": extra.get("tax_tracking_code"),
            "tax_cancelled_in_modian": bool(extra.get("tax_cancelled_in_modian")),
            "accepted": result.get("status") != "failed",
            "error_message": result.get("error_message"),
            **build_tax_status_fields_for_api(extra),
        }

    registry.register(AIFunction(
        name="cancel_invoice_in_tax_system",
        description="ارسال ابطال برای فاکتور ارسال‌شده به سامانهٔ مالیاتی. اثر بیرونی و برگشت‌ناپذیر؛ ابتدا جزئیات و وضعیت را بررسی و تأیید بگیر.",
        parameters_schema={"type": "object", "properties": {"invoice_id": {"type": "integer", "minimum": 1}}, "required": ["invoice_id"]},
        handler=cancel_invoice_in_tax_system_handler,
        allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
        required_permissions=["invoices.write"], category="tax",
        requires_approval=True, risk_level="high", is_readonly=False,
    ))

    def send_corrective_invoice_to_tax_system_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from app.services.tax_reference_service import can_send_corrective
        from app.services.tax_submission_service import send_corrective_to_tax_system, build_tax_status_fields_for_api

        db = context["db"]
        doc = _get_tax_invoice(context, args["invoice_id"])
        allowed, reason = can_send_corrective(doc)
        if not allowed:
            raise ValueError(reason or "ارسال اصلاحی در وضعیت فعلی مجاز نیست")
        result = send_corrective_to_tax_system(db, doc)
        db.flush()
        extra = dict(doc.extra_info or {})
        return {
            "invoice_id": doc.id,
            "tax_status": extra.get("tax_status"),
            "tax_tracking_code": extra.get("tax_tracking_code"),
            "accepted": result.get("status") != "failed",
            "error_message": result.get("error_message"),
            **build_tax_status_fields_for_api(extra),
        }

    registry.register(AIFunction(
        name="send_corrective_invoice_to_tax_system",
        description="ارسال صورتحساب اصلاحی برای فاکتور مالیاتی مجاز. اثر بیرونی؛ قبل از اجرا داده و فاکتور مرجع را بررسی و تأیید بگیر.",
        parameters_schema={"type": "object", "properties": {"invoice_id": {"type": "integer", "minimum": 1}}, "required": ["invoice_id"]},
        handler=send_corrective_invoice_to_tax_system_handler,
        allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
        required_permissions=["invoices.write"], category="tax",
        requires_approval=True, risk_level="high", is_readonly=False,
    ))

    def get_invoice_tax_status_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from app.services.tax_submission_service import build_tax_status_fields_for_api
        doc = _get_tax_invoice(context, args["invoice_id"])
        extra = dict(doc.extra_info or {})
        return {
            "invoice_id": doc.id,
            "invoice_code": doc.code,
            "document_type": doc.document_type,
            "tax_workspace": bool(extra.get("tax_workspace")),
            "tax_status": extra.get("tax_status"),
            "tax_tracking_code": extra.get("tax_tracking_code"),
            "tax_last_send_at": extra.get("tax_last_send_at"),
            "tax_last_inquiry_at": extra.get("tax_last_inquiry_at"),
            "tax_error_message": extra.get("tax_error_message"),
            "tax_cancelled_in_modian": bool(extra.get("tax_cancelled_in_modian")),
            **build_tax_status_fields_for_api(extra),
        }

    registry.register(AIFunction(
        name="get_invoice_tax_status",
        description="وضعیت فعلی فاکتور در کارپوشه و اطلاعات رهگیری مالیاتی را بخوان؛ این ابزار استعلام زنده انجام نمی‌دهد.",
        parameters_schema={"type": "object", "properties": {"invoice_id": {"type": "integer", "minimum": 1}}, "required": ["invoice_id"]},
        handler=get_invoice_tax_status_handler,
        allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
        required_permissions=["invoices.read"], category="tax",
    ))

    def validate_invoice_for_tax_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from adapters.db.models.tax_setting import TaxSetting
        from app.services.tax_validation_service import validate_document_for_tax, validate_tax_submission_scenario

        db = context["db"]
        business_id = int(context["business_id"])
        doc = _get_tax_invoice(context, args["invoice_id"])
        setting = db.query(TaxSetting).filter(TaxSetting.business_id == business_id).first()
        if not setting:
            raise ValueError("تنظیمات مالیاتی کسب‌وکار ثبت نشده است")
        basic = validate_document_for_tax(db, doc)
        scenario = validate_tax_submission_scenario(
            db, doc, setting, "return" if doc.document_type == "invoice_sales_return" else "normal"
        )
        issues = list(basic.get("issues") or []) + list(scenario.get("issues") or [])
        return {"invoice_id": doc.id, "valid": bool(basic.get("valid")) and bool(scenario.get("valid")), "issues": issues}

    registry.register(AIFunction(
        name="validate_invoice_for_tax",
        description="اعتبارسنجی داده و سناریوی فروش/برگشت پیش از ارسال مالیاتی؛ هیچ ارسال یا تغییری انجام نمی‌دهد.",
        parameters_schema={"type": "object", "properties": {"invoice_id": {"type": "integer", "minimum": 1}}, "required": ["invoice_id"]},
        handler=validate_invoice_for_tax_handler,
        allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
        required_permissions=["invoices.read"], category="tax",
    ))

    def inquire_invoice_tax_status_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from adapters.db.models.document import Document
        from app.services.tax_submission_service import inquire_tax_status

        db = context["db"]
        business_id = int(context["business_id"])
        raw_ids = args["invoice_ids"]
        if len(raw_ids) > 50:
            raise ValueError("در هر استعلام حداکثر ۵۰ فاکتور بفرست")
        ids = list(dict.fromkeys(int(value) for value in raw_ids))
        documents = db.query(Document).filter(
            Document.business_id == business_id,
            Document.id.in_(ids),
            Document.document_type.in_(["invoice_sales", "invoice_sales_return"]),
        ).all()
        if len(documents) != len(ids):
            raise ValueError("یک یا چند فاکتور فروش در کسب‌وکار متصل پیدا نشد")
        result = inquire_tax_status(db, business_id, invoice_ids=ids)
        return result

    registry.register(AIFunction(
        name="inquire_invoice_tax_status",
        description="استعلام زندهٔ وضعیت مالیاتی حداکثر ۵۰ فاکتور متعلق به همین کسب‌وکار؛ دادهٔ رهگیری را در سامانه به‌روز می‌کند. نیازمند مجوز عملیات مالیاتی و تأیید است.",
        parameters_schema={
            "type": "object", "properties": {"invoice_ids": {"type": "array", "minItems": 1, "maxItems": 50, "items": {"type": "integer", "minimum": 1}}},
            "required": ["invoice_ids"],
        },
        handler=inquire_invoice_tax_status_handler,
        allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
        required_permissions=["moadian.operate"], category="tax",
        requires_approval=True, risk_level="medium", is_readonly=False,
    ))

    # --- CRM lead ---
    def create_lead_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from datetime import date as date_cls

        from adapters.db.models.crm import CrmProcessDefinition, CrmProcessStage, Lead
        from app.services.document_numbering_service import generate_document_code

        db = context["db"]
        business_id = int(args.get("business_id") or context.get("business_id"))
        user_id = context["user_context"].get_user_id()
        process_id = int(args["process_definition_id"])
        stage_id = int(args["stage_id"])

        proc = (
            db.query(CrmProcessDefinition)
            .filter(
                CrmProcessDefinition.id == process_id,
                CrmProcessDefinition.business_id == business_id,
            )
            .first()
        )
        if not proc:
            raise ValueError("فرایند CRM یافت نشد")
        stage = (
            db.query(CrmProcessStage)
            .filter(
                CrmProcessStage.id == stage_id,
                CrmProcessStage.process_definition_id == process_id,
            )
            .first()
        )
        if not stage:
            raise ValueError("مرحله CRM یافت نشد")

        code_val = args.get("code")
        if code_val and str(code_val).strip():
            code_val = str(code_val).strip()
        else:
            code_val = generate_document_code(db, business_id, "crm_lead", date_cls.today())

        lead = Lead(
            business_id=business_id,
            process_definition_id=process_id,
            stage_id=stage_id,
            code=code_val,
            source_code=args.get("source_code"),
            name=args["name"],
            company_name=args.get("company_name"),
            mobile=args.get("mobile"),
            email=args.get("email"),
            description=args.get("description"),
            assigned_to_user_id=args.get("assigned_to_user_id"),
            created_by_user_id=user_id,
        )
        db.add(lead)
        db.commit()
        db.refresh(lead)
        try:
            from app.services.workflow.workflow_trigger_service import trigger_lead_created

            trigger_lead_created(
                db,
                business_id,
                lead_id=lead.id,
                process_definition_id=lead.process_definition_id,
                stage_id=lead.stage_id,
                name=lead.name,
                user_id=user_id,
            )
        except Exception:
            pass
        return {
            "id": lead.id,
            "code": lead.code,
            "name": lead.name,
            "stage_id": lead.stage_id,
            "process_definition_id": lead.process_definition_id,
        }

    registry.register(
        AIFunction(
            name="create_lead",
            description=(
                "ایجاد سرنخ CRM. process_definition_id و stage_id را از قیف/pipeline بگیر. "
                "name الزامی است. نیاز به تأیید."
            ),
            parameters_schema={
                "type": "object",
                "properties": {
                    "process_definition_id": {
                        "type": "integer",
                        "description": "شناسه تعریف قیف/فرآیند CRM",
                    },
                    "stage_id": {"type": "integer", "description": "شناسه مرحله قیف"},
                    "name": {"type": "string", "description": "نام سرنخ"},
                    "code": {"type": "string", "description": "کد سرنخ (اختیاری)"},
                    "source_code": {"type": "string", "description": "کد منبع جذب (اختیاری)"},
                    "company_name": {"type": "string", "description": "نام شرکت (اختیاری)"},
                    "mobile": {"type": "string", "description": "موبایل (اختیاری)"},
                    "email": {"type": "string", "format": "email", "description": "ایمیل (اختیاری)"},
                    "description": {"type": "string", "description": "توضیحات (اختیاری)"},
                    "assigned_to_user_id": {
                        "type": "integer",
                        "description": "شناسه کاربر مسئول (اختیاری)",
                    },
                },
                "required": ["process_definition_id", "stage_id", "name"],
            },
            handler=create_lead_handler,
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["crm.write"],
            category="crm",
            requires_approval=True,
            risk_level="medium",
            is_readonly=False,
        )
    )

    # --- workflow execute ---
    def execute_workflow_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from adapters.db.models.workflow import Workflow, WorkflowStatus
        from app.services.workflow.workflow_engine import WorkflowEngine

        db = context["db"]
        business_id = int(args.get("business_id") or context.get("business_id"))
        user_id = context["user_context"].get_user_id()
        workflow_id = int(args["workflow_id"])
        trigger_data = args.get("trigger_data") or {}
        if not isinstance(trigger_data, dict):
            trigger_data = {}
        dry_run = bool(args.get("dry_run", False))
        if dry_run:
            from app.services.workflow.dry_run import DRY_RUN_TRIGGER_KEY

            trigger_data = {**trigger_data, DRY_RUN_TRIGGER_KEY: True}

        workflow = db.get(Workflow, workflow_id)
        if not workflow or workflow.business_id != business_id:
            raise ValueError("Workflow یافت نشد")
        if workflow.status != WorkflowStatus.ACTIVE:
            raise ValueError("Workflow فعال نیست")

        engine = WorkflowEngine(db, business_id, user_id)
        execution = engine.execute_workflow(workflow, trigger_data)
        return {
            "execution_id": execution.id,
            "workflow_id": workflow_id,
            "status": getattr(execution.status, "value", str(execution.status)),
            "dry_run": dry_run,
        }

    registry.register(
        AIFunction(
            name="execute_workflow",
            description="اجرای دستی یک workflow فعال. trigger_data اختیاری. dry_run برای آزمایش.",
            parameters_schema={
                "type": "object",
                "properties": {
                    "workflow_id": {"type": "integer"},
                    "trigger_data": {"type": "object"},
                    "dry_run": {"type": "boolean"},
                },
                "required": ["workflow_id"],
            },
            handler=execute_workflow_handler,
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["workflows.write"],
            category="workflow",
            requires_approval=True,
            risk_level="high",
            is_readonly=False,
        )
    )

    # --- export ---
    def export_business_data_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from app.services.ai.ai_export_service import export_business_file

        db = context["db"]
        business_id = int(args.get("business_id") or context.get("business_id"))
        export_type = str(args.get("export_type", "")).strip().lower()
        fmt = str(args.get("format", "excel")).strip().lower()
        if export_type not in _EXPORT_TYPES:
            raise ValueError(f"export_type نامعتبر. مجاز: {', '.join(_EXPORT_TYPES)}")
        if fmt not in ("excel", "xlsx", "pdf"):
            raise ValueError("format باید excel یا pdf باشد")
        if export_type == "checks":
            raise ValueError("export checks از AI هنوز پشتیبانی نمی‌شود؛ از search_checks استفاده کنید")

        filters = dict(args.get("filters") or {})
        file_bytes, filename, mime = export_business_file(
            db, business_id, export_type, fmt, filters
        )

        if len(file_bytes) > 8 * 1024 * 1024:
            return {
                "error": "EXPORT_TOO_LARGE",
                "message": "حجم فایل بیش از ۸ مگابایت است. فیلترها را محدود کنید.",
                "size_bytes": len(file_bytes),
            }

        return {
            "filename": filename,
            "mime_type": mime,
            "size_bytes": len(file_bytes),
            "content_base64": base64.b64encode(file_bytes).decode("ascii"),
            "export_type": export_type,
            "format": fmt,
        }

    registry.register(
        AIFunction(
            name="export_business_data",
            description=(
                "خروجی Excel/PDF داده‌های کسب‌وکار. "
                f"export_type: {', '.join(_EXPORT_TYPES)}. "
                "format: excel یا pdf. نتیجه شامل content_base64 برای دانلود."
            ),
            parameters_schema={
                "type": "object",
                "properties": {
                    "export_type": {"type": "string", "enum": _EXPORT_TYPES},
                    "format": {"type": "string", "enum": ["excel", "pdf"]},
                    "filters": {
                        "type": "object",
                        "description": "from_date, to_date, search, document_type, ...",
                    },
                },
                "required": ["export_type"],
            },
            handler=export_business_data_handler,
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["reports.read"],
            category="export",
            requires_approval=True,
            risk_level="medium",
            is_readonly=False,
        )
    )
