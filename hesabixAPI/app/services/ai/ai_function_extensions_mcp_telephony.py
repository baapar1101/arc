"""MCP tools for Asterisk/Issabel telephony — business ops, no connector/token/media."""
from __future__ import annotations

from typing import Any, Dict

UPDATE_TELEPHONY_SETTINGS_SCHEMA: Dict[str, Any] = {}
CLICK_TO_CALL_SCHEMA: Dict[str, Any] = {}


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


def _ensure_plugin(db, business_id: int) -> None:
    from app.core.telephony_plugin_dependency import check_telephony_plugin_active

    if not check_telephony_plugin_active(db, int(business_id)):
        raise ValueError("افزونه تلفن Asterisk/Issabel برای این کسب‌وکار فعال نیست.")


def _run(fn, *args, **kwargs):
    try:
        return fn(*args, **kwargs)
    except Exception as exc:
        _raise_service(exc)


def _ctx(context):
    return context["db"], int(context["business_id"]), int(context["user_context"].get_user_id())


def _redact_pbx(item: Dict[str, Any]) -> Dict[str, Any]:
    data = dict(item)
    data.pop("connector_token", None)
    data.pop("install_hint", None)
    data.pop("settings", None)
    return data


def _redact_dashboard(payload: Dict[str, Any]) -> Dict[str, Any]:
    data = dict(payload)
    rows = data.get("pbx_connections")
    if isinstance(rows, list):
        data["pbx_connections"] = [_redact_pbx(row) if isinstance(row, dict) else row for row in rows]
    return data


UPDATE_TELEPHONY_SETTINGS_SCHEMA = _schema(
    {
        "primary_phone_fields": {"type": "array", "maxItems": 12, "items": {"type": "string", "minLength": 1, "maxLength": 40}},
        "screen_pop_enabled": {"type": "boolean"},
        "auto_create_activity": {"type": "boolean"},
        "post_call_form_required": {"type": "boolean"},
        "default_category": {"type": ["string", "null"], "maxLength": 80},
        "missed_call_create_task": {"type": "boolean"},
        "missed_call_task_due_minutes": {"type": ["integer", "null"], "minimum": 1, "maximum": 10080},
        "recording_access_mode": {"type": "string", "enum": ["permission_based", "all_operators"]},
        "multi_pbx_enabled": {"type": "boolean"},
    }
)
CLICK_TO_CALL_SCHEMA = _schema(
    {
        "destination": {"type": "string", "minLength": 3, "maxLength": 32, "description": "شماره مقصد"},
        "extension_id": {"type": ["integer", "null"], "minimum": 1},
    },
    ["destination"],
)


def get_telephony_settings_handler(args, context):
    from app.services.telephony import telephony_service as svc

    db, bid, _ = _ctx(context)
    _ensure_plugin(db, bid)
    row = _run(svc.get_or_create_settings, db, bid)
    data = svc.settings_to_dict(row)
    data.pop("extra_settings", None)
    data.pop("ui_preferences", None)
    data.pop("number_normalization_rules", None)
    return data


def update_telephony_settings_handler(args, context):
    from app.services.telephony import telephony_service as svc

    db, bid, _ = _ctx(context)
    _ensure_plugin(db, bid)
    data = _run(svc.update_settings, db, bid, dict(args))
    data.pop("extra_settings", None)
    data.pop("ui_preferences", None)
    data.pop("number_normalization_rules", None)
    return data


def get_telephony_dashboard_handler(args, context):
    from app.services.telephony import telephony_service as svc

    db, bid, uid = _ctx(context)
    _ensure_plugin(db, bid)
    return _redact_dashboard(_run(svc.dashboard_summary, db, bid, uid))


def list_telephony_pbx_handler(args, context):
    from app.services.telephony import telephony_service as svc

    db, bid, _ = _ctx(context)
    _ensure_plugin(db, bid)
    return {"items": [_redact_pbx(item) for item in _run(svc.list_pbx, db, bid)]}


def update_telephony_pbx_handler(args, context):
    from app.services.telephony import telephony_service as svc

    db, bid, _ = _ctx(context)
    _ensure_plugin(db, bid)
    payload = {k: v for k, v in args.items() if k != "pbx_id"}
    return _redact_pbx(_run(svc.update_pbx, db, bid, int(args["pbx_id"]), payload))


def list_telephony_extensions_handler(args, context):
    from app.services.telephony import telephony_service as svc

    db, bid, _ = _ctx(context)
    _ensure_plugin(db, bid)
    return {"items": _run(svc.list_extensions, db, bid, args.get("pbx_id"))}


def upsert_telephony_extension_handler(args, context):
    from app.services.telephony import telephony_service as svc

    db, bid, _ = _ctx(context)
    _ensure_plugin(db, bid)
    return _run(svc.upsert_extension, db, bid, dict(args))


def list_telephony_user_extensions_handler(args, context):
    from app.services.telephony import telephony_service as svc

    db, bid, _ = _ctx(context)
    _ensure_plugin(db, bid)
    return {"items": _run(svc.list_user_extensions, db, bid, args.get("user_id"))}


def upsert_telephony_user_extension_handler(args, context):
    from app.services.telephony import telephony_service as svc

    db, bid, _ = _ctx(context)
    _ensure_plugin(db, bid)
    return _run(svc.upsert_user_extension, db, bid, dict(args))


def delete_telephony_user_extension_handler(args, context):
    from app.services.telephony import telephony_service as svc

    db, bid, _ = _ctx(context)
    _ensure_plugin(db, bid)
    _run(svc.delete_user_extension, db, bid, int(args["link_id"]))
    return {"deleted": True, "link_id": int(args["link_id"])}


def list_telephony_calls_handler(args, context):
    from app.services.telephony import telephony_service as svc

    db, bid, _ = _ctx(context)
    _ensure_plugin(db, bid)
    return _run(
        svc.list_calls,
        db,
        bid,
        direction=args.get("direction"),
        status=args.get("status"),
        assigned_user_id=args.get("assigned_user_id"),
        person_id=args.get("person_id"),
        q=args.get("q"),
        limit=int(args.get("limit", 50)),
        offset=int(args.get("offset", 0)),
    )


def get_telephony_call_handler(args, context):
    from app.services.telephony import telephony_service as svc

    db, bid, _ = _ctx(context)
    _ensure_plugin(db, bid)
    return _run(svc.get_call, db, bid, int(args["call_id"]))


def update_telephony_call_handler(args, context):
    from app.services.telephony import telephony_service as svc

    db, bid, _ = _ctx(context)
    _ensure_plugin(db, bid)
    payload = {k: v for k, v in args.items() if k != "call_id"}
    return _run(svc.patch_call, db, bid, int(args["call_id"]), payload)


def create_person_from_telephony_call_handler(args, context):
    from app.services.telephony import telephony_service as svc

    db, bid, uid = _ctx(context)
    _ensure_plugin(db, bid)
    payload = {k: v for k, v in args.items() if k != "call_id"}
    return _run(svc.create_person_from_call, db, bid, int(args["call_id"]), payload, uid)


def create_lead_from_telephony_call_handler(args, context):
    from app.services.telephony import telephony_service as svc

    db, bid, uid = _ctx(context)
    _ensure_plugin(db, bid)
    payload = {k: v for k, v in args.items() if k != "call_id"}
    return _run(svc.create_lead_from_call, db, bid, int(args["call_id"]), payload, uid)


def click_to_call_handler(args, context):
    from app.services.telephony import telephony_service as svc

    db, bid, uid = _ctx(context)
    _ensure_plugin(db, bid)
    return _run(svc.click_to_call, db, bid, uid, dict(args))


def lookup_telephony_number_handler(args, context):
    from app.services.telephony import telephony_service as svc

    db, bid, _ = _ctx(context)
    _ensure_plugin(db, bid)
    return _run(svc.match_caller, db, bid, args["number"])


def get_telephony_reports_summary_handler(args, context):
    from app.services.telephony.reports_service import summary_report

    db, bid, _ = _ctx(context)
    _ensure_plugin(db, bid)
    return _run(summary_report, db, bid, date_from=args.get("date_from"), date_to=args.get("date_to"))


def register_mcp_telephony_functions(registry) -> None:
    from app.services.ai.function_registry import AIFunction, AIRole

    roles = {AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN}
    empty = _schema({})
    call_id = _schema({"call_id": {"type": "integer", "minimum": 1}}, ["call_id"])
    registry.register(AIFunction(name="get_telephony_settings", description="تنظیمات افزونه تلفن کسب‌وکار متصل. افزونه باید فعال باشد.", parameters_schema=empty, handler=get_telephony_settings_handler, allowed_roles=roles, required_permissions=["telephony.view"], category="crm", is_readonly=True))
    registry.register(AIFunction(name="update_telephony_settings", description="ویرایش پاپ‌آپ صفحه، فعالیت خودکار و دسترسی ضبط. توکن کانکتور اینجا نیست. نیاز به تأیید.", parameters_schema=UPDATE_TELEPHONY_SETTINGS_SCHEMA, handler=update_telephony_settings_handler, allowed_roles=roles, required_permissions=["telephony.manage"], category="crm", requires_approval=True, risk_level="high", is_readonly=False))
    registry.register(AIFunction(name="get_telephony_dashboard", description="خلاصه تماس‌های امروز و وضعیت مراکز تلفن بدون افشای توکن.", parameters_schema=empty, handler=get_telephony_dashboard_handler, allowed_roles=roles, required_permissions=["telephony.view"], category="crm", is_readonly=True))
    registry.register(AIFunction(name="list_telephony_pbx", description="فهرست مراکز تلفن متصل. توکن کانکتور برنمی‌گردد.", parameters_schema=empty, handler=list_telephony_pbx_handler, allowed_roles=roles, required_permissions=["telephony.view"], category="crm", is_readonly=True))
    registry.register(AIFunction(name="update_telephony_pbx", description="ویرایش نام/نوع/وضعیت مرکز تلفن. چرخش توکن از MCP ممکن نیست.", parameters_schema=_schema({"pbx_id": {"type": "integer", "minimum": 1}, "name": {"type": "string", "minLength": 1, "maxLength": 120}, "pbx_type": {"type": "string", "enum": ["issabel", "asterisk"]}, "host_hint": {"type": ["string", "null"], "maxLength": 255}, "is_active": {"type": "boolean"}}, ["pbx_id"]), handler=update_telephony_pbx_handler, allowed_roles=roles, required_permissions=["telephony.manage"], category="crm", requires_approval=True, risk_level="medium", is_readonly=False))
    registry.register(AIFunction(name="list_telephony_extensions", description="فهرست داخلی‌های مراکز تلفن کسب‌وکار متصل.", parameters_schema=_schema({"pbx_id": {"type": "integer", "minimum": 1}}), handler=list_telephony_extensions_handler, allowed_roles=roles, required_permissions=["telephony.view"], category="crm", is_readonly=True))
    registry.register(AIFunction(name="upsert_telephony_extension", description="ایجاد یا به‌روزرسانی داخلی روی یک مرکز تلفن متعلق به کسب‌وکار.", parameters_schema=_schema({"pbx_id": {"type": "integer", "minimum": 1}, "extension": {"type": "string", "minLength": 1, "maxLength": 32}, "display_name": {"type": ["string", "null"], "maxLength": 120}, "is_active": {"type": "boolean"}}, ["pbx_id", "extension"]), handler=upsert_telephony_extension_handler, allowed_roles=roles, required_permissions=["telephony.manage"], category="crm", requires_approval=True, risk_level="medium", is_readonly=False))
    registry.register(AIFunction(name="list_telephony_user_extensions", description="اتصال کاربران کسب‌وکار به داخلی‌ها.", parameters_schema=_schema({"user_id": {"type": "integer", "minimum": 1}}), handler=list_telephony_user_extensions_handler, allowed_roles=roles, required_permissions=["telephony.view"], category="crm", is_readonly=True))
    registry.register(AIFunction(name="upsert_telephony_user_extension", description="اتصال کاربر عضو کسب‌وکار به داخلی برای Screen-pop یا Click-to-Call.", parameters_schema=_schema({"user_id": {"type": "integer", "minimum": 1}, "extension_id": {"type": "integer", "minimum": 1}, "is_primary": {"type": "boolean"}, "receive_screen_pop": {"type": "boolean"}, "can_click_to_call": {"type": "boolean"}, "caller_id_override": {"type": ["string", "null"], "maxLength": 32}}, ["user_id", "extension_id"]), handler=upsert_telephony_user_extension_handler, allowed_roles=roles, required_permissions=["telephony.manage"], category="crm", requires_approval=True, risk_level="medium", is_readonly=False))
    registry.register(AIFunction(name="delete_telephony_user_extension", description="حذف اتصال کاربر به داخلی. نیازمند تأیید.", parameters_schema=_schema({"link_id": {"type": "integer", "minimum": 1}}, ["link_id"]), handler=delete_telephony_user_extension_handler, allowed_roles=roles, required_permissions=["telephony.manage"], category="crm", requires_approval=True, risk_level="high", is_readonly=False))
    registry.register(AIFunction(name="list_telephony_calls", description="جستجوی تماس‌های کسب‌وکار متصل، حداکثر ۲۰۰ مورد در صفحه.", parameters_schema=_schema({"direction": {"type": "string", "enum": ["inbound", "outbound"]}, "status": {"type": "string", "enum": ["ringing", "answered", "completed", "missed", "busy", "failed"]}, "assigned_user_id": {"type": "integer", "minimum": 1}, "person_id": {"type": "integer", "minimum": 1}, "q": {"type": "string", "maxLength": 80}, "limit": {"type": "integer", "minimum": 1, "maximum": 200}, "offset": {"type": "integer", "minimum": 0}}), handler=list_telephony_calls_handler, allowed_roles=roles, required_permissions=["telephony.view"], category="crm", is_readonly=True))
    registry.register(AIFunction(name="get_telephony_call", description="جزئیات یک تماس متعلق به کسب‌وکار متصل.", parameters_schema=call_id, handler=get_telephony_call_handler, allowed_roles=roles, required_permissions=["telephony.view"], category="crm", is_readonly=True))
    registry.register(AIFunction(name="update_telephony_call", description="ثبت نتیجه، دسته یا اتصال شخص/سرنخ به تماس.", parameters_schema=_schema({"call_id": {"type": "integer", "minimum": 1}, "note": {"type": ["string", "null"], "maxLength": 2000}, "category": {"type": ["string", "null"], "maxLength": 80}, "outcome": {"type": ["string", "null"], "maxLength": 80}, "person_id": {"type": ["integer", "null"], "minimum": 1}, "lead_id": {"type": ["integer", "null"], "minimum": 1}, "deal_id": {"type": ["integer", "null"], "minimum": 1}, "document_id": {"type": ["integer", "null"], "minimum": 1}}, ["call_id"]), handler=update_telephony_call_handler, allowed_roles=roles, required_permissions=["telephony.view"], category="crm", requires_approval=True, risk_level="medium", is_readonly=False))
    registry.register(AIFunction(name="create_person_from_telephony_call", description="ساخت شخص از شماره تماس و اتصال آن به همان تماس. نیاز به تأیید.", parameters_schema=_schema({"call_id": {"type": "integer", "minimum": 1}, "alias_name": {"type": ["string", "null"], "maxLength": 255}, "first_name": {"type": ["string", "null"], "maxLength": 100}, "last_name": {"type": ["string", "null"], "maxLength": 100}, "company_name": {"type": ["string", "null"], "maxLength": 255}, "mobile": {"type": ["string", "null"], "maxLength": 20}}, ["call_id"]), handler=create_person_from_telephony_call_handler, allowed_roles=roles, required_permissions=["telephony.view"], category="crm", requires_approval=True, risk_level="high", is_readonly=False))
    registry.register(AIFunction(name="create_lead_from_telephony_call", description="ساخت سرنخ CRM از تماس و اتصال آن. نیاز به تأیید.", parameters_schema=_schema({"call_id": {"type": "integer", "minimum": 1}, "title": {"type": ["string", "null"], "maxLength": 255}}, ["call_id"]), handler=create_lead_from_telephony_call_handler, allowed_roles=roles, required_permissions=["telephony.view"], category="crm", requires_approval=True, risk_level="high", is_readonly=False))
    registry.register(AIFunction(name="click_to_call", description="شروع تماس خروجی از داخلی کاربر جاری به شماره مقصد. اثر بیرونی روی سانترال؛ نیازمند تأیید.", parameters_schema=CLICK_TO_CALL_SCHEMA, handler=click_to_call_handler, allowed_roles=roles, required_permissions=["telephony.click_to_call"], category="crm", requires_approval=True, risk_level="high", is_readonly=False))
    registry.register(AIFunction(name="lookup_telephony_number", description="تطبیق شماره تلفن با شخص یا سرنخ کسب‌وکار متصل.", parameters_schema=_schema({"number": {"type": "string", "minLength": 3, "maxLength": 32}}, ["number"]), handler=lookup_telephony_number_handler, allowed_roles=roles, required_permissions=["telephony.view"], category="crm", is_readonly=True))
    registry.register(AIFunction(name="get_telephony_reports_summary", description="خلاصه گزارش تماس‌ها در بازه تاریخ.", parameters_schema=_schema({"date_from": {"type": "string", "format": "date"}, "date_to": {"type": "string", "format": "date"}}), handler=get_telephony_reports_summary_handler, allowed_roles=roles, required_permissions=["telephony.reports"], category="crm", is_readonly=True))
