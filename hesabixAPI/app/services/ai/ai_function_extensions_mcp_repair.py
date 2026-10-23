"""Repair-shop MCP workflows with tenant permission parity and confirmations."""
from __future__ import annotations

from typing import Any, Dict

from app.services.ai.function_registry import AIRole, AIFunction

_ROLES = {AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN}


def _schema(properties=None, required=()):
    return {"type": "object", "properties": properties or {}, "required": list(required), "additionalProperties": False}


def _register(registry, name, description, schema, handler, permission, *, write=False, high=False):
    registry.register(AIFunction(name=name, description=description, parameters_schema=schema, handler=handler,
        allowed_roles=_ROLES, required_permissions=[permission], category="repair",
        requires_approval=bool(write), risk_level="high" if high else ("medium" if write else "safe"), is_readonly=not write))


def _model(model_name: str, payload: Dict[str, Any], *, partial=False):
    import importlib
    cls = getattr(importlib.import_module("adapters.api.v1.schema_models.repair_shop"), model_name)
    instance = cls(**payload)
    return instance.dict(exclude_unset=partial)


def register_mcp_repair_functions(registry) -> None:
    order_id = {"order_id": {"type": "integer", "minimum": 1}}
    technician_id = {"technician_id": {"type": "integer", "minimum": 1}}
    def call_service(module, method, argument_builder):
        def handler(args, context):
            import importlib
            mod = importlib.import_module(f"app.services.{module}")
            return getattr(mod, method)(context["db"], int(context["business_id"]), *argument_builder(args, context))
        return handler

    _register(registry, "get_repair_shop_settings", "تنظیمات افزونه تعمیرگاه برای کسب‌وکار متصل.", _schema(),
        call_service("repair_shop_service", "get_repair_shop_settings", lambda a,c: ()), "repair_shop.read")
    settings = {"receipt_code_format": {"type": "string", "enum": ["random", "sequential", "custom"]}, "receipt_code_prefix": {"type": "string", "maxLength": 10},
        "auto_send_sms_on_receive": {"type": "boolean"}, "auto_send_sms_on_status_change": {"type": "boolean"}, "auto_send_email_on_receive": {"type": "boolean"},
        "auto_send_email_on_status_change": {"type": "boolean"}, "sms_templates": {"type": "object"}, "email_templates": {"type": "object"},
        "default_service_product_id": {"type": ["integer", "null"], "minimum": 1}, "default_warehouse_id": {"type": ["integer", "null"], "minimum": 1}, "extra_settings": {"type": "object"}}
    _register(registry, "update_repair_shop_settings", "به‌روزرسانی تنظیمات تعمیرگاه؛ تغییر پیامک/ایمیل خودکار می‌تواند به مشتری اطلاع‌رسانی کند و نیازمند تأیید است.", _schema({"settings": _schema(settings)}, ["settings"]),
        call_service("repair_shop_service", "update_repair_shop_settings", lambda a,c: (a["settings"],)), "repair_shop.manage", write=True, high=True)

    _register(registry, "list_repair_technicians", "فهرست تعمیرکاران فعال با صفحه‌بندی (حداکثر ۲۰۰).", _schema({"only_active": {"type": "boolean"}, "offset": {"type": "integer", "minimum": 0}, "limit": {"type": "integer", "minimum": 1, "maximum": 200}}),
        call_service("repair_shop_service", "list_technicians", lambda a,c: (bool(a.get("only_active", True)), int(a.get("offset", 0)), int(a.get("limit", 100)))), "repair_shop.read")
    tech_payload = _schema({"person_id": {"type": "integer", "minimum": 1}, "code": {"type": ["string", "null"], "maxLength": 50}, "commission_type": {"type": "string", "enum": ["fixed", "percentage", "case_by_case"]}, "commission_value": {"type": "number", "minimum": 0}, "is_active": {"type": "boolean"}, "extra_info": {"type": ["object", "null"]}})
    def create_tech(args, context):
        from app.services import repair_shop_service as svc
        return svc.create_technician(context["db"], int(context["business_id"]), _model("RepairTechnicianCreate", args["payload"]), context["user_context"].get_user_id())
    def update_tech(args, context):
        from app.services import repair_shop_service as svc
        return svc.update_technician(context["db"], int(context["business_id"]), int(args["technician_id"]), _model("RepairTechnicianUpdate", args["payload"], partial=True), context["user_context"].get_user_id())
    _register(registry, "create_repair_technician", "ثبت تعمیرکار از شخص ثبت‌شدهٔ کسب‌وکار؛ حق‌الزحمه را با قرارداد واقعی مشخص کن. نیازمند تأیید.", _schema({"payload": tech_payload}, ["payload"]), create_tech, "repair_shop.manage", write=True)
    _register(registry, "update_repair_technician", "ویرایش مشخصات/حق‌الزحمه تعمیرکار.", _schema({**technician_id, "payload": tech_payload}, ["technician_id", "payload"]), update_tech, "repair_shop.manage", write=True)
    _register(registry, "delete_repair_technician", "غیرفعال‌سازی تعمیرکار؛ سفارش فعال مانع حذف است. نیازمند تأیید.", _schema(technician_id, ["technician_id"]),
        call_service("repair_shop_service", "delete_technician", lambda a,c: (int(a["technician_id"]), c["user_context"].get_user_id())), "repair_shop.delete", write=True, high=True)

    def create_order(args, context):
        from app.services import repair_shop_service as svc
        ctx = context["user_context"]
        return svc.create_repair_order(context["db"], int(context["business_id"]), _model("RepairOrderCreate", args["payload"]), ctx.get_user_id(), calendar_type=ctx.get_calendar_type())
    def update_order(args, context):
        from app.services import repair_shop_service as svc
        return svc.update_repair_order(context["db"], int(context["business_id"]), int(args["order_id"]), _model("RepairOrderUpdate", args["payload"], partial=True), context["user_context"].get_user_id())
    order_create = _schema({"customer_person_id": {"type": "integer", "minimum": 1}, "product_id": {"type": ["integer", "null"], "minimum": 1}, "product_name": {"type": "string", "minLength": 1, "maxLength": 255},
        "product_serial": {"type": ["string", "null"], "maxLength": 100}, "warranty_code_id": {"type": ["integer", "null"], "minimum": 1}, "problem_description": {"type": "string", "minLength": 1}, "customer_notes": {"type": ["string", "null"]},
        "estimated_cost": {"type": ["number", "null"], "minimum": 0}, "currency_id": {"type": ["integer", "null"], "minimum": 1}, "estimated_delivery_at": {"type": ["string", "null"], "format": "date-time"}}, ["customer_person_id", "product_name", "problem_description"])
    order_update = _schema({"product_serial": {"type": ["string", "null"], "maxLength": 100}, "problem_description": {"type": "string"}, "customer_notes": {"type": ["string", "null"]}, "technician_notes": {"type": ["string", "null"]},
        "estimated_cost": {"type": ["number", "null"], "minimum": 0}, "estimated_delivery_at": {"type": ["string", "null"], "format": "date-time"}})
    _register(registry, "create_repair_order", "ثبت سفارش تعمیر برای مشتری؛ مشتری/کالا/گارانتی باید از ابزارهای همین کسب‌وکار انتخاب شوند. ممکن است اعلان تنظیم‌شده برای دریافت ارسال شود؛ نیازمند تأیید.", _schema({"payload": order_create}, ["payload"]), create_order, "repair_shop.write", write=True, high=True)
    _register(registry, "update_repair_order", "ویرایش سفارش باز تعمیر؛ اطلاعات customer و کالا از جستجوهای tenant متصل گرفته شود.", _schema({**order_id, "payload": order_update}, ["order_id", "payload"]), update_order, "repair_shop.write", write=True)
    _register(registry, "cancel_repair_order", "لغو (soft delete) سفارش تعمیر؛ سفارش دارای فاکتور یا تحویل‌شده قابل لغو نیست. نیازمند تأیید.", _schema(order_id, ["order_id"]),
        call_service("repair_shop_service", "delete_repair_order", lambda a,c: (int(a["order_id"]), c["user_context"].get_user_id())), "repair_shop.delete", write=True, high=True)

    def assign(args, context):
        from app.services.repair_shop_operations import assign_technician_to_order
        ctx = context["user_context"]
        return assign_technician_to_order(context["db"], int(context["business_id"]), int(args["order_id"]), int(args["technician_id"]), ctx.get_user_id())
    _register(registry, "assign_repair_technician", "اختصاص تعمیرکار فعال به سفارش و انتقال سفارش به وضعیت assigned.", _schema({**order_id, **technician_id}, ["order_id", "technician_id"]), assign, "repair_shop.write", write=True)
    statuses = ["received", "assigned", "in_progress", "waiting_parts", "testing", "completed_fixed", "completed_unfixable", "ready_for_pickup", "delivered", "cancelled"]
    def update_status(args, context):
        from app.services.repair_shop_operations import update_repair_order_status
        ctx = context["user_context"]
        return update_repair_order_status(context["db"], int(context["business_id"]), int(args["order_id"]), args["status"], args.get("notes"), ctx.get_user_id(), bool(args.get("send_notification", True)), calendar_type=ctx.get_calendar_type())
    _register(registry, "update_repair_order_status", "تغییر وضعیت سفارش تعمیر؛ ارسال پیامک/ایمیل در صورت فعال بودن تنظیمات با send_notification کنترل می‌شود. اعلان خارجی نیازمند تأیید است.", _schema({**order_id, "status": {"type": "string", "enum": statuses}, "notes": {"type": ["string", "null"], "maxLength": 2000}, "send_notification": {"type": "boolean"}}, ["order_id", "status"]), update_status, "repair_shop.write", write=True, high=True)

    def add_parts(args, context):
        from app.services.repair_shop_operations import add_parts_to_repair_order
        ctx = context["user_context"]
        items = _model("AddPartsRequest", {"parts": args["parts"]})["parts"]
        return add_parts_to_repair_order(context["db"], int(context["business_id"]), int(args["order_id"]), items, ctx.get_user_id())
    part = _schema({"product_id": {"type": "integer", "minimum": 1}, "quantity": {"type": "number", "exclusiveMinimum": 0}, "unit_price": {"type": ["number", "null"], "minimum": 0}, "warehouse_id": {"type": ["integer", "null"], "minimum": 1}, "description": {"type": ["string", "null"]}}, ["product_id", "quantity"])
    _register(registry, "add_repair_parts", "افزودن حداکثر ۲۵ قطعه به سفارش؛ اگر کالا انبارگردانی شود ممکن است حواله خروج ساخته شود و موجودی بررسی می‌شود. نیازمند تأیید.", _schema({**order_id, "parts": {"type": "array", "minItems": 1, "maxItems": 25, "items": part}}, ["order_id", "parts"]), add_parts, "repair_shop.write", write=True, high=True)
    def costs(args, context):
        from app.services.repair_shop_operations import calculate_repair_costs
        return calculate_repair_costs(context["db"], int(context["business_id"]), int(args["order_id"]), args["labor_cost"], context["user_context"].get_user_id())
    _register(registry, "calculate_repair_costs", "ثبت دستمزد و محاسبه هزینه نهایی/کمیسیون سفارش تعمیر.", _schema({**order_id, "labor_cost": {"type": "number", "minimum": 0}}, ["order_id", "labor_cost"]), costs, "repair_shop.write", write=True)
    def complete(args, context):
        from app.services.repair_shop_operations import complete_repair_order
        ctx = context["user_context"]
        return complete_repair_order(context["db"], int(context["business_id"]), int(args["order_id"]), bool(args["is_fixed"]), ctx.get_user_id(), args.get("notes"), calendar_type=ctx.get_calendar_type())
    _register(registry, "complete_repair_order", "اتمام تعمیر؛ در صورت وجود حواله خروج، آن را قطعی می‌کند و ممکن است اعلان مشتری ارسال شود. نیازمند تأیید.", _schema({**order_id, "is_fixed": {"type": "boolean"}, "notes": {"type": ["string", "null"], "maxLength": 2000}}, ["order_id", "is_fixed"]), complete, "repair_shop.write", write=True, high=True)
    def deliver(args, context):
        from app.services.repair_shop_operations import deliver_repair_order
        ctx = context["user_context"]
        return deliver_repair_order(context["db"], int(context["business_id"]), int(args["order_id"]), ctx.get_user_id(), args.get("notes"))
    _register(registry, "deliver_repair_order", "ثبت تحویل سفارش تعمیر به مشتری؛ فقط سفارش تکمیل‌شده قابل تحویل است. نیازمند تأیید.", _schema({**order_id, "notes": {"type": ["string", "null"], "maxLength": 2000}}, ["order_id"]), deliver, "repair_shop.write", write=True, high=True)

    def invoice(args, context):
        from adapters.db.repositories.repair_shop_repository import RepairOrderRepository
        from app.services.repair_shop_accounting import create_repair_invoice_accounting
        db, bid, ctx = context["db"], int(context["business_id"]), context["user_context"]
        order = RepairOrderRepository(db).get_by_id(int(args["order_id"]), bid)
        if not order:
            raise ValueError("سفارش تعمیر در کسب‌وکار متصل پیدا نشد")
        result = create_repair_invoice_accounting(db, bid, order, ctx.get_user_id())
        db.commit()
        return result
    _register(registry, "create_repair_invoice", "صدور فاکتور و سندهای حسابداری مرتبط با سفارش تعمیر؛ پیش از اجرا سفارش و مبالغ را مرور کن. نیازمند تأیید.", _schema(order_id, ["order_id"]), invoice, "repair_shop.write", write=True, high=True)

    def accounting_summary(args, context):
        from app.services.repair_shop_accounting import get_repair_accounting_summary
        return get_repair_accounting_summary(context["db"], int(context["business_id"]), int(args["order_id"]))
    _register(registry, "get_repair_accounting_summary", "خلاصه اسناد حسابداری صادرشده از سفارش تعمیر.", _schema(order_id, ["order_id"]), accounting_summary, "repair_shop.read")
    def warranty_history(args, context):
        from app.services.repair_shop_operations import get_repair_history_by_warranty
        items = get_repair_history_by_warranty(context["db"], int(context["business_id"]), int(args["warranty_code_id"]))
        return {"items": items[:200], "total": len(items), "truncated": len(items) > 200}
    _register(registry, "get_repair_history_by_warranty", "سفارش‌های تعمیر مرتبط با کد گارانتی متعلق به کسب‌وکار متصل؛ حداکثر ۲۰۰ مورد بازمی‌گردد.", _schema({"warranty_code_id": {"type": "integer", "minimum": 1}}, ["warranty_code_id"]), warranty_history, "repair_shop.read")
