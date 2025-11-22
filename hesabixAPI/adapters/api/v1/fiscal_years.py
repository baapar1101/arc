from typing import Dict, Any
from fastapi import APIRouter, Depends, Request
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.permissions import require_business_access, require_business_permission_dep
from app.core.responses import success_response, ApiError, format_datetime_fields
from adapters.db.repositories.fiscal_year_repo import FiscalYearRepository


router = APIRouter(prefix="/business", tags=["fiscal-years"])


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


