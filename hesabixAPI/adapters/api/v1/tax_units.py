from fastapi import APIRouter, Depends, Request
from sqlalchemy.orm import Session
from typing import Dict, Any

from adapters.db.session import get_db
from adapters.db.models.tax_unit import TaxUnit
from adapters.api.v1.schemas import SuccessResponse
from app.core.responses import success_response


router = APIRouter(prefix="/tax-units", tags=["tax-units"])


@router.get("/", 
    summary="لیست واحدهای مالیاتی", 
    description="دریافت لیست تمام واحدهای مالیاتی استاندارد",
    response_model=SuccessResponse,
    responses={
        200: {
            "description": "لیست واحدهای مالیاتی با موفقیت دریافت شد",
            "content": {
                "application/json": {
                    "example": {
                        "success": True,
                        "message": "لیست واحدهای مالیاتی دریافت شد",
                        "data": [
                            {
                                "id": 1,
                                "name": "کیلوگرم",
                                "code": "کیلوگرم",
                                "description": None,
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
def list_tax_units(
    request: Request,
    db: Session = Depends(get_db)
) -> Dict[str, Any]:
    """دریافت لیست تمام واحدهای مالیاتی استاندارد"""
    
    # Query all tax units (they are global now)
    tax_units = db.query(TaxUnit).order_by(TaxUnit.name).all()
    
    # Convert to response format
    tax_unit_dicts = []
    for tax_unit in tax_units:
        tax_unit_dict = {
            "id": tax_unit.id,
            "name": tax_unit.name,
            "code": tax_unit.code,
            "description": tax_unit.description,
            "created_at": tax_unit.created_at.isoformat(),
            "updated_at": tax_unit.updated_at.isoformat()
        }
        tax_unit_dicts.append(tax_unit_dict)
    
    return success_response(tax_unit_dicts, request)