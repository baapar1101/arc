"""MCP leftovers: CRM deal lines read + repair-shop plugin status."""
from __future__ import annotations

from app.services.ai.ai_mcp_tool_util import mcp_bid, mcp_db, mcp_jsonable, mcp_run, mcp_schema

EMPTY = mcp_schema({})
DEAL_ID = mcp_schema({"deal_id": {"type": "integer", "minimum": 1}}, ["deal_id"])


def list_crm_deal_lines_handler(args, context):
    from app.services.crm_deal_line_service import list_lines

    items = mcp_run(list_lines, mcp_db(context), mcp_bid(context), int(args["deal_id"]))
    return mcp_jsonable({"items": items[:100], "truncated": len(items) > 100})


def get_repair_shop_plugin_status_handler(args, context):
    from app.core.repair_shop_plugin_dependency import get_business_plugin_status

    return mcp_jsonable(get_business_plugin_status(mcp_db(context), mcp_bid(context)))


def register_mcp_ops16_functions(registry) -> None:
    from app.services.ai.function_registry import AIFunction, AIRole

    roles = {AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN}
    registry.register(AIFunction(name="list_crm_deal_lines", description="خطوط کالا/خدمت یک فرصت فروش در کسب‌وکار متصل (حداکثر ۱۰۰).", parameters_schema=DEAL_ID, handler=list_crm_deal_lines_handler, allowed_roles=roles, required_permissions=["crm.view"], category="crm", is_readonly=True))
    registry.register(AIFunction(name="get_repair_shop_plugin_status", description="وضعیت لایسنس افزونه تعمیرگاه برای کسب‌وکار متصل.", parameters_schema=EMPTY, handler=get_repair_shop_plugin_status_handler, allowed_roles=roles, required_permissions=["repair_shop.read"], category="repair", is_readonly=True))
