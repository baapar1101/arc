from typing import Dict, Any
from fastapi import APIRouter, Depends, Request, Body
from sqlalchemy.orm import Session
from pydantic import BaseModel, Field
from datetime import date

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.permissions import require_business_access, require_business_permission_dep
from app.core.responses import success_response, ApiError, format_datetime_fields
from adapters.db.repositories.fiscal_year_repo import FiscalYearRepository
from adapters.db.models.fiscal_year import FiscalYear
from app.services.year_end_closing_service import preview_year_end_closing, close_fiscal_year


router = APIRouter(prefix="/business", tags=["fiscal-years"])


class YearEndClosingRequest(BaseModel):
    new_fiscal_year_title: str = Field(..., min_length=1, max_length=255, description="عنوان سال مالی جدید")
    auto_create_opening_balance: bool = Field(default=True, description="ایجاد خودکار تراز افتتاحیه سال جدید")


@router.get("/{business_id}/fiscal-years")
@require_business_access("business_id")
def list_fiscal_years(
    request: Request,
    business_id: int,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    _: None = Depends(require_business_permission_dep("fiscal_years", "view")),
) -> Dict[str, Any]:
    repo = FiscalYearRepository(db)

    items = repo.list_by_business(business_id)

    data = [
        {
            "id": fy.id,
            "title": fy.title,
            "start_date": fy.start_date,
            "end_date": fy.end_date,
            "is_current": fy.is_last,
        }
        for fy in items
    ]

    return success_response(data=format_datetime_fields({"items": data}, request), request=request, message="FISCAL_YEARS_LIST_FETCHED")


@router.get("/{business_id}/fiscal-years/current")
@require_business_access("business_id")
def get_current_fiscal_year(
    request: Request,
    business_id: int,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    _: None = Depends(require_business_permission_dep("fiscal_years", "view")),
) -> Dict[str, Any]:
    repo = FiscalYearRepository(db)

    fy = repo.get_current_for_business(business_id)
    if not fy:
        return success_response(data=None, request=request, message="NO_CURRENT_FISCAL_YEAR")

    data = {
        "id": fy.id,
        "title": fy.title,
        "start_date": fy.start_date,
        "end_date": fy.end_date,
        "is_current": fy.is_last,
    }
    return success_response(data=format_datetime_fields(data, request), request=request, message="FISCAL_YEAR_CURRENT_FETCHED")


@router.get("/{business_id}/fiscal-years/{fiscal_year_id}/closing/preview")
@require_business_access("business_id")
def preview_year_end_closing_endpoint(
    request: Request,
    business_id: int,
    fiscal_year_id: int,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    _: None = Depends(require_business_permission_dep("fiscal_years", "view")),
) -> Dict[str, Any]:
    """پیش‌نمایش بستن سال مالی"""
    try:
        preview_data = preview_year_end_closing(db, business_id, fiscal_year_id)
        return success_response(
            data=format_datetime_fields(preview_data, request),
            request=request,
            message="YEAR_END_CLOSING_PREVIEW_FETCHED"
        )
    except ApiError as e:
        raise e
    except Exception as e:
        raise ApiError("PREVIEW_FAILED", f"خطا در پیش‌نمایش بستن سال مالی: {str(e)}", http_status=500)


@router.post("/{business_id}/fiscal-years/{fiscal_year_id}/close")
@require_business_access("business_id")
def close_fiscal_year_endpoint(
    request: Request,
    business_id: int,
    fiscal_year_id: int,
    payload: YearEndClosingRequest = Body(...),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    _: None = Depends(require_business_permission_dep("fiscal_years", "close")),
) -> Dict[str, Any]:
    """بستن سال مالی"""
    try:
        result = close_fiscal_year(
            db=db,
            business_id=business_id,
            fiscal_year_id=fiscal_year_id,
            user_id=ctx.get_user_id(),
            new_fiscal_year_title=payload.new_fiscal_year_title,
            auto_create_opening_balance=payload.auto_create_opening_balance,
        )
        return success_response(
            data=format_datetime_fields(result, request),
            request=request,
            message="FISCAL_YEAR_CLOSED_SUCCESSFULLY"
        )
    except ApiError as e:
        raise e
    except Exception as e:
        raise ApiError("CLOSING_FAILED", f"خطا در بستن سال مالی: {str(e)}", http_status=500)


class FiscalYearUpdateRequest(BaseModel):
    title: str = Field(..., min_length=1, max_length=255, description="عنوان سال مالی")
    start_date: date = Field(..., description="تاریخ شروع سال مالی")
    end_date: date = Field(..., description="تاریخ پایان سال مالی")


@router.put("/{business_id}/fiscal-years/current")
@require_business_access("business_id")
def update_current_fiscal_year(
    request: Request,
    business_id: int,
    payload: FiscalYearUpdateRequest = Body(...),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    _: None = Depends(require_business_permission_dep("fiscal_years", "edit")),
) -> Dict[str, Any]:
    """ویرایش سال مالی جاری (فقط عنوان و تاریخ‌ها)"""
    repo = FiscalYearRepository(db)
    
    # دریافت سال مالی جاری
    fiscal_year = repo.get_current_for_business(business_id)
    
    if not fiscal_year:
        raise ApiError("NO_CURRENT_FISCAL_YEAR", "سال مالی جاری یافت نشد", http_status=404)
    
    # بررسی اینکه سال مالی متعلق به این کسب و کار است
    if int(fiscal_year.business_id) != int(business_id):
        raise ApiError("FISCAL_YEAR_NOT_FOUND", "سال مالی متعلق به این کسب‌وکار نیست", http_status=404)
    
    # بررسی اعتبار تاریخ‌ها
    if payload.start_date >= payload.end_date:
        raise ApiError("INVALID_DATE_RANGE", "تاریخ شروع باید قبل از تاریخ پایان باشد", http_status=400)
    
    # به‌روزرسانی فیلدها
    fiscal_year.title = payload.title
    fiscal_year.start_date = payload.start_date
    fiscal_year.end_date = payload.end_date
    
    db.commit()
    db.refresh(fiscal_year)
    
    data = {
        "id": fiscal_year.id,
        "title": fiscal_year.title,
        "start_date": fiscal_year.start_date,
        "end_date": fiscal_year.end_date,
        "is_current": fiscal_year.is_last,
    }
    
    return success_response(
        data=format_datetime_fields(data, request),
        request=request,
        message="FISCAL_YEAR_UPDATED_SUCCESSFULLY"
    )


