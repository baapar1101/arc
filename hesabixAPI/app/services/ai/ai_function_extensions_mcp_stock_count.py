"""MCP tools for bounded stock-count workflows."""
from __future__ import annotations

from datetime import date
from typing import Any, Dict

from app.services.ai.function_registry import AIRole, AIFunction

_ROLES = {AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN}


def _schema(properties, required):
    return {"type": "object", "properties": properties, "required": required, "additionalProperties": False}


def _register(registry, name, description, schema, handler, *, write=False, high=False):
    registry.register(AIFunction(name=name, description=description, parameters_schema=schema, handler=handler,
        allowed_roles=_ROLES, required_permissions=["inventory.write" if write else "inventory.read"],
        category="warehouse", requires_approval=bool(write), risk_level="high" if high else ("medium" if write else "safe"), is_readonly=not write))


def register_mcp_stock_count_functions(registry) -> None:
    _register(registry, "start_stock_count", "شروع انبارگردانی برای یک انبار و حداکثر ۵۰۰ کالای انتخاب‌شده؛ برای پوشش کامل کالاها چند فراخوانی محدود انجام دهید.",
        _schema({"warehouse_id": {"type": "integer", "minimum": 1}, "product_ids": {"type": "array", "minItems": 1, "maxItems": 500, "uniqueItems": True, "items": {"type": "integer", "minimum": 1}},
            "as_of_date": {"type": "string", "format": "date"}, "only_with_warehouse_history": {"type": "boolean"}}, ["warehouse_id", "product_ids"]), _start)
    item_schema = {"type": "object", "properties": {"product_id": {"type": "integer", "minimum": 1}, "warehouse_id": {"type": ["integer", "null"], "minimum": 1},
        "physical_quantity": {"type": "number", "minimum": 0}}, "required": ["product_id", "physical_quantity"], "additionalProperties": False}
    _register(registry, "calculate_stock_count_differences", "محاسبه تفاوت موجودی فیزیکی با موجودی سیستمی؛ شناسه محصول و مقدار واقعی برای حداکثر ۵۰۰ ردیف لازم است.",
        _schema({"items": {"type": "array", "minItems": 1, "maxItems": 500, "items": item_schema}, "as_of_date": {"type": "string", "format": "date"}}, ["items"]), _calculate)
    adjustment_item = {"type": "object", "properties": {"product_id": {"type": "integer", "minimum": 1}, "warehouse_id": {"type": ["integer", "null"], "minimum": 1},
        "difference": {"type": "number"}, "movement": {"type": ["string", "null"], "enum": ["in", "out", None]}, "quantity": {"type": "number", "minimum": 0}},
        "required": ["product_id", "difference", "quantity"], "additionalProperties": False}
    _register(registry, "create_stock_count_adjustment", "ایجاد نتیجه انبارگردانی طبق تنظیم فعلی کسب‌وکار؛ ممکن است حواله تعدیل یا اسناد کالای هزینه/درآمد ایجاد کند. نیازمند تأیید است.",
        _schema({"items": {"type": "array", "minItems": 1, "maxItems": 500, "items": adjustment_item}, "stock_count_code": {"type": "string", "maxLength": 80},
            "stock_count_date": {"type": "string", "format": "date"}, "notes": {"type": ["string", "null"], "maxLength": 2000},
            "result_mode": {"type": "string", "enum": ["goods_docs", "physical_adjustment"]}}, ["items"]), _create_adjustment, write=True, high=True)


def _require_permission(ctx, business_id: int, action: str) -> None:
    if not ctx.can_access_business(business_id) or not ctx.has_business_permission("inventory", action):
        raise ValueError(f"برای این عملیات inventory.{action} لازم است")


def _start(args: Dict[str, Any], context: Dict[str, Any]):
    from app.services.warehouse_service import start_stock_count
    db, bid, ctx = context["db"], int(context["business_id"]), context["user_context"]
    _require_permission(ctx, bid, "read")
    warehouse_id = int(args["warehouse_id"])
    as_of_date = date.fromisoformat(args["as_of_date"]) if args.get("as_of_date") else None
    result = start_stock_count(db, bid, warehouse_id, [int(x) for x in args["product_ids"]], as_of_date,
        only_with_warehouse_history=bool(args.get("only_with_warehouse_history", False)))
    if len(result.get("items") or []) > 500:
        raise ValueError("نتیجه از سقف ۵۰۰ ردیف بیشتر است؛ محصول‌ها را به گروه‌های کوچک‌تر تقسیم کنید")
    return result


def _calculate(args: Dict[str, Any], context: Dict[str, Any]):
    from app.services.warehouse_service import calculate_stock_count_differences
    db, bid, ctx = context["db"], int(context["business_id"]), context["user_context"]
    _require_permission(ctx, bid, "read")
    as_of_date = date.fromisoformat(args["as_of_date"]) if args.get("as_of_date") else None
    return calculate_stock_count_differences(db, bid, args["items"], as_of_date=as_of_date)


def _create_adjustment(args: Dict[str, Any], context: Dict[str, Any]):
    from datetime import datetime
    from app.core.permissions import has_business_permission_for_business
    from app.services.warehouse_service import create_stock_count_adjustment, warehouse_document_to_dict
    from app.services.goods_expense_income_service import (
        STOCK_COUNT_ASK, STOCK_COUNT_GOODS_DOCS, STOCK_COUNT_PHYSICAL, create_from_stock_count, get_workflow_settings,
    )
    from adapters.db.models.business import Business

    db, bid, ctx = context["db"], int(context["business_id"]), context["user_context"]
    _require_permission(ctx, bid, "write")
    biz = db.query(Business).filter(Business.id == bid).first()
    settings = get_workflow_settings(biz) if biz else {"stock_count_mode": STOCK_COUNT_GOODS_DOCS}
    mode = str(args.get("result_mode") or settings.get("stock_count_mode") or STOCK_COUNT_GOODS_DOCS).strip().lower()
    if mode == STOCK_COUNT_ASK and args.get("result_mode") not in (STOCK_COUNT_GOODS_DOCS, STOCK_COUNT_PHYSICAL):
        return {"needs_choice": True, "options": [STOCK_COUNT_GOODS_DOCS, STOCK_COUNT_PHYSICAL], "settings": settings}
    if mode not in (STOCK_COUNT_GOODS_DOCS, STOCK_COUNT_PHYSICAL):
        raise ValueError("result_mode نامعتبر است")
    count_date = date.fromisoformat(args["stock_count_date"]) if args.get("stock_count_date") else datetime.now().date()
    count_code = (args.get("stock_count_code") or "").strip() or f"INV-{datetime.now().strftime('%Y%m%d-%H%M%S')}"
    if mode == STOCK_COUNT_GOODS_DOCS:
        if not has_business_permission_for_business(ctx, db, bid, "goods_expense_income", "add"):
            raise ValueError("ثبت کالاهای هزینه/درآمد به مجوز goods_expense_income.add نیاز دارد")
        created = create_from_stock_count(db, bid, ctx.get_user_id(), stock_count_code=count_code,
            stock_count_date=count_date, items=args["items"], notes=args.get("notes"),
            user_can_allocate=has_business_permission_for_business(ctx, db, bid, "goods_expense_income", "allocate"),
            user_can_post=False, commit=False)
        db.commit()
        return {"mode": STOCK_COUNT_GOODS_DOCS, **created}
    wh = create_stock_count_adjustment(db, bid, ctx.get_user_id(), count_code, count_date, args["items"], args.get("notes"))
    db.commit()
    return warehouse_document_to_dict(db, wh)
