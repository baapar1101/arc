from fastapi import APIRouter, Depends, Request, HTTPException
from sqlalchemy.orm import Session
from typing import List, Optional
from decimal import Decimal

from adapters.db.session import get_db
from adapters.db.models.tax_unit import TaxUnit
from adapters.api.v1.schemas import SuccessResponse
from app.core.responses import success_response, format_datetime_fields
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.permissions import require_business_access
from pydantic import BaseModel, Field


router = APIRouter(prefix="/tax-units", tags=["tax-units"])


class TaxUnitCreateRequest(BaseModel):
    name: str = Field(..., min_length=1, max_length=255, description="نام واحد مالیاتی")
    code: str = Field(..., min_length=1, max_length=64, description="کد واحد مالیاتی")
    description: Optional[str] = Field(default=None, description="توضیحات")
    tax_rate: Optional[Decimal] = Field(default=None, ge=0, le=100, description="نرخ مالیات (درصد)")
    is_active: bool = Field(default=True, description="وضعیت فعال/غیرفعال")


class TaxUnitUpdateRequest(BaseModel):
    name: Optional[str] = Field(default=None, min_length=1, max_length=255, description="نام واحد مالیاتی")
    code: Optional[str] = Field(default=None, min_length=1, max_length=64, description="کد واحد مالیاتی")
    description: Optional[str] = Field(default=None, description="توضیحات")
    tax_rate: Optional[Decimal] = Field(default=None, ge=0, le=100, description="نرخ مالیات (درصد)")
    is_active: Optional[bool] = Field(default=None, description="وضعیت فعال/غیرفعال")


class TaxUnitResponse(BaseModel):
    id: int
    business_id: int
    name: str
    code: str
    description: Optional[str] = None
    tax_rate: Optional[Decimal] = None
    is_active: bool
    created_at: str
    updated_at: str

    class Config:
        from_attributes = True


@router.get("/business/{business_id}", 
    summary="لیست واحدهای مالیاتی کسب‌وکار", 
    description="دریافت لیست واحدهای مالیاتی یک کسب‌وکار",
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
                                "business_id": 1,
                                "name": "مالیات بر ارزش افزوده",
                                "code": "VAT",
                                "description": "مالیات بر ارزش افزوده 9 درصد",
                                "tax_rate": 9.0,
                                "is_active": True,
                                "created_at": "2024-01-01T00:00:00Z",
                                "updated_at": "2024-01-01T00:00:00Z"
                            }
                        ]
                    }
                }
            }
        },
        401: {
            "description": "کاربر احراز هویت نشده است"
        },
        403: {
            "description": "دسترسی غیرمجاز به کسب‌وکار"
        },
        404: {
            "description": "کسب‌وکار یافت نشد"
        }
    }
)
@require_business_access()
def get_tax_units(
    request: Request,
    business_id: int,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
) -> dict:
    """دریافت لیست واحدهای مالیاتی یک کسب‌وکار"""
    
    # Query tax units for the business
    tax_units = db.query(TaxUnit).filter(
        TaxUnit.business_id == business_id
    ).order_by(TaxUnit.name).all()
    
    # Convert to response format
    tax_unit_dicts = []
    for tax_unit in tax_units:
        tax_unit_dict = {
            "id": tax_unit.id,
            "business_id": tax_unit.business_id,
            "name": tax_unit.name,
            "code": tax_unit.code,
            "description": tax_unit.description,
            "tax_rate": float(tax_unit.tax_rate) if tax_unit.tax_rate else None,
            "is_active": tax_unit.is_active,
            "created_at": tax_unit.created_at.isoformat(),
            "updated_at": tax_unit.updated_at.isoformat()
        }
        tax_unit_dicts.append(format_datetime_fields(tax_unit_dict, request))
    
    return success_response(tax_unit_dicts, request)


@router.post("/business/{business_id}", 
    summary="ایجاد واحد مالیاتی جدید", 
    description="ایجاد یک واحد مالیاتی جدید برای کسب‌وکار",
    response_model=SuccessResponse,
    responses={
        201: {
            "description": "واحد مالیاتی با موفقیت ایجاد شد",
            "content": {
                "application/json": {
                    "example": {
                        "success": True,
                        "message": "واحد مالیاتی با موفقیت ایجاد شد",
                        "data": {
                            "id": 1,
                            "business_id": 1,
                            "name": "مالیات بر ارزش افزوده",
                            "code": "VAT",
                            "description": "مالیات بر ارزش افزوده 9 درصد",
                            "tax_rate": 9.0,
                            "is_active": True,
                            "created_at": "2024-01-01T00:00:00Z",
                            "updated_at": "2024-01-01T00:00:00Z"
                        }
                    }
                }
            }
        },
        400: {
            "description": "خطا در اعتبارسنجی داده‌ها"
        },
        401: {
            "description": "کاربر احراز هویت نشده است"
        },
        403: {
            "description": "دسترسی غیرمجاز به کسب‌وکار"
        },
        404: {
            "description": "کسب‌وکار یافت نشد"
        }
    }
)
@require_business_access()
def create_tax_unit(
    request: Request,
    business_id: int,
    tax_unit_data: TaxUnitCreateRequest,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
) -> dict:
    """ایجاد واحد مالیاتی جدید"""
    
    # Check if code already exists for this business
    existing_tax_unit = db.query(TaxUnit).filter(
        TaxUnit.business_id == business_id,
        TaxUnit.code == tax_unit_data.code
    ).first()
    
    if existing_tax_unit:
        raise HTTPException(
            status_code=400,
            detail="کد واحد مالیاتی قبلاً استفاده شده است"
        )
    
    # Create new tax unit
    tax_unit = TaxUnit(
        business_id=business_id,
        name=tax_unit_data.name,
        code=tax_unit_data.code,
        description=tax_unit_data.description,
        tax_rate=tax_unit_data.tax_rate,
        is_active=tax_unit_data.is_active
    )
    
    db.add(tax_unit)
    db.commit()
    db.refresh(tax_unit)
    
    # Convert to response format
    tax_unit_dict = {
        "id": tax_unit.id,
        "business_id": tax_unit.business_id,
        "name": tax_unit.name,
        "code": tax_unit.code,
        "description": tax_unit.description,
        "tax_rate": float(tax_unit.tax_rate) if tax_unit.tax_rate else None,
        "is_active": tax_unit.is_active,
        "created_at": tax_unit.created_at.isoformat(),
        "updated_at": tax_unit.updated_at.isoformat()
    }
    
    formatted_response = format_datetime_fields(tax_unit_dict, request)
    
    return success_response(formatted_response, request)


@router.put("/{tax_unit_id}", 
    summary="به‌روزرسانی واحد مالیاتی", 
    description="به‌روزرسانی اطلاعات یک واحد مالیاتی",
    response_model=SuccessResponse,
    responses={
        200: {
            "description": "واحد مالیاتی با موفقیت به‌روزرسانی شد",
            "content": {
                "application/json": {
                    "example": {
                        "success": True,
                        "message": "واحد مالیاتی با موفقیت به‌روزرسانی شد",
                        "data": {
                            "id": 1,
                            "business_id": 1,
                            "name": "مالیات بر ارزش افزوده",
                            "code": "VAT",
                            "description": "مالیات بر ارزش افزوده 9 درصد",
                            "tax_rate": 9.0,
                            "is_active": True,
                            "created_at": "2024-01-01T00:00:00Z",
                            "updated_at": "2024-01-01T00:00:00Z"
                        }
                    }
                }
            }
        },
        400: {
            "description": "خطا در اعتبارسنجی داده‌ها"
        },
        401: {
            "description": "کاربر احراز هویت نشده است"
        },
        403: {
            "description": "دسترسی غیرمجاز به کسب‌وکار"
        },
        404: {
            "description": "واحد مالیاتی یافت نشد"
        }
    }
)
@require_business_access()
def update_tax_unit(
    request: Request,
    tax_unit_id: int,
    tax_unit_data: TaxUnitUpdateRequest,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
) -> dict:
    """به‌روزرسانی واحد مالیاتی"""
    
    # Find the tax unit
    tax_unit = db.query(TaxUnit).filter(TaxUnit.id == tax_unit_id).first()
    if not tax_unit:
        raise HTTPException(status_code=404, detail="واحد مالیاتی یافت نشد")
    
    # Check business access
    if tax_unit.business_id not in ctx.business_ids:
        raise HTTPException(status_code=403, detail="دسترسی غیرمجاز به این کسب‌وکار")
    
    # Check if new code conflicts with existing ones
    if tax_unit_data.code and tax_unit_data.code != tax_unit.code:
        existing_tax_unit = db.query(TaxUnit).filter(
            TaxUnit.business_id == tax_unit.business_id,
            TaxUnit.code == tax_unit_data.code,
            TaxUnit.id != tax_unit_id
        ).first()
        
        if existing_tax_unit:
            raise HTTPException(
                status_code=400,
                detail="کد واحد مالیاتی قبلاً استفاده شده است"
            )
    
    # Update fields
    update_data = tax_unit_data.dict(exclude_unset=True)
    for field, value in update_data.items():
        setattr(tax_unit, field, value)
    
    db.commit()
    db.refresh(tax_unit)
    
    # Convert to response format
    tax_unit_dict = {
        "id": tax_unit.id,
        "business_id": tax_unit.business_id,
        "name": tax_unit.name,
        "code": tax_unit.code,
        "description": tax_unit.description,
        "tax_rate": float(tax_unit.tax_rate) if tax_unit.tax_rate else None,
        "is_active": tax_unit.is_active,
        "created_at": tax_unit.created_at.isoformat(),
        "updated_at": tax_unit.updated_at.isoformat()
    }
    
    formatted_response = format_datetime_fields(tax_unit_dict, request)
    
    return success_response(formatted_response, request)


@router.delete("/{tax_unit_id}", 
    summary="حذف واحد مالیاتی", 
    description="حذف یک واحد مالیاتی",
    response_model=SuccessResponse,
    responses={
        200: {
            "description": "واحد مالیاتی با موفقیت حذف شد",
            "content": {
                "application/json": {
                    "example": {
                        "success": True,
                        "message": "واحد مالیاتی با موفقیت حذف شد",
                        "data": None
                    }
                }
            }
        },
        401: {
            "description": "کاربر احراز هویت نشده است"
        },
        403: {
            "description": "دسترسی غیرمجاز به کسب‌وکار"
        },
        404: {
            "description": "واحد مالیاتی یافت نشد"
        },
        409: {
            "description": "امکان حذف واحد مالیاتی به دلیل استفاده در محصولات وجود ندارد"
        }
    }
)
@require_business_access()
def delete_tax_unit(
    request: Request,
    tax_unit_id: int,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
) -> dict:
    """حذف واحد مالیاتی"""
    
    # Find the tax unit
    tax_unit = db.query(TaxUnit).filter(TaxUnit.id == tax_unit_id).first()
    if not tax_unit:
        raise HTTPException(status_code=404, detail="واحد مالیاتی یافت نشد")
    
    # Check business access
    if tax_unit.business_id not in ctx.business_ids:
        raise HTTPException(status_code=403, detail="دسترسی غیرمجاز به این کسب‌وکار")
    
    # Check if tax unit is used in products
    from adapters.db.models.product import Product
    products_using_tax_unit = db.query(Product).filter(
        Product.tax_unit_id == tax_unit_id
    ).count()
    
    if products_using_tax_unit > 0:
        raise HTTPException(
            status_code=409,
            detail=f"امکان حذف واحد مالیاتی به دلیل استفاده در {products_using_tax_unit} محصول وجود ندارد"
        )
    
    # Delete the tax unit
    db.delete(tax_unit)
    db.commit()
    
    return success_response(None, request)
