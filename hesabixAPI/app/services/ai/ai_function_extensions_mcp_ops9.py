"""MCP leftovers: distribution team/plan/offline sync and currency usage-check."""
from __future__ import annotations

from datetime import date

from app.services.ai.ai_mcp_tool_util import mcp_bid, mcp_db, mcp_jsonable, mcp_run, mcp_schema, mcp_uid

EMPTY = mcp_schema({})
UNPUBLISH = mcp_schema(
    {
        "plan_date": {"type": "string"},
        "target_user_id": {"type": "integer", "minimum": 1},
    }
)
SYNC = mcp_schema(
    {
        "client_batch_id": {"type": "string", "maxLength": 64},
        "actions": {"type": "array", "minItems": 1, "maxItems": 50, "items": {"type": "object"}},
    },
    ["actions"],
)
CUR_ID = mcp_schema({"currency_id": {"type": "integer", "minimum": 1}}, ["currency_id"])


def _plugin(db, bid: int) -> None:
    from app.core.distribution_plugin_dependency import check_distribution_plugin_active

    if not check_distribution_plugin_active(db, int(bid)):
        raise ValueError("افزونه توزیع برای این کسب‌وکار فعال نیست")


def list_distribution_team_members_handler(args, context):
    from app.services.distribution_service import list_team_members

    db, bid = mcp_db(context), mcp_bid(context)
    _plugin(db, bid)
    return mcp_jsonable({"items": mcp_run(list_team_members, db, bid, context.get("user_context"))})


def get_distribution_my_preferences_handler(args, context):
    from app.services.distribution_service import get_user_preference, preference_to_dict

    db, bid, uid = mcp_db(context), mcp_bid(context), mcp_uid(context)
    _plugin(db, bid)
    row = mcp_run(get_user_preference, db, bid, uid)
    if not row:
        return {"user_id": uid, "location_consent": False, "location_consent_at": None}
    return mcp_jsonable(preference_to_dict(row))


def unpublish_distribution_daily_plan_handler(args, context):
    from app.core.business_calendar import business_today
    from app.services.distribution_service import unpublish_daily_plan

    db, bid = mcp_db(context), mcp_bid(context)
    _plugin(db, bid)
    uid = mcp_uid(context)
    target = int(args["target_user_id"]) if args.get("target_user_id") else uid
    day = date.fromisoformat(str(args["plan_date"])) if args.get("plan_date") else business_today(bid)
    mcp_run(unpublish_daily_plan, db, bid, target, day, ctx=context.get("user_context"))
    return {"ok": True, "plan_date": day.isoformat(), "target_user_id": target}


def sync_distribution_offline_handler(args, context):
    from app.services.distribution_phase3_service import process_offline_sync

    db, bid = mcp_db(context), mcp_bid(context)
    _plugin(db, bid)
    actions = list(args.get("actions") or [])[:50]
    return mcp_jsonable(
        mcp_run(
            process_offline_sync,
            db,
            bid,
            mcp_uid(context),
            str(args.get("client_batch_id") or ""),
            actions,
            context.get("user_context"),
        )
    )


def check_business_currency_usage_handler(args, context):
    from app.services.business_service import get_business_currency_usage

    return mcp_jsonable(mcp_run(get_business_currency_usage, mcp_db(context), mcp_bid(context), int(args["currency_id"])))


def register_mcp_ops9_functions(registry) -> None:
    from app.services.ai.function_registry import AIFunction, AIRole

    roles = {AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN}
    registry.register(AIFunction(name="list_distribution_team_members", description="ویزیتورها و ناظران قابل مشاهده برای تخصیص مسیر و برنامه روزانه.", parameters_schema=EMPTY, handler=list_distribution_team_members_handler, allowed_roles=roles, required_permissions=["distribution.view"], category="distribution", is_readonly=True))
    registry.register(AIFunction(name="get_distribution_my_preferences", description="ترجیح اشتراک موقعیت زنده کاربر جاری در افزونه توزیع.", parameters_schema=EMPTY, handler=get_distribution_my_preferences_handler, allowed_roles=roles, required_permissions=["distribution.view"], category="distribution", is_readonly=True))
    registry.register(AIFunction(name="unpublish_distribution_daily_plan", description="لغو نشر برنامه روزانه ویزیتور. نیازمند تأیید.", parameters_schema=UNPUBLISH, handler=unpublish_distribution_daily_plan_handler, allowed_roles=roles, required_permissions=["distribution.manage"], category="distribution", requires_approval=True, risk_level="medium", is_readonly=False))
    registry.register(AIFunction(name="sync_distribution_offline", description="اعمال دسته اقدامات آفلاین ویزیتور (حداکثر ۵۰). نیازمند تأیید.", parameters_schema=SYNC, handler=sync_distribution_offline_handler, allowed_roles=roles, required_permissions=["distribution.operate"], category="distribution", requires_approval=True, risk_level="high", is_readonly=False))
    registry.register(AIFunction(name="check_business_currency_usage", description="آیا ارز جانبی در اسناد کسب‌وکار متصل استفاده شده و قابل حذف است.", parameters_schema=CUR_ID, handler=check_business_currency_usage_handler, allowed_roles=roles, required_permissions=["settings.business"], category="business", is_readonly=True))
