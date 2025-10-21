"""
API endpoints برای هزینه و درآمد (Expense & Income)
"""

from typing import Any, Dict
from fastapi import APIRouter, Depends, Request, Body
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.permissions import require_business_management_dep, require_business_access
from app.core.responses import success_response, format_datetime_fields
from adapters.api.v1.schemas import QueryInfo
from app.services.expense_income_service import (
    create_expense_income,
    list_expense_income,
)


router = APIRouter(tags=["expense-income"])


@router.post(
    "/businesses/{business_id}/expense-income/create",
    summary="ایجاد سند هزینه یا درآمد",
    description="ایجاد سند هزینه/درآمد با چند سطر حساب و چند طرف‌حساب",
)
@require_business_access("business_id")
async def create_expense_income_endpoint(
    request: Request,
    business_id: int,
    body: Dict[str, Any] = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_management_dep),
):
    created = create_expense_income(db, business_id, ctx.get_user_id(), body)
    return success_response(
        data=format_datetime_fields(created, request),
        request=request,
        message="EXPENSE_INCOME_CREATED",
    )


@router.post(
    "/businesses/{business_id}/expense-income",
    summary="لیست اسناد هزینه/درآمد",
    description="دریافت لیست اسناد هزینه/درآمد با جستجو و صفحه‌بندی",
)
@require_business_access("business_id")
async def list_expense_income_endpoint(
    request: Request,
    business_id: int,
    query_info: QueryInfo = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    query_dict: Dict[str, Any] = {
        "take": query_info.take,
        "skip": query_info.skip,
        "sort_by": query_info.sort_by,
        "sort_desc": query_info.sort_desc,
        "search": query_info.search,
    }

    # Read extra body filters
    try:
        body_json = await request.json()
        if isinstance(body_json, dict):
            for key in ["document_type", "from_date", "to_date"]:
                if key in body_json:
                    query_dict[key] = body_json[key]
    except Exception:
        pass

    # Fiscal year from header
    try:
        fy_header = request.headers.get("X-Fiscal-Year-ID")
        if fy_header:
            query_dict["fiscal_year_id"] = int(fy_header)
    except Exception:
        pass

    result = list_expense_income(db, business_id, query_dict)
    result["items"] = [format_datetime_fields(item, request) for item in result.get("items", [])]
    return success_response(data=result, request=request, message="EXPENSE_INCOME_LIST_FETCHED")


