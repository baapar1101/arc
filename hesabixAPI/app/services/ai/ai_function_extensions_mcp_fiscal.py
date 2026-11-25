"""MCP tools for fiscal-year create/set-current/close/rollback. Tenant pinned; close/rollback always high-risk."""
from __future__ import annotations

from datetime import date
from typing import Any, Dict

from app.services.ai.ai_mcp_tool_util import (
    mcp_await,
    mcp_bid,
    mcp_db,
    mcp_jsonable,
    mcp_run,
    mcp_schema,
    mcp_translator,
    mcp_uid,
)

CREATE_FISCAL_YEAR_SCHEMA: Dict[str, Any] = {}
UPDATE_CURRENT_FISCAL_YEAR_SCHEMA: Dict[str, Any] = {}
CLOSE_FISCAL_YEAR_SCHEMA: Dict[str, Any] = {}

CREATE_FISCAL_YEAR_SCHEMA = mcp_schema(
    {
        "title": {"type": "string", "minLength": 1, "maxLength": 255},
        "start_date": {"type": "string", "description": "ISO date YYYY-MM-DD"},
        "end_date": {"type": "string", "description": "ISO date YYYY-MM-DD"},
        "set_as_current": {"type": "boolean"},
    },
    ["title", "start_date", "end_date"],
)
UPDATE_CURRENT_FISCAL_YEAR_SCHEMA = mcp_schema(
    {
        "title": {"type": "string", "minLength": 1, "maxLength": 255},
        "start_date": {"type": "string"},
        "end_date": {"type": "string"},
    },
    ["title", "start_date", "end_date"],
)
_SET_CURRENT = mcp_schema({"fiscal_year_id": {"type": "integer", "minimum": 1}}, ["fiscal_year_id"])
_PREVIEW_CLOSE = mcp_schema(
    {
        "fiscal_year_id": {"type": "integer", "minimum": 1},
        "closing_fiscal_end_date": {"type": ["string", "null"]},
        "document_relocation_basis": {"type": "string", "enum": ["document_date", "registered_at"]},
    },
    ["fiscal_year_id"],
)
_SHARE = {
    "type": "object",
    "additionalProperties": False,
    "required": ["person_id", "profit_amount"],
    "properties": {
        "person_id": {"type": "integer", "minimum": 1},
        "profit_amount": {"type": "number", "minimum": 0},
    },
}
CLOSE_FISCAL_YEAR_SCHEMA = mcp_schema(
    {
        "fiscal_year_id": {"type": "integer", "minimum": 1},
        "new_fiscal_year_title": {"type": "string", "minLength": 1, "maxLength": 255},
        "auto_create_opening_balance": {"type": "boolean"},
        "tax_percentage": {"type": ["number", "null"], "minimum": 0, "maximum": 100},
        "tax_amount": {"type": ["number", "null"], "minimum": 0},
        "profit_distribution_percentage": {"type": ["number", "null"], "minimum": 0, "maximum": 100},
        "profit_distribution_amount": {"type": ["number", "null"], "minimum": 0},
        "shareholder_profit_account_id": {"type": ["integer", "null"], "minimum": 1},
        "retained_earnings_from_previous_years": {"type": ["number", "null"], "minimum": 0},
        "auto_issue_person_balance_document": {"type": "boolean"},
        "new_fiscal_year_start_date": {"type": ["string", "null"]},
        "new_fiscal_year_end_date": {"type": ["string", "null"]},
        "inventory_valuation_method": {"type": "string", "enum": ["FIFO", "LIFO", "WeightedAverage"]},
        "shareholder_distributions": {"type": "array", "maxItems": 200, "items": _SHARE},
        "closing_fiscal_end_date": {"type": ["string", "null"]},
        "document_relocation_basis": {"type": "string", "enum": ["document_date", "registered_at"]},
        "move_post_cutoff_documents_to_new_fiscal_year": {"type": "boolean"},
    },
    ["fiscal_year_id", "new_fiscal_year_title"],
)
_TOKEN = mcp_schema({"confirmation_token": {"type": "string", "minLength": 10}}, ["confirmation_token"])


def _date(value) -> date:
    return date.fromisoformat(str(value)[:10])


def _date_or_none(value):
    if value in (None, ""):
        return None
    return _date(value)


def _pin_fiscal(db, business_id: int, fiscal_year_id: int):
    from adapters.db.repositories.fiscal_year_repo import FiscalYearRepository

    fy = FiscalYearRepository(db).get_by_id(int(fiscal_year_id))
    if not fy or int(fy.business_id) != int(business_id):
        raise ValueError("سال مالی یافت نشد")
    return fy


def create_fiscal_year_handler(args, context):
    from adapters.api.v1.fiscal_years import _date_ranges_overlap
    from adapters.db.repositories.fiscal_year_repo import FiscalYearRepository
    from app.core.cache import get_cache

    db = mcp_db(context)
    bid = mcp_bid(context)
    start = _date(args["start_date"])
    end = _date(args["end_date"])
    if start >= end:
        raise ValueError("تاریخ شروع باید قبل از تاریخ پایان باشد")
    repo = FiscalYearRepository(db)
    all_fiscal = repo.list_by_business(bid)
    for fy in all_fiscal:
        if _date_ranges_overlap(start, end, fy.start_date, fy.end_date):
            raise ValueError(f"بازهٔ انتخاب‌شده با سال مالی «{fy.title}» همپوشانی دارد.")
    is_last = bool(args.get("set_as_current")) or len(all_fiscal) == 0
    if is_last and all_fiscal:
        for fy in all_fiscal:
            if fy.is_last:
                fy.is_last = False
                db.add(fy)
        db.flush()
    fiscal_year = mcp_run(
        repo.create_fiscal_year,
        business_id=bid,
        title=str(args["title"]).strip(),
        start_date=start,
        end_date=end,
        is_last=is_last,
    )
    cache = get_cache()
    if cache.enabled:
        cache.delete(f"fiscal_years:{bid}")
    return mcp_jsonable(
        {
            "id": fiscal_year.id,
            "title": fiscal_year.title,
            "start_date": fiscal_year.start_date,
            "end_date": fiscal_year.end_date,
            "is_current": fiscal_year.is_last,
        }
    )


def update_current_fiscal_year_handler(args, context):
    from adapters.api.v1.fiscal_years import _date_ranges_overlap
    from adapters.db.repositories.fiscal_year_repo import FiscalYearRepository
    from app.core.cache import get_cache

    db = mcp_db(context)
    bid = mcp_bid(context)
    start = _date(args["start_date"])
    end = _date(args["end_date"])
    if start >= end:
        raise ValueError("تاریخ شروع باید قبل از تاریخ پایان باشد")
    repo = FiscalYearRepository(db)
    all_fiscal = repo.list_by_business(bid)
    current = repo.get_current_for_business(bid)
    exclude_id = int(current.id) if current else None
    for fy in all_fiscal:
        if exclude_id is not None and int(fy.id) == exclude_id:
            continue
        if _date_ranges_overlap(start, end, fy.start_date, fy.end_date):
            raise ValueError(f"بازهٔ انتخاب‌شده با سال مالی «{fy.title}» همپوشانی دارد.")
    if current:
        if int(current.business_id) != bid:
            raise ValueError("سال مالی متعلق به این کسب‌وکار نیست")
        current.title = str(args["title"]).strip()
        current.start_date = start
        current.end_date = end
        db.commit()
        db.refresh(current)
        fiscal_year = current
    else:
        fiscal_year = repo.create_fiscal_year(
            business_id=bid,
            title=str(args["title"]).strip(),
            start_date=start,
            end_date=end,
            is_last=True,
        )
    cache = get_cache()
    if cache.enabled:
        cache.delete(f"fiscal_years:{bid}")
    return mcp_jsonable(
        {
            "id": fiscal_year.id,
            "title": fiscal_year.title,
            "start_date": fiscal_year.start_date,
            "end_date": fiscal_year.end_date,
            "is_current": fiscal_year.is_last,
        }
    )


def set_current_fiscal_year_handler(args, context):
    from adapters.db.repositories.fiscal_year_repo import FiscalYearRepository
    from app.core.cache import get_cache

    db = mcp_db(context)
    bid = mcp_bid(context)
    _pin_fiscal(db, bid, int(args["fiscal_year_id"]))
    fiscal_year = mcp_run(FiscalYearRepository(db).set_current_for_business, bid, int(args["fiscal_year_id"]))
    cache = get_cache()
    if cache.enabled:
        cache.delete(f"fiscal_years:{bid}")
    return mcp_jsonable(
        {
            "id": fiscal_year.id,
            "title": fiscal_year.title,
            "start_date": fiscal_year.start_date,
            "end_date": fiscal_year.end_date,
            "is_current": fiscal_year.is_last,
        }
    )


def preview_year_end_closing_handler(args, context):
    from app.services.year_end_closing_service import preview_year_end_closing

    bid = mcp_bid(context)
    _pin_fiscal(mcp_db(context), bid, int(args["fiscal_year_id"]))
    return mcp_jsonable(
        mcp_run(
            preview_year_end_closing,
            mcp_db(context),
            bid,
            int(args["fiscal_year_id"]),
            closing_fiscal_end_date=_date_or_none(args.get("closing_fiscal_end_date")),
            document_relocation_basis=args.get("document_relocation_basis") or "document_date",
        )
    )


def close_fiscal_year_handler(args, context):
    from app.core.cache import get_cache
    from app.services.year_end_closing_service import close_fiscal_year

    bid = mcp_bid(context)
    _pin_fiscal(mcp_db(context), bid, int(args["fiscal_year_id"]))
    if args.get("tax_percentage") is not None and args.get("tax_amount") is not None:
        raise ValueError("فقط یکی از درصد یا مبلغ مالیات باید وارد شود")
    if args.get("profit_distribution_percentage") is not None and args.get("profit_distribution_amount") is not None:
        raise ValueError("فقط یکی از درصد یا مبلغ تقسیم سود باید وارد شود")
    distributions = None
    if args.get("shareholder_distributions"):
        distributions = [
            {"person_id": item["person_id"], "profit_amount": item["profit_amount"]}
            for item in args["shareholder_distributions"]
        ]
    result = mcp_await(
        close_fiscal_year(
            db=mcp_db(context),
            business_id=bid,
            fiscal_year_id=int(args["fiscal_year_id"]),
            user_id=mcp_uid(context),
            new_fiscal_year_title=args["new_fiscal_year_title"],
            auto_create_opening_balance=bool(args.get("auto_create_opening_balance", True)),
            tax_percentage=args.get("tax_percentage"),
            tax_amount=args.get("tax_amount"),
            profit_distribution_percentage=args.get("profit_distribution_percentage"),
            profit_distribution_amount=args.get("profit_distribution_amount"),
            shareholder_profit_account_id=args.get("shareholder_profit_account_id"),
            retained_earnings_from_previous_years=args.get("retained_earnings_from_previous_years"),
            auto_issue_person_balance_document=bool(args.get("auto_issue_person_balance_document", False)),
            new_fiscal_year_start_date=_date_or_none(args.get("new_fiscal_year_start_date")),
            new_fiscal_year_end_date=_date_or_none(args.get("new_fiscal_year_end_date")),
            inventory_valuation_method=args.get("inventory_valuation_method") or "FIFO",
            shareholder_distributions=distributions,
            closing_fiscal_end_date=_date_or_none(args.get("closing_fiscal_end_date")),
            document_relocation_basis=args.get("document_relocation_basis") or "document_date",
            move_post_cutoff_documents_to_new_fiscal_year=bool(
                args.get("move_post_cutoff_documents_to_new_fiscal_year", True)
            ),
        )
    )
    cache = get_cache()
    if cache.enabled:
        cache.delete(f"fiscal_years:{bid}")
    return mcp_jsonable(result)


def preview_fiscal_year_rollback_handler(args, context):
    from app.services.fiscal_year_rollback_service import preview_current_fiscal_year_rollback

    return mcp_jsonable(
        mcp_run(
            preview_current_fiscal_year_rollback,
            mcp_db(context),
            mcp_bid(context),
            mcp_uid(context),
            mcp_translator(),
        )
    )


def execute_fiscal_year_rollback_handler(args, context):
    from app.services.fiscal_year_rollback_service import execute_current_fiscal_year_rollback

    return mcp_jsonable(
        mcp_run(
            execute_current_fiscal_year_rollback,
            mcp_db(context),
            mcp_bid(context),
            mcp_uid(context),
            args["confirmation_token"],
            mcp_translator(),
        )
    )


def register_mcp_fiscal_functions(registry) -> None:
    from app.services.ai.function_registry import AIFunction, AIRole

    roles = {AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN}
    registry.register(AIFunction(
        name="create_fiscal_year",
        description="ایجاد سال مالی بدون همپوشانی بازه. set_as_current آن را سال جاری می‌کند بدون بستن حساب‌ها.",
        parameters_schema=CREATE_FISCAL_YEAR_SCHEMA,
        handler=create_fiscal_year_handler,
        allowed_roles=roles,
        required_permissions=["fiscal_years.edit"],
        category="financial",
        requires_approval=True,
        risk_level="medium",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="update_current_fiscal_year",
        description="ویرایش عنوان و بازه سال مالی جاری کسب‌وکار متصل. اگر سال جاری نباشد ایجاد می‌شود.",
        parameters_schema=UPDATE_CURRENT_FISCAL_YEAR_SCHEMA,
        handler=update_current_fiscal_year_handler,
        allowed_roles=roles,
        required_permissions=["fiscal_years.edit"],
        category="financial",
        requires_approval=True,
        risk_level="medium",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="set_current_fiscal_year",
        description="تعویض نرم سال مالی جاری بدون بستن سود و زیان. فقط is_last جابه‌جا می‌شود.",
        parameters_schema=_SET_CURRENT,
        handler=set_current_fiscal_year_handler,
        allowed_roles=roles,
        required_permissions=["fiscal_years.edit"],
        category="financial",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="preview_year_end_closing",
        description="پیش‌نمایش بستن سال مالی جاری: مانده حساب‌های موقت و اسناد قابل انتقال.",
        parameters_schema=_PREVIEW_CLOSE,
        handler=preview_year_end_closing_handler,
        allowed_roles=roles,
        required_permissions=["fiscal_years.view"],
        category="financial",
        is_readonly=True,
    ))
    registry.register(AIFunction(
        name="close_fiscal_year",
        description="بستن سال مالی جاری و ایجاد سال جدید. برگشت‌ناپذیر مگر rollback. نیازمند تأیید.",
        parameters_schema=CLOSE_FISCAL_YEAR_SCHEMA,
        handler=close_fiscal_year_handler,
        allowed_roles=roles,
        required_permissions=["fiscal_years.close"],
        category="financial",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="preview_fiscal_year_rollback",
        description="پیش‌نمایش حذف سال مالی جاری و بازگشت به سال قبل به‌همراه توکن تأیید.",
        parameters_schema=mcp_schema({}),
        handler=preview_fiscal_year_rollback_handler,
        allowed_roles=roles,
        required_permissions=["fiscal_years.rollback"],
        category="financial",
        is_readonly=True,
    ))
    registry.register(AIFunction(
        name="execute_fiscal_year_rollback",
        description="اجرای بازگشت سال مالی با توکن پیش‌نمایش. نیازمند تأیید.",
        parameters_schema=_TOKEN,
        handler=execute_fiscal_year_rollback_handler,
        allowed_roles=roles,
        required_permissions=["fiscal_years.rollback"],
        category="financial",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
