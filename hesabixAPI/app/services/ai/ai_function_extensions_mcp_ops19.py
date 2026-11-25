"""MCP leftovers: business currency list + project details with stats."""
from __future__ import annotations

from app.services.ai.ai_mcp_tool_util import mcp_bid, mcp_db, mcp_jsonable, mcp_run, mcp_schema

EMPTY = mcp_schema({})
PROJECT_ID = mcp_schema({"project_id": {"type": "integer", "minimum": 1}}, ["project_id"])


def _public_project(row) -> dict:
    return {
        "id": row.id,
        "code": row.code,
        "name": row.name,
        "description": row.description,
        "status": row.status,
        "is_active": bool(row.is_active),
        "start_date": row.start_date.isoformat() if row.start_date else None,
        "end_date": row.end_date.isoformat() if row.end_date else None,
        "budget": float(row.budget) if row.budget is not None else None,
        "currency_id": row.currency_id,
        "manager_user_id": row.manager_user_id,
        "person_id": row.person_id,
    }


def list_business_currencies_handler(args, context):
    from adapters.db.models.business import Business
    from adapters.db.models.currency import BusinessCurrency, Currency

    db = mcp_db(context)
    bid = mcp_bid(context)
    business = db.query(Business).filter(Business.id == bid).first()
    if not business:
        raise ValueError("کسب‌وکار متصل یافت نشد")
    seen = set()
    items = []

    def _row(c, is_default: bool) -> dict:
        return {
            "id": c.id,
            "name": c.name,
            "title": c.title,
            "symbol": c.symbol,
            "code": c.code,
            "decimal_places": int(c.decimal_places) if getattr(c, "decimal_places", None) is not None else 2,
            "round_monetary_amounts": bool(c.round_monetary_amounts)
            if getattr(c, "round_monetary_amounts", None) is not None
            else True,
            "is_default": is_default,
        }

    if business.default_currency_id:
        default_c = db.query(Currency).filter(Currency.id == business.default_currency_id).first()
        if default_c:
            items.append(_row(default_c, True))
            seen.add(default_c.id)
    extra = (
        db.query(Currency)
        .join(BusinessCurrency, BusinessCurrency.currency_id == Currency.id)
        .filter(BusinessCurrency.business_id == bid)
        .all()
    )
    for c in extra:
        if c.id in seen:
            continue
        items.append(_row(c, False))
        seen.add(c.id)
    return mcp_jsonable({"items": items, "default_currency_id": business.default_currency_id})


def get_project_handler(args, context):
    from adapters.db.repositories.project_repository import ProjectRepository
    from app.services.project_service import get_project_statistics

    db = mcp_db(context)
    bid = mcp_bid(context)
    project_id = int(args["project_id"])
    project = ProjectRepository(db).get_by_id(project_id, load_relations=True)
    if not project or int(project.business_id) != bid:
        raise ValueError("پروژه در کسب‌وکار متصل یافت نشد")
    stats = mcp_run(get_project_statistics, db, project_id)
    return mcp_jsonable({"project": _public_project(project), "statistics": stats})


def register_mcp_ops19_functions(registry) -> None:
    from app.services.ai.function_registry import AIFunction, AIRole

    roles = {AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN}
    registry.register(
        AIFunction(
            name="list_business_currencies",
            description="ارز پیش‌فرض و ارزهای فعال کسب‌وکار متصل (بدون تکرار). برای فاکتور و پروژه از id همین فهرست استفاده کن.",
            parameters_schema=EMPTY,
            handler=list_business_currencies_handler,
            allowed_roles=roles,
            required_permissions=["settings.view"],
            category="financial",
            is_readonly=True,
        )
    )
    registry.register(
        AIFunction(
            name="get_project",
            description="جزئیات یک پروژه متعلق به کسب‌وکار متصل به‌همراه آمار اسناد (بدون extra_info).",
            parameters_schema=PROJECT_ID,
            handler=get_project_handler,
            allowed_roles=roles,
            required_permissions=["projects.view"],
            category="projects",
            is_readonly=True,
        )
    )
