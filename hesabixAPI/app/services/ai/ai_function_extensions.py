"""
ثبت functionهای تکمیلی AI (فاز گسترش دسترسی به داده‌های کسب‌وکار).
"""
from __future__ import annotations

from typing import Any, Dict, TYPE_CHECKING

from app.services.ai.ai_query_service import (
    SUPPORTED_ACTIONS,
    SUPPORTED_ENTITIES,
    get_business_dashboard_summary,
    get_current_fiscal_year_data,
    get_warehouse_stock_summary,
    list_fiscal_years_data,
    query_business_data,
)
from app.services.ai.function_registry import AIRole, AIFunction

if TYPE_CHECKING:
    from app.services.ai.function_registry import AIFunctionRegistry

_COMMON_LIST_PROPS = {
    "search": {"type": "string", "description": "متن جستجو (اختیاری)"},
    "from_date": {"type": "string", "format": "date", "description": "از تاریخ (اختیاری)"},
    "to_date": {"type": "string", "format": "date", "description": "تا تاریخ (اختیاری)"},
    "fiscal_year_id": {"type": "integer", "description": "شناسه سال مالی (اختیاری)"},
    "take": {"type": "integer", "description": "تعداد نتایج (پیش‌فرض ۵۰، حداکثر ۲۰۰)"},
    "skip": {"type": "integer", "description": "ردیف شروع (پیش‌فرض ۰)"},
}


def register_extended_business_functions(registry: "AIFunctionRegistry") -> None:
    create_handler = registry._create_handler  # noqa: SLF001

    def query_business_data_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from sqlalchemy.orm import Session

        db: Session = context["db"]
        user_context = context["user_context"]
        business_id = args.get("business_id") or context.get("business_id")
        flt = args.get("filters")
        if flt is None:
            flt = {k: v for k, v in args.items() if k not in ("entity", "action", "record_id", "business_id", "user_id", "filters") and v is not None}
        return query_business_data(
            db,
            int(business_id),
            user_context,
            entity=str(args["entity"]),
            action=str(args.get("action") or "search"),
            filters=flt if isinstance(flt, dict) else None,
            record_id=args.get("record_id"),
        )

    registry.register(
        AIFunction(
            name="query_business_data",
            description=(
                "ابزار جنریک برای خواندن داده‌های کسب‌وکار. "
                f"entityهای مجاز: {', '.join(sorted(SUPPORTED_ENTITIES))}. "
                f"action: {', '.join(sorted(SUPPORTED_ACTIONS))}. "
                "برای get، record_id یا id در filters بدهید. "
                "ترجیحاً برای موجودیت‌های تخصصی از functionهای اختصاصی استفاده کن."
            ),
            parameters_schema={
                "type": "object",
                "properties": {
                    "entity": {
                        "type": "string",
                        "enum": sorted(SUPPORTED_ENTITIES),
                        "description": "نوع موجودیت",
                    },
                    "action": {
                        "type": "string",
                        "enum": sorted(SUPPORTED_ACTIONS),
                        "description": "search/list برای لیست، get برای جزئیات، count برای تعداد",
                    },
                    "record_id": {
                        "type": "integer",
                        "description": "شناسه رکورد (برای action=get)",
                    },
                    "filters": {
                        "type": "object",
                        "description": "فیلترها: search, from_date, to_date, document_type, person_id, ...",
                    },
                },
                "required": ["entity"],
            },
            handler=query_business_data_handler,
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=[],
            category="query",
        )
    )

    # --- انبار ---
    registry.register(
        AIFunction(
            name="search_warehouse_documents",
            description="جستجو و لیست حواله‌های انبار (ورود، خروج، انتقال). شناسه کسب‌وکار خودکار است.",
            parameters_schema={
                "type": "object",
                "properties": {
                    **_COMMON_LIST_PROPS,
                    "doc_type": {"type": "string", "description": "نوع حواله (اختیاری)"},
                    "status": {"type": "string", "description": "وضعیت (اختیاری)"},
                    "warehouse_id": {"type": "integer", "description": "شناسه انبار (اختیاری)"},
                },
                "required": [],
            },
            handler=create_handler(_wh_doc_search),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["warehouses.view"],
            category="warehouse",
        )
    )

    registry.register(
        AIFunction(
            name="get_warehouse_document_details",
            description="جزئیات یک حواله انبار.",
            parameters_schema={
                "type": "object",
                "properties": {
                    "warehouse_document_id": {"type": "integer", "description": "شناسه حواله"},
                },
                "required": ["warehouse_document_id"],
            },
            handler=create_handler(_wh_doc_get),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["warehouses.view"],
            category="warehouse",
        )
    )

    registry.register(
        AIFunction(
            name="list_warehouses",
            description="لیست انبارهای کسب‌وکار.",
            parameters_schema={"type": "object", "properties": {}, "required": []},
            handler=create_handler(_list_warehouses),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["warehouses.view"],
            category="warehouse",
        )
    )

    registry.register(
        AIFunction(
            name="get_warehouse_stock_summary",
            description="خلاصه موجودی انبار (گزارش stock).",
            parameters_schema={
                "type": "object",
                "properties": {
                    "product_id": {"type": "integer", "description": "فیلتر کالا (اختیاری)"},
                    "warehouse_id": {"type": "integer", "description": "فیلتر انبار (اختیاری)"},
                    "as_of_date": {"type": "string", "format": "date", "description": "موجودی در تاریخ (اختیاری)"},
                    "include_zero": {"type": "boolean", "description": "شامل موجودی صفر"},
                },
                "required": [],
            },
            handler=create_handler(_stock_summary),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["inventory.read"],
            category="warehouse",
        )
    )

    # --- چک ---
    registry.register(
        AIFunction(
            name="search_checks",
            description="جستجو در چک‌های دریافتی و پرداختی.",
            parameters_schema={
                "type": "object",
                "properties": {
                    **_COMMON_LIST_PROPS,
                    "person_id": {"type": "integer", "description": "شناسه شخص (اختیاری)"},
                },
                "required": [],
            },
            handler=create_handler(_search_checks),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["checks.view"],
            category="checks",
        )
    )

    registry.register(
        AIFunction(
            name="get_check_details",
            description="جزئیات یک چک.",
            parameters_schema={
                "type": "object",
                "properties": {"check_id": {"type": "integer", "description": "شناسه چک"}},
                "required": ["check_id"],
            },
            handler=create_handler(_get_check),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["checks.view"],
            category="checks",
        )
    )

    # --- انتقال / هزینه / سند ---
    registry.register(
        AIFunction(
            name="search_transfers",
            description="جستجو در اسناد انتقال وجه بین حساب‌ها.",
            parameters_schema={"type": "object", "properties": dict(_COMMON_LIST_PROPS), "required": []},
            handler=create_handler(_search_transfers),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["transfers.view"],
            category="financial",
        )
    )

    registry.register(
        AIFunction(
            name="search_expense_income",
            description="جستجو در اسناد هزینه و درآمد.",
            parameters_schema={
                "type": "object",
                "properties": {
                    **_COMMON_LIST_PROPS,
                    "document_type": {
                        "type": "string",
                        "enum": ["expense", "income"],
                        "description": "نوع سند (اختیاری)",
                    },
                },
                "required": [],
            },
            handler=create_handler(_search_expense_income),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["expenses_income.view"],
            category="financial",
        )
    )

    registry.register(
        AIFunction(
            name="search_documents",
            description="جستجو در اسناد حسابداری (manual، receipt، payment و غیره — غیر از فاکتور تخصصی).",
            parameters_schema={
                "type": "object",
                "properties": {
                    **_COMMON_LIST_PROPS,
                    "document_type": {"type": "string", "description": "نوع سند (اختیاری)"},
                    "person_id": {"type": "integer", "description": "شناسه شخص در سطر سند (اختیاری)"},
                },
                "required": [],
            },
            handler=create_handler(_search_documents),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["accounting_documents.view"],
            category="accounting",
        )
    )

    registry.register(
        AIFunction(
            name="get_document_details",
            description="جزئیات یک سند حسابداری (شامل سطرها).",
            parameters_schema={
                "type": "object",
                "properties": {"document_id": {"type": "integer", "description": "شناسه سند"}},
                "required": ["document_id"],
            },
            handler=create_handler(_get_document),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["accounting_documents.view"],
            category="accounting",
        )
    )

    # --- حساب‌های نقد/بانک ---
    registry.register(
        AIFunction(
            name="list_bank_accounts",
            description="لیست حساب‌های بانکی با موجودی (سال مالی جاری اگر مشخص نشود).",
            parameters_schema={
                "type": "object",
                "properties": {
                    "search": {"type": "string", "description": "جستجو (اختیاری)"},
                    "fiscal_year_id": {"type": "integer", "description": "سال مالی (اختیاری)"},
                    "take": {"type": "integer"},
                    "skip": {"type": "integer"},
                },
                "required": [],
            },
            handler=create_handler(_list_bank_accounts),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["bank_accounts.view"],
            category="financial",
        )
    )

    registry.register(
        AIFunction(
            name="list_cash_registers",
            description="لیست صندوق‌ها با موجودی.",
            parameters_schema={
                "type": "object",
                "properties": {
                    "search": {"type": "string"},
                    "fiscal_year_id": {"type": "integer"},
                    "take": {"type": "integer"},
                    "skip": {"type": "integer"},
                },
                "required": [],
            },
            handler=create_handler(_list_cash_registers),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["cash_registers.view"],
            category="financial",
        )
    )

    # --- سال مالی ---
    registry.register(
        AIFunction(
            name="list_fiscal_years",
            description="لیست سال‌های مالی کسب‌وکار.",
            parameters_schema={"type": "object", "properties": {}, "required": []},
            handler=create_handler(_list_fiscal_years),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["fiscal_years.view"],
            category="accounting",
        )
    )

    registry.register(
        AIFunction(
            name="get_current_fiscal_year",
            description="سال مالی جاری (فعال) کسب‌وکار.",
            parameters_schema={"type": "object", "properties": {}, "required": []},
            handler=create_handler(_get_current_fy),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["fiscal_years.view"],
            category="accounting",
        )
    )

    # --- داشبورد و گردش اشخاص ---
    registry.register(
        AIFunction(
            name="get_business_dashboard",
            description="خلاصه داشبورد: اطلاعات کسب‌وکار، آمار فروش/خرید، فعالیت‌های اخیر.",
            parameters_schema={"type": "object", "properties": {}, "required": []},
            handler=_dashboard_handler,
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["reports.read"],
            category="business",
        )
    )

    registry.register(
        AIFunction(
            name="get_person_transactions",
            description="گزارش گردش/تراکنش‌های یک یا چند شخص (مشتری/تامین‌کننده).",
            parameters_schema={
                "type": "object",
                "properties": {
                    **_COMMON_LIST_PROPS,
                    "person_id": {"type": "integer", "description": "شناسه شخص (توصیه می‌شود)"},
                    "document_type": {
                        "type": "string",
                        "enum": ["receipt", "payment"],
                        "description": "فیلتر نوع (اختیاری)",
                    },
                },
                "required": [],
            },
            handler=create_handler(_person_transactions),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["persons.read"],
            category="persons",
        )
    )


# --- handler implementations (db, business_id, user_id, **kwargs) ---


def _wh_doc_search(db, business_id, user_id, **kwargs):
    from app.services.workflow.actions.hesabix_query_actions import (
        _search_warehouse_documents_internal,
    )
    from app.services.ai.ai_query_service import _build_list_query

    return _search_warehouse_documents_internal(db, business_id, _build_list_query(kwargs))


def _wh_doc_get(db, business_id, user_id, warehouse_document_id, **kwargs):
    from adapters.db.models.warehouse_document import WarehouseDocument
    from app.services.warehouse_service import warehouse_document_to_dict

    wh = (
        db.query(WarehouseDocument)
        .filter(
            WarehouseDocument.id == warehouse_document_id,
            WarehouseDocument.business_id == business_id,
        )
        .first()
    )
    if not wh:
        raise ValueError(f"حواله انبار {warehouse_document_id} یافت نشد")
    return warehouse_document_to_dict(db, wh)


def _list_warehouses(db, business_id, user_id, **kwargs):
    from app.services.warehouse_service import list_warehouses

    return list_warehouses(db, business_id)


def _stock_summary(db, business_id, user_id, **kwargs):
    return get_warehouse_stock_summary(db, business_id, kwargs)


def _search_checks(db, business_id, user_id, **kwargs):
    from app.services.check_service import list_checks
    from app.services.ai.ai_query_service import _build_list_query

    q = _build_list_query(kwargs)
    if q.get("search") and not q.get("search_fields"):
        q["search_fields"] = [
            "check_number",
            "sayad_code",
            "bank_name",
            "branch_name",
            "person_name",
        ]
    return list_checks(db, business_id, q)


def _get_check(db, business_id, user_id, check_id, **kwargs):
    from app.services.check_service import get_check_by_id
    from adapters.db.models.check import Check

    chk = db.query(Check).filter(Check.id == check_id, Check.business_id == business_id).first()
    if not chk:
        raise ValueError(f"چک {check_id} یافت نشد")
    return get_check_by_id(db, check_id)


def _search_transfers(db, business_id, user_id, **kwargs):
    from app.services.transfer_service import list_transfers
    from app.services.ai.ai_query_service import _build_list_query

    q = _build_list_query(kwargs)
    if q.get("search") and not q.get("search_fields"):
        q["search_fields"] = ["code", "description", "created_by_name"]
    return list_transfers(db, business_id, q)


def _search_expense_income(db, business_id, user_id, **kwargs):
    from app.services.expense_income_service import list_expense_income
    from app.services.ai.ai_query_service import _build_list_query

    q = _build_list_query(kwargs)
    if q.get("search") and not q.get("search_fields"):
        q["search_fields"] = ["code", "description", "created_by_name"]
    return list_expense_income(db, business_id, q)


def _search_documents(db, business_id, user_id, **kwargs):
    from app.services.document_service import list_documents
    from app.services.ai.ai_query_service import _build_list_query

    return list_documents(db, business_id, _build_list_query(kwargs))


def _get_document(db, business_id, user_id, document_id, **kwargs):
    from app.services.document_service import get_document
    from adapters.db.models.document import Document

    doc = db.query(Document).filter(
        Document.id == document_id, Document.business_id == business_id
    ).first()
    if not doc:
        raise ValueError(f"سند {document_id} یافت نشد")
    data = get_document(db, document_id)
    if not data:
        raise ValueError(f"سند {document_id} یافت نشد")
    return data


def _list_bank_accounts(db, business_id, user_id, **kwargs):
    from app.services.bank_account_service import list_bank_accounts
    from app.services.ai.ai_query_service import _build_list_query

    q = _build_list_query(kwargs)
    if q.get("search") and not q.get("search_fields"):
        q["search_fields"] = ["code", "name", "branch", "account_number", "owner_name"]
    return list_bank_accounts(db, business_id, q)


def _list_cash_registers(db, business_id, user_id, **kwargs):
    from app.services.cash_register_service import list_cash_registers
    from app.services.ai.ai_query_service import _build_list_query

    q = _build_list_query(kwargs)
    if q.get("search") and not q.get("search_fields"):
        q["search_fields"] = ["code", "name"]
    return list_cash_registers(db, business_id, q)


def _list_fiscal_years(db, business_id, user_id, **kwargs):
    return list_fiscal_years_data(db, business_id)


def _get_current_fy(db, business_id, user_id, **kwargs):
    return get_current_fiscal_year_data(db, business_id)


def _person_transactions(db, business_id, user_id, **kwargs):
    from app.services.person_service import get_people_transactions_report
    from app.services.ai.ai_query_service import _clamp_pagination, _to_int

    q = _clamp_pagination(kwargs)
    pid = _to_int(kwargs.get("person_id"))
    person_ids = [pid] if pid is not None else None
    return get_people_transactions_report(
        db,
        business_id,
        fiscal_year_id=_to_int(kwargs.get("fiscal_year_id")),
        currency_id=_to_int(kwargs.get("currency_id")),
        date_from=kwargs.get("from_date"),
        date_to=kwargs.get("to_date"),
        person_ids=person_ids,
        document_type=kwargs.get("document_type"),
        search=kwargs.get("search"),
        skip=q["skip"],
        take=q["take"],
    )


def _dashboard_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
    db = context["db"]
    user_context = context["user_context"]
    business_id = args.get("business_id") or context.get("business_id")
    return get_business_dashboard_summary(db, int(business_id), user_context)
