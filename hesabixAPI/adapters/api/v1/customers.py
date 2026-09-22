from fastapi import APIRouter, Depends, Request, HTTPException
from sqlalchemy.orm import Session
from pydantic import BaseModel
from typing import Optional, List

from adapters.db.models.person import Person
from adapters.db.session import get_db
from app.core.responses import ApiError
from app.core.auth_dependency import get_current_user, AuthContext
from app.services.person_service import search_persons, count_persons, get_person_by_id
from app.services.customer_quick_entry_service import resolve_or_create_quick_customer

router = APIRouter(prefix="/customers", tags=["اشخاص و مشتریان"])


def _require_business_access(ctx: AuthContext, business_id: int) -> None:
    """business_id در body/query است؛ dependency مبتنی بر path اینجا کافی نیست."""
    if not ctx.can_access_business(int(business_id)):
        raise ApiError(
            "FORBIDDEN",
            f"No access to business {business_id}",
            http_status=403,
        )


class CustomerSearchRequest(BaseModel):
    business_id: int
    page: int = 1
    limit: int = 20
    search: Optional[str] = None


class CustomerResponse(BaseModel):
    id: int
    name: str
    code: Optional[str] = None
    phone: Optional[str] = None
    email: Optional[str] = None
    address: Optional[str] = None
    is_active: bool = True
    created_at: Optional[str] = None


class CustomerSearchResponse(BaseModel):
    customers: List[CustomerResponse]
    total: int
    page: int
    limit: int
    has_more: bool


class CustomerQuickResolveRequest(BaseModel):
    business_id: int
    alias_name: Optional[str] = None
    mobile: Optional[str] = None


class CustomerQuickResolveResponse(BaseModel):
    customers: List[CustomerResponse]
    created: bool


def _customer_response(person: Person) -> CustomerResponse:
    name_parts = [
        value
        for value in (person.alias_name, person.first_name, person.last_name)
        if value
    ]
    return CustomerResponse(
        id=person.id,
        name=" ".join(name_parts) if name_parts else "نامشخص",
        code=str(person.code) if person.code else None,
        phone=person.phone or person.mobile,
        email=person.email,
        address=person.address,
        is_active=True,
        created_at=person.created_at.isoformat() if person.created_at else None,
    )


@router.post(
    "/quick-resolve",
    summary="یافتن یا ایجاد سریع مشتری",
    description=(
        "مشتری موجود را با موبایل یا نام مشابه برمی‌گرداند و تنها در صورت "
        "نبود نتیجه، مشتری جدید ایجاد می‌کند"
    ),
    response_model=CustomerQuickResolveResponse,
)
async def quick_resolve_customer(
    request: Request,
    payload: CustomerQuickResolveRequest,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    _require_business_access(ctx, payload.business_id)
    resolution = resolve_or_create_quick_customer(
        db,
        business_id=payload.business_id,
        alias_name=payload.alias_name,
        mobile=payload.mobile,
    )
    return CustomerQuickResolveResponse(
        customers=[_customer_response(person) for person in resolution.persons],
        created=resolution.created,
    )


@router.post("/search", 
    summary="جست‌وجوی مشتری‌ها", 
    description="جست‌وجو در لیست مشتری‌ها (اشخاص) با قابلیت فیلتر و صفحه‌بندی",
    response_model=CustomerSearchResponse,
    responses={
        200: {
            "description": "لیست مشتری‌ها با موفقیت دریافت شد",
            "content": {
                "application/json": {
                    "example": {
                        "customers": [
                            {
                                "id": 1,
                                "name": "احمد احمدی",
                                "code": "CUST001",
                                "phone": "09123456789",
                                "email": "ahmad@example.com",
                                "address": "تهران، خیابان ولیعصر",
                                "is_active": True,
                                "created_at": "2024-01-01T00:00:00Z"
                            }
                        ],
                        "total": 1,
                        "page": 1,
                        "limit": 20,
                        "has_more": False
                    }
                }
            }
        },
        401: {
            "description": "کاربر احراز هویت نشده است"
        },
        403: {
            "description": "دسترسی غیرمجاز - نیاز به دسترسی به کسب و کار"
        }
    }
)
async def search_customers(
    request: Request,
    search_request: CustomerSearchRequest,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """جست‌وجو در لیست مشتری‌ها"""
    _require_business_access(ctx, search_request.business_id)

    # جست‌وجو در اشخاص
    persons = search_persons(
        db=db,
        business_id=search_request.business_id,
        search_query=search_request.search,
        page=search_request.page,
        limit=search_request.limit
    )
    
    customers = [_customer_response(person) for person in persons]
    
    # محاسبه تعداد کل
    total_count = count_persons(
        db=db,
        business_id=search_request.business_id,
        search_query=search_request.search
    )
    
    has_more = len(customers) == search_request.limit
    
    return CustomerSearchResponse(
        customers=customers,
        total=total_count,
        page=search_request.page,
        limit=search_request.limit,
        has_more=has_more
    )


@router.get("/detail/{customer_id}", 
    summary="دریافت اطلاعات مشتری", 
    description="دریافت اطلاعات کامل یک مشتری بر اساس شناسه",
    response_model=CustomerResponse,
    responses={
        200: {
            "description": "اطلاعات مشتری با موفقیت دریافت شد"
        },
        401: {
            "description": "کاربر احراز هویت نشده است"
        },
        403: {
            "description": "دسترسی غیرمجاز"
        },
        404: {
            "description": "مشتری یافت نشد"
        }
    }
)
async def get_customer(
    customer_id: int,
    business_id: int,
    request: Request,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """دریافت اطلاعات یک مشتری"""
    _require_business_access(ctx, business_id)

    # دریافت اطلاعات شخص
    person_data = get_person_by_id(db, customer_id, business_id)
    
    if not person_data:
        raise HTTPException(status_code=404, detail="مشتری یافت نشد")
    
    # ساخت نام کامل
    name_parts = []
    if person_data.get('alias_name'):
        name_parts.append(person_data['alias_name'])
    if person_data.get('first_name'):
        name_parts.append(person_data['first_name'])
    if person_data.get('last_name'):
        name_parts.append(person_data['last_name'])
    full_name = " ".join(name_parts) if name_parts else person_data.get('alias_name', 'نامشخص')
    
    customer = CustomerResponse(
        id=person_data['id'],
        name=full_name,
        code=str(person_data['code']) if person_data.get('code') else None,
        phone=person_data.get('phone') or person_data.get('mobile'),
        email=person_data.get('email'),
        address=person_data.get('address'),
        is_active=True,  # اشخاص همیشه فعال در نظر گرفته می‌شوند
        created_at=person_data.get('created_at')
    )
    
    return customer


@router.get("/check-access", 
    summary="بررسی دسترسی به مشتری‌ها", 
    description="بررسی دسترسی کاربر به بخش مشتری‌ها",
    responses={
        200: {
            "description": "دسترسی مجاز است"
        },
        401: {
            "description": "کاربر احراز هویت نشده است"
        },
        403: {
            "description": "دسترسی غیرمجاز"
        }
    }
)
async def check_customer_access(
    business_id: int,
    ctx: AuthContext = Depends(get_current_user),
):
    """بررسی دسترسی به بخش مشتری‌ها"""
    _require_business_access(ctx, business_id)
    return {"access": True, "message": "دسترسی مجاز است"}
