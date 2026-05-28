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
                "گزارش یکپارچه. ابتدا list_available_reports را ببینید. "
                f"نمونه report_type: sales_by_product, trial_balance, inventory_stock, basalam_overview. "
                f"مجموعاً {len(_REPORT_TYPES)} نوع. general_ledger نیاز به account_ids دارد."
            ),
            parameters_schema={
                "type": "object",
                "properties": {
                    "report_type": {"type": "string", "description": "نوع گزارش؛ از list_available_reports"},
                    "from_date": {"type": "string", "format": "date"},
                    "to_date": {"type": "string", "format": "date"},
                    "fiscal_year_id": {"type": "integer"},
                    "product_id": {"type": "integer"},
                    "as_of_date": {"type": "string", "format": "date"},
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
            description="لیست ارزهای سیستم (برای ثبت فاکتور و اسناد).",
            parameters_schema={"type": "object", "properties": {"search": {"type": "string"}}},
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
    def create_product_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from adapters.api.v1.schema_models.product import ProductCreateRequest
        from app.services.product_service import create_product

        db = context["db"]
        business_id = int(args.get("business_id") or context.get("business_id"))
        item_type = args.get("item_type") or "کالا"
        payload = ProductCreateRequest(
            name=args["name"],
            item_type=item_type,
            code=args.get("code"),
            description=args.get("description"),
            category_id=args.get("category_id"),
            base_sales_price=args.get("base_sales_price"),
            base_purchase_price=args.get("base_purchase_price"),
            track_inventory=bool(args.get("track_inventory", False)),
        )
        return create_product(db, business_id, payload)

    registry.register(
        AIFunction(
            name="create_product",
            description="ایجاد کالا یا خدمت جدید. نیاز به تأیید.",
            parameters_schema={
                "type": "object",
                "properties": {
                    "name": {"type": "string"},
                    "item_type": {"type": "string", "enum": ["کالا", "خدمت"]},
                    "code": {"type": "string"},
                    "description": {"type": "string"},
                    "category_id": {"type": "integer"},
                    "base_sales_price": {"type": "number"},
                    "base_purchase_price": {"type": "number"},
                    "track_inventory": {"type": "boolean"},
                },
                "required": ["name"],
            },
            handler=create_product_handler,
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
        from app.services.product_service import update_product

        db = context["db"]
        business_id = int(args.get("business_id") or context.get("business_id"))
        product_id = int(args["product_id"])
        fields = {k: v for k, v in args.items() if k not in ("product_id", "business_id", "user_id") and v is not None}
        payload = ProductUpdateRequest(**fields)
        return update_product(db, product_id, business_id, payload)

    registry.register(
        AIFunction(
            name="update_product",
            description="ویرایش کالا/خدمت. فقط فیلدهای ارسالی تغییر می‌کنند. نیاز به تأیید.",
            parameters_schema={
                "type": "object",
                "properties": {
                    "product_id": {"type": "integer"},
                    "name": {"type": "string"},
                    "description": {"type": "string"},
                    "base_sales_price": {"type": "number"},
                    "base_purchase_price": {"type": "number"},
                    "track_inventory": {"type": "boolean"},
                },
                "required": ["product_id"],
            },
            handler=update_product_handler,
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["products.write"],
            category="products",
            requires_approval=True,
            risk_level="medium",
            is_readonly=False,
        )
    )

    # --- Write: check ---
    def create_check_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from app.services.check_service import create_check

        db = context["db"]
        business_id = int(args.get("business_id") or context.get("business_id"))
        user_id = context.get("user_context").get_user_id()
        data = {
            "type": args.get("type"),
            "check_number": args.get("check_number"),
            "amount": args.get("amount"),
            "issue_date": args.get("issue_date"),
            "due_date": args.get("due_date"),
            "person_id": args.get("person_id"),
            "bank_name": args.get("bank_name"),
            "sayad_code": args.get("sayad_code"),
        }
        return create_check(db, business_id, user_id, data)

    registry.register(
        AIFunction(
            name="create_check",
            description="ثبت چک دریافتی یا پرداختی. type: received یا transferred. نیاز به تأیید.",
            parameters_schema={
                "type": "object",
                "properties": {
                    "type": {"type": "string", "enum": ["received", "transferred"]},
                    "check_number": {"type": "string"},
                    "amount": {"type": "number"},
                    "issue_date": {"type": "string", "format": "date"},
                    "due_date": {"type": "string", "format": "date"},
                    "person_id": {"type": "integer"},
                    "bank_name": {"type": "string"},
                    "sayad_code": {"type": "string"},
                },
                "required": ["type", "check_number", "amount", "issue_date", "due_date"],
            },
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
        from app.services.transfer_service import create_transfer

        db = context["db"]
        business_id = int(args.get("business_id") or context.get("business_id"))
        user_id = context.get("user_context").get_user_id()
        data = {
            "document_date": args["document_date"],
            "currency_id": int(args["currency_id"]),
            "amount": float(args["amount"]),
            "description": args.get("description"),
            "source": {
                "type": args["from_account_type"],
                "id": int(args["from_account_id"]),
            },
            "destination": {
                "type": args["to_account_type"],
                "id": int(args["to_account_id"]),
            },
        }
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
                    "document_date": {"type": "string", "format": "date"},
                    "currency_id": {"type": "integer"},
                    "from_account_type": {
                        "type": "string",
                        "enum": ["bank", "cash_register", "petty_cash"],
                    },
                    "from_account_id": {"type": "integer"},
                    "to_account_type": {
                        "type": "string",
                        "enum": ["bank", "cash_register", "petty_cash"],
                    },
                    "to_account_id": {"type": "integer"},
                    "amount": {"type": "number"},
                    "description": {"type": "string"},
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
