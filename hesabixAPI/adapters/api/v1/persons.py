from fastapi import APIRouter, Depends, HTTPException, Query, Request
from sqlalchemy.orm import Session
from typing import Dict, Any

from adapters.db.session import get_db
from adapters.api.v1.schema_models.person import (
    PersonCreateRequest, PersonUpdateRequest, PersonResponse,
    PersonListResponse, PersonSummaryResponse, PersonBankAccountCreateRequest
)
from adapters.api.v1.schemas import QueryInfo, SuccessResponse
from app.core.responses import success_response, format_datetime_fields
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.permissions import require_business_management
from app.services.person_service import (
    create_person, get_person_by_id, get_persons_by_business,
    update_person, delete_person, get_person_summary
)
from adapters.db.models.person import Person

router = APIRouter(prefix="/persons", tags=["persons"])


@router.post("/businesses/{business_id}/persons/create", 
    summary="ایجاد شخص جدید", 
    description="ایجاد شخص جدید برای کسب و کار مشخص",
    response_model=SuccessResponse,
    responses={
        200: {
            "description": "شخص با موفقیت ایجاد شد",
            "content": {
                "application/json": {
                    "example": {
                        "success": True,
                        "message": "شخص با موفقیت ایجاد شد",
                        "data": {
                            "id": 1,
                            "business_id": 1,
                            "alias_name": "علی احمدی",
                            "person_type": "مشتری",
                            "created_at": "2024-01-01T00:00:00Z"
                        }
                    }
                }
            }
        },
        400: {
            "description": "خطا در اعتبارسنجی داده‌ها"
        },
        401: {
            "description": "عدم احراز هویت"
        },
        403: {
            "description": "عدم دسترسی به کسب و کار"
        }
    }
)
async def create_person_endpoint(
    business_id: int,
    person_data: PersonCreateRequest,
    db: Session = Depends(get_db),
    auth_context: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_management())
):
    """ایجاد شخص جدید برای کسب و کار"""
    result = create_person(db, business_id, person_data)
    return success_response(
        message=result['message'],
        data=format_datetime_fields(result['data'])
    )


@router.post("/businesses/{business_id}/persons",
    summary="لیست اشخاص کسب و کار",
    description="دریافت لیست اشخاص یک کسب و کار با امکان جستجو و فیلتر",
    response_model=SuccessResponse,
    responses={
        200: {
            "description": "لیست اشخاص با موفقیت دریافت شد",
            "content": {
                "application/json": {
                    "example": {
                        "success": True,
                        "message": "لیست اشخاص با موفقیت دریافت شد",
                        "data": {
                            "items": [],
                            "pagination": {
                                "total": 0,
                                "page": 1,
                                "per_page": 20,
                                "total_pages": 0,
                                "has_next": False,
                                "has_prev": False
                            },
                            "query_info": {}
                        }
                    }
                }
            }
        }
    }
)
async def get_persons_endpoint(
    business_id: int,
    query_info: QueryInfo,
    db: Session = Depends(get_db),
    auth_context: AuthContext = Depends(get_current_user)
):
    """دریافت لیست اشخاص کسب و کار"""
    query_dict = {
        "take": query_info.take,
        "skip": query_info.skip,
        "sort_by": query_info.sort_by,
        "sort_desc": query_info.sort_desc,
        "search": query_info.search
    }
    result = get_persons_by_business(db, business_id, query_dict)
    
    # فرمت کردن تاریخ‌ها
    for item in result['items']:
        item = format_datetime_fields(item)
    
    return success_response(
        message="لیست اشخاص با موفقیت دریافت شد",
        data=result
    )


@router.get("/persons/{person_id}",
    summary="جزئیات شخص",
    description="دریافت جزئیات یک شخص",
    response_model=SuccessResponse,
    responses={
        200: {
            "description": "جزئیات شخص با موفقیت دریافت شد"
        },
        404: {
            "description": "شخص یافت نشد"
        }
    }
)
async def get_person_endpoint(
    person_id: int,
    db: Session = Depends(get_db),
    auth_context: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_management())
):
    """دریافت جزئیات شخص"""
    # ابتدا باید business_id را از person دریافت کنیم
    person = db.query(Person).filter(Person.id == person_id).first()
    if not person:
        raise HTTPException(status_code=404, detail="شخص یافت نشد")
    
    result = get_person_by_id(db, person_id, person.business_id)
    if not result:
        raise HTTPException(status_code=404, detail="شخص یافت نشد")
    
    return success_response(
        message="جزئیات شخص با موفقیت دریافت شد",
        data=format_datetime_fields(result)
    )


@router.put("/persons/{person_id}",
    summary="ویرایش شخص",
    description="ویرایش اطلاعات یک شخص",
    response_model=SuccessResponse,
    responses={
        200: {
            "description": "شخص با موفقیت ویرایش شد"
        },
        404: {
            "description": "شخص یافت نشد"
        }
    }
)
async def update_person_endpoint(
    person_id: int,
    person_data: PersonUpdateRequest,
    db: Session = Depends(get_db),
    auth_context: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_management())
):
    """ویرایش شخص"""
    # ابتدا باید business_id را از person دریافت کنیم
    person = db.query(Person).filter(Person.id == person_id).first()
    if not person:
        raise HTTPException(status_code=404, detail="شخص یافت نشد")
    
    result = update_person(db, person_id, person.business_id, person_data)
    if not result:
        raise HTTPException(status_code=404, detail="شخص یافت نشد")
    
    return success_response(
        message=result['message'],
        data=format_datetime_fields(result['data'])
    )


@router.delete("/persons/{person_id}",
    summary="حذف شخص",
    description="حذف یک شخص",
    response_model=SuccessResponse,
    responses={
        200: {
            "description": "شخص با موفقیت حذف شد"
        },
        404: {
            "description": "شخص یافت نشد"
        }
    }
)
async def delete_person_endpoint(
    person_id: int,
    db: Session = Depends(get_db),
    auth_context: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_management())
):
    """حذف شخص"""
    # ابتدا باید business_id را از person دریافت کنیم
    person = db.query(Person).filter(Person.id == person_id).first()
    if not person:
        raise HTTPException(status_code=404, detail="شخص یافت نشد")
    
    success = delete_person(db, person_id, person.business_id)
    if not success:
        raise HTTPException(status_code=404, detail="شخص یافت نشد")
    
    return success_response(message="شخص با موفقیت حذف شد")


@router.get("/businesses/{business_id}/persons/summary",
    summary="خلاصه اشخاص کسب و کار",
    description="دریافت خلاصه آماری اشخاص یک کسب و کار",
    response_model=SuccessResponse,
    responses={
        200: {
            "description": "خلاصه اشخاص با موفقیت دریافت شد"
        }
    }
)
async def get_persons_summary_endpoint(
    business_id: int,
    db: Session = Depends(get_db),
    auth_context: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_management())
):
    """دریافت خلاصه اشخاص کسب و کار"""
    result = get_person_summary(db, business_id)
    
    return success_response(
        message="خلاصه اشخاص با موفقیت دریافت شد",
        data=result
    )
