"""MCP tools for person-group write cycle. Nested groups and extra keys are out of band."""
from __future__ import annotations

from typing import Any, Dict

from adapters.api.v1.schema_models.person_group import ALLOWED_PROFILE_DEFAULT_KEYS

CREATE_PERSON_GROUP_SCHEMA: Dict[str, Any] = {}
UPDATE_PERSON_GROUP_SCHEMA: Dict[str, Any] = {}


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


_PROFILE_DEFAULTS = {
    "type": "object",
    "additionalProperties": False,
    "properties": {
        key: {"type": ["string", "number", "boolean", "array", "null"]}
        for key in sorted(ALLOWED_PROFILE_DEFAULT_KEYS)
    },
}
_PROFILE_DEFAULTS["properties"]["legal_entity_type"] = {
    "anyOf": [
        {"type": "string", "enum": ["natural", "legal"]},
        {"type": "null"},
    ]
}
_PROFILE_DEFAULTS["properties"]["person_types"] = {
    "type": "array",
    "maxItems": 8,
    "items": {"type": "string", "minLength": 1, "maxLength": 40},
}
_PROFILE_DEFAULTS["properties"]["credit_limit"] = {"type": ["number", "null"], "minimum": 0}
_PROFILE_DEFAULTS["properties"]["credit_check_enabled"] = {"type": ["boolean", "null"]}

CREATE_PERSON_GROUP_SCHEMA = _schema(
    {
        "name": {"type": "string", "minLength": 1, "maxLength": 255},
        "code": {"type": ["integer", "null"], "minimum": 1},
        "description": {"type": ["string", "null"], "maxLength": 1000},
        "profile_defaults": _PROFILE_DEFAULTS,
        "sort_order": {"type": "integer", "minimum": 0, "maximum": 100000},
        "is_active": {"type": "boolean"},
    },
    ["name"],
)
UPDATE_PERSON_GROUP_SCHEMA = _schema(
    {
        "group_id": {"type": "integer", "minimum": 1},
        "name": {"type": "string", "minLength": 1, "maxLength": 255},
        "code": {"type": ["integer", "null"], "minimum": 1},
        "description": {"type": ["string", "null"], "maxLength": 1000},
        "profile_defaults": _PROFILE_DEFAULTS,
        "sort_order": {"type": "integer", "minimum": 0, "maximum": 100000},
        "is_active": {"type": "boolean"},
    },
    ["group_id"],
)
_GROUP_ID = _schema({"group_id": {"type": "integer", "minimum": 1}}, ["group_id"])


def get_person_group_handler(args, context):
    from app.services.person_group_service import get_person_group, serialize_person_group

    row = get_person_group(_db(context), _bid(context), int(args["group_id"]))
    if not row:
        raise ValueError("گروه اشخاص در کسب‌وکار متصل یافت نشد.")
    return serialize_person_group(row)


_GROUP_KEYS = ("name", "code", "description", "profile_defaults", "sort_order", "is_active")


def _group_payload(args: Dict[str, Any]) -> Dict[str, Any]:
    return {k: v for k, v in args.items() if k in _GROUP_KEYS}


def create_person_group_handler(args, context):
    from adapters.api.v1.schema_models.person_group import PersonGroupCreateRequest
    from app.services.person_group_service import create_person_group

    payload = PersonGroupCreateRequest(**_group_payload(args))
    return _run(create_person_group, _db(context), _bid(context), payload)


def update_person_group_handler(args, context):
    from adapters.api.v1.schema_models.person_group import PersonGroupUpdateRequest
    from app.services.person_group_service import update_person_group

    group_id = int(args["group_id"])
    payload = PersonGroupUpdateRequest(**_group_payload(args))
    result = _run(update_person_group, _db(context), _bid(context), group_id, payload)
    if result is None:
        raise ValueError("گروه اشخاص در کسب‌وکار متصل یافت نشد.")
    return result


def delete_person_group_handler(args, context):
    from app.services.person_group_service import delete_person_group

    group_id = int(args["group_id"])
    _run(delete_person_group, _db(context), _bid(context), group_id)
    return {"deleted": True, "group_id": group_id}


def register_mcp_person_group_functions(registry) -> None:
    from app.services.ai.function_registry import AIFunction, AIRole

    roles = {AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN}
    registry.register(AIFunction(
        name="get_person_group",
        description="جزئیات یک گروه اشخاص متعلق به کسب‌وکار متصل.",
        parameters_schema=_GROUP_ID,
        handler=get_person_group_handler,
        allowed_roles=roles,
        required_permissions=["persons.read"],
        category="persons",
        is_readonly=True,
    ))
    registry.register(AIFunction(
        name="create_person_group",
        description="ثبت گروه اشخاص سطح اول. والد تو در تو از MCP نیست. نیاز به تأیید.",
        parameters_schema=CREATE_PERSON_GROUP_SCHEMA,
        handler=create_person_group_handler,
        allowed_roles=roles,
        required_permissions=["persons.write"],
        category="persons",
        requires_approval=True,
        risk_level="medium",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="update_person_group",
        description="ویرایش نام، کد، قالب پیش‌فرض یا وضعیت گروه اشخاص کسب‌وکار متصل.",
        parameters_schema=UPDATE_PERSON_GROUP_SCHEMA,
        handler=update_person_group_handler,
        allowed_roles=roles,
        required_permissions=["persons.write"],
        category="persons",
        requires_approval=True,
        risk_level="medium",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="delete_person_group",
        description="حذف گروه خالی اشخاص. اگر شخصی منتسب باشد کل درخواست رد می‌شود. نیازمند تأیید.",
        parameters_schema=_GROUP_ID,
        handler=delete_person_group_handler,
        allowed_roles=roles,
        required_permissions=["people.delete"],
        category="persons",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
