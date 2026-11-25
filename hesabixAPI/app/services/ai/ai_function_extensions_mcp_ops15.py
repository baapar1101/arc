"""MCP leftovers: product categories, POS quick customer, entity activity logs, chart-of-accounts tree."""
from __future__ import annotations

from typing import Any, Dict, List

from app.services.ai.ai_mcp_tool_util import mcp_bid, mcp_db, mcp_jsonable, mcp_run, mcp_schema, mcp_uid

EMPTY = mcp_schema({})
CREATE_CAT = mcp_schema(
    {
        "label": {"type": "string", "minLength": 1, "maxLength": 200},
        "parent_id": {"type": "integer", "minimum": 1},
        "description": {"type": "string", "maxLength": 500},
    },
    ["label"],
)
UPDATE_CAT = mcp_schema(
    {
        "category_id": {"type": "integer", "minimum": 1},
        "label": {"type": "string", "maxLength": 200},
        "description": {"type": "string", "maxLength": 500},
        "sort_order": {"type": "integer"},
        "parent_id": {"type": ["integer", "null"], "minimum": 1},
    },
    ["category_id"],
)
MOVE_CAT = mcp_schema(
    {"category_id": {"type": "integer", "minimum": 1}, "new_parent_id": {"type": ["integer", "null"], "minimum": 1}},
    ["category_id"],
)
CAT_ID = mcp_schema({"category_id": {"type": "integer", "minimum": 1}}, ["category_id"])
QUICK = mcp_schema(
    {"alias_name": {"type": "string", "maxLength": 200}, "mobile": {"type": "string", "maxLength": 32}},
)
ENTITY_LOGS = mcp_schema(
    {"entity_type": {"type": "string", "minLength": 1, "maxLength": 80}, "entity_id": {"type": "string", "minLength": 1, "maxLength": 80}},
    ["entity_type", "entity_id"],
)


def _cat_item(obj, lang: str = "fa") -> Dict[str, Any]:
    tr = obj.title_translations or {}
    return {
        "id": obj.id,
        "parent_id": obj.parent_id,
        "label": tr.get(lang) or tr.get("fa") or tr.get("en"),
        "description": obj.description,
        "sort_order": getattr(obj, "sort_order", 0),
    }


def _owned_category(db, bid: int, category_id: int):
    from adapters.db.models.category import BusinessCategory

    obj = db.get(BusinessCategory, int(category_id))
    if not obj or int(obj.business_id) != int(bid):
        raise ValueError("دسته در این کسب‌وکار یافت نشد")
    return obj


def get_category_tree_handler(args, context):
    from adapters.db.repositories.category_repository import CategoryRepository

    tree = CategoryRepository(mcp_db(context)).get_tree(mcp_bid(context), None)

    def _map(nodes: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        out = []
        for n in nodes or []:
            children = n.get("children") or []
            out.append(
                {
                    "id": n.get("id"),
                    "parent_id": n.get("parent_id"),
                    "label": n.get("title", ""),
                    "sort_order": n.get("sort_order", 0),
                    "children": _map(children) if isinstance(children, list) else [],
                }
            )
        return out

    return {"items": _map(tree)}


def create_product_category_handler(args, context):
    from adapters.db.repositories.category_repository import CategoryRepository

    label = str(args["label"]).strip()
    obj = mcp_run(
        CategoryRepository(mcp_db(context)).create_category,
        business_id=mcp_bid(context),
        parent_id=args.get("parent_id"),
        translations={"fa": label, "en": label},
        description=(str(args["description"]).strip() if args.get("description") else None),
    )
    return {"item": _cat_item(obj)}


def update_product_category_handler(args, context):
    from adapters.db.repositories.category_repository import CategoryRepository

    _owned_category(mcp_db(context), mcp_bid(context), int(args["category_id"]))
    label = args.get("label")
    translations = {"fa": str(label).strip(), "en": str(label).strip()} if isinstance(label, str) and label.strip() else None
    obj = mcp_run(
        CategoryRepository(mcp_db(context)).update_category,
        category_id=int(args["category_id"]),
        translations=translations,
        description=args.get("description"),
        sort_order=args.get("sort_order"),
        parent_id=args.get("parent_id") if "parent_id" in args else None,
    )
    if not obj:
        raise ValueError("دسته یافت نشد")
    return {"item": _cat_item(obj)}


def move_product_category_handler(args, context):
    from adapters.db.repositories.category_repository import CategoryRepository

    _owned_category(mcp_db(context), mcp_bid(context), int(args["category_id"]))
    if args.get("new_parent_id"):
        _owned_category(mcp_db(context), mcp_bid(context), int(args["new_parent_id"]))
    obj = mcp_run(
        CategoryRepository(mcp_db(context)).move_category,
        category_id=int(args["category_id"]),
        new_parent_id=args.get("new_parent_id"),
    )
    if not obj:
        raise ValueError("دسته یافت نشد")
    return {"item": _cat_item(obj)}


def delete_product_category_handler(args, context):
    from adapters.db.repositories.category_repository import CategoryRepository

    _owned_category(mcp_db(context), mcp_bid(context), int(args["category_id"]))
    ok = mcp_run(CategoryRepository(mcp_db(context)).delete_category, category_id=int(args["category_id"]))
    return {"deleted": bool(ok)}


def resolve_or_create_quick_customer_handler(args, context):
    from app.services.customer_quick_entry_service import resolve_or_create_quick_customer

    if not (args.get("alias_name") or args.get("mobile")):
        raise ValueError("نام یا موبایل مشتری لازم است")
    resolution = mcp_run(
        resolve_or_create_quick_customer,
        mcp_db(context),
        business_id=mcp_bid(context),
        alias_name=args.get("alias_name"),
        mobile=args.get("mobile"),
    )
    return mcp_jsonable(
        {
            "created": resolution.created,
            "customers": [
                {"id": p.id, "name": p.alias_name, "mobile": p.mobile}
                for p in (resolution.persons or [])[:20]
            ],
        }
    )


def get_entity_activity_logs_handler(args, context):
    from adapters.db.repositories.activity_log_repo import ActivityLogRepository

    bid = mcp_bid(context)
    logs = ActivityLogRepository(mcp_db(context)).get_by_entity(
        entity_type=str(args["entity_type"]),
        entity_id=str(args["entity_id"]),
        business_id=bid,
    )[:50]
    items = []
    for log in logs:
        items.append(
            {
                "id": log.id,
                "user_id": log.user_id,
                "category": log.category,
                "action": log.action,
                "entity_type": log.entity_type,
                "entity_id": log.entity_id,
                "created_at": log.created_at.isoformat() if log.created_at else None,
            }
        )
    return {"items": items}


def get_accounts_tree_handler(args, context):
    from adapters.db.models.account import Account

    bid = mcp_bid(context)
    rows = (
        mcp_db(context)
        .query(Account)
        .filter((Account.business_id == None) | (Account.business_id == bid))  # noqa: E711
        .order_by(Account.code.asc())
        .all()
    )
    children_map: dict[int, int] = {}
    for r in rows:
        if r.parent_id:
            children_map[r.parent_id] = children_map.get(r.parent_id, 0) + 1
    items = [
        {
            "id": r.id,
            "code": r.code,
            "name": r.name,
            "account_type": r.account_type,
            "parent_id": r.parent_id,
            "is_public": r.business_id is None,
            "has_children": children_map.get(r.id, 0) > 0,
        }
        for r in rows
    ]
    return {"items": items}


def register_mcp_ops15_functions(registry) -> None:
    from app.services.ai.function_registry import AIFunction, AIRole

    roles = {AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN}
    registry.register(AIFunction(name="get_category_tree", description="درخت دسته‌بندی کالاهای کسب‌وکار متصل.", parameters_schema=EMPTY, handler=get_category_tree_handler, allowed_roles=roles, required_permissions=["categories.view"], category="products", is_readonly=True))
    registry.register(AIFunction(name="create_product_category", description="ایجاد دسته کالای جدید. نیازمند تأیید.", parameters_schema=CREATE_CAT, handler=create_product_category_handler, allowed_roles=roles, required_permissions=["categories.write"], category="products", requires_approval=True, risk_level="low", is_readonly=False))
    registry.register(AIFunction(name="update_product_category", description="ویرایش برچسب، شرح یا والد دسته کالا. نیازمند تأیید.", parameters_schema=UPDATE_CAT, handler=update_product_category_handler, allowed_roles=roles, required_permissions=["categories.write"], category="products", requires_approval=True, risk_level="low", is_readonly=False))
    registry.register(AIFunction(name="move_product_category", description="جابه‌جایی دسته کالا در درخت. نیازمند تأیید.", parameters_schema=MOVE_CAT, handler=move_product_category_handler, allowed_roles=roles, required_permissions=["categories.write"], category="products", requires_approval=True, risk_level="medium", is_readonly=False))
    registry.register(AIFunction(name="delete_product_category", description="حذف دسته کالا. نیازمند تأیید.", parameters_schema=CAT_ID, handler=delete_product_category_handler, allowed_roles=roles, required_permissions=["categories.delete"], category="products", requires_approval=True, risk_level="high", is_readonly=False))
    registry.register(AIFunction(name="resolve_or_create_quick_customer", description="یافتن مشتری فروش سریع با موبایل/نام یا ایجاد در صورت نبود. نیازمند تأیید.", parameters_schema=QUICK, handler=resolve_or_create_quick_customer_handler, allowed_roles=roles, required_permissions=["people.write"], category="persons", requires_approval=True, risk_level="medium", is_readonly=False))
    registry.register(AIFunction(name="get_entity_activity_logs", description="تاریخچه تغییرات یک موجودیت در کسب‌وکار متصل (حداکثر ۵۰).", parameters_schema=ENTITY_LOGS, handler=get_entity_activity_logs_handler, allowed_roles=roles, required_permissions=["activity_logs.view"], category="audit", is_readonly=True))
    registry.register(AIFunction(name="get_accounts_tree", description="کدینگ حساب‌ها به‌صورت تخت با parent_id برای ساخت درخت (عمومی + اختصاصی).", parameters_schema=EMPTY, handler=get_accounts_tree_handler, allowed_roles=roles, required_permissions=["chart_of_accounts.view"], category="accounting", is_readonly=True))
