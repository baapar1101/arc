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


def _tool(registry, name, description, properties, handler, required=()):
    registry.register(AIFunction(name=name, description=description, parameters_schema={
        "type": "object", "properties": properties, "required": list(required), "additionalProperties": False,
    }, handler=handler, allowed_roles=_ROLES, required_permissions=["reports.view"], category="warehouse", is_readonly=True))


def _report(method: str, fields):
    def handler(args: Dict[str, Any], context: Dict[str, Any]):
        from app.services import warehouse_reports_service as svc
        db, bid = context["db"], int(context["business_id"])
        values = {key: args[key] for key in fields if key in args}
        return getattr(svc, method)(db=db, business_id=bid, **values)
    return handler


def register_mcp_warehouse_report_functions(registry) -> None:
    common_dates = {"date_from": _DATE, "date_to": _DATE}
    _tool(registry, "get_warehouse_documents_summary", "گزارش خلاصه حواله‌های posted بر اساس نوع، تاریخ و انبار؛ حداکثر ۲۰۰ ردیف در صفحه.",
        {**common_dates, "doc_types": {"type": "array", "maxItems": 10, "items": {"type": "string", "maxLength": 40}}, "warehouse_ids": _IDS,
         "status": {"type": "string", "enum": ["draft", "posted", "cancelled"]}, **_PAGE},
        _report("get_warehouse_documents_summary_report", ("date_from", "date_to", "doc_types", "warehouse_ids", "status", "skip", "take")))
    _tool(registry, "get_slow_moving_warehouse_items", "کالاهای بدون حرکت تا تاریخ/بازهٔ روز تعیین‌شده با فیلتر انبار و دسته؛ حداکثر ۲۰۰ ردیف.",
        {"days_without_movement": {"type": "integer", "minimum": 1, "maximum": 3650}, "warehouse_ids": _IDS,
         "category_ids": _IDS, **_PAGE}, _report("get_slow_moving_items_report", ("days_without_movement", "warehouse_ids", "category_ids", "skip", "take")))
    _tool(registry, "get_critical_stock_report", "فهرست کالاهای انبارداری زیر نقطه سفارش در تاریخ انتخابی؛ حداکثر ۲۰۰ ردیف.",
        {"warehouse_ids": _IDS, "category_ids": _IDS, "as_of_date": _DATE, **_PAGE},
        _report("get_critical_stock_report", ("warehouse_ids", "category_ids", "as_of_date", "skip", "take")))
    _tool(registry, "get_inter_warehouse_transfers_report", "گزارش حواله‌های انتقال posted با فیلتر تاریخ، انبار مبدأ/مقصد و صفحه‌بندی محدود.",
        {**common_dates, "warehouse_from_ids": _IDS, "warehouse_to_ids": _IDS, **_PAGE},
        _report("get_inter_warehouse_transfers_report", ("date_from", "date_to", "warehouse_from_ids", "warehouse_to_ids", "skip", "take")))
    _tool(registry, "get_warehouse_adjustment_report", "گزارش حواله‌های تعدیل posted و تغییر خالص موجودی با فیلتر تاریخ و انبار.",
        {**common_dates, "warehouse_ids": _IDS, **_PAGE},
        _report("get_adjustment_documents_report", ("date_from", "date_to", "warehouse_ids", "skip", "take")))
    _tool(registry, "get_warehouse_performance_report", "مقایسه تعداد حواله، اقلام، ورود/خروج و خالص حرکت انبارها؛ در صورت امکان warehouse_ids را برای محدودسازی بفرست.",
        {**common_dates, "warehouse_ids": _IDS}, _report("get_warehouse_performance_report", ("date_from", "date_to", "warehouse_ids")))
    _tool(registry, "get_product_movement_history", "تاریخچه گردش یک کالا در انبارها. product_id باید از search_products گرفته شود؛ حداکثر ۲۰۰ حرکت.",
        {"product_id": {"type": "integer", "minimum": 1}, **common_dates, "warehouse_ids": _IDS, **_PAGE},
        _report("get_product_movement_history_report", ("product_id", "date_from", "date_to", "warehouse_ids", "skip", "take")), ["product_id"])
    _tool(registry, "get_inventory_valuation_report", "ارزش موجودی به ارز پایه کسب‌وکار در تاریخ انتخابی؛ currency_id روی قرارداد API پذیرفته می‌شود اما گزارش همیشه ارز پایه است. حداکثر ۲۰۰ ردیف.",
        {"as_of_date": _DATE, "warehouse_ids": _IDS, "category_ids": _IDS, "currency_id": {"type": "integer", "minimum": 1}, **_PAGE},
        _report("get_inventory_valuation_report", ("as_of_date", "warehouse_ids", "category_ids", "currency_id", "skip", "take")))
    _tool(registry, "get_pending_warehouse_documents", "حواله‌های draft در انتظار اقدام، به تفکیک انبار؛ حداکثر ۲۰۰ ردیف.",
        {"warehouse_ids": _IDS, **_PAGE}, _report("get_pending_documents_report", ("warehouse_ids", "skip", "take")))
    _tool(registry, "get_inventory_turnover_report", "نرخ گردش کالا در بازه، دسته و انبار؛ حداکثر ۲۰۰ ردیف.",
        {**common_dates, "warehouse_ids": _IDS, "category_ids": _IDS, **_PAGE},
        _report("get_inventory_turnover_report", ("date_from", "date_to", "warehouse_ids", "category_ids", "skip", "take")))
