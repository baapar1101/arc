"""Remaining customer-club MCP tools. Plugin must be active; tenant pinned; extra_info omitted."""
from __future__ import annotations

from typing import Any, Dict

from app.services.ai.ai_mcp_tool_util import mcp_bid, mcp_db, mcp_jsonable, mcp_run, mcp_schema, mcp_uid

REPLACE_CUSTOMER_CLUB_TIERS_SCHEMA: Dict[str, Any] = {}
SAVE_CUSTOMER_CLUB_REWARD_SCHEMA: Dict[str, Any] = {}
SAVE_CUSTOMER_CLUB_CAMPAIGN_SCHEMA: Dict[str, Any] = {}

_REWARD_TYPES = ["discount_amount", "discount_percent", "free_product", "wallet_credit"]
_TIER = {
    "type": "object",
    "additionalProperties": False,
    "required": ["name"],
    "properties": {
        "name": {"type": "string", "minLength": 1, "maxLength": 120},
        "sort_order": {"type": "integer"},
        "min_balance_points": {"type": "number", "minimum": 0},
        "min_rfm_normalized": {"type": ["number", "null"], "minimum": 0, "maximum": 1},
        "earn_multiplier": {"type": "number", "exclusiveMinimum": 0},
        "benefits": {"type": "array", "maxItems": 30, "items": {"type": "string", "maxLength": 240}},
    },
}
REPLACE_CUSTOMER_CLUB_TIERS_SCHEMA = mcp_schema(
    {"tiers": {"type": "array", "minItems": 0, "maxItems": 50, "items": _TIER}},
    ["tiers"],
)
SAVE_CUSTOMER_CLUB_REWARD_SCHEMA = mcp_schema(
    {
        "reward_id": {"type": "integer", "minimum": 1},
        "name": {"type": "string", "minLength": 1, "maxLength": 160},
        "reward_type": {"type": "string", "enum": _REWARD_TYPES},
        "points_cost": {"type": "number", "minimum": 0},
        "value": {"type": "number", "minimum": 0},
        "description": {"type": ["string", "null"], "maxLength": 4000},
        "product_id": {"type": ["integer", "null"], "minimum": 1},
        "valid_days": {"type": ["integer", "null"], "minimum": 1, "maximum": 3650},
        "max_issuances": {"type": ["integer", "null"], "minimum": 1},
        "active": {"type": "boolean"},
    },
    ["name"],
)
_REDEEM = mcp_schema(
    {"person_id": {"type": "integer", "minimum": 1}, "reward_id": {"type": "integer", "minimum": 1}},
    ["person_id", "reward_id"],
)
_PERSON = mcp_schema({"person_id": {"type": "integer", "minimum": 1}}, ["person_id"])
_CONSENT = mcp_schema(
    {
        "person_id": {"type": "integer", "minimum": 1},
        "sms_consent": {"type": "boolean"},
        "email_consent": {"type": "boolean"},
        "referral_code": {"type": ["string", "null"], "maxLength": 32},
    },
    ["person_id"],
)
_SURVEY = mcp_schema(
    {
        "person_id": {"type": "integer", "minimum": 1},
        "survey_key": {"type": "string", "minLength": 1, "maxLength": 80},
        "answers": {"type": "object"},
        "score": {"type": ["number", "null"]},
    },
    ["person_id", "survey_key"],
)
_SEGMENT = mcp_schema(
    {
        "filters": {"type": "object"},
        "limit": {"type": "integer", "minimum": 1, "maximum": 200},
    }
)
SAVE_CUSTOMER_CLUB_CAMPAIGN_SCHEMA = mcp_schema(
    {
        "campaign_id": {"type": "integer", "minimum": 1},
        "name": {"type": "string", "minLength": 1, "maxLength": 160},
        "description": {"type": ["string", "null"], "maxLength": 4000},
        "trigger_type": {"type": "string", "enum": ["manual", "purchase", "inactivity", "referral", "survey", "scheduled"]},
        "segment": {"type": "object"},
        "reward_type": {"type": "string", "enum": ["points", *_REWARD_TYPES]},
        "reward_value": {"type": "number", "minimum": 0},
        "min_purchase_amount": {"type": ["number", "null"], "minimum": 0},
        "reward_valid_days": {"type": ["integer", "null"], "minimum": 1, "maximum": 3650},
        "message_template": {"type": ["string", "null"], "maxLength": 1000},
        "channel": {"type": "string", "enum": ["none", "sms", "email"]},
        "status": {"type": "string", "enum": ["draft", "active", "paused", "completed"]},
        "starts_at": {"type": ["string", "null"]},
        "ends_at": {"type": ["string", "null"]},
    },
    ["name"],
)
_CAMPAIGN_ID = mcp_schema({"campaign_id": {"type": "integer", "minimum": 1}}, ["campaign_id"])
_VOUCHERS = mcp_schema({"person_id": {"type": "integer", "minimum": 1}})
_REWARD_KEYS = (
    "name",
    "reward_type",
    "points_cost",
    "value",
    "description",
    "product_id",
    "valid_days",
    "max_issuances",
    "active",
)
_CAMPAIGN_KEYS = (
    "name",
    "description",
    "trigger_type",
    "segment",
    "reward_type",
    "reward_value",
    "min_purchase_amount",
    "reward_valid_days",
    "message_template",
    "channel",
    "status",
    "starts_at",
    "ends_at",
)


def _ensure_club(context) -> None:
    from app.core.customer_club_plugin_dependency import check_customer_club_plugin_active

    if not check_customer_club_plugin_active(mcp_db(context), mcp_bid(context)):
        raise ValueError("افزونه باشگاه مشتریان برای این کسب‌وکار فعال نیست")


def list_customer_club_tiers_handler(args, context):
    from app.services.customer_club_service import list_tiers

    _ensure_club(context)
    return {"items": mcp_jsonable(mcp_run(list_tiers, mcp_db(context), mcp_bid(context)))}


def replace_customer_club_tiers_handler(args, context):
    from app.services.customer_club_service import replace_tiers

    _ensure_club(context)
    return {"items": mcp_jsonable(mcp_run(replace_tiers, mcp_db(context), mcp_bid(context), list(args.get("tiers") or [])))}


def list_customer_club_rewards_handler(args, context):
    from app.services.customer_club_program_service import list_rewards

    _ensure_club(context)
    return {"items": mcp_jsonable(mcp_run(list_rewards, mcp_db(context), mcp_bid(context)))}


def save_customer_club_reward_handler(args, context):
    from app.services.customer_club_program_service import save_reward

    _ensure_club(context)
    payload = {k: v for k, v in args.items() if k in _REWARD_KEYS}
    return mcp_jsonable(
        mcp_run(save_reward, mcp_db(context), mcp_bid(context), payload, args.get("reward_id"))
    )


def redeem_customer_club_reward_handler(args, context):
    from app.services.customer_club_program_service import redeem_reward

    _ensure_club(context)
    return mcp_jsonable(
        mcp_run(redeem_reward, mcp_db(context), mcp_bid(context), int(args["person_id"]), int(args["reward_id"]))
    )


def list_customer_club_vouchers_handler(args, context):
    from app.services.customer_club_program_service import list_vouchers

    _ensure_club(context)
    return {
        "items": mcp_jsonable(
            mcp_run(list_vouchers, mcp_db(context), mcp_bid(context), args.get("person_id"))
        )
    }


def set_customer_club_consent_handler(args, context):
    from app.services.customer_club_program_service import set_member_consent

    _ensure_club(context)
    payload = {k: v for k, v in args.items() if k in ("sms_consent", "email_consent", "referral_code")}
    return mcp_jsonable(
        mcp_run(set_member_consent, mcp_db(context), mcp_bid(context), int(args["person_id"]), payload)
    )


def submit_customer_club_survey_handler(args, context):
    from app.services.customer_club_program_service import submit_survey_response

    _ensure_club(context)
    payload = {k: v for k, v in args.items() if k in ("survey_key", "answers", "score")}
    return mcp_jsonable(
        mcp_run(submit_survey_response, mcp_db(context), mcp_bid(context), int(args["person_id"]), payload)
    )


def get_customer_club_member_profile_handler(args, context):
    from app.services.customer_club_program_service import list_member_profile

    _ensure_club(context)
    return mcp_jsonable(mcp_run(list_member_profile, mcp_db(context), mcp_bid(context), int(args["person_id"])))


def preview_customer_club_segment_handler(args, context):
    from app.services.customer_club_program_service import preview_segment

    _ensure_club(context)
    filters = args.get("filters") or {}
    if not isinstance(filters, dict):
        raise ValueError("filters باید شیء باشد")
    return mcp_jsonable(
        mcp_run(preview_segment, mcp_db(context), mcp_bid(context), filters, int(args.get("limit") or 100))
    )


def list_customer_club_campaigns_handler(args, context):
    from app.services.customer_club_program_service import list_campaigns

    _ensure_club(context)
    return {"items": mcp_jsonable(mcp_run(list_campaigns, mcp_db(context), mcp_bid(context)))}


def save_customer_club_campaign_handler(args, context):
    from app.services.customer_club_program_service import save_campaign

    _ensure_club(context)
    payload = {k: v for k, v in args.items() if k in _CAMPAIGN_KEYS}
    return mcp_jsonable(
        mcp_run(
            save_campaign,
            mcp_db(context),
            mcp_bid(context),
            payload,
            mcp_uid(context),
            args.get("campaign_id"),
        )
    )


def run_customer_club_campaign_handler(args, context):
    from app.services.customer_club_program_service import run_campaign

    _ensure_club(context)
    return mcp_jsonable(mcp_run(run_campaign, mcp_db(context), mcp_bid(context), int(args["campaign_id"])))


def get_customer_club_campaign_stats_handler(args, context):
    from app.services.customer_club_program_service import campaign_stats

    _ensure_club(context)
    return mcp_jsonable(mcp_run(campaign_stats, mcp_db(context), mcp_bid(context), int(args["campaign_id"])))


def register_mcp_club_extra_functions(registry) -> None:
    from app.services.ai.function_registry import AIFunction, AIRole

    roles = {AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN}
    registry.register(AIFunction(
        name="replace_customer_club_tiers",
        description="جایگزینی کامل سطح‌های باشگاه مشتریان. نیازمند تأیید.",
        parameters_schema=REPLACE_CUSTOMER_CLUB_TIERS_SCHEMA,
        handler=replace_customer_club_tiers_handler,
        allowed_roles=roles,
        required_permissions=["customer_club.write"],
        category="persons",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="list_customer_club_rewards",
        description="فهرست جوایز باشگاه مشتریان کسب‌وکار متصل.",
        parameters_schema=mcp_schema({}),
        handler=list_customer_club_rewards_handler,
        allowed_roles=roles,
        required_permissions=["customer_club.view"],
        category="persons",
        is_readonly=True,
    ))
    registry.register(AIFunction(
        name="save_customer_club_reward",
        description="ایجاد یا ویرایش جایزه باشگاه. اگر reward_id باشد ویرایش است.",
        parameters_schema=SAVE_CUSTOMER_CLUB_REWARD_SCHEMA,
        handler=save_customer_club_reward_handler,
        allowed_roles=roles,
        required_permissions=["customer_club.write"],
        category="persons",
        requires_approval=True,
        risk_level="medium",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="redeem_customer_club_reward",
        description="مصرف امتیاز عضو برای جایزه. نیازمند تأیید.",
        parameters_schema=_REDEEM,
        handler=redeem_customer_club_reward_handler,
        allowed_roles=roles,
        required_permissions=["customer_club.redeem"],
        category="persons",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="list_customer_club_vouchers",
        description="کوپن‌های صادرشده باشگاه مشتریان. اختیاری فیلتر شخص.",
        parameters_schema=_VOUCHERS,
        handler=list_customer_club_vouchers_handler,
        allowed_roles=roles,
        required_permissions=["customer_club.view"],
        category="persons",
        is_readonly=True,
    ))
    registry.register(AIFunction(
        name="set_customer_club_consent",
        description="ثبت رضایت پیامک/ایمیل و کد معرف عضو باشگاه.",
        parameters_schema=_CONSENT,
        handler=set_customer_club_consent_handler,
        allowed_roles=roles,
        required_permissions=["customer_club.write"],
        category="persons",
        requires_approval=True,
        risk_level="medium",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="submit_customer_club_survey",
        description="ثبت پاسخ نظرسنجی عضو باشگاه مشتریان.",
        parameters_schema=_SURVEY,
        handler=submit_customer_club_survey_handler,
        allowed_roles=roles,
        required_permissions=["customer_club.write"],
        category="persons",
        requires_approval=True,
        risk_level="medium",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="get_customer_club_member_profile",
        description="پروفایل باشگاهی یک شخص متعلق به کسب‌وکار متصل.",
        parameters_schema=_PERSON,
        handler=get_customer_club_member_profile_handler,
        allowed_roles=roles,
        required_permissions=["customer_club.view"],
        category="persons",
        is_readonly=True,
    ))
    registry.register(AIFunction(
        name="preview_customer_club_segment",
        description="پیش‌نمایش اعضای یک سگمنت باشگاه. حداکثر ۲۰۰ نفر.",
        parameters_schema=_SEGMENT,
        handler=preview_customer_club_segment_handler,
        allowed_roles=roles,
        required_permissions=["customer_club.view"],
        category="persons",
        is_readonly=True,
    ))
    registry.register(AIFunction(
        name="list_customer_club_campaigns",
        description="فهرست کمپین‌های باشگاه مشتریان کسب‌وکار متصل.",
        parameters_schema=mcp_schema({}),
        handler=list_customer_club_campaigns_handler,
        allowed_roles=roles,
        required_permissions=["customer_club.view"],
        category="persons",
        is_readonly=True,
    ))
    registry.register(AIFunction(
        name="save_customer_club_campaign",
        description="ایجاد یا ویرایش کمپین باشگاه. اگر campaign_id باشد ویرایش است.",
        parameters_schema=SAVE_CUSTOMER_CLUB_CAMPAIGN_SCHEMA,
        handler=save_customer_club_campaign_handler,
        allowed_roles=roles,
        required_permissions=["customer_club.write"],
        category="persons",
        requires_approval=True,
        risk_level="medium",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="run_customer_club_campaign",
        description="اجرای کمپین دستی باشگاه مشتریان. نیازمند تأیید.",
        parameters_schema=_CAMPAIGN_ID,
        handler=run_customer_club_campaign_handler,
        allowed_roles=roles,
        required_permissions=["customer_club.write"],
        category="persons",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="get_customer_club_campaign_stats",
        description="آمار اجرای یک کمپین باشگاه مشتریان.",
        parameters_schema=_CAMPAIGN_ID,
        handler=get_customer_club_campaign_stats_handler,
        allowed_roles=roles,
        required_permissions=["customer_club.view"],
        category="persons",
        is_readonly=True,
    ))
