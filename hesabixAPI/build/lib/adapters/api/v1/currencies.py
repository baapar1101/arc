from fastapi import APIRouter, Depends, Request
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from adapters.db.models.currency import Currency
from app.core.responses import success_response


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


