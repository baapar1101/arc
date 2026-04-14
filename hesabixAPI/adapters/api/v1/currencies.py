from fastapi import APIRouter, Depends, Request
from sqlalchemy.orm import Session, joinedload

from adapters.db.session import get_db
from adapters.db.models.currency import Currency
from app.core.responses import success_response
from app.core.responses import ApiError
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.permissions import require_business_access
from adapters.db.models.business import Business
from app.core.cache import get_cache


router = APIRouter(prefix="/currencies", tags=["currencies"])


@router.get(
    "",
    summary="فهرست ارزها",
    description="دریافت فهرست ارزهای قابل استفاده",
)
def list_currencies(request: Request, db: Session = Depends(get_db)) -> dict:
    cache = get_cache()
    cache_key = "currencies:all"

    if cache.enabled:
        cached = cache.get(cache_key)
        if cached is not None:
            return success_response(cached, request)

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

    if cache.enabled:
        cache.set(cache_key, items, ttl=300)

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
    # کش نتایج بر اساس کسب‌وکار
    cache = get_cache()
    cache_key = f"business_currencies:{business_id}"

    if cache.enabled:
        cached = cache.get(cache_key)
        if cached is not None:
            return success_response(cached, request)

    # بهینه‌سازی: استفاده از query مستقیم به جای joinedload برای کاهش زمان
    from adapters.db.models.currency import Currency, BusinessCurrency
    
    # دریافت business برای بررسی default_currency_id
    business = db.query(Business).filter(Business.id == business_id).first()
    if not business:
        raise ApiError("NOT_FOUND", "کسب‌وکار یافت نشد", http_status=404)

    seen_ids = set()
    result = []

    # Add default currency first if exists
    if business.default_currency_id:
        default_currency = db.query(Currency).filter(Currency.id == business.default_currency_id).first()
        if default_currency:
            result.append({
                "id": default_currency.id,
                "name": default_currency.name,
                "title": default_currency.title,
                "symbol": default_currency.symbol,
                "code": default_currency.code,
                "is_default": True,
            })
            seen_ids.add(default_currency.id)

    # Add active business currencies (excluding duplicates)
    # استفاده از query مستقیم به جای relationship
    business_currencies = (
        db.query(Currency)
        .join(BusinessCurrency, BusinessCurrency.currency_id == Currency.id)
        .filter(BusinessCurrency.business_id == business_id)
        .all()
    )
    
    for c in business_currencies:
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
    if cache.enabled:
        cache.set(cache_key, result, ttl=300)

    return success_response(result, request)

