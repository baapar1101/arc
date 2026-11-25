"""MCP tools for product-bundle search and CRUD. Services only; extra_info is out of band."""
from __future__ import annotations

from datetime import datetime
from decimal import Decimal
from typing import Any, Dict

CREATE_PRODUCT_BUNDLE_SCHEMA: Dict[str, Any] = {}
UPDATE_PRODUCT_BUNDLE_SCHEMA: Dict[str, Any] = {}
SEARCH_PRODUCT_BUNDLES_SCHEMA: Dict[str, Any] = {}
EXPAND_PRODUCT_BUNDLE_SCHEMA: Dict[str, Any] = {}

_MAX_ITEMS = 500
_MAX_TAKE = 100


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


_ITEM = {
    "type": "object",
    "additionalProperties": False,
    "required": ["product_id", "quantity"],
    "properties": {
        "product_id": {
            "type": "integer",
            "minimum": 1,
            "description": "شناسه کالا از search_products؛ خدمت در باندل مجاز نیست",
        },
        "quantity": {"type": "number", "exclusiveMinimum": 0},
    },
}
_BUNDLE_ID = _schema({"bundle_id": {"type": "integer", "minimum": 1}}, ["bundle_id"])
SEARCH_PRODUCT_BUNDLES_SCHEMA = _schema(
    {
        "search": {"type": "string", "maxLength": 200},
        "is_active": {"type": "boolean"},
        "take": {"type": "integer", "minimum": 1, "maximum": _MAX_TAKE},
        "skip": {"type": "integer", "minimum": 0},
    }
)
CREATE_PRODUCT_BUNDLE_SCHEMA = _schema(
    {
        "name": {"type": "string", "minLength": 1, "maxLength": 255},
        "description": {"type": ["string", "null"], "maxLength": 5000},
        "is_active": {"type": "boolean"},
        "items": {"type": "array", "minItems": 1, "maxItems": _MAX_ITEMS, "items": _ITEM},
    },
    ["name", "items"],
)
UPDATE_PRODUCT_BUNDLE_SCHEMA = _schema(
    {
        "bundle_id": {"type": "integer", "minimum": 1},
        "name": {"type": "string", "minLength": 1, "maxLength": 255},
        "description": {"type": ["string", "null"], "maxLength": 5000},
        "is_active": {"type": "boolean"},
        "items": {"type": "array", "minItems": 1, "maxItems": _MAX_ITEMS, "items": _ITEM},
    },
    ["bundle_id"],
)
EXPAND_PRODUCT_BUNDLE_SCHEMA = _schema(
    {
        "bundle_id": {"type": "integer", "minimum": 1},
        "quantity": {"type": "number", "exclusiveMinimum": 0, "description": "ضریب تعداد باندل؛ پیش‌فرض ۱"},
    },
    ["bundle_id"],
)
_CREATE_KEYS = ("name", "description", "is_active", "items")
_UPDATE_KEYS = ("name", "description", "is_active", "items")


def _picked(args: Dict[str, Any], keys) -> Dict[str, Any]:
    return {k: v for k, v in args.items() if k in keys}


def search_product_bundles_handler(args, context):
    from app.services.product_bundle_service import search_bundles

    filters = []
    if "is_active" in args:
        filters.append({"property": "is_active", "value": bool(args["is_active"])})
    result = _run(
        search_bundles,
        _db(context),
        _bid(context),
        {
            "search": args.get("search"),
            "take": args.get("take", 20),
            "skip": args.get("skip", 0),
            "filters": filters or None,
        },
    )
    return _jsonable(result)


def get_product_bundle_handler(args, context):
    from app.services.product_bundle_service import get_bundle

    result = get_bundle(_db(context), _bid(context), int(args["bundle_id"]))
    if result is None:
        raise ValueError("باندل در کسب‌وکار متصل یافت نشد.")
    return _jsonable(result)


def create_product_bundle_handler(args, context):
    from adapters.api.v1.schema_models.product_bundle import ProductBundleCreateRequest
    from app.services.product_bundle_service import create_bundle

    payload = ProductBundleCreateRequest(**_picked(args, _CREATE_KEYS))
    return _jsonable(_run(create_bundle, _db(context), _bid(context), payload))


def update_product_bundle_handler(args, context):
    from adapters.api.v1.schema_models.product_bundle import ProductBundleUpdateRequest
    from app.services.product_bundle_service import update_bundle

    bundle_id = int(args["bundle_id"])
    payload = ProductBundleUpdateRequest(**_picked(args, _UPDATE_KEYS))
    result = _run(update_bundle, _db(context), _bid(context), bundle_id, payload)
    if result is None:
        raise ValueError("باندل در کسب‌وکار متصل یافت نشد.")
    return _jsonable(result)


def delete_product_bundle_handler(args, context):
    from app.services.product_bundle_service import delete_bundle

    bundle_id = int(args["bundle_id"])
    deleted = _run(delete_bundle, _db(context), _bid(context), bundle_id)
    if not deleted:
        raise ValueError("باندل در کسب‌وکار متصل یافت نشد.")
    return {"deleted": True, "bundle_id": bundle_id}


def expand_product_bundle_handler(args, context):
    from app.services.product_bundle_service import expand_bundle

    qty = args.get("quantity", 1)
    return _jsonable(
        _run(expand_bundle, _db(context), _bid(context), int(args["bundle_id"]), Decimal(str(qty)))
    )


def register_mcp_bundle_functions(registry) -> None:
    from app.services.ai.function_registry import AIFunction, AIRole

    roles = {AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN}
    registry.register(AIFunction(
        name="search_product_bundles",
        description="جستجوی باندل کالا در کسب‌وکار متصل. حداکثر ۱۰۰ مورد در صفحه.",
        parameters_schema=SEARCH_PRODUCT_BUNDLES_SCHEMA,
        handler=search_product_bundles_handler,
        allowed_roles=roles,
        required_permissions=["products.read"],
        category="products",
        is_readonly=True,
    ))
    registry.register(AIFunction(
        name="get_product_bundle",
        description="جزئیات یک باندل کالا متعلق به کسب‌وکار متصل، شامل اقلام.",
        parameters_schema=_BUNDLE_ID,
        handler=get_product_bundle_handler,
        allowed_roles=roles,
        required_permissions=["products.read"],
        category="products",
        is_readonly=True,
    ))
    registry.register(AIFunction(
        name="create_product_bundle",
        description="ثبت باندل کالا. فقط کالای همین کسب‌وکار؛ خدمت مجاز نیست. نیاز به تأیید.",
        parameters_schema=CREATE_PRODUCT_BUNDLE_SCHEMA,
        handler=create_product_bundle_handler,
        allowed_roles=roles,
        required_permissions=["products.write"],
        category="products",
        requires_approval=True,
        risk_level="medium",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="update_product_bundle",
        description="ویرایش نام، وضعیت یا اقلام باندل کسب‌وکار متصل. ارسال items جایگزین کامل اقلام است.",
        parameters_schema=UPDATE_PRODUCT_BUNDLE_SCHEMA,
        handler=update_product_bundle_handler,
        allowed_roles=roles,
        required_permissions=["products.write"],
        category="products",
        requires_approval=True,
        risk_level="medium",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="delete_product_bundle",
        description="حذف باندل کالا متعلق به کسب‌وکار متصل. نیازمند تأیید.",
        parameters_schema=_BUNDLE_ID,
        handler=delete_product_bundle_handler,
        allowed_roles=roles,
        required_permissions=["products.delete"],
        category="products",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="expand_product_bundle",
        description="گسترش باندل فعال به اقلام کالا با ضریب تعداد، برای افزودن به فاکتور. نوشتن نیست.",
        parameters_schema=EXPAND_PRODUCT_BUNDLE_SCHEMA,
        handler=expand_product_bundle_handler,
        allowed_roles=roles,
        required_permissions=["products.read"],
        category="products",
        is_readonly=True,
    ))
