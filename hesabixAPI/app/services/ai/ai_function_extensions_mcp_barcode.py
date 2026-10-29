"""MCP tools for barcode label studio — templates and printer profiles, no binary print."""
from __future__ import annotations

from typing import Any, Dict

UPDATE_BARCODE_PRINTER_SETTINGS_SCHEMA: Dict[str, Any] = {}


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
    from app.core.barcode_label_plugin_dependency import check_barcode_label_plugin_active

    if not check_barcode_label_plugin_active(db, int(business_id)):
        raise ValueError("افزونه استودیو برچسب بارکد برای این کسب‌وکار فعال نیست.")


def _run(fn, *args, **kwargs):
    try:
        return fn(*args, **kwargs)
    except Exception as exc:
        _raise_service(exc)


def _ctx(context):
    return context["db"], int(context["business_id"]), int(context["user_context"].get_user_id())


_PRINTER_PROFILE = {
    "type": "object",
    "additionalProperties": False,
    "required": ["id", "name"],
    "properties": {
        "id": {"type": "string", "minLength": 1, "maxLength": 64},
        "name": {"type": "string", "minLength": 1, "maxLength": 120},
        "mode": {"type": "string", "enum": ["pdf_spooler", "zpl", "escpos"]},
        "connection": {"type": "string", "enum": ["system_default", "tcp", "usb", "ble"]},
        "host": {"type": ["string", "null"], "maxLength": 255},
        "port": {"type": ["integer", "null"], "minimum": 1, "maximum": 65535},
        "label_width_mm": {"type": "number", "exclusiveMinimum": 0, "maximum": 500},
        "label_height_mm": {"type": "number", "exclusiveMinimum": 0, "maximum": 500},
        "dpi": {"type": "integer", "minimum": 72, "maximum": 1200},
        "enabled": {"type": "boolean"},
    },
}
UPDATE_BARCODE_PRINTER_SETTINGS_SCHEMA = _schema(
    {
        "printer_profiles": {"type": "array", "maxItems": 50, "items": _PRINTER_PROFILE},
        "active_profile_id": {"type": ["string", "null"], "maxLength": 64},
    },
    ["printer_profiles"],
)
_TEMPLATE_ID = _schema({"template_id": {"type": "integer", "minimum": 1}}, ["template_id"])


def list_barcode_label_templates_handler(args, context):
    from app.services import barcode_label_service as svc

    db, bid, _ = _ctx(context)
    _ensure_plugin(db, bid)
    return _run(svc.list_templates, db, bid, status=args.get("status") or "all", q=args.get("q"))


def get_barcode_label_template_handler(args, context):
    from app.services import barcode_label_service as svc

    db, bid, _ = _ctx(context)
    _ensure_plugin(db, bid)
    return _run(svc.get_template, db, bid, int(args["template_id"]))


def get_default_barcode_label_template_handler(args, context):
    from app.services import barcode_label_service as svc

    db, bid, _ = _ctx(context)
    _ensure_plugin(db, bid)
    return _run(svc.get_default_template, db, bid)


def set_default_barcode_label_template_handler(args, context):
    from app.services import barcode_label_service as svc

    db, bid, _ = _ctx(context)
    _ensure_plugin(db, bid)
    return _run(svc.set_default_template, db, bid, int(args["template_id"]))


def create_barcode_label_from_preset_handler(args, context):
    from app.services import barcode_label_service as svc

    db, bid, uid = _ctx(context)
    _ensure_plugin(db, bid)
    return _run(
        svc.create_from_preset,
        db,
        bid,
        preset_code=args["preset_code"],
        name=args.get("name"),
        user_id=uid,
    )


def publish_barcode_label_template_handler(args, context):
    from app.services import barcode_label_service as svc

    db, bid, uid = _ctx(context)
    _ensure_plugin(db, bid)
    return _run(svc.publish_template, db, bid, int(args["template_id"]), user_id=uid)


def archive_barcode_label_template_handler(args, context):
    from app.services import barcode_label_service as svc

    db, bid, uid = _ctx(context)
    _ensure_plugin(db, bid)
    return _run(svc.archive_template, db, bid, int(args["template_id"]), user_id=uid)


def duplicate_barcode_label_template_handler(args, context):
    from app.services import barcode_label_service as svc

    db, bid, uid = _ctx(context)
    _ensure_plugin(db, bid)
    return _run(svc.duplicate_template, db, bid, int(args["template_id"]), user_id=uid)


def list_barcode_label_presets_handler(args, context):
    from app.services import barcode_label_service as svc

    db, bid, _ = _ctx(context)
    _ensure_plugin(db, bid)
    return svc.presets_catalog()


def get_barcode_label_printer_settings_handler(args, context):
    from app.services import barcode_label_service as svc

    db, bid, _ = _ctx(context)
    _ensure_plugin(db, bid)
    return _run(svc.get_printer_settings, db, bid)


def update_barcode_label_printer_settings_handler(args, context):
    from app.services import barcode_label_service as svc

    db, bid, _ = _ctx(context)
    _ensure_plugin(db, bid)
    return _run(svc.upsert_printer_settings, db, bid, dict(args))


def register_mcp_barcode_functions(registry) -> None:
    from app.services.ai.function_registry import AIFunction, AIRole

    roles = {AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN}
    empty = _schema({})
    registry.register(AIFunction(name="list_barcode_label_templates", description="فهرست طرح‌های برچسب بارکد کسب‌وکار متصل. افزونه باید فعال باشد.", parameters_schema=_schema({"status": {"type": "string", "enum": ["all", "draft", "published", "archived"]}, "q": {"type": "string", "maxLength": 160}}), handler=list_barcode_label_templates_handler, allowed_roles=roles, required_permissions=["barcode_labels.view"], category="inventory", is_readonly=True))
    registry.register(AIFunction(name="get_barcode_label_template", description="جزئیات یک طرح برچسب متعلق به کسب‌وکار متصل.", parameters_schema=_TEMPLATE_ID, handler=get_barcode_label_template_handler, allowed_roles=roles, required_permissions=["barcode_labels.view"], category="inventory", is_readonly=True))
    registry.register(AIFunction(name="get_default_barcode_label_template", description="طرح برچسب پیش‌فرض کسب‌وکار متصل.", parameters_schema=empty, handler=get_default_barcode_label_template_handler, allowed_roles=roles, required_permissions=["barcode_labels.view"], category="inventory", is_readonly=True))
    registry.register(AIFunction(name="set_default_barcode_label_template", description="تنظیم طرح پیش‌فرض چاپ برچسب. نیاز به تأیید.", parameters_schema=_TEMPLATE_ID, handler=set_default_barcode_label_template_handler, allowed_roles=roles, required_permissions=["barcode_labels.design"], category="inventory", requires_approval=True, risk_level="medium", is_readonly=False))
    registry.register(AIFunction(name="create_barcode_label_from_preset", description="ساخت طرح برچسب از preset سیستمی. طراحی آزاد استودیو از MCP نیست. نیاز به تأیید.", parameters_schema=_schema({"preset_code": {"type": "string", "minLength": 1, "maxLength": 64}, "name": {"type": ["string", "null"], "maxLength": 160}}, ["preset_code"]), handler=create_barcode_label_from_preset_handler, allowed_roles=roles, required_permissions=["barcode_labels.design"], category="inventory", requires_approval=True, risk_level="medium", is_readonly=False))
    registry.register(AIFunction(name="publish_barcode_label_template", description="انتشار طرح برچسب برای چاپ. نیاز به تأیید.", parameters_schema=_TEMPLATE_ID, handler=publish_barcode_label_template_handler, allowed_roles=roles, required_permissions=["barcode_labels.design"], category="inventory", requires_approval=True, risk_level="medium", is_readonly=False))
    registry.register(AIFunction(name="archive_barcode_label_template", description="بایگانی طرح برچسب. نیاز به تأیید.", parameters_schema=_TEMPLATE_ID, handler=archive_barcode_label_template_handler, allowed_roles=roles, required_permissions=["barcode_labels.design"], category="inventory", requires_approval=True, risk_level="high", is_readonly=False))
    registry.register(AIFunction(name="duplicate_barcode_label_template", description="کپی طرح برچسب به پیش‌نویس جدید.", parameters_schema=_TEMPLATE_ID, handler=duplicate_barcode_label_template_handler, allowed_roles=roles, required_permissions=["barcode_labels.design"], category="inventory", requires_approval=True, risk_level="medium", is_readonly=False))
    registry.register(AIFunction(name="list_barcode_label_presets", description="گالری presetهای سیستمی طرح برچسب.", parameters_schema=empty, handler=list_barcode_label_presets_handler, allowed_roles=roles, required_permissions=["barcode_labels.view"], category="inventory", is_readonly=True))
    registry.register(AIFunction(name="get_barcode_label_printer_settings", description="پروفایل‌های چاپگر برچسب کسب‌وکار متصل.", parameters_schema=empty, handler=get_barcode_label_printer_settings_handler, allowed_roles=roles, required_permissions=["barcode_labels.view"], category="inventory", is_readonly=True))
    registry.register(AIFunction(name="update_barcode_label_printer_settings", description="ذخیره پروفایل چاپگر رولی/سیستم. چاپ باینری از MCP نیست. نیاز به تأیید.", parameters_schema=UPDATE_BARCODE_PRINTER_SETTINGS_SCHEMA, handler=update_barcode_label_printer_settings_handler, allowed_roles=roles, required_permissions=["barcode_labels.print"], category="inventory", requires_approval=True, risk_level="medium", is_readonly=False))
