"""MCP leftovers: report HTML preview, workflow catalogs/timeline, kardex JSON lines."""
from __future__ import annotations

from app.services.ai.ai_mcp_tool_util import mcp_bid, mcp_db, mcp_jsonable, mcp_run, mcp_schema

EMPTY = mcp_schema({})
HTML_PREVIEW = mcp_schema(
    {
        "engine": {"type": "string", "enum": ["jinja2", "builder", "template_v2"]},
        "content_html": {"type": "string", "maxLength": 200000},
        "content_css": {"type": "string", "maxLength": 100000},
        "header_html": {"type": "string", "maxLength": 50000},
        "footer_html": {"type": "string", "maxLength": 50000},
        "design": {"type": "object"},
        "context": {"type": "object"},
        "paper_size": {"type": "string", "maxLength": 20},
        "orientation": {"type": "string", "enum": ["portrait", "landscape"]},
    }
)
TIMELINE = mcp_schema(
    {"workflow_id": {"type": "integer", "minimum": 1}, "execution_id": {"type": "integer", "minimum": 1}},
    ["workflow_id", "execution_id"],
)
LANG = mcp_schema({"lang": {"type": "string", "enum": ["fa", "en"]}})
IDS = {"type": "array", "maxItems": 40, "items": {"type": "integer", "minimum": 1}}
KARDEX = mcp_schema(
    {
        "from_date": {"type": "string"},
        "to_date": {"type": "string"},
        "fiscal_year_id": {"type": "integer", "minimum": 1},
        "person_ids": IDS,
        "product_ids": IDS,
        "account_ids": IDS,
        "bank_account_ids": IDS,
        "cash_register_ids": IDS,
        "petty_cash_ids": IDS,
        "check_ids": IDS,
        "match_mode": {"type": "string", "enum": ["any", "same_line", "document_and"]},
        "result_scope": {"type": "string", "enum": ["lines_matching", "lines_of_document"]},
        "skip": {"type": "integer", "minimum": 0},
        "take": {"type": "integer", "minimum": 1, "maximum": 100},
        "sort_by": {"type": "string", "maxLength": 40},
        "sort_desc": {"type": "boolean"},
    }
)


def _slim_meta(item: dict) -> dict:
    return {
        "key": item.get("key"),
        "name": item.get("name") or item.get("label") or item.get("title"),
        "description": item.get("description"),
        "category": item.get("category"),
    }


def preview_report_template_html_handler(args, context):
    from adapters.api.v1.report_templates import _preview_assets, _preview_context
    from app.services.report_template_service import ReportTemplateService

    engine = str(args.get("engine") or "jinja2").lower()
    html = str(args.get("content_html") or "")
    css = str(args.get("content_css") or "")
    if len(html) > 200000 or len(css) > 100000:
        raise ValueError("HTML/CSS برای پیش‌نمایش بزرگ است")
    body = dict(args)
    temp = type(
        "T",
        (),
        {
            "engine": engine,
            "content_html": html,
            "content_css": css,
            "header_html": args.get("header_html") or "",
            "footer_html": args.get("footer_html") or "",
            "paper_size": args.get("paper_size"),
            "orientation": args.get("orientation"),
            "margins": None,
            "assets": _preview_assets(body, engine),
        },
    )()
    rendered = mcp_run(ReportTemplateService.render_with_template, temp, _preview_context(body, include_farsi_fonts=False))
    if isinstance(rendered, str) and len(rendered) > 200000:
        rendered = rendered[:200000] + "…"
    return {"ok": True, "html": rendered}


def get_workflow_execution_timeline_handler(args, context):
    from sqlalchemy import select
    from adapters.db.models.workflow import Workflow, WorkflowExecution, WorkflowLog

    db, bid = mcp_db(context), mcp_bid(context)
    wf = db.get(Workflow, int(args["workflow_id"]))
    if not wf or wf.business_id != bid:
        raise ValueError("ورک‌فلو در این کسب‌وکار یافت نشد")
    execution = db.get(WorkflowExecution, int(args["execution_id"]))
    if not execution or execution.workflow_id != wf.id:
        raise ValueError("اجرای ورک‌فلو یافت نشد")
    logs = list(
        db.execute(
            select(WorkflowLog).where(WorkflowLog.execution_id == execution.id).order_by(WorkflowLog.timestamp.asc())
        )
        .scalars()
        .all()
    )[:200]
    timeline = []
    for log in logs:
        timeline.append(
            {
                "timestamp": log.timestamp.isoformat() if log.timestamp else None,
                "level": log.level.value if hasattr(log.level, "value") else str(log.level),
                "message": (log.message or "")[:500],
                "node_id": log.node_id,
            }
        )
    return mcp_jsonable(
        {
            "workflow_id": wf.id,
            "execution_id": execution.id,
            "status": execution.status.value if hasattr(execution.status, "value") else str(execution.status),
            "error_message": execution.error_message,
            "timeline": timeline,
            "total_logs": len(timeline),
            "capped": True,
        }
    )


def list_workflow_trigger_catalog_handler(args, context):
    from app.services.workflow.i18n import TRIGGER_TRANSLATIONS_BY_KEY, translate_trigger_metadata
    from app.services.workflow.trigger_registry import TriggerRegistry

    lang = str(args.get("lang") or "fa")
    items = []
    for t in TriggerRegistry().get_all_metadata():
        key = t.get("key") or ""
        if key in TRIGGER_TRANSLATIONS_BY_KEY:
            t = translate_trigger_metadata(t, lang, key)
        items.append(_slim_meta(t if isinstance(t, dict) else {}))
    return {"items": items, "lang": lang}


def list_workflow_action_catalog_handler(args, context):
    from app.services.workflow.action_registry import ActionRegistry
    from app.services.workflow.i18n import translate_metadata
    from app.services.workflow.i18n.hesabix_data_actions_i18n import get_workflow_action_keys

    lang = str(args.get("lang") or "fa")
    keys = set(get_workflow_action_keys() or [])
    items = []
    for action in ActionRegistry().get_all_metadata():
        meta = dict(action)
        key = meta.get("key") or ""
        ctx_name = None
        if key == "ai_agent":
            ctx_name = "ai_agent"
        elif key == "business_backup":
            ctx_name = "business_backup"
        elif key in keys or "invoice" in key:
            ctx_name = key
        try:
            if ctx_name:
                meta = translate_metadata(meta, lang, ctx_name)
        except Exception:
            pass
        items.append(_slim_meta(meta if isinstance(meta, dict) else {}))
    return {"items": items, "lang": lang}


def list_kardex_document_lines_handler(args, context):
    from app.services.kardex_service import list_kardex_lines

    query = {
        "from_date": args.get("from_date"),
        "to_date": args.get("to_date"),
        "fiscal_year_id": args.get("fiscal_year_id"),
        "person_ids": args.get("person_ids"),
        "product_ids": args.get("product_ids"),
        "account_ids": args.get("account_ids"),
        "bank_account_ids": args.get("bank_account_ids"),
        "cash_register_ids": args.get("cash_register_ids"),
        "petty_cash_ids": args.get("petty_cash_ids"),
        "check_ids": args.get("check_ids"),
        "match_mode": args.get("match_mode") or "any",
        "result_scope": args.get("result_scope") or "lines_matching",
        "skip": int(args.get("skip") or 0),
        "take": min(100, int(args.get("take") or 20)),
        "sort_by": args.get("sort_by") or "document_date",
        "sort_desc": bool(args.get("sort_desc", True)),
    }
    return mcp_jsonable(mcp_run(list_kardex_lines, mcp_db(context), mcp_bid(context), query))


def register_mcp_ops14_functions(registry) -> None:
    from app.services.ai.function_registry import AIFunction, AIRole

    roles = {AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN}
    registry.register(AIFunction(name="preview_report_template_html", description="پیش‌نمایش HTML زنده قالب چاپ بدون PDF و بدون ذخیره.", parameters_schema=HTML_PREVIEW, handler=preview_report_template_html_handler, allowed_roles=roles, required_permissions=["report_templates.write"], category="report_templates", is_readonly=True))
    registry.register(AIFunction(name="get_workflow_execution_timeline", description="خط زمانی لاگ یک اجرای ورک‌فلو (حداکثر ۲۰۰ رویداد، بدون payload حجیم).", parameters_schema=TIMELINE, handler=get_workflow_execution_timeline_handler, allowed_roles=roles, required_permissions=["workflows.view"], category="workflow", is_readonly=True))
    registry.register(AIFunction(name="list_workflow_trigger_catalog", description="کاتالوگ تریگرهای ورک‌فلو (کلید و توضیح، بدون اسکیمای محرمانه).", parameters_schema=LANG, handler=list_workflow_trigger_catalog_handler, allowed_roles=roles, required_permissions=["workflows.view"], category="workflow", is_readonly=True))
    registry.register(AIFunction(name="list_workflow_action_catalog", description="کاتالوگ اکشن‌های ورک‌فلو (کلید و توضیح).", parameters_schema=LANG, handler=list_workflow_action_catalog_handler, allowed_roles=roles, required_permissions=["workflows.view"], category="workflow", is_readonly=True))
    registry.register(AIFunction(name="list_kardex_document_lines", description="خطوط کاردکس اسناد با فیلتر شخص/کالا/حساب؛ حداکثر ۱۰۰ ردیف.", parameters_schema=KARDEX, handler=list_kardex_document_lines_handler, allowed_roles=roles, required_permissions=["reports.view"], category="reports", is_readonly=True))
