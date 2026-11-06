"""MCP leftovers: lot-date preview and HScript docs/validate (no ZIP restore)."""
from __future__ import annotations

from datetime import date

from app.services.ai.ai_mcp_tool_util import mcp_bid, mcp_db, mcp_jsonable, mcp_schema

LOT_PREVIEW = mcp_schema(
    {
        "product_id": {"type": "integer", "minimum": 1},
        "manufacturing_date": {"type": "string", "format": "date"},
        "expiry_date": {"type": "string", "format": "date"},
    },
    ["product_id"],
)
EMPTY = mcp_schema({})
DOC_ID = mcp_schema({"doc_id": {"type": "string", "minLength": 1, "maxLength": 80}}, ["doc_id"])
DOC_SEARCH = mcp_schema(
    {"query": {"type": "string", "minLength": 1, "maxLength": 200}, "take": {"type": "integer", "minimum": 1, "maximum": 8}},
    ["query"],
)
ASSIST = mcp_schema(
    {
        "query": {"type": "string", "minLength": 1, "maxLength": 400},
        "source_code": {"type": "string", "maxLength": 8000},
        "take": {"type": "integer", "minimum": 1, "maximum": 8},
    },
    ["query"],
)
VALIDATE = mcp_schema({"source_code": {"type": "string", "minLength": 1, "maxLength": 20000}}, ["source_code"])


def preview_inventory_lot_dates_handler(args, context):
    from adapters.db.models.product import Product
    from app.services.inventory_lot_service import _as_date, compute_lot_dates

    bid = mcp_bid(context)
    product = (
        mcp_db(context)
        .query(Product)
        .filter(Product.id == int(args["product_id"]), Product.business_id == bid)
        .first()
    )
    if product is None:
        raise ValueError("کالا در این کسب‌وکار یافت نشد")
    dates = compute_lot_dates(
        product,
        manufacturing_date=_as_date(args.get("manufacturing_date")),
        expiry_date=_as_date(args.get("expiry_date")),
    )
    return {k: (v.isoformat() if isinstance(v, date) else v) for k, v in dates.items()}


def list_hscript_docs_manifest_handler(args, context):
    from app.services.hscript.docs_catalog import list_doc_manifest

    mcp_bid(context)
    data = list_doc_manifest()
    entries = [
        {"doc_id": e.get("doc_id"), "title": e.get("title"), "tags": e.get("tags")}
        for e in (data.get("entries") or [])
    ]
    return {"language_version": data.get("language_version"), "items": entries}


def get_hscript_doc_handler(args, context):
    from app.services.hscript.docs_catalog import read_doc_by_id

    mcp_bid(context)
    item = read_doc_by_id(str(args["doc_id"]))
    if not item:
        raise ValueError("مستند HScript یافت نشد")
    content = item.get("content") or ""
    if len(content) > 20000:
        content = content[:20000]
    return mcp_jsonable(
        {
            "doc_id": item.get("doc_id"),
            "title": item.get("title"),
            "tags": item.get("tags"),
            "missing": item.get("missing"),
            "content": content,
            "truncated": len(item.get("content") or "") > 20000,
        }
    )


def search_hscript_docs_handler(args, context):
    from app.services.hscript.docs_catalog import search_docs

    mcp_bid(context)
    take = min(int(args.get("take") or 5), 8)
    items = search_docs(str(args["query"]), limit=take)
    slim = []
    for e in items or []:
        slim.append({"doc_id": e.get("doc_id"), "title": e.get("title"), "tags": e.get("tags")})
    return {"items": slim}


def get_hscript_assist_context_handler(args, context):
    from app.services.hscript_report_service import build_assist_context

    mcp_bid(context)
    take = min(int(args.get("take") or 5), 8)
    return mcp_jsonable(
        build_assist_context(str(args["query"]), source_code=args.get("source_code"), limit=take)
    )


def validate_hscript_source_handler(args, context):
    from app.services.hscript_report_service import validate_only

    mcp_bid(context)
    return mcp_jsonable(validate_only(str(args["source_code"])))


def register_mcp_ops17_functions(registry) -> None:
    from app.services.ai.function_registry import AIFunction, AIRole

    roles = {AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN}
    registry.register(AIFunction(name="preview_inventory_lot_dates", description="پیش‌نمایش تاریخ تولید/انقضای لات بر اساس تنظیمات کالا؛ چیزی ثبت نمی‌شود.", parameters_schema=LOT_PREVIEW, handler=preview_inventory_lot_dates_handler, allowed_roles=roles, required_permissions=["products.read"], category="warehouse", is_readonly=True))
    registry.register(AIFunction(name="list_hscript_docs_manifest", description="فهرست مستندات زبان HScript (شناسه و عنوان، بدون فایل).", parameters_schema=EMPTY, handler=list_hscript_docs_manifest_handler, allowed_roles=roles, required_permissions=["hscript.view"], category="hscript", is_readonly=True))
    registry.register(AIFunction(name="get_hscript_doc", description="متن یک مستند HScript حداکثر ۲۰هزار نویسه.", parameters_schema=DOC_ID, handler=get_hscript_doc_handler, allowed_roles=roles, required_permissions=["hscript.view"], category="hscript", is_readonly=True))
    registry.register(AIFunction(name="search_hscript_docs", description="جستجوی مستندات HScript برای کمک به نوشتن اسکریپت.", parameters_schema=DOC_SEARCH, handler=search_hscript_docs_handler, allowed_roles=roles, required_permissions=["hscript.view"], category="hscript", is_readonly=True))
    registry.register(AIFunction(name="get_hscript_assist_context", description="بازیابی راهنما و مستندات مرتبط برای دستیار HScript.", parameters_schema=ASSIST, handler=get_hscript_assist_context_handler, allowed_roles=roles, required_permissions=["hscript.view"], category="hscript", is_readonly=True))
    registry.register(AIFunction(name="validate_hscript_source", description="اعتبارسنجی نحوی اسکریپت HScript بدون اجرا روی داده واقعی.", parameters_schema=VALIDATE, handler=validate_hscript_source_handler, allowed_roles=roles, required_permissions=["hscript.write"], category="hscript", is_readonly=True))
