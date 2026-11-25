"""MCP tools for price-list write cycle. Existing list tools stay in phase3."""
from __future__ import annotations

from datetime import datetime
from decimal import Decimal
from typing import Any, Dict

CREATE_PRICE_LIST_SCHEMA: Dict[str, Any] = {}
UPDATE_PRICE_LIST_SCHEMA: Dict[str, Any] = {}
UPSERT_PRICE_LIST_ITEM_SCHEMA: Dict[str, Any] = {}


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


def _jsonable(value: Any) -> Any:
    if isinstance(value, datetime):
        return value.isoformat()
    if isinstance(value, Decimal):
        return float(value)
    if isinstance(value, dict):
        return {k: _jsonable(v) for k, v in value.items()}
    if isinstance(value, list):
        return [_jsonable(v) for v in value]
    return value


def _unwrap(result: Any) -> Any:
    if isinstance(result, dict) and "data" in result:
        return _jsonable(result["data"])
    return _jsonable(result)


_PRICE_LIST_ID = _schema({"price_list_id": {"type": "integer", "minimum": 1}}, ["price_list_id"])
CREATE_PRICE_LIST_SCHEMA = _schema(
    {
        "name": {"type": "string", "minLength": 1, "maxLength": 255},
        "is_active": {"type": "boolean"},
    },
    ["name"],
)
UPDATE_PRICE_LIST_SCHEMA = _schema(
    {
        "price_list_id": {"type": "integer", "minimum": 1},
        "name": {"type": "string", "minLength": 1, "maxLength": 255},
        "is_active": {"type": "boolean"},
    },
    ["price_list_id"],
)
UPSERT_PRICE_LIST_ITEM_SCHEMA = _schema(
    {
        "price_list_id": {"type": "integer", "minimum": 1, "description": "شناسه از list_price_lists"},
        "product_id": {"type": "integer", "minimum": 1, "description": "شناسه کالا از search_products"},
        "currency_id": {"type": "integer", "minimum": 1, "description": "شناسه ارز از list_currencies"},
        "price": {"type": "number", "minimum": 0},
        "unit_id": {"type": ["integer", "null"], "minimum": 1},
        "tier_name": {"type": ["string", "null"], "minLength": 1, "maxLength": 64},
        "min_qty": {"type": "number", "minimum": 0},
    },
    ["price_list_id", "product_id", "currency_id", "price"],
)
_ITEM_ID = _schema({"item_id": {"type": "integer", "minimum": 1}}, ["item_id"])
_LIST_KEYS = ("name", "is_active")
_ITEM_KEYS = ("product_id", "currency_id", "price", "unit_id", "tier_name", "min_qty")


def _picked(args: Dict[str, Any], keys) -> Dict[str, Any]:
    return {k: v for k, v in args.items() if k in keys}


def get_price_list_handler(args, context):
    from app.services.price_list_service import get_price_list

    result = get_price_list(_db(context), _bid(context), int(args["price_list_id"]))
    if result is None:
        raise ValueError("لیست قیمت در کسب‌وکار متصل یافت نشد.")
    return _jsonable(result)


def create_price_list_handler(args, context):
    from adapters.api.v1.schema_models.price_list import PriceListCreateRequest
    from app.services.price_list_service import create_price_list

    payload = PriceListCreateRequest(**_picked(args, _LIST_KEYS))
    return _unwrap(_run(create_price_list, _db(context), _bid(context), payload))


def update_price_list_handler(args, context):
    from adapters.api.v1.schema_models.price_list import PriceListUpdateRequest
    from app.services.price_list_service import update_price_list

    payload = PriceListUpdateRequest(**_picked(args, _LIST_KEYS))
    result = _run(update_price_list, _db(context), _bid(context), int(args["price_list_id"]), payload)
    if result is None:
        raise ValueError("لیست قیمت در کسب‌وکار متصل یافت نشد.")
    return _unwrap(result)


def delete_price_list_handler(args, context):
    from app.services.price_list_service import delete_price_list

    price_list_id = int(args["price_list_id"])
    ok = _run(delete_price_list, _db(context), _bid(context), price_list_id)
    if not ok:
        raise ValueError("لیست قیمت در کسب‌وکار متصل یافت نشد.")
    return {"deleted": True, "price_list_id": price_list_id}


def upsert_price_list_item_handler(args, context):
    from adapters.api.v1.schema_models.price_list import PriceItemUpsertRequest
    from app.services.price_list_service import upsert_price_item

    payload = PriceItemUpsertRequest(**_picked(args, _ITEM_KEYS))
    return _unwrap(
        _run(upsert_price_item, _db(context), _bid(context), int(args["price_list_id"]), payload)
    )


def delete_price_list_item_handler(args, context):
    from app.services.price_list_service import delete_price_item

    item_id = int(args["item_id"])
    ok = _run(delete_price_item, _db(context), _bid(context), item_id)
    if not ok:
        raise ValueError("قلم لیست قیمت در کسب‌وکار متصل یافت نشد.")
    return {"deleted": True, "item_id": item_id}


def register_mcp_price_list_functions(registry) -> None:
    from app.services.ai.function_registry import AIFunction, AIRole

    roles = {AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN}
    registry.register(AIFunction(
        name="get_price_list",
        description="جزئیات یک لیست قیمت متعلق به کسب‌وکار متصل.",
        parameters_schema=_PRICE_LIST_ID,
        handler=get_price_list_handler,
        allowed_roles=roles,
        required_permissions=["price_lists.view"],
        category="products",
        is_readonly=True,
    ))
    registry.register(AIFunction(
        name="create_price_list",
        description="ثبت لیست قیمت جدید برای کسب‌وکار متصل. نیاز به تأیید.",
        parameters_schema=CREATE_PRICE_LIST_SCHEMA,
        handler=create_price_list_handler,
        allowed_roles=roles,
        required_permissions=["price_lists.write"],
        category="products",
        requires_approval=True,
        risk_level="medium",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="update_price_list",
        description="ویرایش نام یا وضعیت لیست قیمت کسب‌وکار متصل.",
        parameters_schema=UPDATE_PRICE_LIST_SCHEMA,
        handler=update_price_list_handler,
        allowed_roles=roles,
        required_permissions=["price_lists.write"],
        category="products",
        requires_approval=True,
        risk_level="medium",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="delete_price_list",
        description="حذف لیست قیمت متعلق به کسب‌وکار متصل. نیازمند تأیید.",
        parameters_schema=_PRICE_LIST_ID,
        handler=delete_price_list_handler,
        allowed_roles=roles,
        required_permissions=["price_lists.delete"],
        category="products",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="upsert_price_list_item",
        description="ثبت یا به‌روزرسانی قیمت یک کالا در لیست قیمت کسب‌وکار متصل. کالا و لیست باید متعلق به همین کسب‌وکار باشند.",
        parameters_schema=UPSERT_PRICE_LIST_ITEM_SCHEMA,
        handler=upsert_price_list_item_handler,
        allowed_roles=roles,
        required_permissions=["price_lists.write"],
        category="products",
        requires_approval=True,
        risk_level="medium",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="delete_price_list_item",
        description="حذف یک قلم از لیست قیمت کسب‌وکار متصل. نیازمند تأیید.",
        parameters_schema=_ITEM_ID,
        handler=delete_price_list_item_handler,
        allowed_roles=roles,
        required_permissions=["price_lists.delete"],
        category="products",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
