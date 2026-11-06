"""MCP leftovers: POS extras, product insights, barcode sample, instance search, workflow errors, numbering."""
from __future__ import annotations

from datetime import date, datetime, timedelta

from app.services.ai.ai_mcp_tool_util import mcp_bid, mcp_can, mcp_commit, mcp_db, mcp_jsonable, mcp_run, mcp_schema, mcp_uid

EMPTY = mcp_schema({})
PERSON_SUM = EMPTY
INSIGHTS = mcp_schema(
    {
        "product_id": {"type": "integer", "minimum": 1},
        "date_from": {"type": "string"},
        "date_to": {"type": "string"},
        "bucket": {"type": "string", "enum": ["day", "week", "month"]},
    },
    ["product_id"],
)
RECENT = mcp_schema({"take": {"type": "integer", "minimum": 1, "maximum": 50}, "category_ids": {"type": "array", "items": {"type": "integer"}}})
BAL = mcp_schema(
    {
        "person_id": {"type": "integer", "minimum": 1},
        "currency_id": {"type": "integer", "minimum": 1},
        "as_of_date": {"type": "string"},
        "fiscal_year_id": {"type": "integer", "minimum": 1},
    },
    ["person_id", "currency_id"],
)
JOBS = mcp_schema({"limit": {"type": "integer", "minimum": 1, "maximum": 50}})
RESOLVE = mcp_schema(
    {
        "case_id": {"type": "integer", "minimum": 1},
        "lines": {"type": "array", "maxItems": 40, "items": {"type": "object"}},
        "document_date": {"type": "string"},
    },
    ["case_id"],
)
REV = mcp_schema({"template_id": {"type": "integer", "minimum": 1}}, ["template_id"])
CODE = mcp_schema({"code": {"type": "string", "minLength": 1, "maxLength": 120}}, ["code"])
WF_ERR = mcp_schema({"days": {"type": "integer", "minimum": 1, "maximum": 90}, "workflow_id": {"type": "integer", "minimum": 1}})
NUM = mcp_schema({"document_type": {"type": "string", "minLength": 1, "maxLength": 80}}, ["document_type"])


def get_persons_summary_handler(args, context):
    from app.services.person_service import get_person_summary

    return mcp_jsonable(mcp_run(get_person_summary, mcp_db(context), mcp_bid(context)))


def get_product_commercial_insights_handler(args, context):
    from app.services.product_commercial_insights_service import get_product_commercial_insights

    df = date.fromisoformat(str(args["date_from"])) if args.get("date_from") else None
    dt = date.fromisoformat(str(args["date_to"])) if args.get("date_to") else None
    return mcp_jsonable(
        mcp_run(
            get_product_commercial_insights,
            mcp_db(context),
            mcp_bid(context),
            int(args["product_id"]),
            df,
            dt,
            str(args.get("bucket") or "month"),
        )
    )


def list_recent_sales_invoice_products_handler(args, context):
    from app.services.product_service import list_recent_sales_invoice_products

    cats = args.get("category_ids") if isinstance(args.get("category_ids"), list) else None
    return mcp_jsonable(mcp_run(list_recent_sales_invoice_products, mcp_db(context), mcp_bid(context), int(args.get("take") or 10), cats))


def get_quick_sales_customer_balance_handler(args, context):
    from app.core.business_calendar import business_today
    from app.services.quick_sales_service import get_quick_sales_customer_balance

    bid = mcp_bid(context)
    as_of = date.fromisoformat(str(args["as_of_date"])) if args.get("as_of_date") else business_today(bid)
    return mcp_jsonable(
        mcp_run(
            get_quick_sales_customer_balance,
            mcp_db(context),
            business_id=bid,
            person_id=int(args["person_id"]),
            currency_id=int(args["currency_id"]),
            as_of_date=as_of,
            fiscal_year_id=args.get("fiscal_year_id"),
        )
    )


def get_quick_sales_anonymous_customer_handler(args, context):
    from adapters.api.v1.quick_sales import _anonymous_customer_data
    from app.services.quick_sales_service import get_configured_anonymous_customer

    try:
        customer = mcp_run(get_configured_anonymous_customer, mcp_db(context), mcp_bid(context))
    except ValueError:
        return {"configured": False}
    return mcp_jsonable({"configured": True, **_anonymous_customer_data(customer)})


def ensure_quick_sales_anonymous_customer_handler(args, context):
    from adapters.api.v1.quick_sales import _anonymous_customer_data
    from app.services.quick_sales_service import get_or_create_anonymous_customer

    customer = mcp_run(get_or_create_anonymous_customer, mcp_db(context), mcp_bid(context))
    mcp_commit(context)
    return mcp_jsonable(_anonymous_customer_data(customer))


def list_quick_sale_jobs_handler(args, context):
    from app.services.quick_sale_invoice_job_service import list_quick_sale_invoice_jobs, serialize_quick_sale_job

    jobs = mcp_run(
        list_quick_sale_invoice_jobs,
        mcp_db(context),
        business_id=mcp_bid(context),
        user_id=mcp_uid(context),
        limit=int(args.get("limit") or 20),
    )
    return mcp_jsonable([serialize_quick_sale_job(j) for j in jobs])


def resolve_quick_sales_stock_discrepancy_handler(args, context):
    from app.core.business_calendar import business_today
    from app.services.inventory_discrepancy_service import resolve_case_with_goods_income

    bid = mcp_bid(context)
    day = date.fromisoformat(str(args["document_date"])) if args.get("document_date") else business_today(bid)
    out = mcp_run(
        resolve_case_with_goods_income,
        mcp_db(context),
        business_id=bid,
        case_id=int(args["case_id"]),
        user_id=mcp_uid(context),
        lines=list(args.get("lines") or []),
        document_date=day,
        user_can_allocate=mcp_can(context, "goods_expense_income", "allocate"),
        user_can_post=mcp_can(context, "goods_expense_income", "post"),
        user_can_change_unit_cost=mcp_can(context, "goods_expense_income", "change_unit_cost"),
    )
    mcp_commit(context)
    return mcp_jsonable(out)


def list_barcode_label_revisions_handler(args, context):
    from app.services.barcode_label_service import list_template_revisions

    return mcp_jsonable(mcp_run(list_template_revisions, mcp_db(context), mcp_bid(context), int(args["template_id"])))


def get_barcode_label_sample_context_handler(args, context):
    from app.services.barcode_label_service import get_sample_context

    return mcp_jsonable(mcp_run(get_sample_context))


def search_product_instance_by_code_handler(args, context):
    from sqlalchemy import and_, or_
    from adapters.api.v1.product_instances import _instance_search_payload
    from adapters.db.models.product_instance import ProductInstance

    db, bid = mcp_db(context), mcp_bid(context)
    code = str(args["code"]).strip()
    if not code:
        raise ValueError("بارکد یا سریال الزامی است")
    q = db.query(ProductInstance).filter(
        and_(
            ProductInstance.business_id == bid,
            or_(ProductInstance.barcode == code, ProductInstance.serial_number == code),
        )
    )
    inst = q.first()
    if inst:
        return mcp_jsonable(_instance_search_payload(inst))
    like = f"%{code}%"
    inst = (
        db.query(ProductInstance)
        .filter(
            and_(
                ProductInstance.business_id == bid,
                or_(ProductInstance.barcode.ilike(like), ProductInstance.serial_number.ilike(like)),
            )
        )
        .first()
    )
    if not inst:
        raise ValueError("کالای یونیک با این کد یافت نشد")
    return mcp_jsonable(_instance_search_payload(inst))


def get_workflow_error_analytics_handler(args, context):
    from collections import defaultdict
    from sqlalchemy import and_, select
    from adapters.db.models.workflow import Workflow, WorkflowExecution, WorkflowLog, WorkflowLogLevel

    days = max(1, min(90, int(args.get("days") or 7)))
    bid = mcp_bid(context)
    stmt = (
        select(WorkflowLog)
        .select_from(WorkflowLog)
        .join(WorkflowExecution, WorkflowExecution.id == WorkflowLog.execution_id)
        .join(Workflow, Workflow.id == WorkflowExecution.workflow_id)
        .where(
            and_(
                Workflow.business_id == bid,
                WorkflowLog.level == WorkflowLogLevel.ERROR,
                WorkflowLog.timestamp >= datetime.utcnow() - timedelta(days=days),
            )
        )
    )
    if args.get("workflow_id"):
        stmt = stmt.where(Workflow.id == int(args["workflow_id"]))
    logs = list(mcp_db(context).execute(stmt).scalars().all())
    stats = defaultdict(lambda: {"count": 0, "last_occurrence": None, "first_occurrence": None})
    for log in logs:
        data = log.data or {}
        error_type = str(data.get("error_type") or data.get("error_message") or "Unknown")[:100]
        stats[error_type]["count"] += 1
        ts = log.timestamp
        if stats[error_type]["last_occurrence"] is None or ts > stats[error_type]["last_occurrence"]:
            stats[error_type]["last_occurrence"] = ts
        if stats[error_type]["first_occurrence"] is None or ts < stats[error_type]["first_occurrence"]:
            stats[error_type]["first_occurrence"] = ts
    total = sum(v["count"] for v in stats.values())
    rows = sorted(({"error_type": k, **v} for k, v in stats.items()), key=lambda x: x["count"], reverse=True)
    return mcp_jsonable(
        {
            "total_errors": total,
            "unique_error_types": len(rows),
            "period_days": days,
            "errors_by_type": [
                {
                    "error_type": r["error_type"],
                    "count": r["count"],
                    "percentage": round((r["count"] / total * 100), 2) if total else 0,
                    "last_occurrence": r["last_occurrence"].isoformat() if r["last_occurrence"] else None,
                    "first_occurrence": r["first_occurrence"].isoformat() if r["first_occurrence"] else None,
                }
                for r in rows[:40]
            ],
        }
    )


def delete_document_numbering_setting_handler(args, context):
    from sqlalchemy import and_
    from adapters.db.models.document_numbering import BusinessDocumentNumberingSetting

    db, bid = mcp_db(context), mcp_bid(context)
    dtype = str(args["document_type"]).strip()
    setting = (
        db.query(BusinessDocumentNumberingSetting)
        .filter(
            and_(
                BusinessDocumentNumberingSetting.business_id == bid,
                BusinessDocumentNumberingSetting.document_type == dtype,
            )
        )
        .first()
    )
    if setting:
        db.delete(setting)
        mcp_commit(context)
        return {"deleted": True, "document_type": dtype}
    return {"deleted": False, "document_type": dtype}


def register_mcp_ops12_functions(registry) -> None:
    from app.services.ai.function_registry import AIFunction, AIRole

    roles = {AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN}
    registry.register(AIFunction(name="get_persons_summary", description="خلاصه تعداد اشخاص کسب‌وکار به تفکیک نوع.", parameters_schema=PERSON_SUM, handler=get_persons_summary_handler, allowed_roles=roles, required_permissions=["people.view"], category="persons", is_readonly=True))
    registry.register(AIFunction(name="get_product_commercial_insights", description="بینش فروش و گردش یک کالا در بازه و سطل زمانی.", parameters_schema=INSIGHTS, handler=get_product_commercial_insights_handler, allowed_roles=roles, required_permissions=["products.read"], category="products", is_readonly=True))
    registry.register(AIFunction(name="list_recent_sales_invoice_products", description="کالاهایی که اخیراً در فاکتور فروش قطعی آمده‌اند.", parameters_schema=RECENT, handler=list_recent_sales_invoice_products_handler, allowed_roles=roles, required_permissions=["products.read"], category="products", is_readonly=True))
    registry.register(AIFunction(name="get_quick_sales_customer_balance", description="مانده مشتری به ارز انتخابی برای فروش سریع.", parameters_schema=BAL, handler=get_quick_sales_customer_balance_handler, allowed_roles=roles, required_permissions=["quick_sales.view_customer_balance"], category="invoices", is_readonly=True))
    registry.register(AIFunction(name="get_quick_sales_anonymous_customer", description="مشتری ناشناس تنظیم‌شده فروش سریع (بدون ایجاد).", parameters_schema=EMPTY, handler=get_quick_sales_anonymous_customer_handler, allowed_roles=roles, required_permissions=["invoices.write"], category="invoices", is_readonly=True))
    registry.register(AIFunction(name="ensure_quick_sales_anonymous_customer", description="دریافت یا ایجاد مشتری ناشناس فروش سریع. نیازمند تأیید.", parameters_schema=EMPTY, handler=ensure_quick_sales_anonymous_customer_handler, allowed_roles=roles, required_permissions=["invoices.write"], category="invoices", requires_approval=True, risk_level="low", is_readonly=False))
    registry.register(AIFunction(name="list_quick_sale_jobs", description="صف فروش سریع ناهمزمان کاربر جاری.", parameters_schema=JOBS, handler=list_quick_sale_jobs_handler, allowed_roles=roles, required_permissions=["invoices.write"], category="invoices", is_readonly=True))
    registry.register(AIFunction(name="resolve_quick_sales_stock_discrepancy", description="رفع مغایرت موجودی فروش سریع با کالای درآمدشده. نیازمند تأیید.", parameters_schema=RESOLVE, handler=resolve_quick_sales_stock_discrepancy_handler, allowed_roles=roles, required_permissions=["goods_expense_income.write"], category="warehouse", requires_approval=True, risk_level="high", is_readonly=False))
    registry.register(AIFunction(name="list_barcode_label_revisions", description="تاریخچه بازنگری یک قالب برچسب بارکد.", parameters_schema=REV, handler=list_barcode_label_revisions_handler, allowed_roles=roles, required_permissions=["barcode_labels.view"], category="products", is_readonly=True))
    registry.register(AIFunction(name="get_barcode_label_sample_context", description="داده نمونه برای پیش‌نمایش قالب برچسب بارکد.", parameters_schema=EMPTY, handler=get_barcode_label_sample_context_handler, allowed_roles=roles, required_permissions=["barcode_labels.view"], category="products", is_readonly=True))
    registry.register(AIFunction(name="search_product_instance_by_code", description="جستجوی کالای یونیک با بارکد یا سریال (دقیق سپس جزئی).", parameters_schema=CODE, handler=search_product_instance_by_code_handler, allowed_roles=roles, required_permissions=["warehouses.view"], category="products", is_readonly=True))
    registry.register(AIFunction(name="get_workflow_error_analytics", description="آمار خطاهای اجرای ورک‌فلو در چند روز اخیر.", parameters_schema=WF_ERR, handler=get_workflow_error_analytics_handler, allowed_roles=roles, required_permissions=["workflows.view"], category="workflow", is_readonly=True))
    registry.register(AIFunction(name="delete_document_numbering_setting", description="حذف تنظیم شماره‌گذاری یک نوع سند و بازگشت به پیش‌فرض. نیازمند تأیید.", parameters_schema=NUM, handler=delete_document_numbering_setting_handler, allowed_roles=roles, required_permissions=["settings.join"], category="business", requires_approval=True, risk_level="medium", is_readonly=False))
