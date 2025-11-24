from typing import Dict, Any
from fastapi import APIRouter, Depends, Request

from adapters.api.v1.schemas import SuccessResponse
from adapters.db.session import get_db
from app.core.responses import success_response
from sqlalchemy.orm import Session
from adapters.db.models.tax_type import TaxType


router = APIRouter(prefix="/tax-types", tags=["tax-types"])


@router.get("/", 
    summary="لیست نوع‌های مالیات", 
    description="دریافت لیست تمام نوع‌های مالیات استاندارد",
    response_model=SuccessResponse,
    responses={
        200: {
            "description": "لیست نوع‌های مالیات با موفقیت دریافت شد",
            "content": {
                "application/json": {
                    "example": {
                        "success": True,
                        "message": "لیست نوع‌های مالیات دریافت شد",
                        "data": [
                            {
                                "id": 1,
                                "title": "ارزش افزوده گروه دارو",
                                "code": "VAT_DRUG",
                                "description": "مالیات ارزش افزوده برای گروه دارو و تجهیزات پزشکی",
                                "created_at": "2024-01-01T00:00:00Z",
                                "updated_at": "2024-01-01T00:00:00Z"
                            }
                        ]
                    }
                }
            }
        }
    }
)
def list_tax_types(
    request: Request,
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    """دریافت لیست تمام نوع‌های مالیات استاندارد"""
    
    items = [
        {
            "id": it.id,
            "title": it.title,
            "code": it.code,
            "description": it.description,
            "created_at": it.created_at.isoformat(),
            "updated_at": it.updated_at.isoformat(),
        }
        for it in db.query(TaxType).order_by(TaxType.id).all()
    ]
    return success_response(items, request)