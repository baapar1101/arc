"""Tenant-bound MCP tools for warranty administration and code lifecycle."""
from __future__ import annotations

from app.services.ai.function_registry import AIRole, AIFunction

_ROLES = {AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN}


def _redact_customer_data(result):
    """Do not return customer contact payloads or bearer-like tracking links by default."""
    if isinstance(result, dict):
        result = dict(result)
        items = result.get("items")
        if isinstance(items, list):
            result["items"] = [_redact_customer_data(item) for item in items]
        for key in ("activated_by_customer_info", "tracking_link_code"):
            if key in result:
                result[key] = None
    elif isinstance(result, list):
        return [_redact_customer_data(item) for item in result]
    return result


def _schema(properties=None, required=()):
    return {"type": "object", "properties": properties or {}, "required": list(required), "additionalProperties": False}


def _register(registry, name, description, schema, handler, permission, *, write=False, high=False):
    registry.register(AIFunction(name=name, description=description, parameters_schema=schema, handler=handler,
        allowed_roles=_ROLES, required_permissions=[permission], category="warranty", requires_approval=bool(write),
        risk_level="high" if high else ("medium" if write else "safe"), is_readonly=not write))


def register_mcp_warranty_functions(registry) -> None:
    def get_settings(args, context):
        from app.services.warranty_service import get_warranty_settings
        return get_warranty_settings(context["db"], int(context["business_id"]))
    _register(registry, "get_warranty_settings", "خواندن تنظیمات فعال‌سازی، امنیت، رهگیری و اعلان گارانتی.", _schema(), get_settings, "warranty.read")

    settings = {"code_format": {"type": "string", "enum": ["random", "sequential", "custom"]}, "code_prefix": {"type": ["string", "null"], "maxLength": 20},
        "serial_format": {"type": "string", "enum": ["random", "custom"]}, "serial_length": {"type": ["integer", "null"], "minimum": 1, "maximum": 50},
        "require_serial_verification": {"type": "boolean"}, "require_product_instance_match": {"type": "boolean"}, "max_activation_attempts": {"type": ["integer", "null"], "minimum": 1, "maximum": 100},
        "activation_lockout_duration_minutes": {"type": ["integer", "null"], "minimum": 1, "maximum": 10080}, "require_customer_registration": {"type": "boolean"}, "auto_link_to_person": {"type": "boolean"},
        "enable_tracking_link": {"type": "boolean"}, "tracking_link_expires_days": {"type": ["integer", "null"], "minimum": 1, "maximum": 3650},
        "enable_sms_notification": {"type": "boolean"}, "enable_email_notification": {"type": "boolean"}, "security_features": {"type": ["object", "null"]}}
    def update_settings(args, context):
        from app.services.warranty_service import update_warranty_settings
        return update_warranty_settings(context["db"], int(context["business_id"]), args["settings"])
    _register(registry, "update_warranty_settings", "ویرایش تولید کد، قواعد تطبیق، قفل تلاش، رهگیری و اعلان گارانتی. این تنظیمات روی مشتریان و فعال‌سازی‌های بعدی اثر می‌گذارد؛ نیازمند تأیید.", _schema({"settings": _schema(settings)}, ["settings"]), update_settings, "warranty.manage", write=True, high=True)

    def generate(args, context):
        from app.services.warranty_service import generate_warranty_codes
        ctx = context["user_context"]
        return generate_warranty_codes(context["db"], int(context["business_id"]), int(args["product_id"]), int(args.get("quantity", 1)),
            int(args.get("warranty_duration_days", 365)), user_id=ctx.get_user_id(), serial_format=args.get("serial_format", "random"),
            custom_serials=args.get("custom_serials"), code_format=args.get("code_format"), custom_codes=args.get("custom_codes"))
    _register(registry, "generate_warranty_codes", "تولید حداکثر ۵۰ کد گارانتی برای کالای کسب‌وکار متصل. تعداد کد/سریال سفارشی باید دقیقاً با quantity برابر باشد. نیازمند تأیید.",
        _schema({"product_id": {"type": "integer", "minimum": 1}, "quantity": {"type": "integer", "minimum": 1, "maximum": 50},
            "warranty_duration_days": {"type": "integer", "minimum": 1, "maximum": 36500}, "serial_format": {"type": "string", "enum": ["random", "custom"]},
            "custom_serials": {"type": "array", "maxItems": 50, "items": {"type": "string", "minLength": 1, "maxLength": 50}},
            "code_format": {"type": "string", "enum": ["random", "sequential", "custom"]}, "custom_codes": {"type": "array", "maxItems": 50, "items": {"type": "string", "minLength": 1, "maxLength": 50}}}, ["product_id"]),
        generate, "warranty.write", write=True, high=True)

    def list_by_person(args, context):
        from app.services.warranty_service import list_warranty_codes_by_person
        result = list_warranty_codes_by_person(context["db"], int(context["business_id"]), int(args["person_id"]), args.get("status"), int(args.get("limit", 100)), int(args.get("skip", 0)))
        return _redact_customer_data(result)
    _register(registry, "list_warranty_codes_by_person", "فهرست کدهای گارانتی متصل به شخص کسب‌وکار، حداکثر ۱۰۰ مورد در صفحه.",
        _schema({"person_id": {"type": "integer", "minimum": 1}, "status": {"type": "string", "enum": ["generated", "activated", "expired", "used", "revoked"]},
            "limit": {"type": "integer", "minimum": 1, "maximum": 100}, "skip": {"type": "integer", "minimum": 0}}, ["person_id"]), list_by_person, "warranty.read")

    def delete_one(args, context):
        from app.services.warranty_service import delete_warranty_code
        return delete_warranty_code(context["db"], int(context["business_id"]), int(args["code_id"]), bool(args.get("force", False)))
    _register(registry, "delete_warranty_code", "حذف کد گارانتی؛ کد فعال/استفاده‌شده فقط با force=true حذف می‌شود و سوابق رهگیری/فعال‌سازی هم پاک می‌شوند. نیازمند تأیید.",
        _schema({"code_id": {"type": "integer", "minimum": 1}, "force": {"type": "boolean"}}, ["code_id"]), delete_one, "warranty.delete", write=True, high=True)

    def delete_many(args, context):
        from app.services.warranty_service import delete_warranty_codes_bulk
        return delete_warranty_codes_bulk(context["db"], int(context["business_id"]), [int(i) for i in args["code_ids"]], bool(args.get("force", False)))
    _register(registry, "bulk_delete_warranty_codes", "حذف حداکثر ۵۰ کد گارانتی متعلق به کسب‌وکار متصل؛ نتیجهٔ حذف/رد/صرف‌نظر هر کد جداست. force=true کدهای فعال یا استفاده‌شده و سوابق وابسته را حذف می‌کند. نیازمند تأیید.",
        _schema({"code_ids": {"type": "array", "minItems": 1, "maxItems": 50, "uniqueItems": True, "items": {"type": "integer", "minimum": 1}}, "force": {"type": "boolean"}}, ["code_ids"]), delete_many, "warranty.delete", write=True, high=True)
