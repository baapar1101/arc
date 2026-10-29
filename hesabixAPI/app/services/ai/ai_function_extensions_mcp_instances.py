"""MCP tools for unique product instances / serials. Tenant is pinned from the credential."""
from __future__ import annotations

from datetime import date
from typing import Any, Dict

from app.services.ai.ai_mcp_tool_util import (
    mcp_bid,
    mcp_db,
    mcp_jsonable,
    mcp_raise,
    mcp_run,
    mcp_schema,
)

CREATE_PRODUCT_INSTANCE_SCHEMA: Dict[str, Any] = {}
UPDATE_PRODUCT_INSTANCE_SCHEMA: Dict[str, Any] = {}
GET_AVAILABLE_PRODUCT_INSTANCES_SCHEMA: Dict[str, Any] = {}

_STATUSES = ["available", "reserved", "sold", "returned", "scrapped", "in_transit"]
_INSTANCE_ID = mcp_schema({"instance_id": {"type": "integer", "minimum": 1}}, ["instance_id"])
GET_AVAILABLE_PRODUCT_INSTANCES_SCHEMA = mcp_schema(
    {
        "product_id": {"type": "integer", "minimum": 1},
        "warehouse_id": {"type": "integer", "minimum": 1},
    },
    ["product_id"],
)
CREATE_PRODUCT_INSTANCE_SCHEMA = mcp_schema(
    {
        "product_id": {"type": "integer", "minimum": 1},
        "serial_number": {"type": "string", "minLength": 1, "maxLength": 255},
        "barcode": {"type": ["string", "null"], "maxLength": 255},
        "warehouse_id": {"type": ["integer", "null"], "minimum": 1},
        "entry_date": {"type": "string", "description": "ISO date YYYY-MM-DD"},
        "custom_attributes": {"type": "object"},
    },
    ["product_id", "serial_number"],
)
UPDATE_PRODUCT_INSTANCE_SCHEMA = mcp_schema(
    {
        "instance_id": {"type": "integer", "minimum": 1},
        "barcode": {"type": ["string", "null"], "maxLength": 255},
        "warehouse_id": {"type": ["integer", "null"], "minimum": 1},
        "status": {"type": "string", "enum": _STATUSES},
        "custom_attributes": {"type": "object"},
        "last_movement_date": {"type": ["string", "null"]},
    },
    ["instance_id"],
)


def _instance_public(inst, warehouse_name=None) -> Dict[str, Any]:
    return {
        "id": inst.id,
        "product_id": inst.product_id,
        "serial_number": inst.serial_number,
        "barcode": inst.barcode,
        "warehouse_id": inst.warehouse_id,
        "warehouse_name": warehouse_name,
        "status": inst.status,
        "custom_attributes": inst.custom_attributes or {},
        "entry_date": inst.entry_date.isoformat() if inst.entry_date else None,
        "last_movement_date": inst.last_movement_date.isoformat() if inst.last_movement_date else None,
        "current_invoice_id": getattr(inst, "current_invoice_id", None),
    }


def _load_instance(db, business_id: int, instance_id: int):
    from sqlalchemy import and_

    from adapters.db.models.product_instance import ProductInstance

    inst = (
        db.query(ProductInstance)
        .filter(and_(ProductInstance.id == int(instance_id), ProductInstance.business_id == business_id))
        .first()
    )
    if not inst:
        raise ValueError("کالای یونیک یافت نشد")
    return inst


def get_available_product_instances_handler(args, context):
    from sqlalchemy import and_

    from adapters.db.models.product import Product
    from adapters.db.models.product_instance import ProductInstance

    db = mcp_db(context)
    bid = mcp_bid(context)
    product_id = int(args["product_id"])
    product = db.query(Product).filter(and_(Product.id == product_id, Product.business_id == bid)).first()
    if not product:
        raise ValueError("کالا یافت نشد")
    q = db.query(ProductInstance).filter(
        and_(
            ProductInstance.business_id == bid,
            ProductInstance.product_id == product_id,
            ProductInstance.status == "available",
        )
    )
    if args.get("warehouse_id"):
        q = q.filter(ProductInstance.warehouse_id == int(args["warehouse_id"]))
    items = []
    for inst in q.order_by(ProductInstance.entry_date.desc()).all():
        wh_name = inst.warehouse.name if inst.warehouse_id and inst.warehouse else None
        items.append(_instance_public(inst, wh_name))
    return {"items": items, "total": len(items)}


def create_product_instance_handler(args, context):
    from sqlalchemy import and_

    from adapters.db.models.product import Product
    from adapters.db.models.product_instance import ProductInstance
    from adapters.db.models.warehouse import Warehouse
    from app.services.product_attribute_service import validate_custom_attributes

    db = mcp_db(context)
    bid = mcp_bid(context)
    product_id = int(args["product_id"])
    serial_number = str(args["serial_number"]).strip()
    barcode = args.get("barcode")
    warehouse_id = args.get("warehouse_id")
    custom_attributes = args.get("custom_attributes") or {}
    product = db.query(Product).filter(and_(Product.id == product_id, Product.business_id == bid)).first()
    if not product:
        raise ValueError("کالا یافت نشد")
    if db.query(ProductInstance).filter(and_(ProductInstance.business_id == bid, ProductInstance.serial_number == serial_number)).first():
        raise ValueError(f"شماره سریال {serial_number} تکراری است")
    if barcode:
        if db.query(ProductInstance).filter(and_(ProductInstance.business_id == bid, ProductInstance.barcode == barcode)).first():
            raise ValueError(f"بارکد {barcode} تکراری است")
    if warehouse_id:
        warehouse = db.query(Warehouse).filter(and_(Warehouse.id == int(warehouse_id), Warehouse.business_id == bid)).first()
        if not warehouse:
            raise ValueError("انبار یافت نشد")
    if custom_attributes:
        ok, err = validate_custom_attributes(db=db, business_id=bid, product_id=product_id, custom_attributes=custom_attributes)
        if not ok:
            raise ValueError(err or "مقادیر ویژگی‌های کالا معتبر نیست")
    entry_raw = args.get("entry_date")
    instance = ProductInstance(
        business_id=bid,
        product_id=product_id,
        serial_number=serial_number,
        barcode=barcode,
        warehouse_id=int(warehouse_id) if warehouse_id else None,
        status="available",
        custom_attributes=custom_attributes or None,
        entry_date=date.fromisoformat(str(entry_raw)[:10]) if entry_raw else date.today(),
    )
    db.add(instance)
    db.flush()
    return _instance_public(instance)


def update_product_instance_handler(args, context):
    from sqlalchemy import and_

    from adapters.db.models.product_instance import ProductInstance
    from adapters.db.models.warehouse import Warehouse
    from app.services.product_attribute_service import validate_custom_attributes

    db = mcp_db(context)
    bid = mcp_bid(context)
    inst = _load_instance(db, bid, int(args["instance_id"]))
    if "barcode" in args:
        barcode = args.get("barcode")
        if barcode:
            existing = (
                db.query(ProductInstance)
                .filter(
                    and_(
                        ProductInstance.business_id == bid,
                        ProductInstance.barcode == barcode,
                        ProductInstance.id != inst.id,
                    )
                )
                .first()
            )
            if existing:
                raise ValueError(f"بارکد {barcode} تکراری است")
        inst.barcode = barcode
    if "warehouse_id" in args:
        warehouse_id = args.get("warehouse_id")
        if warehouse_id:
            warehouse = db.query(Warehouse).filter(and_(Warehouse.id == int(warehouse_id), Warehouse.business_id == bid)).first()
            if not warehouse:
                raise ValueError("انبار یافت نشد")
        inst.warehouse_id = int(warehouse_id) if warehouse_id else None
    if "status" in args and args.get("status"):
        inst.status = args["status"]
    if "custom_attributes" in args:
        custom_attributes = args.get("custom_attributes")
        if custom_attributes:
            ok, err = validate_custom_attributes(
                db=db, business_id=bid, product_id=inst.product_id, custom_attributes=custom_attributes
            )
            if not ok:
                raise ValueError(err or "مقادیر ویژگی‌های کالا معتبر نیست")
        inst.custom_attributes = custom_attributes
    if args.get("last_movement_date"):
        inst.last_movement_date = date.fromisoformat(str(args["last_movement_date"])[:10])
    db.flush()
    return _instance_public(inst)


def delete_product_instance_handler(args, context):
    db = mcp_db(context)
    bid = mcp_bid(context)
    inst = _load_instance(db, bid, int(args["instance_id"]))
    if inst.status == "sold":
        raise ValueError("کالای یونیک فروخته‌شده قابل حذف نیست")
    db.delete(inst)
    db.flush()
    return {"deleted": True, "id": int(args["instance_id"])}


def register_mcp_instance_functions(registry) -> None:
    from app.services.ai.function_registry import AIFunction, AIRole

    roles = {AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN}
    registry.register(AIFunction(
        name="get_available_product_instances",
        description="کالاهای یونیک موجود یک محصول در کسب‌وکار متصل. فقط وضعیت available.",
        parameters_schema=GET_AVAILABLE_PRODUCT_INSTANCES_SCHEMA,
        handler=get_available_product_instances_handler,
        allowed_roles=roles,
        required_permissions=["inventory.read"],
        category="products",
        is_readonly=True,
    ))
    registry.register(AIFunction(
        name="create_product_instance",
        description="ثبت کالای یونیک با شماره سریال یکتا در کسب‌وکار متصل. نیاز به تأیید.",
        parameters_schema=CREATE_PRODUCT_INSTANCE_SCHEMA,
        handler=create_product_instance_handler,
        allowed_roles=roles,
        required_permissions=["inventory.write"],
        category="products",
        requires_approval=True,
        risk_level="medium",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="update_product_instance",
        description="ویرایش بارکد، انبار، وضعیت یا ویژگی کالای یونیک متعلق به کسب‌وکار متصل.",
        parameters_schema=UPDATE_PRODUCT_INSTANCE_SCHEMA,
        handler=update_product_instance_handler,
        allowed_roles=roles,
        required_permissions=["inventory.write"],
        category="products",
        requires_approval=True,
        risk_level="medium",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="delete_product_instance",
        description="حذف کالای یونیک فروخته‌نشده متعلق به کسب‌وکار متصل. نیازمند تأیید.",
        parameters_schema=_INSTANCE_ID,
        handler=delete_product_instance_handler,
        allowed_roles=roles,
        required_permissions=["inventory.write"],
        category="products",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
