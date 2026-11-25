"""MCP write tools for received loan facilities. get/update/delete pin tenant because some services load by id."""
from __future__ import annotations

from typing import Any, Dict

from app.services.ai.ai_mcp_tool_util import mcp_bid, mcp_db, mcp_jsonable, mcp_run, mcp_schema, mcp_uid

CREATE_LOAN_FACILITY_SCHEMA: Dict[str, Any] = {}
UPDATE_LOAN_FACILITY_SCHEMA: Dict[str, Any] = {}
REGENERATE_LOAN_SCHEDULE_SCHEMA: Dict[str, Any] = {}
RECORD_LOAN_PAYMENT_SCHEMA: Dict[str, Any] = {}

CREATE_LOAN_FACILITY_SCHEMA = mcp_schema(
    {
        "title": {"type": "string", "minLength": 1, "maxLength": 255},
        "currency_id": {"type": "integer", "minimum": 1},
        "principal_amount": {"type": "number", "exclusiveMinimum": 0},
        "contract_date": {"type": "string", "description": "ISO date YYYY-MM-DD"},
        "lender_bank_account_id": {"type": ["integer", "null"], "minimum": 1},
        "annual_interest_rate_percent": {"type": ["number", "null"], "minimum": 0},
        "first_installment_date": {"type": ["string", "null"]},
        "installment_count": {"type": ["integer", "null"], "minimum": 1, "maximum": 600},
        "notes": {"type": ["string", "null"], "maxLength": 4000},
    },
    ["title", "currency_id", "principal_amount", "contract_date"],
)
_CREATE_KEYS = (
    "title",
    "currency_id",
    "principal_amount",
    "contract_date",
    "lender_bank_account_id",
    "annual_interest_rate_percent",
    "first_installment_date",
    "installment_count",
    "notes",
)
UPDATE_LOAN_FACILITY_SCHEMA = mcp_schema(
    {
        "facility_id": {"type": "integer", "minimum": 1},
        **{k: v for k, v in CREATE_LOAN_FACILITY_SCHEMA["properties"].items()},
    },
    ["facility_id"],
)
_FACILITY_ID = mcp_schema({"facility_id": {"type": "integer", "minimum": 1}}, ["facility_id"])
REGENERATE_LOAN_SCHEDULE_SCHEMA = mcp_schema(
    {
        "facility_id": {"type": "integer", "minimum": 1},
        "schedule_method": {"type": "string", "enum": ["annuity", "equal_principal"]},
        "installment_count": {"type": "integer", "minimum": 1, "maximum": 600},
        "first_installment_date": {"type": "string"},
    },
    ["facility_id"],
)
RECORD_LOAN_PAYMENT_SCHEMA = mcp_schema(
    {
        "facility_id": {"type": "integer", "minimum": 1},
        "installment_id": {"type": "integer", "minimum": 1},
        "amount": {"type": "number", "exclusiveMinimum": 0},
        "payment_date": {"type": "string"},
        "bank_account_id": {"type": ["integer", "null"], "minimum": 1},
        "post_accounting_payment": {"type": "boolean"},
        "notes": {"type": ["string", "null"], "maxLength": 2000},
    },
    ["facility_id", "installment_id", "amount"],
)
_PAY_ID = mcp_schema(
    {
        "facility_id": {"type": "integer", "minimum": 1},
        "installment_id": {"type": "integer", "minimum": 1},
        "payment_id": {"type": "integer", "minimum": 1},
    },
    ["facility_id", "installment_id", "payment_id"],
)


def _load_facility(db, business_id: int, facility_id: int, *, with_installments: bool = False):
    from app.services.received_loan_facility_service import get_facility_by_id

    data = get_facility_by_id(db, int(facility_id), with_installments=with_installments)
    if not data or int(data.get("business_id") or 0) != int(business_id):
        raise ValueError("تسهیل یافت نشد")
    return data


def create_loan_facility_handler(args, context):
    from app.services.received_loan_facility_service import create_facility

    data = {k: v for k, v in args.items() if k in _CREATE_KEYS}
    return mcp_jsonable(mcp_run(create_facility, mcp_db(context), mcp_bid(context), mcp_uid(context), data))


def update_loan_facility_handler(args, context):
    from app.services.received_loan_facility_service import update_facility

    bid = mcp_bid(context)
    _load_facility(mcp_db(context), bid, int(args["facility_id"]))
    data = {k: v for k, v in args.items() if k in _CREATE_KEYS}
    result = mcp_run(update_facility, mcp_db(context), int(args["facility_id"]), data)
    if not result or int(result.get("business_id") or 0) != bid:
        raise ValueError("تسهیل یافت نشد")
    return mcp_jsonable(result)


def delete_loan_facility_handler(args, context):
    from app.services.received_loan_facility_service import delete_facility

    ok = mcp_run(delete_facility, mcp_db(context), int(args["facility_id"]), mcp_bid(context))
    if not ok:
        raise ValueError("تسهیل یافت نشد یا قابل حذف نیست")
    return {"deleted": True, "id": int(args["facility_id"])}


def regenerate_loan_schedule_handler(args, context):
    from app.services.received_loan_facility_service import regenerate_schedule

    bid = mcp_bid(context)
    _load_facility(mcp_db(context), bid, int(args["facility_id"]))
    data = {k: args[k] for k in ("schedule_method", "installment_count", "first_installment_date") if k in args}
    return mcp_jsonable(
        mcp_run(regenerate_schedule, mcp_db(context), int(args["facility_id"]), data, mcp_uid(context))
    )


def record_loan_payment_handler(args, context):
    from app.services.received_loan_facility_service import record_payment

    payload = {k: v for k, v in args.items() if k in ("amount", "payment_date", "bank_account_id", "post_accounting_payment", "notes")}
    return mcp_jsonable(
        mcp_run(
            record_payment,
            mcp_db(context),
            mcp_bid(context),
            mcp_uid(context),
            int(args["facility_id"]),
            int(args["installment_id"]),
            payload,
        )
    )


def delete_loan_payment_handler(args, context):
    from app.services.received_loan_facility_service import delete_loan_payment

    return mcp_jsonable(
        mcp_run(
            delete_loan_payment,
            mcp_db(context),
            mcp_bid(context),
            int(args["facility_id"]),
            int(args["installment_id"]),
            int(args["payment_id"]),
        )
    )


def register_mcp_loan_functions(registry) -> None:
    from app.services.ai.function_registry import AIFunction, AIRole

    roles = {AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN}
    registry.register(AIFunction(
        name="create_loan_facility",
        description="ثبت تسهیل دریافتی پیش‌نویس در کسب‌وکار متصل. ارز و حساب بانک باید متعلق به همین کسب‌وکار باشند.",
        parameters_schema=CREATE_LOAN_FACILITY_SCHEMA,
        handler=create_loan_facility_handler,
        allowed_roles=roles,
        required_permissions=["loan_facilities.write"],
        category="financial",
        requires_approval=True,
        risk_level="medium",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="update_loan_facility",
        description="ویرایش تسهیل متعلق به کسب‌وکار متصل. پس از فعال‌سازی جدول اقساط فیلدهای مالی قفل می‌شوند.",
        parameters_schema=UPDATE_LOAN_FACILITY_SCHEMA,
        handler=update_loan_facility_handler,
        allowed_roles=roles,
        required_permissions=["loan_facilities.write"],
        category="financial",
        requires_approval=True,
        risk_level="medium",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="delete_loan_facility",
        description="حذف تسهیل دریافتی متعلق به کسب‌وکار متصل. نیازمند تأیید.",
        parameters_schema=_FACILITY_ID,
        handler=delete_loan_facility_handler,
        allowed_roles=roles,
        required_permissions=["loan_facilities.delete"],
        category="financial",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="regenerate_loan_schedule",
        description="ساخت یا بازسازی جدول اقساط تسهیل. پس از ثبت پرداخت مجاز نیست.",
        parameters_schema=REGENERATE_LOAN_SCHEDULE_SCHEMA,
        handler=regenerate_loan_schedule_handler,
        allowed_roles=roles,
        required_permissions=["loan_facilities.write"],
        category="financial",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="record_loan_payment",
        description="ثبت پرداخت قسط تسهیل متعلق به کسب‌وکار متصل. می‌تواند سند حسابداری بسازد.",
        parameters_schema=RECORD_LOAN_PAYMENT_SCHEMA,
        handler=record_loan_payment_handler,
        allowed_roles=roles,
        required_permissions=["loan_facilities.write"],
        category="financial",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="delete_loan_payment",
        description="حذف پرداخت قسط تسهیل در سال مالی جاری. نیازمند تأیید.",
        parameters_schema=_PAY_ID,
        handler=delete_loan_payment_handler,
        allowed_roles=roles,
        required_permissions=["loan_facilities.delete"],
        category="financial",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
