"""
ثبت functionهای فاز ۴ AI — meta-tools، writeهای تکمیلی، گزارش یکپارچه.
"""
from __future__ import annotations

from typing import Any, Dict, List, TYPE_CHECKING

from app.services.ai.ai_query_service import SUPPORTED_ENTITIES, query_business_data
from app.services.ai.function_registry import AIRole, AIFunction

if TYPE_CHECKING:
    from app.services.ai.function_registry import AIFunctionRegistry

from app.services.ai.ai_reports_catalog import REPORT_TYPES as _REPORT_TYPES


def register_phase4_business_functions(registry: "AIFunctionRegistry") -> None:
    create_handler = registry._create_handler  # noqa: SLF001

    # --- Meta: batch query ---
    def batch_query_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from sqlalchemy.orm import Session

        db: Session = context["db"]
        user_context = context["user_context"]
        business_id = int(args.get("business_id") or context.get("business_id"))
        queries = args.get("queries") or []
        if not isinstance(queries, list):
            raise ValueError("queries باید آرایه باشد")
        results: List[Dict[str, Any]] = []
        for i, q in enumerate(queries[:8]):
            if not isinstance(q, dict):
                continue
            entity = str(q.get("entity", ""))
            try:
                data = query_business_data(
                    db,
                    business_id,
                    user_context,
                    entity=entity,
                    action=str(q.get("action") or "search"),
                    filters=q.get("filters") if isinstance(q.get("filters"), dict) else None,
                    record_id=q.get("record_id"),
                )
                results.append({"index": i, "entity": entity, "ok": True, "data": data})
            except Exception as exc:
                results.append({"index": i, "entity": entity, "ok": False, "error": str(exc)})
        return {"results": results}

    registry.register(
        AIFunction(
            name="batch_query_business_data",
            description=(
                "اجرای چند پرس‌وجوی read در یک فراخوانی (حداکثر ۸). "
                f"هر آیتم: entity از {', '.join(sorted(SUPPORTED_ENTITIES)[:12])}… و action/filters."
            ),
            parameters_schema={
                "type": "object",
                "properties": {
                    "queries": {
                        "type": "array",
                        "maxItems": 8,
                        "items": {
                            "type": "object",
                            "properties": {
                                "entity": {"type": "string"},
                                "action": {"type": "string", "enum": ["search", "list", "get", "count"]},
                                "record_id": {"type": "integer"},
                                "filters": {"type": "object"},
                            },
                            "required": ["entity"],
                        },
                    }
                },
                "required": ["queries"],
            },
            handler=batch_query_handler,
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=[],
            category="query",
            is_readonly=True,
        )
    )

    # --- Meta: unified report (فاز ۶: ai_reports_service) ---
    def get_report_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from app.services.ai.ai_reports_service import execute_ai_report

        db = context["db"]
        business_id = int(args.get("business_id") or context.get("business_id"))
        report_type = str(args.get("report_type", "")).strip().lower()
        return execute_ai_report(
            db,
            business_id,
            report_type,
            args,
            user_context=context.get("user_context"),
        )

    registry.register(
        AIFunction(
            name="get_report",
            description=(
                "گزارش یکپارچه معادل صفحهٔ گزارشات. ابتدا list_available_reports را ببینید. "
                "نمونه report_type: trial_balance, cash_flow_statement, ar_aging, installments, "
                "checks, stock_count, financial_package, fx_revaluation, woocommerce_overview. "
                f"مجموعاً {len(_REPORT_TYPES)} نوع. general_ledger نیاز به account_ids دارد. "
                "خروجی JSON است؛ فایل Excel/PDF برنمی‌گردد."
            ),
            parameters_schema={
                "type": "object",
                "properties": {
                    "report_type": {
                        "type": "string",
                        "enum": list(_REPORT_TYPES),
                        "description": "نوع گزارش؛ از list_available_reports",
                    },
                    "from_date": {"type": "string", "format": "date"},
                    "to_date": {"type": "string", "format": "date"},
                    "as_of_date": {"type": "string", "format": "date"},
                    "due_from": {"type": "string", "format": "date"},
                    "due_to": {"type": "string", "format": "date"},
                    "fiscal_year_id": {"type": "integer"},
                    "currency_id": {"type": "integer"},
                    "project_id": {"type": "integer"},
                    "product_id": {"type": "integer"},
                    "product_ids": {"type": "array", "items": {"type": "integer"}, "maxItems": 100},
                    "account_id": {"type": "integer"},
                    "account_ids": {"type": "array", "items": {"type": "integer"}, "maxItems": 100},
                    "person_id": {"type": "integer"},
                    "person_ids": {"type": "array", "items": {"type": "integer"}, "maxItems": 100},
                    "warehouse_ids": {"type": "array", "items": {"type": "integer"}, "maxItems": 100},
                    "category_ids": {"type": "array", "items": {"type": "integer"}, "maxItems": 100},
                    "bank_account_ids": {"type": "array", "items": {"type": "integer"}, "maxItems": 100},
                    "cash_register_ids": {"type": "array", "items": {"type": "integer"}, "maxItems": 100},
                    "petty_cash_ids": {"type": "array", "items": {"type": "integer"}, "maxItems": 100},
                    "invoice_id": {"type": "integer"},
                    "target_user_id": {"type": "integer"},
                    "skip": {"type": "integer", "minimum": 0},
                    "take": {"type": "integer", "minimum": 1, "maximum": 200},
                    "search": {"type": "string"},
                    "status": {"type": "string"},
                    "status_in": {"type": "array", "items": {"type": "string"}, "maxItems": 20},
                    "check_type": {"type": "string"},
                    "document_type": {"type": "string"},
                    "account_type": {"type": "string"},
                    "detail_level": {"type": "string"},
                    "display_mode": {"type": "string"},
                    "compare_mode": {"type": "string"},
                    "group_by": {"type": "string"},
                    "bucket": {"type": "string"},
                    "log_category": {"type": "string"},
                    "entity_type": {"type": "string"},
                    "conflict_type": {"type": "string"},
                    "direction": {"type": "string"},
                    "item_type": {"type": "string"},
                    "include_zero_balance": {"type": "boolean"},
                    "include_indirect": {"type": "boolean"},
                    "include_proforma": {"type": "boolean"},
                    "include_base_equivalent": {"type": "boolean"},
                    "compare_prior_period": {"type": "boolean"},
                    "only_with_balance": {"type": "boolean"},
                    "account_level": {"type": "integer"},
                    "column_mode": {"type": "integer"},
                    "chart_days": {"type": "integer", "minimum": 1, "maximum": 365},
                },
                "required": ["report_type"],
            },
            handler=get_report_handler,
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["reports.read"],
            category="reports",
            is_readonly=True,
        )
    )

    def search_categories_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from app.services.ai.ai_query_phase4_service import phase4_entity_search

        db = context["db"]
        business_id = int(args.get("business_id") or context.get("business_id"))
        return phase4_entity_search(
            db,
            business_id,
            "category",
            {"search": args.get("search"), "take": args.get("take", 50)},
            context.get("user_context"),
        )

    registry.register(
        AIFunction(
            name="search_categories",
            description="جستجوی دسته‌بندی کالا با مسیر (breadcrumb).",
            parameters_schema={
                "type": "object",
                "properties": {
                    "search": {"type": "string", "description": "متن جستجو"},
                    "take": {"type": "integer"},
                },
                "required": ["search"],
            },
            handler=search_categories_handler,
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["categories.view"],
            category="products",
        )
    )

    def _list_person_groups_wrapper(db, business_id, user_id, **kwargs):
        from app.services.person_group_service import list_person_groups

        return list_person_groups(
            db,
            business_id,
            skip=int(kwargs.get("skip") or 0),
            take=int(kwargs.get("take") or 50),
            active_only=bool(kwargs.get("active_only", False)),
        )

    registry.register(
        AIFunction(
            name="list_person_groups",
            description="لیست گروه‌های اشخاص (مشتری/تامین‌کننده).",
            parameters_schema={
                "type": "object",
                "properties": {
                    "take": {"type": "integer"},
                    "skip": {"type": "integer"},
                    "active_only": {"type": "boolean"},
                },
            },
            handler=create_handler(_list_person_groups_wrapper),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["people.view"],
            category="persons",
        )
    )

    def list_currencies_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from app.services.ai.ai_query_phase4_service import phase4_entity_search

        db = context["db"]
        business_id = int(args.get("business_id") or context.get("business_id"))
        return phase4_entity_search(
            db, business_id, "currency", args, context.get("user_context")
        )

    registry.register(
        AIFunction(
            name="list_currencies",
            description=(
                "لیست ارزهای سیستم با id عددی. قبل از create_invoice اگر currency_id را نمی‌دانی صدا بزن. "
                "اگر خالی بماند، ارز پیش‌فرض کسب‌وکار در create_invoice استفاده می‌شود."
            ),
            parameters_schema={
                "type": "object",
                "properties": {
                    "search": {"type": "string", "description": "جستجو روی نام/کد ارز (اختیاری)"},
                },
            },
            handler=list_currencies_handler,
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["invoices.view"],
            category="financial",
            is_readonly=True,
        )
    )

    # --- Write: person ---
    def delete_person_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from app.services.person_service import delete_person

        db = context["db"]
        business_id = args.get("business_id") or context.get("business_id")
        person_id = args.get("person_id")
        if not person_id:
            raise ValueError("person_id is required")
        ok, msg = delete_person(db, int(person_id), int(business_id))
        return {"deleted": ok, "message": msg}

    registry.register(
        AIFunction(
            name="delete_person",
            description="حذف یک شخص (مشتری/تامین‌کننده). نیاز به تأیید.",
            parameters_schema={
                "type": "object",
                "properties": {"person_id": {"type": "integer"}},
                "required": ["person_id"],
            },
            handler=delete_person_handler,
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["people.delete"],
            category="persons",
            requires_approval=True,
            risk_level="high",
            is_readonly=False,
        )
    )

    # --- Write: product ---
    def _ensure_product_opening_balance_permission(
        context: Dict[str, Any],
        business_id: int,
        opening_balance: Any,
    ) -> None:
        if not opening_balance:
            return
        from app.core.permissions import has_business_permission_for_business
        from app.core.responses import ApiError

        user_context = context["user_context"]
        db = context["db"]
        if not has_business_permission_for_business(
            user_context, db, int(business_id), "opening_balance", "edit"
        ):
            raise ApiError(
                "OPENING_BALANCE_PERMISSION_REQUIRED",
                "برای ثبت تعداد اولیه به دسترسی ویرایش تراز افتتاحیه نیاز است",
                http_status=403,
            )

    def _ensure_product_price_list_permission(
        context: Dict[str, Any],
        business_id: int,
        price_list_items: Any,
    ) -> None:
        if not price_list_items:
            return
        from app.core.permissions import has_business_permission_for_business
        from app.core.responses import ApiError

        user_context = context["user_context"]
        db = context["db"]
        if not (
            has_business_permission_for_business(
                user_context, db, int(business_id), "price_lists", "edit"
            )
            or has_business_permission_for_business(
                user_context, db, int(business_id), "price_lists", "add"
            )
        ):
            raise ApiError(
                "PRICE_LIST_PERMISSION_REQUIRED",
                "برای ثبت قیمت در لیست‌های قیمت به دسترسی ویرایش لیست قیمت نیاز است",
                http_status=403,
            )

    def _attach_price_list_items_to_product_result(
        db: Any,
        business_id: int,
        result: Any,
        items: Any,
        *,
        product_id: int | None = None,
    ) -> Any:
        if not items or not result:
            return result
        from app.services.price_list_service import upsert_price_items_for_product

        data = result.get("data") if isinstance(result, dict) else None
        pid = product_id
        if pid is None and isinstance(data, dict) and data.get("id") is not None:
            pid = int(data["id"])
        if pid is None:
            return result
        applied = upsert_price_items_for_product(db, business_id, pid, items)
        if not isinstance(result, dict):
            return result
        out = dict(result)
        merged = dict(out.get("data") or {})
        merged["price_list_items"] = applied
        out["data"] = merged
        return out

    def create_product_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from adapters.api.v1.schema_models.product import ProductCreateRequest
        from app.services.ai.ai_tool_payloads import (
            build_create_product_payload,
            extract_product_price_list_items,
        )
        from app.services.product_opening_balance_service import create_product_with_opening_balance
        from app.services.product_service import create_product, delete_product

        db = context["db"]
        user_context = context["user_context"]
        business_id = int(args.get("business_id") or context.get("business_id"))
        price_list_items = extract_product_price_list_items(args)
        payload = ProductCreateRequest(**build_create_product_payload(args))
        _ensure_product_opening_balance_permission(
            context, business_id, getattr(payload, "opening_balance", None)
        )
        _ensure_product_price_list_permission(context, business_id, price_list_items)
        if payload.opening_balance is not None:
            result = create_product_with_opening_balance(
                db,
                business_id,
                user_context.get_user_id(),
                payload,
                create_product_fn=create_product,
                delete_product_fn=delete_product,
            )
        else:
            result = create_product(db, business_id, payload)
        return _attach_price_list_items_to_product_result(
            db, business_id, result, price_list_items
        )

    from app.services.ai.ai_tool_payloads import (
        CREATE_PRODUCT_DESCRIPTION,
        CREATE_PRODUCT_PARAMETERS_SCHEMA,
        UPDATE_PRODUCT_DESCRIPTION,
        UPDATE_PRODUCT_PARAMETERS_SCHEMA,
    )

    registry.register(
        AIFunction(
            name="create_product",
            description=CREATE_PRODUCT_DESCRIPTION,
            parameters_schema=CREATE_PRODUCT_PARAMETERS_SCHEMA,
            handler=create_handler(create_product_handler),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["products.write"],
            category="products",
            requires_approval=True,
            risk_level="medium",
            is_readonly=False,
        )
    )

    def update_product_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from adapters.api.v1.schema_models.product import ProductUpdateRequest
        from app.services.ai.ai_tool_payloads import (
            build_update_product_payload,
            extract_product_price_list_items,
        )
        from app.services.product_opening_balance_service import update_product_with_opening_balance
        from app.services.product_service import update_product

        db = context["db"]
        user_context = context["user_context"]
        business_id = int(args.get("business_id") or context.get("business_id"))
        product_id = int(args["product_id"])
        price_list_items = extract_product_price_list_items(args)
        payload = ProductUpdateRequest(**build_update_product_payload(args))
        _ensure_product_opening_balance_permission(
            context, business_id, getattr(payload, "opening_balance", None)
        )
        _ensure_product_price_list_permission(context, business_id, price_list_items)
        if payload.opening_balance is not None:
            result = update_product_with_opening_balance(
                db,
                business_id,
                user_context.get_user_id(),
                product_id,
                payload,
                update_product_fn=update_product,
            )
        else:
            result = update_product(
                db, product_id, business_id, payload, user_id=user_context.get_user_id()
            )
        return _attach_price_list_items_to_product_result(
            db, business_id, result, price_list_items, product_id=product_id
        )

    registry.register(
        AIFunction(
            name="update_product",
            description=UPDATE_PRODUCT_DESCRIPTION,
            parameters_schema=UPDATE_PRODUCT_PARAMETERS_SCHEMA,
            handler=create_handler(update_product_handler),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["products.write"],
            category="products",
            requires_approval=True,
            risk_level="medium",
            is_readonly=False,
        )
    )

    def check_product_usage_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from adapters.db.models.product import Product
        from app.services.product_service import check_product_has_related_documents

        db = context["db"]
        business_id = int(context["business_id"])
        product_id = int(args["product_id"])
        product = db.query(Product).filter(
            Product.id == product_id, Product.business_id == business_id
        ).first()
        if not product:
            raise ValueError("کالا در کسب‌وکار متصل پیدا نشد")
        has_documents, document_types = check_product_has_related_documents(db, product_id)
        return {
            "product_id": product_id,
            "can_delete": not has_documents,
            "has_related_documents": has_documents,
            "related_document_types": document_types,
        }

    registry.register(AIFunction(
        name="check_product_usage",
        description="پیش‌بررسی وابستگی‌های کالا در اسناد، BOM و گردش‌های دیگر؛ بدون تغییر داده. پیش از حذف این ابزار را اجرا کن.",
        parameters_schema={
            "type": "object", "properties": {"product_id": {"type": "integer", "minimum": 1}},
            "required": ["product_id"],
        },
        handler=create_handler(check_product_usage_handler),
        allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
        required_permissions=["products.read"], category="products",
    ))

    def delete_product_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from app.services.product_service import delete_product

        db = context["db"]
        business_id = int(context["business_id"])
        product_id = int(args["product_id"])
        deleted, error = delete_product(db, product_id, business_id)
        if not deleted:
            raise ValueError(error or "حذف کالا انجام نشد")
        return {"product_id": product_id, "deleted": True}

    registry.register(AIFunction(
        name="delete_product",
        description="حذف کالا از سرویس دامنه؛ کالاهای دارای وابستگی حذف نمی‌شوند. ابتدا check_product_usage را اجرا کن. حذف غیرقابل بازگشت و نیازمند تأیید است.",
        parameters_schema={
            "type": "object", "properties": {"product_id": {"type": "integer", "minimum": 1}},
            "required": ["product_id"],
        },
        handler=create_handler(delete_product_handler),
        allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
        required_permissions=["products.delete"], category="products",
        requires_approval=True, risk_level="high", is_readonly=False,
    ))

    # --- Write: check ---
    def create_check_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from app.services.ai.ai_tool_payloads import build_create_check_payload
        from app.services.check_service import create_check

        db = context["db"]
        business_id = int(args.get("business_id") or context.get("business_id"))
        user_id = context.get("user_context").get_user_id()
        data = build_create_check_payload(args, db=db, business_id=business_id)
        return create_check(db, business_id, user_id, data)

    from app.services.ai.ai_tool_payloads import CREATE_CHECK_PARAMETERS_SCHEMA

    registry.register(
        AIFunction(
            name="create_check",
            description=(
                "ثبت چک دریافتی (received) یا پرداختی (transferred). "
                "قبل از صدا: search_persons و در صورت نیاز list_currencies. "
                "برای دریافتی person_id اجباری است. نیاز به تأیید."
            ),
            parameters_schema=CREATE_CHECK_PARAMETERS_SCHEMA,
            handler=create_check_handler,
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["checks.write"],
            category="financial",
            requires_approval=True,
            risk_level="high",
            is_readonly=False,
        )
    )

    # --- Write: transfer ---
    def create_transfer_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from app.services.ai.ai_tool_payloads import build_create_transfer_payload
        from app.services.transfer_service import create_transfer

        db = context["db"]
        business_id = int(args.get("business_id") or context.get("business_id"))
        user_id = context.get("user_context").get_user_id()
        data = build_create_transfer_payload(args, db=db, business_id=business_id)
        return create_transfer(db, business_id, user_id, data)

    registry.register(
        AIFunction(
            name="create_transfer",
            description=(
                "ثبت سند انتقال بین حساب‌ها. "
                "from_account_type/to_account_type: bank, cash_register, petty_cash. نیاز به تأیید."
            ),
            parameters_schema={
                "type": "object",
                "properties": {
                    "document_date": {
                        "type": "string",
                        "format": "date",
                        "description": "تاریخ سند YYYY-MM-DD یا شمسی",
                    },
                    "currency_id": {
                        "type": "integer",
                        "description": "شناسه ارز از list_currencies",
                    },
                    "from_account_type": {
                        "type": "string",
                        "enum": ["bank", "cash_register", "petty_cash"],
                        "description": "نوع حساب مبدأ",
                    },
                    "from_account_id": {
                        "type": "integer",
                        "description": "شناسه مبدأ از list_bank_accounts / list_cash_registers / list_petty_cash",
                    },
                    "to_account_type": {
                        "type": "string",
                        "enum": ["bank", "cash_register", "petty_cash"],
                        "description": "نوع حساب مقصد",
                    },
                    "to_account_id": {
                        "type": "integer",
                        "description": "شناسه مقصد از همان لیست‌های حساب نقدی",
                    },
                    "amount": {"type": "number", "description": "مبلغ انتقال"},
                    "description": {"type": "string", "description": "شرح (اختیاری)"},
                },
                "required": [
                    "document_date",
                    "currency_id",
                    "from_account_type",
                    "from_account_id",
                    "to_account_type",
                    "to_account_id",
                    "amount",
                ],
            },
            handler=create_transfer_handler,
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["transfers.write"],
            category="financial",
            requires_approval=True,
            risk_level="high",
            is_readonly=False,
        )
    )
