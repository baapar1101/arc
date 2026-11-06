"""MCP tools for period-end FX revaluation documents."""
from __future__ import annotations

from datetime import date, datetime

from app.services.ai.ai_mcp_tool_util import mcp_bid, mcp_db, mcp_jsonable, mcp_run, mcp_schema, mcp_uid

PREVIEW_SCHEMA = mcp_schema(
    {
        "fiscal_year_id": {"type": "integer", "minimum": 1},
        "as_of": {"type": "string", "description": "ISO datetime ارزشیابی"},
    }
)
CREATE_SCHEMA = mcp_schema(
    {
        "fiscal_year_id": {"type": "integer", "minimum": 1},
        "as_of": {"type": "string"},
        "document_date": {"type": "string", "description": "YYYY-MM-DD"},
        "description": {"type": ["string", "null"], "maxLength": 500},
    }
)


def _as_of(raw):
    if not raw:
        return None
    return datetime.fromisoformat(str(raw).replace("Z", "+00:00"))


def preview_period_end_fx_revaluation_handler(args, context):
    from app.services.period_end_fx_revaluation_service import preview_period_end_fx_revaluation

    return mcp_jsonable(
        mcp_run(
            preview_period_end_fx_revaluation,
            mcp_db(context),
            mcp_bid(context),
            fiscal_year_id=args.get("fiscal_year_id"),
            as_of=_as_of(args.get("as_of")),
        )
    )


def create_period_end_fx_revaluation_handler(args, context):
    from app.services.period_end_fx_revaluation_service import create_period_end_fx_revaluation_document

    doc_date = None
    if args.get("document_date"):
        doc_date = date.fromisoformat(str(args["document_date"])[:10])
    return mcp_jsonable(
        mcp_run(
            create_period_end_fx_revaluation_document,
            mcp_db(context),
            mcp_bid(context),
            mcp_uid(context),
            fiscal_year_id=args.get("fiscal_year_id"),
            as_of=_as_of(args.get("as_of")),
            document_date=doc_date,
            description=args.get("description"),
        )
    )


def register_mcp_period_fx_functions(registry) -> None:
    from app.services.ai.function_registry import AIFunction, AIRole

    roles = {AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN}
    registry.register(AIFunction(
        name="preview_period_end_fx_revaluation",
        description="پیش‌نمایش اقلام تسعیر پایان دوره برای حساب‌های پولی کسب‌وکار چندارزی. سندی ساخته نمی‌شود.",
        parameters_schema=PREVIEW_SCHEMA,
        handler=preview_period_end_fx_revaluation_handler,
        allowed_roles=roles,
        required_permissions=["currency_revaluation.view"],
        category="accounting",
        is_readonly=True,
    ))
    registry.register(AIFunction(
        name="create_period_end_fx_revaluation",
        description="ایجاد سند دستی تسعیر پایان دوره از پیش‌نمایش جاری. سند قابل بازبینی است. نیازمند تأیید.",
        parameters_schema=CREATE_SCHEMA,
        handler=create_period_end_fx_revaluation_handler,
        allowed_roles=roles,
        required_permissions=["currency_revaluation.add"],
        category="accounting",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
