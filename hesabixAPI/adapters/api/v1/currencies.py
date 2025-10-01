from fastapi import APIRouter, Depends, Request
from sqlalchemy.orm import Session, joinedload

from adapters.db.session import get_db
from adapters.db.models.currency import Currency
from app.core.responses import success_response
from app.core.responses import ApiError
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.permissions import require_business_access
from adapters.db.models.business import Business


router = APIRouter(prefix="/currencies", tags=["currencies"])


@router.get(
    "",
    summary="فهرست ارزها",
    description="دریافت فهرست ارزهای قابل استفاده",
)
def list_currencies(request: Request, db: Session = Depends(get_db)) -> dict:
    items = [
        {
            "id": c.id,
            "name": c.name,
            "title": c.title,
            "symbol": c.symbol,
            "code": c.code,
        }
        for c in db.query(Currency).order_by(Currency.title.asc()).all()
    ]
    return success_response(items, request)


@router.get(
    "/business/{business_id}",
    summary="فهرست ارزهای کسب‌وکار",
    description="دریافت ارز پیش‌فرض کسب‌وکار به‌علاوه ارزهای فعال آن کسب‌وکار (بدون تکرار)",
)
@require_business_access()
def list_business_currencies(
    request: Request,
    business_id: int,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    business = (
        db.query(Business)
        .options(
            joinedload(Business.default_currency),
            joinedload(Business.currencies),
        )
        .filter(Business.id == business_id)
        .first()
    )
    if not business:
        raise ApiError("NOT_FOUND", "کسب‌وکار یافت نشد", http_status=404)

    seen_ids = set()
    result = []

    # Add default currency first if exists
    if business.default_currency:
        c = business.default_currency
        result.append({
            "id": c.id,
            "name": c.name,
            "title": c.title,
            "symbol": c.symbol,
            "code": c.code,
            "is_default": True,
        })
        seen_ids.add(c.id)

    # Add active business currencies (excluding duplicates)
    for c in business.currencies or []:
        if c.id in seen_ids:
            continue
        result.append({
            "id": c.id,
            "name": c.name,
            "title": c.title,
            "symbol": c.symbol,
            "code": c.code,
            "is_default": False,
        })
        seen_ids.add(c.id)

    # If nothing found, return empty list
    return success_response(result, request)

