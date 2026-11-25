"""MCP tools for business credit settings, installment plans, and per-person limits."""
from __future__ import annotations

from typing import Any, Dict

UPDATE_CREDIT_SETTINGS_SCHEMA: Dict[str, Any] = {}
CREATE_INSTALLMENT_PLAN_SCHEMA: Dict[str, Any] = {}
UPDATE_INSTALLMENT_PLAN_SCHEMA: Dict[str, Any] = {}
UPDATE_PERSON_CREDIT_SCHEMA: Dict[str, Any] = {}


def _schema(properties: Dict[str, Any], required: list[str] | None = None) -> Dict[str, Any]:
    return {
        "type": "object",
        "properties": properties,
        "required": list(required or []),
        "additionalProperties": False,
    }


def _raise_service(exc: BaseException) -> None:
    from app.core.responses import ApiError

    if isinstance(exc, ApiError):
        raise ValueError(exc.message) from exc
    raise exc


def _run(fn, *args, **kwargs):
    try:
        return fn(*args, **kwargs)
    except Exception as exc:
        _raise_service(exc)


def _bid(context: Dict[str, Any]) -> int:
    return int(context["business_id"])


def _db(context: Dict[str, Any]):
    return context["db"]


UPDATE_CREDIT_SETTINGS_SCHEMA = _schema(
    {
        "is_enabled": {"type": "boolean"},
        "default_limit": {"type": ["number", "null"], "minimum": 0},
        "grace_days": {"type": ["integer", "null"], "minimum": 0, "maximum": 3650},
        "late_fee_rate": {"type": ["number", "null"], "minimum": 0, "maximum": 100},
        "auto_block_after_days": {"type": ["integer", "null"], "minimum": 0, "maximum": 3650},
        "strategy": {"type": "string", "enum": ["single-default", "by-group", "per-user"]},
    }
)
_PLAN_FIELDS = {
    "name": {"type": "string", "minLength": 1, "maxLength": 160},
    "method": {"type": "string", "enum": ["flat", "amortized"]},
    "num_installments": {"type": "integer", "minimum": 1, "maximum": 360},
    "period_days": {"type": "integer", "minimum": 1, "maximum": 3650},
    "down_payment_percent": {"type": ["number", "null"], "minimum": 0, "maximum": 100},
    "interest_rate": {"type": ["number", "null"], "minimum": 0, "maximum": 100},
    "late_fee_rate": {"type": ["number", "null"], "minimum": 0, "maximum": 100},
    "issue_fee": {"type": ["number", "null"], "minimum": 0},
    "description": {"type": ["string", "null"], "maxLength": 1000},
    "is_active": {"type": "boolean"},
}
CREATE_INSTALLMENT_PLAN_SCHEMA = _schema(dict(_PLAN_FIELDS), ["name", "num_installments"])
UPDATE_INSTALLMENT_PLAN_SCHEMA = _schema(
    {"plan_id": {"type": "integer", "minimum": 1}, **_PLAN_FIELDS},
    ["plan_id"],
)
_PLAN_ID = _schema({"plan_id": {"type": "integer", "minimum": 1}}, ["plan_id"])
UPDATE_PERSON_CREDIT_SCHEMA = _schema(
    {
        "person_id": {"type": "integer", "minimum": 1},
        "credit_limit": {"type": ["number", "null"], "minimum": 0},
        "credit_check_enabled": {"type": ["boolean", "null"]},
    },
    ["person_id"],
)


_CREDIT_SETTING_KEYS = (
    "is_enabled",
    "default_limit",
    "grace_days",
    "late_fee_rate",
    "auto_block_after_days",
    "strategy",
)
_PLAN_KEYS = tuple(_PLAN_FIELDS)
_PERSON_CREDIT_KEYS = ("credit_limit", "credit_check_enabled")


def _picked(args: Dict[str, Any], keys) -> Dict[str, Any]:
    return {k: v for k, v in args.items() if k in keys}


def update_credit_settings_handler(args, context):
    from app.services.credit_service import update_business_credit_settings

    return _run(
        update_business_credit_settings,
        _db(context),
        _bid(context),
        _picked(args, _CREDIT_SETTING_KEYS),
    )


def get_credit_installment_plan_handler(args, context):
    from app.services.credit_service import get_installment_plan

    return _run(get_installment_plan, _db(context), _bid(context), int(args["plan_id"]))


def create_credit_installment_plan_handler(args, context):
    from app.services.credit_service import create_installment_plan

    return _run(
        create_installment_plan,
        _db(context),
        _bid(context),
        _picked(args, _PLAN_KEYS),
    )


def update_credit_installment_plan_handler(args, context):
    from app.services.credit_service import update_installment_plan

    return _run(
        update_installment_plan,
        _db(context),
        _bid(context),
        int(args["plan_id"]),
        _picked(args, _PLAN_KEYS),
    )


def delete_credit_installment_plan_handler(args, context):
    from app.services.credit_service import delete_installment_plan

    _run(delete_installment_plan, _db(context), _bid(context), int(args["plan_id"]))
    return {"deleted": True, "plan_id": int(args["plan_id"])}


def update_person_credit_handler(args, context):
    from app.services.credit_service import update_person_credit

    db = _db(context)
    payload = _picked(args, _PERSON_CREDIT_KEYS)
    result = _run(update_person_credit, db, _bid(context), int(args["person_id"]), payload)
    db.commit()
    return result


def register_mcp_credit_functions(registry) -> None:
    from app.services.ai.function_registry import AIFunction, AIRole

    roles = {AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN}
    registry.register(AIFunction(
        name="update_credit_settings",
        description="ویرایش سقف اعتبار پیش‌فرض، مهلت و استراتژی اعتبار کسب‌وکار متصل. نیاز به تأیید.",
        parameters_schema=UPDATE_CREDIT_SETTINGS_SCHEMA,
        handler=update_credit_settings_handler,
        allowed_roles=roles,
        required_permissions=["credit.write"],
        category="credit",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="get_credit_installment_plan",
        description="جزئیات یک طرح اقساط متعلق به کسب‌وکار متصل.",
        parameters_schema=_PLAN_ID,
        handler=get_credit_installment_plan_handler,
        allowed_roles=roles,
        required_permissions=["credit.view"],
        category="credit",
        is_readonly=True,
    ))
    registry.register(AIFunction(
        name="create_credit_installment_plan",
        description="ثبت طرح اقساط اعتباری. name و تعداد قسط الزامی است. نیاز به تأیید.",
        parameters_schema=CREATE_INSTALLMENT_PLAN_SCHEMA,
        handler=create_credit_installment_plan_handler,
        allowed_roles=roles,
        required_permissions=["credit.write"],
        category="credit",
        requires_approval=True,
        risk_level="medium",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="update_credit_installment_plan",
        description="ویرایش طرح اقساط متعلق به کسب‌وکار متصل.",
        parameters_schema=UPDATE_INSTALLMENT_PLAN_SCHEMA,
        handler=update_credit_installment_plan_handler,
        allowed_roles=roles,
        required_permissions=["credit.write"],
        category="credit",
        requires_approval=True,
        risk_level="medium",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="delete_credit_installment_plan",
        description="حذف طرح اقساط کسب‌وکار متصل. نیازمند تأیید.",
        parameters_schema=_PLAN_ID,
        handler=delete_credit_installment_plan_handler,
        allowed_roles=roles,
        required_permissions=["credit.write"],
        category="credit",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="update_person_credit",
        description="تنظیم سقف اعتبار یا فعال‌سازی بررسی اعتبار یک شخص متعلق به کسب‌وکار متصل. نیاز به تأیید.",
        parameters_schema=UPDATE_PERSON_CREDIT_SCHEMA,
        handler=update_person_credit_handler,
        allowed_roles=roles,
        required_permissions=["persons.write"],
        category="credit",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
