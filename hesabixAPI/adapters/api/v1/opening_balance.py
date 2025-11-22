from __future__ import annotations

from typing import Any, Dict, Optional

from fastapi import APIRouter, Depends, Body, Request
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.permissions import require_business_management_dep, require_business_permission_dep
from app.core.responses import success_response, format_datetime_fields
from app.services.opening_balance_service import (
    get_opening_balance,
    upsert_opening_balance,
    post_opening_balance,
)


router = APIRouter(tags=["opening_balance"], prefix="")


@router.get(
    "/businesses/{business_id}/opening-balance",
    summary="دریافت تراز افتتاحیه",
    description="خواندن سند تراز افتتاحیه برای سال مالی مشخص (یا سال جاری در صورت عدم ارسال)",
)
async def get_opening_balance_endpoint(
    request: Request,
    business_id: int,
    fiscal_year_id: Optional[int] = None,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    # Permission: view opening_balance
    if not ctx.has_business_permission("opening_balance", "view"):
        from app.core.responses import ApiError
        raise ApiError("FORBIDDEN", "Missing business permission: opening_balance.view", http_status=403)
    # Access check
    if not ctx.can_access_business(int(business_id)):
        from app.core.responses import ApiError
        raise ApiError("FORBIDDEN", f"No access to business {business_id}", http_status=403)
    result = get_opening_balance(db, business_id, fiscal_year_id)
    return success_response(data=format_datetime_fields(result, request), request=request, message="OPENING_BALANCE_FETCHED")


@router.put(
    "/businesses/{business_id}/opening-balance",
    summary="ذخیره/به‌روزرسانی تراز افتتاحیه",
    description="ایجاد یا بروزرسانی سند تراز افتتاحیه برای سال مالی مشخص",
)
async def upsert_opening_balance_endpoint(
    request: Request,
    business_id: int,
    body: Dict[str, Any] = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("opening_balance", "edit")),
):
    created = upsert_opening_balance(db, business_id, ctx.get_user_id(), body)
    return success_response(data=format_datetime_fields(created, request), request=request, message="OPENING_BALANCE_SAVED")


@router.post(
    "/businesses/{business_id}/opening-balance/post",
    summary="نهایی‌سازی تراز افتتاحیه",
    description="قفل کردن و علامت‌گذاری سند تراز افتتاحیه به عنوان نهایی",
)
async def post_opening_balance_endpoint(
    request: Request,
    business_id: int,
    fiscal_year_id: Optional[int] = None,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("opening_balance", "edit")),
):
    if not ctx.can_access_business(int(business_id)):
        from app.core.responses import ApiError
        raise ApiError("FORBIDDEN", f"No access to business {business_id}", http_status=403)
    posted = post_opening_balance(db, business_id, ctx.get_user_id(), fiscal_year_id)
    return success_response(data=format_datetime_fields(posted, request), request=request, message="OPENING_BALANCE_POSTED")


