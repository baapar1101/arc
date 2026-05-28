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
    # --- expense / income ---
    def create_expense_income_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from app.services.expense_income_service import create_expense_income

        db = context["db"]
        business_id = int(args.get("business_id") or context.get("business_id"))
        user_id = context["user_context"].get_user_id()
        amount = float(args["amount"])
        doc_date = args.get("document_date") or date.today().isoformat()
        cp_type = str(args.get("counterparty_type", "bank"))
        cp_id = int(args["counterparty_id"])
        tx_date = args.get("transaction_date") or f"{doc_date}T12:00:00"

        counterparty_line: Dict[str, Any] = {
            "transaction_type": cp_type,
            "amount": amount,
            "transaction_date": tx_date,
            "description": args.get("description"),
        }
        if cp_type == "bank":
            counterparty_line["bank_id"] = cp_id
        elif cp_type == "cash_register":
            counterparty_line["cash_register_id"] = cp_id
        elif cp_type == "petty_cash":
            counterparty_line["petty_cash_id"] = cp_id
        elif cp_type == "person":
            counterparty_line["person_id"] = cp_id
        else:
            raise ValueError("counterparty_type نامعتبر")

        body = {
            "document_type": args.get("document_type", "expense"),
            "document_date": doc_date,
            "currency_id": int(args["currency_id"]),
            "description": args.get("description"),
            "item_lines": [
                {
                    "account_id": int(args["account_id"]),
                    "amount": amount,
                    "description": args.get("line_description") or args.get("description"),
                }
            ],
            "counterparty_lines": [counterparty_line],
        }
        return create_expense_income(db, business_id, user_id, body)

    registry.register(
        AIFunction(
            name="create_expense_income",
            description=(
                "ثبت سند هزینه یا درآمد ساده (یک سطر حساب + یک طرف‌حساب). "
                "document_type: expense یا income. counterparty_type: bank, cash_register, petty_cash, person."
            ),
            parameters_schema={
                "type": "object",
                "properties": {
                    "document_type": {"type": "string", "enum": ["expense", "income"]},
                    "document_date": {"type": "string", "format": "date"},
                    "currency_id": {"type": "integer"},
                    "account_id": {"type": "integer", "description": "شناسه حساب هزینه/درآمد"},
                    "amount": {"type": "number"},
                    "counterparty_type": {
                        "type": "string",
                        "enum": ["bank", "cash_register", "petty_cash", "person"],
                    },
                    "counterparty_id": {"type": "integer"},
                    "description": {"type": "string"},
                    "line_description": {"type": "string"},
                    "transaction_date": {"type": "string"},
                },
                "required": [
                    "document_type",
                    "currency_id",
                    "account_id",
                    "amount",
                    "counterparty_type",
                    "counterparty_id",
                ],
            },
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
        from app.services.invoice_service import update_invoice

        db = context["db"]
        user_id = context["user_context"].get_user_id()
        invoice_id = int(args["invoice_id"])
        data: Dict[str, Any] = {}
        for key in (
            "document_date",
            "currency_id",
            "person_id",
            "description",
            "is_proforma",
            "project_id",
            "lines",
            "extra_info",
        ):
            if key in args and args[key] is not None:
                data[key] = args[key]
        if args.get("description") is not None and "extra_info" not in data:
            data["extra_info"] = {"description": args["description"]}
        return update_invoice(db, invoice_id, user_id, data)

    registry.register(
        AIFunction(
            name="update_invoice",
            description="ویرایش فاکتور موجود. فقط فیلدهای ارسالی تغییر می‌کنند. نیاز به تأیید.",
            parameters_schema={
                "type": "object",
                "properties": {
                    "invoice_id": {"type": "integer", "description": "شناسه سند فاکتور"},
                    "document_date": {"type": "string", "format": "date"},
                    "currency_id": {"type": "integer"},
                    "person_id": {"type": "integer"},
                    "description": {"type": "string"},
                    "is_proforma": {"type": "boolean"},
                    "project_id": {"type": "integer"},
                    "lines": {"type": "array", "items": {"type": "object"}},
                },
                "required": ["invoice_id"],
            },
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
            description="ایجاد سرنخ CRM. process_definition_id و stage_id الزامی است.",
            parameters_schema={
                "type": "object",
                "properties": {
                    "process_definition_id": {"type": "integer"},
                    "stage_id": {"type": "integer"},
                    "name": {"type": "string"},
                    "code": {"type": "string"},
                    "source_code": {"type": "string"},
                    "company_name": {"type": "string"},
                    "mobile": {"type": "string"},
                    "email": {"type": "string", "format": "email"},
                    "description": {"type": "string"},
                    "assigned_to_user_id": {"type": "integer"},
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
