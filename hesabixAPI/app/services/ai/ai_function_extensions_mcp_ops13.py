"""MCP leftovers: unique-instance bulk, report studio JSON, profit ledger, CRM message, POS shortcuts, workflow perf."""
from __future__ import annotations

from datetime import datetime, timedelta

from app.services.ai.ai_mcp_tool_util import (
    mcp_await,
    mcp_bid,
    mcp_commit,
    mcp_db,
    mcp_jsonable,
    mcp_run,
    mcp_schema,
    mcp_uid,
    mcp_unwrap,
)

EMPTY = mcp_schema({})
BULK_INST = mcp_schema(
    {"instances": {"type": "array", "minItems": 1, "maxItems": 50, "items": {"type": "object"}}},
    ["instances"],
)
CONVERT = mcp_schema(
    {
        "product_id": {"type": "integer", "minimum": 1},
        "auto_generate_serial": {"type": "boolean"},
        "serial_prefix": {"type": "string", "maxLength": 40},
        "create_for_existing_stock": {"type": "boolean"},
        "track_serial": {"type": "boolean"},
        "track_barcode": {"type": "boolean"},
    },
    ["product_id"],
)
SCOPE = mcp_schema({"module_key": {"type": "string", "maxLength": 80}, "subtype": {"type": "string", "maxLength": 80}})
DESIGN = mcp_schema(
    {
        "module_key": {"type": "string", "maxLength": 80},
        "subtype": {"type": "string", "maxLength": 80},
        "design": {"type": "object"},
    },
    ["design"],
)
TRANS = mcp_schema(
    {
        "template_id": {"type": "integer", "minimum": 1},
        "to_status": {"type": "string", "enum": ["draft", "in_review", "approved", "published", "deprecated"]},
        "reason": {"type": "string", "maxLength": 400},
    },
    ["template_id", "to_status"],
)
TID = mcp_schema({"template_id": {"type": "integer", "minimum": 1}, "limit": {"type": "integer", "minimum": 1, "maximum": 100}}, ["template_id"])
AUDIT = mcp_schema(
    {
        "status": {"type": "string", "maxLength": 40},
        "actor_user_id": {"type": "integer", "minimum": 1},
        "limit": {"type": "integer", "minimum": 1, "maximum": 100},
        "offset": {"type": "integer", "minimum": 0},
    }
)
BACKFILL = mcp_schema(
    {
        "fiscal_year_id": {"type": "integer", "minimum": 1},
        "invoice_ids": {"type": "array", "maxItems": 50, "items": {"type": "integer", "minimum": 1}},
        "limit": {"type": "integer", "minimum": 1, "maximum": 200},
    }
)
MSG_DEL = mcp_schema(
    {"conversation_id": {"type": "integer", "minimum": 1}, "message_id": {"type": "integer", "minimum": 1}},
    ["conversation_id", "message_id"],
)
SHORT_PUT = mcp_schema({"shortcuts": {"type": "array", "minItems": 1, "maxItems": 40, "items": {"type": "object"}}}, ["shortcuts"])
WF_PERF = mcp_schema({"days": {"type": "integer", "minimum": 1, "maximum": 90}, "workflow_id": {"type": "integer", "minimum": 1}})


def bulk_create_product_instances_handler(args, context):
    from adapters.api.v1.product_instances import create_bulk_product_instances

    out = mcp_run(
        create_bulk_product_instances,
        None,
        mcp_bid(context),
        {"instances": list(args.get("instances") or [])[:50]},
        context.get("user_context"),
        mcp_db(context),
    )
    return mcp_jsonable(mcp_unwrap(out))


def convert_product_to_unique_instances_handler(args, context):
    from adapters.api.v1.product_instances import convert_product_to_unique

    payload = {k: args[k] for k in args if k != "product_id"}
    out = mcp_run(
        convert_product_to_unique,
        None,
        mcp_bid(context),
        int(args["product_id"]),
        payload,
        context.get("user_context"),
        mcp_db(context),
    )
    return mcp_jsonable(mcp_unwrap(out))


def list_report_template_gallery_handler(args, context):
    from app.services.report_template_gallery import list_gallery_items
    from app.services.report_template_v3_service import migrate_v2_design_to_v3
    from app.services.report_template_v4_service import migrate_v3_design_to_v4

    items = mcp_run(list_gallery_items, module_key=args.get("module_key"), subtype=args.get("subtype"))
    for item in items:
        try:
            item["studio_design"] = migrate_v3_design_to_v4(migrate_v2_design_to_v3(item["default_design"]))
        except ValueError:
            pass
    return mcp_jsonable({"items": items})


def list_report_template_studio_blocks_handler(args, context):
    from app.services.report_template_v3_service import studio_block_catalog

    key = str(args.get("module_key") or "")
    if not key:
        raise ValueError("module_key الزامی است")
    return {"items": mcp_run(studio_block_catalog, key, args.get("subtype"))}


def get_report_template_studio_contract_handler(args, context):
    from app.services.report_template_v4_service import studio_v4_contract

    key = str(args.get("module_key") or "")
    if not key:
        raise ValueError("module_key الزامی است")
    return mcp_jsonable(mcp_run(studio_v4_contract, key, args.get("subtype")))


def validate_report_template_builder_design_handler(args, context):
    from app.services.report_template_service import ReportTemplateService

    return mcp_jsonable(
        mcp_run(
            ReportTemplateService.validate_builder_design_scope,
            str(args.get("module_key") or ""),
            args.get("subtype"),
            args.get("design") or {},
        )
    )


def validate_report_template_studio_design_handler(args, context):
    from app.services.report_template_service import ReportTemplateService

    return mcp_jsonable(
        mcp_run(
            ReportTemplateService.validate_template_v2_design_scope,
            str(args.get("module_key") or ""),
            args.get("subtype"),
            args.get("design") or {},
        )
    )


def compile_report_template_studio_design_handler(args, context):
    from app.services.template_design_v3_compiler import compile_template_design_to_jinja_html

    html, css, header, footer = mcp_run(compile_template_design_to_jinja_html, args.get("design") or {})
    return {"content_html": html, "content_css": css, "header_html": header, "footer_html": footer}


def migrate_report_template_builder_to_v2_handler(args, context):
    from app.services.report_template_service import ReportTemplateService
    from app.services.report_template_v2_service import migrate_builder_design_to_v2

    module_key = str(args.get("module_key") or "")
    subtype = args.get("subtype")
    builder = args.get("builder_design") or args.get("design") or {}
    if not isinstance(builder, dict):
        raise ValueError("builder_design باید شیء باشد")
    design = mcp_run(migrate_builder_design_to_v2, module_key, subtype, builder)
    validation = mcp_run(ReportTemplateService.validate_template_v2_design_scope, module_key, subtype, design)
    return mcp_jsonable({"design": design, **validation})


def migrate_report_template_v2_to_v3_handler(args, context):
    from app.services.report_template_v3_service import migrate_v2_design_to_v3

    return {"design": mcp_run(migrate_v2_design_to_v3, args.get("design") or {})}


def migrate_report_template_v3_to_v4_handler(args, context):
    from app.services.report_template_v4_service import migrate_v3_design_to_v4

    return {"design": mcp_run(migrate_v3_design_to_v4, args.get("design") or {}), "source_preserved": True}


def transition_report_template_status_handler(args, context):
    from app.services.report_template_service import ReportTemplateService

    to_status = str(args["to_status"]).strip().lower()
    ctx = context.get("user_context")
    if to_status in ("approved", "published", "deprecated"):
        if ctx is None or not ctx.can_approve_section("report_templates"):
            raise ValueError("مجوز تأیید قالب گزارش لازم است")
    elif ctx is None or not ctx.can_write_section("report_templates"):
        raise ValueError("مجوز ویرایش قالب گزارش لازم است")
    entity = mcp_run(
        ReportTemplateService.transition_status,
        db=mcp_db(context),
        template_id=int(args["template_id"]),
        business_id=mcp_bid(context),
        to_status=to_status,
        reason=args.get("reason"),
        actor_user_id=mcp_uid(context),
    )
    mcp_commit(context)
    return {"id": entity.id, "status": entity.status}


def list_report_template_status_events_handler(args, context):
    from app.services.report_template_service import ReportTemplateService

    db, bid = mcp_db(context), mcp_bid(context)
    tid = int(args["template_id"])
    if not mcp_run(ReportTemplateService.get_template, db=db, template_id=tid, business_id=bid):
        raise ValueError("قالب یافت نشد")
    events = mcp_run(
        ReportTemplateService.list_status_events,
        db=db,
        template_id=tid,
        business_id=bid,
        limit=int(args.get("limit") or 50),
    )
    return mcp_jsonable(
        {
            "items": [
                {
                    "id": e.id,
                    "from_status": e.from_status,
                    "to_status": e.to_status,
                    "reason": e.reason,
                    "actor_user_id": e.actor_user_id,
                    "created_at": e.created_at.isoformat() if e.created_at else None,
                }
                for e in events
            ]
        }
    )


def list_report_template_status_audit_handler(args, context):
    from adapters.db.models.report_template_status_event import ReportTemplateStatusEvent

    ctx = context.get("user_context")
    if ctx is None or not (ctx.can_approve_section("report_templates") or ctx.can_export_section("report_templates")):
        raise ValueError("مجوز تأیید یا خروجی قالب گزارش لازم است")
    lim = max(1, min(int(args.get("limit") or 50), 100))
    off = max(0, int(args.get("offset") or 0))
    q = mcp_db(context).query(ReportTemplateStatusEvent).filter(ReportTemplateStatusEvent.business_id == mcp_bid(context))
    if args.get("status"):
        q = q.filter(ReportTemplateStatusEvent.to_status == str(args["status"]))
    if args.get("actor_user_id"):
        q = q.filter(ReportTemplateStatusEvent.actor_user_id == int(args["actor_user_id"]))
    rows = q.order_by(ReportTemplateStatusEvent.created_at.desc()).offset(off).limit(lim).all()
    return mcp_jsonable(
        {
            "items": [
                {
                    "id": e.id,
                    "report_template_id": e.report_template_id,
                    "from_status": e.from_status,
                    "to_status": e.to_status,
                    "reason": e.reason,
                    "actor_user_id": e.actor_user_id,
                    "created_at": e.created_at.isoformat() if e.created_at else None,
                }
                for e in rows
            ]
        }
    )


def backfill_invoice_profit_ledger_handler(args, context):
    from adapters.db.models.business import Business
    from app.services.invoice_profit_ledger_service import backfill_recognized_profit_for_business

    db, bid = mcp_db(context), mcp_bid(context)
    business = db.query(Business).filter(Business.id == bid).first()
    if not business:
        raise ValueError("کسب‌وکار یافت نشد")
    if business.invoice_profit_calculation_method == "disabled":
        return {"processed": 0, "skipped": 0, "message": "محاسبه سود غیرفعال است"}
    ids = [int(x) for x in (args.get("invoice_ids") or [])][:50] or None
    out = mcp_run(
        backfill_recognized_profit_for_business,
        db,
        bid,
        fiscal_year_id=int(args["fiscal_year_id"]) if args.get("fiscal_year_id") else None,
        invoice_ids=ids,
        limit=int(args.get("limit") or 100),
    )
    mcp_commit(context)
    return mcp_jsonable(out)


def recalculate_all_invoice_profits_handler(args, context):
    from app.services.ai.ai_function_extensions_mcp_ops5 import recalculate_invoice_profits_handler

    return recalculate_invoice_profits_handler({}, context)


def delete_crm_chat_message_handler(args, context):
    from app.services import crm_chat_service as chat_svc

    return mcp_jsonable(
        mcp_await(
            chat_svc.delete_message_agent(
                mcp_db(context),
                mcp_bid(context),
                int(args["conversation_id"]),
                int(args["message_id"]),
            )
        )
    )


def list_quick_sales_default_shortcuts_handler(args, context):
    from app.services.quick_sales_service import list_quick_sales_payment_default_shortcuts

    return mcp_jsonable(mcp_run(list_quick_sales_payment_default_shortcuts, mcp_db(context), mcp_bid(context)))


def update_quick_sales_default_shortcuts_handler(args, context):
    from app.services.quick_sales_service import set_quick_sales_payment_default_shortcuts

    out = mcp_run(
        set_quick_sales_payment_default_shortcuts,
        mcp_db(context),
        business_id=mcp_bid(context),
        items=args.get("shortcuts"),
    )
    mcp_commit(context)
    return mcp_jsonable(out)


def get_workflow_performance_analytics_handler(args, context):
    from sqlalchemy import and_, case, func, or_, select
    from adapters.db.models.workflow import Workflow, WorkflowExecution, WorkflowExecutionStatus

    days = max(1, min(90, int(args.get("days") or 30)))
    bid = mcp_bid(context)
    since = datetime.utcnow() - timedelta(days=days)
    stmt = (
        select(
            Workflow.id,
            Workflow.name,
            Workflow.status,
            func.count(WorkflowExecution.id).label("total_executions"),
            func.count(case((WorkflowExecution.status == WorkflowExecutionStatus.COMPLETED, 1))).label("successful"),
            func.count(case((WorkflowExecution.status == WorkflowExecutionStatus.FAILED, 1))).label("failed"),
        )
        .select_from(Workflow)
        .outerjoin(WorkflowExecution, WorkflowExecution.workflow_id == Workflow.id)
        .where(
            and_(
                Workflow.business_id == bid,
                or_(WorkflowExecution.created_at >= since, WorkflowExecution.created_at.is_(None)),
            )
        )
    )
    if args.get("workflow_id"):
        stmt = stmt.where(Workflow.id == int(args["workflow_id"]))
    stmt = stmt.group_by(Workflow.id, Workflow.name, Workflow.status)
    rows = list(mcp_db(context).execute(stmt).all())[:40]
    stats = []
    for r in rows:
        exec_stmt = select(WorkflowExecution).where(
            and_(
                WorkflowExecution.workflow_id == r.id,
                WorkflowExecution.created_at >= since,
                WorkflowExecution.started_at.isnot(None),
                WorkflowExecution.completed_at.isnot(None),
            )
        )
        executions = list(mcp_db(context).execute(exec_stmt).scalars().all())
        durations = [(e.completed_at - e.started_at).total_seconds() for e in executions if e.started_at and e.completed_at]
        total = r.total_executions or 0
        successful = r.successful or 0
        stats.append(
            {
                "workflow_id": r.id,
                "workflow_name": r.name,
                "workflow_status": r.status.value if r.status else None,
                "total_executions": total,
                "successful": successful,
                "failed": r.failed or 0,
                "success_rate": round((successful / total * 100) if total else 0, 2),
                "avg_duration_seconds": round(sum(durations) / len(durations), 2) if durations else 0,
            }
        )
    return {"period_days": days, "workflows": stats}


def register_mcp_ops13_functions(registry) -> None:
    from app.services.ai.function_registry import AIFunction, AIRole

    roles = {AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN}
    registry.register(AIFunction(name="bulk_create_product_instances", description="ایجاد گروهی حداکثر ۵۰ کالای یونیک با سریال. نیازمند تأیید.", parameters_schema=BULK_INST, handler=bulk_create_product_instances_handler, allowed_roles=roles, required_permissions=["warehouses.write"], category="products", requires_approval=True, risk_level="medium", is_readonly=False))
    registry.register(AIFunction(name="convert_product_to_unique_instances", description="تبدیل کالای فله به یونیک و ساخت سریال برای موجودی فعلی. نیازمند تأیید.", parameters_schema=CONVERT, handler=convert_product_to_unique_instances_handler, allowed_roles=roles, required_permissions=["warehouses.write"], category="products", requires_approval=True, risk_level="high", is_readonly=False))
    registry.register(AIFunction(name="list_report_template_gallery", description="گالری قالب‌های آماده استودیو چاپ برای شروع سریع.", parameters_schema=SCOPE, handler=list_report_template_gallery_handler, allowed_roles=roles, required_permissions=["report_templates.view"], category="report_templates", is_readonly=True))
    registry.register(AIFunction(name="list_report_template_studio_blocks", description="کاتالوگ بلوک‌های استودیو قالب گزارش برای یک scope.", parameters_schema=SCOPE, handler=list_report_template_studio_blocks_handler, allowed_roles=roles, required_permissions=["report_templates.view"], category="report_templates", is_readonly=True))
    registry.register(AIFunction(name="get_report_template_studio_contract", description="قرارداد schema و binding استودیو v4 برای یک scope.", parameters_schema=SCOPE, handler=get_report_template_studio_contract_handler, allowed_roles=roles, required_permissions=["report_templates.view"], category="report_templates", is_readonly=True))
    registry.register(AIFunction(name="validate_report_template_builder_design", description="اعتبارسنجی طراحی Builder قالب گزارش در برابر scope.", parameters_schema=DESIGN, handler=validate_report_template_builder_design_handler, allowed_roles=roles, required_permissions=["report_templates.write"], category="report_templates", is_readonly=True))
    registry.register(AIFunction(name="validate_report_template_studio_design", description="اعتبارسنجی طراحی استودیو قالب گزارش در برابر scope.", parameters_schema=DESIGN, handler=validate_report_template_studio_design_handler, allowed_roles=roles, required_permissions=["report_templates.write"], category="report_templates", is_readonly=True))
    registry.register(AIFunction(name="compile_report_template_studio_design", description="کامپایل طراحی استودیو به HTML/CSS (بدون PDF).", parameters_schema=DESIGN, handler=compile_report_template_studio_design_handler, allowed_roles=roles, required_permissions=["report_templates.write"], category="report_templates", is_readonly=True))
    registry.register(AIFunction(name="migrate_report_template_builder_to_v2", description="تبدیل غیرمخرب طراحی Builder قدیمی به استودیو v2. قالب ذخیره‌شده را عوض نمی‌کند.", parameters_schema=DESIGN, handler=migrate_report_template_builder_to_v2_handler, allowed_roles=roles, required_permissions=["report_templates.write"], category="report_templates", is_readonly=True))
    registry.register(AIFunction(name="migrate_report_template_v2_to_v3", description="تبدیل غیرمخرب طراحی استودیو v2 به v3.", parameters_schema=DESIGN, handler=migrate_report_template_v2_to_v3_handler, allowed_roles=roles, required_permissions=["report_templates.write"], category="report_templates", is_readonly=True))
    registry.register(AIFunction(name="migrate_report_template_v3_to_v4", description="تبدیل غیرمخرب طراحی استودیو v3 به v4.", parameters_schema=DESIGN, handler=migrate_report_template_v3_to_v4_handler, allowed_roles=roles, required_permissions=["report_templates.write"], category="report_templates", is_readonly=True))
    registry.register(AIFunction(name="transition_report_template_status", description="تغییر وضعیت lifecycle قالب چاپ. نیازمند تأیید.", parameters_schema=TRANS, handler=transition_report_template_status_handler, allowed_roles=roles, required_permissions=["report_templates.write"], category="report_templates", requires_approval=True, risk_level="medium", is_readonly=False))
    registry.register(AIFunction(name="list_report_template_status_events", description="تاریخچه تغییر وضعیت یک قالب چاپ.", parameters_schema=TID, handler=list_report_template_status_events_handler, allowed_roles=roles, required_permissions=["report_templates.view"], category="report_templates", is_readonly=True))
    registry.register(AIFunction(name="list_report_template_status_audit", description="گزارش مدیریتی تغییر وضعیت قالب‌های چاپ کسب‌وکار.", parameters_schema=AUDIT, handler=list_report_template_status_audit_handler, allowed_roles=roles, required_permissions=["report_templates.approve"], category="report_templates", is_readonly=True))
    registry.register(AIFunction(name="backfill_invoice_profit_ledger", description="پر کردن دفتر سود قطعی اسناد قبلی حداکثر ۲۰۰ سند. نیازمند تأیید.", parameters_schema=BACKFILL, handler=backfill_invoice_profit_ledger_handler, allowed_roles=roles, required_permissions=["invoices.write"], category="invoices", requires_approval=True, risk_level="medium", is_readonly=False))
    registry.register(AIFunction(name="recalculate_all_invoice_profits", description="محاسبه مجدد سود فاکتورهای اخیر (سقف ۵۰، بدون فیلتر). نیازمند تأیید.", parameters_schema=EMPTY, handler=recalculate_all_invoice_profits_handler, allowed_roles=roles, required_permissions=["invoices.read"], category="invoices", requires_approval=True, risk_level="medium", is_readonly=False))
    registry.register(AIFunction(name="delete_crm_chat_message", description="حذف نرم یک پیام چت وب کسب‌وکار. نیازمند تأیید.", parameters_schema=MSG_DEL, handler=delete_crm_chat_message_handler, allowed_roles=roles, required_permissions=["crm.write"], category="crm", requires_approval=True, risk_level="medium", is_readonly=False))
    registry.register(AIFunction(name="list_quick_sales_default_shortcuts", description="میانبرهای پیش‌فرض دکمه‌های پرداخت مشترک فروش سریع.", parameters_schema=EMPTY, handler=list_quick_sales_default_shortcuts_handler, allowed_roles=roles, required_permissions=["quick_sales.manage_default_payment_shortcuts"], category="invoices", is_readonly=True))
    registry.register(AIFunction(name="update_quick_sales_default_shortcuts", description="ذخیره یکجای میانبرهای پیش‌فرض دکمه‌های پرداخت فروش سریع. نیازمند تأیید.", parameters_schema=SHORT_PUT, handler=update_quick_sales_default_shortcuts_handler, allowed_roles=roles, required_permissions=["quick_sales.manage_default_payment_shortcuts"], category="invoices", requires_approval=True, risk_level="low", is_readonly=False))
    registry.register(AIFunction(name="get_workflow_performance_analytics", description="نرخ موفقیت و مدت اجرای ورک‌فلوهای کسب‌وکار در چند روز اخیر.", parameters_schema=WF_PERF, handler=get_workflow_performance_analytics_handler, allowed_roles=roles, required_permissions=["workflows.view"], category="workflow", is_readonly=True))
