"""MCP tools for product category tree write. Repository update/delete lack tenant checks; MCP pins them."""
from __future__ import annotations

from typing import Any, Dict

CREATE_PRODUCT_CATEGORY_SCHEMA: Dict[str, Any] = {}
UPDATE_PRODUCT_CATEGORY_SCHEMA: Dict[str, Any] = {}
MOVE_PRODUCT_CATEGORY_SCHEMA: Dict[str, Any] = {}


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


def _public_category(row: Any, *, language: str = "fa") -> Dict[str, Any]:
    trans = row.title_translations or {}
    return {
        "id": row.id,
        "parent_id": row.parent_id,
        "label": trans.get(language) or trans.get("fa") or trans.get("en"),
        "translations": trans,
        "description": row.description,
        "sort_order": getattr(row, "sort_order", 0),
    }


def _load_tenant_category(db, business_id: int, category_id: int):
    from adapters.db.models.category import BusinessCategory

    row = db.get(BusinessCategory, int(category_id))
    if not row or int(row.business_id) != int(business_id):
        raise ValueError("دسته‌بندی در کسب‌وکار متصل یافت نشد.")
    return row


def _ensure_parent_tenant(db, business_id: int, parent_id: Any) -> None:
    if parent_id is None:
        return
    _load_tenant_category(db, business_id, int(parent_id))


CREATE_PRODUCT_CATEGORY_SCHEMA = _schema(
    {
        "label": {"type": "string", "minLength": 1, "maxLength": 255, "description": "نام دسته به فارسی"},
        "description": {"type": ["string", "null"], "maxLength": 2000},
        "parent_id": {
            "type": ["integer", "null"],
            "minimum": 1,
            "description": "دسته والد از search_categories یا get_product_category_tree",
        },
    },
    ["label"],
)
UPDATE_PRODUCT_CATEGORY_SCHEMA = _schema(
    {
        "category_id": {"type": "integer", "minimum": 1},
        "label": {"type": "string", "minLength": 1, "maxLength": 255},
        "description": {"type": ["string", "null"], "maxLength": 2000},
        "sort_order": {"type": "integer", "minimum": 0, "maximum": 100000},
        "parent_id": {"type": ["integer", "null"], "minimum": 1},
    },
    ["category_id"],
)
MOVE_PRODUCT_CATEGORY_SCHEMA = _schema(
    {
        "category_id": {"type": "integer", "minimum": 1},
        "new_parent_id": {
            "type": ["integer", "null"],
            "minimum": 1,
            "description": "والد جدید؛ null یعنی ریشه",
        },
    },
    ["category_id"],
)
_CATEGORY_ID = _schema({"category_id": {"type": "integer", "minimum": 1}}, ["category_id"])


def _map_tree(nodes: list) -> list:
    mapped = []
    for node in nodes or []:
        children = node.get("children") or []
        mapped.append(
            {
                "id": node.get("id"),
                "parent_id": node.get("parent_id"),
                "label": node.get("title") or "",
                "translations": node.get("translations") or {},
                "description": node.get("description"),
                "sort_order": node.get("sort_order", 0),
                "children": _map_tree(children) if isinstance(children, list) else [],
            }
        )
    return mapped


def get_product_category_tree_handler(args, context):
    from adapters.db.repositories.category_repository import CategoryRepository

    tree = CategoryRepository(_db(context)).get_tree(_bid(context), None)
    return {"items": _map_tree(tree)}


def create_product_category_handler(args, context):
    from adapters.db.repositories.category_repository import CategoryRepository

    db = _db(context)
    bid = _bid(context)
    label = str(args.get("label") or "").strip()
    if not label:
        raise ValueError("نام دسته‌بندی الزامی است.")
    parent_id = args.get("parent_id")
    _ensure_parent_tenant(db, bid, parent_id)
    description = args.get("description")
    if isinstance(description, str):
        description = description.strip() or None
    row = _run(
        CategoryRepository(db).create_category,
        business_id=bid,
        parent_id=int(parent_id) if parent_id is not None else None,
        translations={"fa": label, "en": label},
        description=description,
    )
    return _public_category(row)


def update_product_category_handler(args, context):
    from adapters.db.repositories.category_repository import CategoryRepository

    db = _db(context)
    bid = _bid(context)
    category_id = int(args["category_id"])
    _load_tenant_category(db, bid, category_id)
    parent_id = args.get("parent_id") if "parent_id" in args else None
    if parent_id is not None:
        _ensure_parent_tenant(db, bid, parent_id)
    label = args.get("label")
    translations = {"fa": label, "en": label} if isinstance(label, str) and label.strip() else None
    description = args.get("description") if "description" in args else None
    if isinstance(description, str):
        description = description.strip()
    try:
        row = CategoryRepository(db).update_category(
            category_id=category_id,
            translations=translations,
            description=description,
            sort_order=args.get("sort_order"),
            parent_id=int(parent_id) if parent_id is not None else None,
        )
    except ValueError as exc:
        raise ValueError(str(exc)) from exc
    if row is None:
        raise ValueError("دسته‌بندی در کسب‌وکار متصل یافت نشد.")
    return _public_category(row)


def move_product_category_handler(args, context):
    from adapters.db.repositories.category_repository import CategoryRepository

    db = _db(context)
    bid = _bid(context)
    category_id = int(args["category_id"])
    _load_tenant_category(db, bid, category_id)
    new_parent_id = args.get("new_parent_id")
    repo = CategoryRepository(db)
    try:
        if new_parent_id is not None:
            _ensure_parent_tenant(db, bid, int(new_parent_id))
            row = repo.update_category(category_id=category_id, parent_id=int(new_parent_id))
        else:
            row = repo.move_category(category_id=category_id, new_parent_id=None)
    except ValueError as exc:
        raise ValueError(str(exc)) from exc
    if row is None:
        raise ValueError("دسته‌بندی در کسب‌وکار متصل یافت نشد.")
    return _public_category(row)


def delete_product_category_handler(args, context):
    from adapters.db.repositories.category_repository import CategoryRepository

    db = _db(context)
    bid = _bid(context)
    category_id = int(args["category_id"])
    _load_tenant_category(db, bid, category_id)
    ok = CategoryRepository(db).delete_category(category_id=category_id)
    if not ok:
        raise ValueError("دسته‌بندی در کسب‌وکار متصل یافت نشد.")
    return {"deleted": True, "category_id": category_id}


def register_mcp_category_functions(registry) -> None:
    from app.services.ai.function_registry import AIFunction, AIRole

    roles = {AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN}
    registry.register(AIFunction(
        name="get_product_category_tree",
        description="درخت دسته‌بندی کالا/خدمت کسب‌وکار متصل.",
        parameters_schema=_schema({}),
        handler=get_product_category_tree_handler,
        allowed_roles=roles,
        required_permissions=["categories.view"],
        category="products",
        is_readonly=True,
    ))
    registry.register(AIFunction(
        name="create_product_category",
        description="ثبت دسته‌بندی کالا. والد باید متعلق به همین کسب‌وکار باشد. نیاز به تأیید.",
        parameters_schema=CREATE_PRODUCT_CATEGORY_SCHEMA,
        handler=create_product_category_handler,
        allowed_roles=roles,
        required_permissions=["categories.write"],
        category="products",
        requires_approval=True,
        risk_level="medium",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="update_product_category",
        description="ویرایش نام، توضیح، ترتیب یا والد دسته‌بندی کسب‌وکار متصل.",
        parameters_schema=UPDATE_PRODUCT_CATEGORY_SCHEMA,
        handler=update_product_category_handler,
        allowed_roles=roles,
        required_permissions=["categories.write"],
        category="products",
        requires_approval=True,
        risk_level="medium",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="move_product_category",
        description="جابجایی دسته‌بندی در درخت همان کسب‌وکار. new_parent_id تهی یعنی ریشه.",
        parameters_schema=MOVE_PRODUCT_CATEGORY_SCHEMA,
        handler=move_product_category_handler,
        allowed_roles=roles,
        required_permissions=["categories.write"],
        category="products",
        requires_approval=True,
        risk_level="medium",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="delete_product_category",
        description="حذف دسته‌بندی کسب‌وکار متصل. کالاهای منتسب دسته را از دست می‌دهند. نیازمند تأیید.",
        parameters_schema=_CATEGORY_ID,
        handler=delete_product_category_handler,
        allowed_roles=roles,
        required_permissions=["categories.delete"],
        category="products",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
