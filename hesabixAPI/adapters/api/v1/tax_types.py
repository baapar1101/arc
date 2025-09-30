from typing import Dict, Any, List
from fastapi import APIRouter, Depends, Request

from adapters.api.v1.schemas import SuccessResponse
from adapters.db.session import get_db  # noqa: F401  (kept for consistency/future use)
from app.core.responses import success_response
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.permissions import require_business_access
from sqlalchemy.orm import Session  # noqa: F401


router = APIRouter(prefix="/tax-types", tags=["tax-types"])


def _static_tax_types() -> List[Dict[str, Any]]:
    titles = [
        "دارو",
        "دخانیات",
        "موبایل",
        "لوازم خانگی برقی",
        "قطعات مصرفی و یدکی وسایل نقلیه",
        "فراورده ها و مشتقات نفتی و گازی و پتروشیمیایی",
        "طلا اعم از شمش، مسکوکات و مصنوعات زینتی",
        "منسوجات و پوشاک",
        "اسباب بازی",
        "دام زنده، گوشت سفید و قرمز",
        "محصولات اساسی کشاورزی",
        "سایر کالا ها",
    ]
    return [{"id": idx + 1, "title": t} for idx, t in enumerate(titles)]


@router.get(
    "/business/{business_id}",
    summary="لیست نوع‌های مالیات",
    description="دریافت لیست نوع‌های مالیات (ثابت)",
    response_model=SuccessResponse,
)
@require_business_access()
def list_tax_types(
    request: Request,
    business_id: int,
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    # Currently returns a static list; later can be sourced from DB if needed
    items = _static_tax_types()
    return success_response(items, request)


