"""MCP access to the structured warehouse reports exposed by the UI API."""
from __future__ import annotations

from typing import Any, Dict

from app.services.ai.function_registry import AIRole, AIFunction

_ROLES = {AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN}
_IDS = {"type": "array", "maxItems": 100, "uniqueItems": True, "items": {"type": "integer", "minimum": 1}}
_PAGE = {"skip": {"type": "integer", "minimum": 0}, "take": {"type": "integer", "minimum": 1, "maximum": 200}}
_DATE = {"type": "string", "format": "date", "description": "YYYY-MM-DD"}


def _schema(properties):
    return {"type": "object", "properties": properties, "additionalProperties": False}


def _props(properties, required=()):
    return {"type": "object", "properties": properties, "required": list(required), "additionalProperties": False}


def _report(method: str, fields):
    def handler(args: Dict[str, Any], context: Dict[str, Any]):
        from app.services import warehouse_reports_service as svc
        db, bid = context["db"], int(context["business_id"])
        values = {key: args[key] for key in fields if key in args}
        return getattr(svc, method)(db=db, business_id=bid, **values)
    return handler


def register_mcp_warehouse_report_functions(registry) -> None:
    common_dates = {"date_from": _DATE, "date_to": _DATE}
    _rk = dict(allowed_roles=_ROLES, category="warehouse")
    registry.register(AIFunction(name="get_warehouse_documents_summary", description="گزارش خلاصه حواله‌های posted بر اساس نوع، تاریخ و انبار؛ حداکثر ۲۰۰ ردیف در صفحه.",
        parameters_schema=_props({**common_dates, "doc_types": {"type": "array", "maxItems": 10, "items": {"type": "string", "maxLength": 40}}, "warehouse_ids": _IDS, "status": {"type": "string", "enum": ["draft", "posted", "cancelled"]}, **_PAGE}),
        handler=_report("get_warehouse_documents_summary_report", ("date_from", "date_to", "doc_types", "warehouse_ids", "status", "skip", "take")), required_permissions=["reports.view"], is_readonly=True, **_rk))
    registry.register(AIFunction(name="get_slow_moving_warehouse_items", description="کالاهای بدون حرکت تا تاریخ/بازهٔ روز تعیین‌شده با فیلتر انبار و دسته؛ حداکثر ۲۰۰ ردیف.",
        parameters_schema=_props({"days_without_movement": {"type": "integer", "minimum": 1, "maximum": 3650}, "warehouse_ids": _IDS, "category_ids": _IDS, **_PAGE}),
        handler=_report("get_slow_moving_items_report", ("days_without_movement", "warehouse_ids", "category_ids", "skip", "take")), required_permissions=["reports.view"], is_readonly=True, **_rk))
    registry.register(AIFunction(name="get_critical_stock_report", description="فهرست کالاهای انبارداری زیر نقطه سفارش در تاریخ انتخابی؛ حداکثر ۲۰۰ ردیف.",
        parameters_schema=_props({"warehouse_ids": _IDS, "category_ids": _IDS, "as_of_date": _DATE, **_PAGE}),
        handler=_report("get_critical_stock_report", ("warehouse_ids", "category_ids", "as_of_date", "skip", "take")), required_permissions=["reports.view"], is_readonly=True, **_rk))
    registry.register(AIFunction(name="get_inter_warehouse_transfers_report", description="گزارش حواله‌های انتقال posted با فیلتر تاریخ، انبار مبدأ/مقصد و صفحه‌بندی محدود.",
        parameters_schema=_props({**common_dates, "warehouse_from_ids": _IDS, "warehouse_to_ids": _IDS, **_PAGE}),
        handler=_report("get_inter_warehouse_transfers_report", ("date_from", "date_to", "warehouse_from_ids", "warehouse_to_ids", "skip", "take")), required_permissions=["reports.view"], is_readonly=True, **_rk))
    registry.register(AIFunction(name="get_warehouse_adjustment_report", description="گزارش حواله‌های تعدیل posted و تغییر خالص موجودی با فیلتر تاریخ و انبار.",
        parameters_schema=_props({**common_dates, "warehouse_ids": _IDS, **_PAGE}),
        handler=_report("get_adjustment_documents_report", ("date_from", "date_to", "warehouse_ids", "skip", "take")), required_permissions=["reports.view"], is_readonly=True, **_rk))
    registry.register(AIFunction(name="get_warehouse_performance_report", description="مقایسه تعداد حواله، اقلام، ورود/خروج و خالص حرکت انبارها؛ در صورت امکان warehouse_ids را برای محدودسازی بفرست.",
        parameters_schema=_props({**common_dates, "warehouse_ids": _IDS}),
        handler=_report("get_warehouse_performance_report", ("date_from", "date_to", "warehouse_ids")), required_permissions=["reports.view"], is_readonly=True, **_rk))
    registry.register(AIFunction(name="get_product_movement_history", description="تاریخچه گردش یک کالا در انبارها. product_id باید از search_products گرفته شود؛ حداکثر ۲۰۰ حرکت.",
        parameters_schema=_props({"product_id": {"type": "integer", "minimum": 1}, **common_dates, "warehouse_ids": _IDS, **_PAGE}, ["product_id"]),
        handler=_report("get_product_movement_history_report", ("product_id", "date_from", "date_to", "warehouse_ids", "skip", "take")), required_permissions=["reports.view"], is_readonly=True, **_rk))
    registry.register(AIFunction(name="get_inventory_valuation_report", description="ارزش موجودی به ارز پایه کسب‌وکار در تاریخ انتخابی؛ currency_id روی قرارداد API پذیرفته می‌شود اما گزارش همیشه ارز پایه است. حداکثر ۲۰۰ ردیف.",
        parameters_schema=_props({"as_of_date": _DATE, "warehouse_ids": _IDS, "category_ids": _IDS, "currency_id": {"type": "integer", "minimum": 1}, **_PAGE}),
        handler=_report("get_inventory_valuation_report", ("as_of_date", "warehouse_ids", "category_ids", "currency_id", "skip", "take")), required_permissions=["reports.view"], is_readonly=True, **_rk))
    registry.register(AIFunction(name="get_pending_warehouse_documents", description="حواله‌های draft در انتظار اقدام، به تفکیک انبار؛ حداکثر ۲۰۰ ردیف.",
        parameters_schema=_props({"warehouse_ids": _IDS, **_PAGE}),
        handler=_report("get_pending_documents_report", ("warehouse_ids", "skip", "take")), required_permissions=["reports.view"], is_readonly=True, **_rk))
    registry.register(AIFunction(name="get_inventory_turnover_report", description="نرخ گردش کالا در بازه، دسته و انبار؛ حداکثر ۲۰۰ ردیف.",
        parameters_schema=_props({**common_dates, "warehouse_ids": _IDS, "category_ids": _IDS, **_PAGE}),
        handler=_report("get_inventory_turnover_report", ("date_from", "date_to", "warehouse_ids", "category_ids", "skip", "take")), required_permissions=["reports.view"], is_readonly=True, **_rk))
    registry.register(AIFunction(name="get_expiry_stock_report", description="گزارش موجودی لات‌های تاریخ‌دار به‌تفکیک وضعیت انقضا؛ حداکثر ۲۰۰ ردیف.",
        parameters_schema=_props({"warehouse_ids": _IDS, "statuses": {"type": "array", "maxItems": 10, "items": {"type": "string", "enum": ["sellable", "near_expiry", "blocked", "expired", "undated"]}}, "as_of_date": _DATE, **_PAGE}),
        handler=_report("get_expiry_stock_report", ("warehouse_ids", "statuses", "as_of_date", "skip", "take")), required_permissions=["reports.view"], is_readonly=True, **_rk))

    def list_inventory_lots_handler(args: Dict[str, Any], context: Dict[str, Any]):
        from datetime import date as _date

        from app.services.inventory_lot_service import business_as_of, list_lot_balances

        db, bid = context["db"], int(context["business_id"])
        explicit = None
        raw = args.get("as_of_date")
        if raw:
            explicit = _date.fromisoformat(str(raw)[:10])
        as_of = business_as_of(bid, explicit)
        warehouse_id = int(args["warehouse_id"]) if args.get("warehouse_id") is not None else None
        variant_id = int(args["variant_id"]) if args.get("variant_id") is not None else None
        items = list_lot_balances(
            db,
            bid,
            int(args["product_id"]),
            warehouse_id,
            as_of,
            sellable_only=bool(args.get("sellable_only")),
            variant_id=variant_id,
        )
        return {"items": items, "as_of_date": as_of.isoformat()}

    registry.register(AIFunction(
        name="list_inventory_lots",
        description="موجودی لات‌های تاریخ‌دار یک کالا در انبار؛ product_id را از search_products بگیر.",
        parameters_schema={
            "type": "object",
            "properties": {
                "product_id": {"type": "integer", "minimum": 1},
                "warehouse_id": {"type": "integer", "minimum": 1},
                "variant_id": {"type": "integer", "minimum": 1},
                "sellable_only": {"type": "boolean"},
                "as_of_date": _DATE,
            },
            "required": ["product_id"],
            "additionalProperties": False,
        },
        handler=list_inventory_lots_handler,
        allowed_roles=_ROLES,
        required_permissions=["inventory.read"],
        category="warehouse",
        is_readonly=True,
    ))
