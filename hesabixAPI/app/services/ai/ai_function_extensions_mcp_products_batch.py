"""Bounded product batch operations and preview/apply workflows for MCP."""
from __future__ import annotations

from typing import Any, Dict

from app.services.ai.function_registry import AIRole, AIFunction

_ROLES = {AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN}
_MAX_IDS = 100


def _register(registry, name, description, schema, handler, permission, *, write=False, high=False):
    registry.register(AIFunction(name=name, description=description, parameters_schema=schema,
        handler=handler, allowed_roles=_ROLES, required_permissions=[permission], category="products",
        requires_approval=bool(write), risk_level="high" if high else ("medium" if write else "safe"), is_readonly=not write))


def _schema(properties, required=()):
    return {"type": "object", "properties": properties, "required": list(required), "additionalProperties": False}


_PRODUCT_PAYLOAD = _schema({
    "code": {"type": ["string", "null"], "maxLength": 50}, "name": {"type": "string", "minLength": 1, "maxLength": 200},
    "item_type": {"type": "string", "enum": ["کالا", "خدمت"]}, "description": {"type": ["string", "null"], "maxLength": 2000},
    "category_id": {"type": ["integer", "null"], "minimum": 1}, "main_unit": {"type": ["string", "null"], "maxLength": 50},
    "secondary_unit": {"type": ["string", "null"], "maxLength": 50}, "unit_conversion_factor": {"type": ["number", "null"], "exclusiveMinimum": 0},
    "base_sales_price": {"type": ["number", "null"], "minimum": 0}, "base_purchase_price": {"type": ["number", "null"], "minimum": 0},
    "sales_price_fx": {"type": ["number", "null"], "minimum": 0}, "purchase_price_fx": {"type": ["number", "null"], "minimum": 0},
    "price_fx_currency_id": {"type": ["integer", "null"], "minimum": 1}, "auto_update_base_from_fx": {"type": "boolean"},
    "track_inventory": {"type": "boolean"}, "default_warehouse_id": {"type": ["integer", "null"], "minimum": 1},
    "reorder_point": {"type": ["integer", "null"], "minimum": 0}, "min_order_qty": {"type": ["integer", "null"], "minimum": 0},
    "lead_time_days": {"type": ["integer", "null"], "minimum": 0}, "inventory_mode": {"type": ["string", "null"], "enum": ["bulk", "unique", None]},
    "track_serial": {"type": "boolean"}, "track_barcode": {"type": "boolean"}, "is_sales_taxable": {"type": "boolean"},
    "is_purchase_taxable": {"type": "boolean"}, "sales_tax_rate": {"type": ["number", "null"], "minimum": 0, "maximum": 100},
    "purchase_tax_rate": {"type": ["number", "null"], "minimum": 0, "maximum": 100}, "tax_type_id": {"type": ["integer", "null"], "minimum": 1},
    "tax_code": {"type": ["string", "null"], "maxLength": 50}, "tax_unit_id": {"type": ["integer", "null"], "minimum": 1},
    "base_sales_note": {"type": ["string", "null"], "maxLength": 500}, "base_purchase_note": {"type": ["string", "null"], "maxLength": 500},
    "image_file_id": {"type": ["string", "null"]}, "attribute_ids": {"type": ["array", "null"], "items": {"type": "integer", "minimum": 1}},
    "barcode": {"type": ["string", "null"], "maxLength": 50}, "general_barcodes": {"type": ["string", "null"], "maxLength": 8192},
    "is_active": {"type": "boolean"}, "is_public_catalog": {"type": "boolean"},
    "catalog_short_description": {"type": ["string", "null"], "maxLength": 1000},
    "catalog_expert_review": {"type": ["string", "null"], "maxLength": 16000},
    "catalog_brand": {"type": ["string", "null"], "maxLength": 255}, "catalog_model": {"type": ["string", "null"], "maxLength": 255},
    "catalog_country_of_origin": {"type": ["string", "null"], "maxLength": 128}, "catalog_video_url": {"type": ["string", "null"], "maxLength": 512},
    "catalog_gallery_file_ids": {"type": ["array", "null"], "maxItems": 12, "items": {"type": "string"}},
    "catalog_specifications": {"type": ["array", "null"], "maxItems": 200, "items": _schema({"field_id": {"type": ["integer", "null"], "minimum": 1}, "label": {"type": "string", "minLength": 1, "maxLength": 255}, "value": {"type": "string", "maxLength": 2000}, "sort_order": {"type": "integer", "minimum": 0}})},
    "suppliers": {"type": ["array", "null"], "maxItems": 100, "items": _schema({"id": {"type": ["integer", "null"]}, "person_id": {"type": ["integer", "null"], "minimum": 1}, "name": {"type": ["string", "null"], "maxLength": 255}, "website": {"type": ["string", "null"], "maxLength": 512}, "phone": {"type": ["string", "null"], "maxLength": 64}, "email": {"type": ["string", "null"], "maxLength": 255}, "notes": {"type": ["string", "null"], "maxLength": 4000}, "is_preferred": {"type": "boolean"}, "sort_order": {"type": "integer", "minimum": 0}, "social_contacts": {"type": "array", "maxItems": 30, "items": _schema({"platform_key": {"type": "string", "minLength": 1, "maxLength": 64}, "custom_label": {"type": ["string", "null"], "maxLength": 128}, "value": {"type": "string", "minLength": 1, "maxLength": 2000}}, ["platform_key", "value"])}})},
    "opening_balance": {"type": ["object", "null"], "properties": {
        "quantity": {"type": "number", "minimum": 0}, "cost_price": {"type": "number", "minimum": 0},
        "warehouse_id": {"type": ["integer", "null"], "minimum": 1}, "fiscal_year_id": {"type": ["integer", "null"], "minimum": 1},
        "clear": {"type": "boolean"}}, "additionalProperties": False},
})

_PRICE_PROPERTIES = {
    "update_type": {"type": "string", "enum": ["percentage", "amount"]},
    "direction": {"type": "string", "enum": ["increase", "decrease"]},
    "target": {"type": "string", "enum": ["sales_price", "purchase_price", "both"]},
    "update_scope": {"type": "string", "enum": ["base_prices", "price_list_items", "both"]},
    "value": {"type": "number", "minimum": 0},
    "product_ids": {"type": "array", "minItems": 1, "maxItems": _MAX_IDS, "uniqueItems": True, "items": {"type": "integer", "minimum": 1}},
    "currency_ids": {"type": "array", "minItems": 1, "maxItems": _MAX_IDS, "uniqueItems": True, "items": {"type": "integer", "minimum": 1}},
    "price_list_ids": {"type": "array", "minItems": 1, "maxItems": _MAX_IDS, "uniqueItems": True, "items": {"type": "integer", "minimum": 1}},
    "only_products_with_inventory": {"type": ["boolean", "null"]},
    "only_products_with_base_price": {"type": "boolean"},
}
_DEFAULT_WAREHOUSE_PROPERTIES = {
    "ids": {"type": "array", "minItems": 1, "maxItems": _MAX_IDS, "uniqueItems": True, "items": {"type": "integer", "minimum": 1}},
    "default_warehouse_id": {"type": ["integer", "null"], "minimum": 1},
    "apply_scope": {"type": "string", "enum": ["all", "track_inventory_true", "track_inventory_false"]},
}


def register_mcp_products_batch_functions(registry) -> None:
    def bulk_upsert(args, context):
        from app.services.product_bulk_upsert_service import bulk_upsert_products_integration
        entries = args["items"]
        if len(entries) > 25:
            raise ValueError("حداکثر ۲۵ کالا در هر فراخوانی مجاز است")
        body = {"items": entries, "create_if_update_missing": False}
        return bulk_upsert_products_integration(context["db"], int(context["business_id"]), context["user_context"], body)

    _register(registry, "bulk_upsert_products", "ایجاد/ویرایش حداکثر ۲۵ کالا. payload فیلدهای فرم کالا را می‌پذیرد؛ برای ویرایش product_id را از search_products بگیر. موجودی اولیه نیازمند مجوز opening_balance.edit است و برای هر ردیف جدا گزارش می‌شود. خطای یک کالا بقیه را متوقف نمی‌کند. نیازمند تأیید.",
        _schema({"items": {"type": "array", "minItems": 1, "maxItems": 25, "items": _schema({"client_ref": {"type": "string", "maxLength": 120}, "product_id": {"type": "integer", "minimum": 1}, "payload": _PRODUCT_PAYLOAD}, ["payload"])}}, ["items"]),
        bulk_upsert, "products.write", write=True, high=True)

    def bulk_delete(args, context):
        from adapters.db.models.product import Product
        from app.services.product_service import delete_product
        db, bid = context["db"], int(context["business_id"])
        ids = [int(value) for value in args["product_ids"]]
        if len(set(ids)) != len(ids):
            raise ValueError("product_ids نباید شناسهٔ تکراری داشته باشد")
        found = {int(row.id): row for row in db.query(Product).filter(Product.id.in_(ids), Product.business_id == bid).all()}
        if len(found) != len(ids):
            raise ValueError("همهٔ کالاها باید متعلق به کسب‌وکار متصل باشند")
        results = []
        for pid in ids:
            ok, error = delete_product(db, pid, bid)
            results.append({"product_id": pid, "deleted": bool(ok), "error": error})
        return {"results": results, "deleted_count": sum(row["deleted"] for row in results), "failed_count": sum(not row["deleted"] for row in results)}

    _register(registry, "bulk_delete_products", "حذف حداکثر ۱۰۰ کالای متعلق به کسب‌وکار متصل؛ پیش از اجرا مالکیت همهٔ شناسه‌ها بررسی می‌شود و برای هر کالا نتیجهٔ حذف/وابستگی برمی‌گردد. نیازمند تأیید.",
        _schema({"product_ids": _PRICE_PROPERTIES["product_ids"]}, ["product_ids"]), bulk_delete, "products.delete", write=True, high=True)

    def price_request(args):
        from adapters.api.v1.schema_models.product import BulkPriceUpdateRequest
        if not args.get("product_ids"):
            raise ValueError("برای جلوگیری از تغییر نامحدود، product_ids مشخص و حداکثر ۱۰۰ شناسه الزامی است")
        return BulkPriceUpdateRequest.model_validate(args)

    def preview_prices(args, context):
        from app.services.bulk_price_update_service import preview_bulk_price_update
        return preview_bulk_price_update(context["db"], int(context["business_id"]), price_request(args)).model_dump()

    def apply_prices(args, context):
        from app.services.bulk_price_update_service import apply_bulk_price_update
        return apply_bulk_price_update(context["db"], int(context["business_id"]), price_request(args))

    price_required = ["update_type", "target", "value", "product_ids"]
    _register(registry, "preview_bulk_product_price_update", "پیش‌نمایش تغییر قیمت حداکثر ۱۰۰ کالای صریحاً انتخاب‌شده. قبل از اعمال، نتیجه و واحد پول را به کاربر نشان بده.", _schema(_PRICE_PROPERTIES, price_required), preview_prices, "products.edit")
    _register(registry, "apply_bulk_product_price_update", "اعمال تغییر قیمت پایه/لیست برای حداکثر ۱۰۰ کالای صریحاً انتخاب‌شده؛ عملیات برگشت‌ناپذیر است. ابتدا preview_bulk_product_price_update را اجرا و نتیجه را برای تأیید کاربر ارائه کن.", _schema(_PRICE_PROPERTIES, price_required), apply_prices, "products.edit", write=True, high=True)

    from adapters.api.v1.schema_models.product import BulkDefaultWarehouseRequest
    def warehouse_request(args):
        return BulkDefaultWarehouseRequest.model_validate(args)
    def preview_warehouse(args, context):
        from app.services.product_service import preview_bulk_default_warehouse_update
        return preview_bulk_default_warehouse_update(context["db"], int(context["business_id"]), warehouse_request(args))
    def apply_warehouse(args, context):
        from app.services.product_service import apply_bulk_default_warehouse_update
        db, bid, ctx = context["db"], int(context["business_id"]), context["user_context"]
        result = apply_bulk_default_warehouse_update(db, bid, ctx.get_user_id(), warehouse_request(args))
        db.commit()
        return result
    _register(registry, "preview_bulk_product_default_warehouse", "پیش‌نمایش تغییر انبار پیش‌فرض حداکثر ۱۰۰ کالای انتخاب‌شده.", _schema(_DEFAULT_WAREHOUSE_PROPERTIES, ["ids"]), preview_warehouse, "products.edit")
    _register(registry, "apply_bulk_product_default_warehouse", "تغییر واقعی انبار پیش‌فرض حداکثر ۱۰۰ کالای انتخاب‌شده؛ ابتدا پیش‌نمایش را بررسی و تأیید بگیر. این تغییر موجودی را جابه‌جا نمی‌کند.", _schema(_DEFAULT_WAREHOUSE_PROPERTIES, ["ids"]), apply_warehouse, "products.edit", write=True, high=True)
