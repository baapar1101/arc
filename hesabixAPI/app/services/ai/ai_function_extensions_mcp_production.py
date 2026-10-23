"""Tenant-bound production order and BOM tools for MCP."""
from __future__ import annotations

from app.services.ai.function_registry import AIRole, AIFunction

_ROLES = {AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN}


def _schema(properties=None, required=()):
    return {"type": "object", "properties": properties or {}, "required": list(required), "additionalProperties": False}


def _register(registry, name, description, schema, handler, permission, *, write=False, high=False):
    registry.register(AIFunction(name=name, description=description, parameters_schema=schema, handler=handler,
        allowed_roles=_ROLES, required_permissions=[permission], category="production", requires_approval=bool(write),
        risk_level="high" if high else ("medium" if write else "safe"), is_readonly=not write))


def _model(module: str, name: str, payload: dict, *, partial=False):
    import importlib
    cls = getattr(importlib.import_module(module), name)
    return cls(**payload)


def _commit(db):
    db.commit()


def register_mcp_production_functions(registry) -> None:
    from datetime import date
    from app.services import production_order_service as production
    from app.services import bom_service as bom

    order_id = {"order_id": {"type": "integer", "minimum": 1}}
    bom_id = {"bom_id": {"type": "integer", "minimum": 1}}
    date_props = {"due_from": {"type": ["string", "null"], "format": "date"}, "due_to": {"type": ["string", "null"], "format": "date"}}
    list_schema = _schema({"status": {"type": ["string", "null"], "maxLength": 32}, "product_id": {"type": ["integer", "null"], "minimum": 1}, **date_props,
        "skip": {"type": "integer", "minimum": 0}, "take": {"type": "integer", "minimum": 1, "maximum": 200}})

    def list_orders(a, c):
        df = date.fromisoformat(a["due_from"]) if a.get("due_from") else None
        dt = date.fromisoformat(a["due_to"]) if a.get("due_to") else None
        if df and dt and df > dt:
            raise ValueError("due_from must not be after due_to")
        return production.list_production_orders(c["db"], int(c["business_id"]), status=a.get("status"), product_id=a.get("product_id"), due_from=df, due_to=dt, skip=int(a.get("skip", 0)), take=int(a.get("take", 50)))
    _register(registry, "list_production_orders", "فهرست سفارش‌های تولید با فیلتر وضعیت/کالا/سررسید؛ حداکثر ۲۰۰ مورد.", list_schema, list_orders, "inventory.read")
    _register(registry, "get_production_order", "جزئیات یک سفارش تولید متعلق به کسب‌وکار متصل.", _schema(order_id, ["order_id"]), lambda a,c: production.get_production_order(c["db"], int(c["business_id"]), int(a["order_id"])), "inventory.read")

    def material_plan(a, c):
        df = date.fromisoformat(a["due_from"]) if a.get("due_from") else None
        dt = date.fromisoformat(a["due_to"]) if a.get("due_to") else None
        if df and dt and df > dt:
            raise ValueError("due_from must not be after due_to")
        return production.get_production_material_plan(c["db"], int(c["business_id"]), due_from=df, due_to=dt)
    _register(registry, "get_production_material_plan", "برنامه نیاز مواد سفارش‌های تولید در بازه سررسید.", _schema(date_props), material_plan, "inventory.read")
    _register(registry, "trace_production_orders_by_lot", "ردیابی سفارش‌های تولید با کد lot.", _schema({"lot_code": {"type": "string", "minLength": 1, "maxLength": 64}}, ["lot_code"]), lambda a,c: production.list_production_orders_by_lot(c["db"], int(c["business_id"]), a["lot_code"]), "inventory.read")

    create_order = _schema({"product_id": {"type": "integer", "minimum": 1}, "bom_id": {"type": "integer", "minimum": 1}, "quantity": {"type": "number", "exclusiveMinimum": 0},
        "warehouse_id": {"type": "integer", "minimum": 1}, "output_warehouse_id": {"type": "integer", "minimum": 1}, "planned_start_date": {"type": ["string", "null"], "format": "date"},
        "due_date": {"type": ["string", "null"], "format": "date"}, "priority": {"type": "integer", "minimum": 1, "maximum": 5}, "notes": {"type": ["string", "null"], "maxLength": 5000}},
        ["product_id", "bom_id", "quantity", "warehouse_id", "output_warehouse_id"])
    def create_production(a, c):
        payload = _model("adapters.api.v1.schema_models.production_order", "ProductionOrderCreateRequest", a)
        result = production.create_production_order(c["db"], int(c["business_id"]), c["user_context"].get_user_id(), payload)
        _commit(c["db"])
        return result
    _register(registry, "create_production_order", "ایجاد سفارش تولید؛ کالا، BOM و انبارها باید متعلق به کسب‌وکار باشند. نیازمند تأیید.", create_order, create_production, "inventory.write", write=True)

    update_order_schema = _schema({"order_id": {"type": "integer", "minimum": 1}, "version": {"type": "integer", "minimum": 1}, "quantity": {"type": ["number", "null"], "exclusiveMinimum": 0},
        "warehouse_id": {"type": ["integer", "null"], "minimum": 1}, "output_warehouse_id": {"type": ["integer", "null"], "minimum": 1}, "planned_start_date": {"type": ["string", "null"], "format": "date"},
        "due_date": {"type": ["string", "null"], "format": "date"}, "priority": {"type": ["integer", "null"], "minimum": 1, "maximum": 5}, "notes": {"type": ["string", "null"], "maxLength": 5000}}, ["order_id", "version"])
    def update_production(a, c):
        payload = _model("adapters.api.v1.schema_models.production_order", "ProductionOrderUpdateRequest", {k:v for k,v in a.items() if k != "order_id"}, partial=True)
        result = production.update_production_order(c["db"], int(c["business_id"]), int(a["order_id"]), payload)
        _commit(c["db"])
        return result
    _register(registry, "update_production_order", "ویرایش سفارش تولید با کنترل نسخه هم‌زمانی؛ نیازمند تأیید.", update_order_schema, update_production, "inventory.write", write=True)

    action_schema = _schema({"order_id": {"type": "integer", "minimum": 1}, "version": {"type": "integer", "minimum": 1}, "close_reason": {"type": ["string", "null"], "maxLength": 2000}}, ["order_id", "version"])
    for tool, op, desc in [("release_production_order", production.release_production_order, "آزادسازی سفارش تولید"), ("start_production_order", production.start_production_order, "شروع سفارش تولید"),
        ("complete_production_order", production.complete_production_order, "تکمیل سفارش و ثبت اثر موجودی"), ("cancel_production_order", production.cancel_production_order, "لغو سفارش تولید")]:
        def action(a, c, operation=op, tool_name=tool):
            if tool_name == "complete_production_order":
                result = operation(c["db"], int(c["business_id"]), int(a["order_id"]), int(a["version"]), a.get("close_reason"))
            else:
                result = operation(c["db"], int(c["business_id"]), int(a["order_id"]), int(a["version"]))
            _commit(c["db"])
            return result
        _register(registry, tool, desc + "; تغییر lifecycle/موجودی و نیازمند تأیید.", action_schema, action, "inventory.write", write=True, high=True)

    _register(registry, "get_production_order_costing", "خواندن بهای تمام‌شده سفارش تولید.", _schema(order_id, ["order_id"]), lambda a,c: production.get_production_order_costing(c["db"], int(c["business_id"]), int(a["order_id"])), "inventory.read")
    def refresh_cost(a,c):
        result = production.refresh_production_order_actual_costs(c["db"], int(c["business_id"]), int(a["order_id"]))
        _commit(c["db"])
        return result
    _register(registry, "refresh_production_order_costing", "بازمحاسبه بهای واقعی سفارش تولید از اسناد؛ نیازمند تأیید.", _schema(order_id, ["order_id"]), refresh_cost, "inventory.write", write=True)

    lot_line = _schema({"id": {"type": "integer", "minimum": 1}, "lot_code": {"type": ["string", "null"], "maxLength": 64}, "scrap_quantity": {"type": ["number", "null"], "minimum": 0}}, ["id"])
    def update_lots(a,c):
        payload = _model("adapters.api.v1.schema_models.production_order", "ProductionOrderLotsUpdateRequest", {k:v for k,v in a.items() if k != "order_id"})
        result = production.update_production_order_lots(c["db"], int(c["business_id"]), int(a["order_id"]), expected_version=payload.version,
            material_lots=[x.model_dump() for x in (payload.materials or [])], output_lots=[x.model_dump() for x in (payload.outputs or [])])
        _commit(c["db"])
        return result
    _register(registry, "update_production_order_lots", "ثبت lot مواد و خروجی‌های سفارش با کنترل نسخه؛ نیازمند تأیید.", _schema({"order_id": {"type": "integer", "minimum": 1}, "version": {"type": "integer", "minimum": 1},
        "materials": {"type": ["array", "null"], "items": lot_line}, "outputs": {"type": ["array", "null"], "items": lot_line}}, ["order_id", "version"]), update_lots, "inventory.write", write=True)

    # BOM workflows
    item = _schema({"line_no": {"type": "integer", "minimum": 1}, "component_product_id": {"type": "integer", "minimum": 1}, "qty_per": {"type": "number", "exclusiveMinimum": 0}, "uom": {"type": ["string", "null"], "maxLength": 32},
        "wastage_percent": {"type": ["number", "null"], "minimum": 0, "maximum": 100}, "is_optional": {"type": "boolean"}, "substitute_group": {"type": ["string", "null"], "maxLength": 64}, "suggested_warehouse_id": {"type": ["integer", "null"], "minimum": 1}}, ["line_no", "component_product_id", "qty_per"])
    output = _schema({"line_no": {"type": "integer", "minimum": 1}, "output_product_id": {"type": "integer", "minimum": 1}, "ratio": {"type": "number", "exclusiveMinimum": 0}, "uom": {"type": ["string", "null"], "maxLength": 32}}, ["line_no", "output_product_id", "ratio"])
    operation = _schema({"line_no": {"type": "integer", "minimum": 1}, "operation_name": {"type": "string", "minLength": 1}, "cost_fixed": {"type": ["number", "null"]}, "cost_per_unit": {"type": ["number", "null"]}, "cost_uom": {"type": ["string", "null"], "maxLength": 32}, "work_center": {"type": ["string", "null"], "maxLength": 128}}, ["line_no", "operation_name"])
    bom_create_schema = _schema({"product_id": {"type": "integer", "minimum": 1}, "version": {"type": "string", "maxLength": 64}, "name": {"type": "string", "maxLength": 255}, "is_default": {"type": "boolean"},
        "effective_from": {"type": ["string", "null"]}, "effective_to": {"type": ["string", "null"]}, "yield_percent": {"type": ["number", "null"]}, "wastage_percent": {"type": ["number", "null"]},
        "status": {"type": "string", "enum": ["draft", "approved", "archived"]}, "notes": {"type": ["string", "null"], "maxLength": 5000}, "items": {"type": "array", "items": item}, "outputs": {"type": "array", "items": output}, "operations": {"type": "array", "items": operation}}, ["product_id", "version", "name"])
    _register(registry, "get_bom", "جزئیات BOM متعلق به کسب‌وکار متصل.", _schema(bom_id, ["bom_id"]), lambda a,c: bom.get_bom(c["db"], int(c["business_id"]), int(a["bom_id"])), "inventory.read")
    def create_bom(a,c):
        result = bom.create_bom(c["db"], int(c["business_id"]), _model("adapters.api.v1.schema_models.product_bom", "ProductBOMCreateRequest", a))
        return result
    _register(registry, "create_bom", "تعریف BOM و مواد/خروجی/عملیات؛ اعتبارسنجی تعلق کالا به کسب‌وکار انجام می‌شود. نیازمند تأیید.", bom_create_schema, create_bom, "inventory.write", write=True)
    update_bom_schema = _schema({**bom_id, "version": {"type": ["string", "null"], "maxLength": 64}, "name": {"type": ["string", "null"], "maxLength": 255}, "is_default": {"type": ["boolean", "null"]},
        "effective_from": {"type": ["string", "null"]}, "effective_to": {"type": ["string", "null"]}, "yield_percent": {"type": ["number", "null"]}, "wastage_percent": {"type": ["number", "null"]}, "status": {"type": ["string", "null"], "enum": ["draft", "approved", "archived", None]}, "notes": {"type": ["string", "null"], "maxLength": 5000},
        "items": {"type": ["array", "null"], "items": item}, "outputs": {"type": ["array", "null"], "items": output}, "operations": {"type": ["array", "null"], "items": operation}}, ["bom_id"])
    def update_bom(a,c):
        result = bom.update_bom(c["db"], int(c["business_id"]), int(a["bom_id"]), _model("adapters.api.v1.schema_models.product_bom", "ProductBOMUpdateRequest", {k:v for k,v in a.items() if k != "bom_id"}))
        return result
    _register(registry, "update_bom", "ویرایش BOM؛ خطوط ارسال‌شده جایگزین مواد/خروجی/عملیات فعلی می‌شوند. نیازمند تأیید.", update_bom_schema, update_bom, "inventory.write", write=True)
    _register(registry, "delete_bom", "حذف BOM؛ ممکن است برای سفارش‌های تولید موجود قابل استفاده نباشد. نیازمند تأیید.", _schema(bom_id, ["bom_id"]), lambda a,c: bom.delete_bom(c["db"], int(c["business_id"]), int(a["bom_id"])), "inventory.delete", write=True, high=True)
    explode_schema = _schema({"product_id": {"type": ["integer", "null"], "minimum": 1}, "bom_id": {"type": ["integer", "null"], "minimum": 1}, "quantity": {"type": "number", "exclusiveMinimum": 0}, "date": {"type": ["string", "null"], "format": "date"}, "recursive": {"type": "boolean"}, "max_depth": {"type": "integer", "minimum": 1, "maximum": 32}}, ["quantity"])
    _register(registry, "explode_bom", "محاسبه مواد لازم از BOM بدون ثبت موجودی یا سند؛ حداکثر عمق بازگشتی ۳۲.", explode_schema, lambda a,c: bom.explode_bom(c["db"], int(c["business_id"]), _model("adapters.api.v1.schema_models.product_bom", "BOMExplosionRequest", a)), "inventory.read")
    draft_schema = _schema({"product_id": {"type": ["integer", "null"], "minimum": 1}, "bom_id": {"type": ["integer", "null"], "minimum": 1}, "quantity": {"type": "number", "exclusiveMinimum": 0}, "document_date": {"type": ["string", "null"], "format": "date"}, "fiscal_year_id": {"type": ["integer", "null"], "minimum": 1}, "currency_id": {"type": ["integer", "null"], "minimum": 1}}, ["quantity"])
    _register(registry, "produce_draft_from_bom", "ساخت پیش‌نویس سند تولید بر اساس BOM؛ سند قطعی نمی‌شود. نیازمند تأیید.", draft_schema, lambda a,c: bom.produce_draft(c["db"], int(c["business_id"]), _model("adapters.api.v1.schema_models.product_bom", "ProductionDraftRequest", a)), "inventory.write", write=True)
