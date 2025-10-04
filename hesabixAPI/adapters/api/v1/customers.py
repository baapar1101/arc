from fastapi import APIRouter, Depends, Request, HTTPException
from sqlalchemy.orm import Session
from pydantic import BaseModel
from typing import Optional, List

from adapters.db.session import get_db
from app.core.responses import success_response, format_datetime_fields
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.permissions import require_business_access_dep
from app.services.person_service import search_persons, count_persons, get_person_by_id

router = APIRouter(prefix="/customers", tags=["customers"])


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
    _: None = Depends(require_business_access_dep)
):
    """جست‌وجو در لیست مشتری‌ها"""
    
    # بررسی دسترسی به بخش اشخاص (یا join permission)
    # در اینجا می‌توانید منطق بررسی دسترسی join را پیاده‌سازی کنید
    # برای مثال: اگر کاربر دسترسی مستقیم به اشخاص ندارد، اما دسترسی join دارد
    
    # جست‌وجو در اشخاص
    persons = search_persons(
        db=db,
        business_id=search_request.business_id,
        search_query=search_request.search,
        page=search_request.page,
        limit=search_request.limit
    )
    
    # تبدیل به فرمت مشتری
    customers = []
    for person in persons:
        # ساخت نام کامل
        name_parts = []
        if person.alias_name:
            name_parts.append(person.alias_name)
        if person.first_name:
            name_parts.append(person.first_name)
        if person.last_name:
            name_parts.append(person.last_name)
        full_name = " ".join(name_parts) if name_parts else person.alias_name or "نامشخص"
        
        customer = CustomerResponse(
            id=person.id,
            name=full_name,
            code=str(person.code) if person.code else None,
            phone=person.phone or person.mobile,
            email=person.email,
            address=person.address,
            is_active=True,  # اشخاص همیشه فعال در نظر گرفته می‌شوند
            created_at=person.created_at.isoformat() if person.created_at else None
        )
        customers.append(customer)
    
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
    _: None = Depends(require_business_access_dep)
):
    """دریافت اطلاعات یک مشتری"""
    
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
    _: None = Depends(require_business_access_dep)
):
    """بررسی دسترسی به بخش مشتری‌ها"""
    
    # در اینجا می‌توانید منطق بررسی دسترسی join را پیاده‌سازی کنید
    # برای مثال: بررسی اینکه آیا کاربر دسترسی به اشخاص یا join permission دارد
    
    return {"access": True, "message": "دسترسی مجاز است"}
