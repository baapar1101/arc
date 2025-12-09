from __future__ import annotations

from typing import Any, Dict, Optional
from fastapi import APIRouter, Depends, Request, Body, Header
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.permissions import require_business_access_dep, require_business_permission_dep
from app.core.warranty_plugin_dependency import require_warranty_plugin_active
from app.core.responses import success_response, format_datetime_fields
from app.services.warranty_service import (
    get_warranty_settings,
    update_warranty_settings,
    generate_warranty_codes,
    activate_warranty,
    track_warranty,
    track_warranty_by_link,
    list_warranty_codes,
    list_warranty_codes_by_person,
    delete_warranty_code,
    delete_warranty_codes_bulk,
)


router = APIRouter(prefix="/warranty", tags=["warranty"])


# ========== Settings Endpoints ==========

@router.get(
    "/business/{business_id}/settings",
    summary="دریافت تنظیمات گارانتی",
)
def get_settings_endpoint(
    request: Request,
    business_id: int,
    _: None = Depends(require_business_access_dep),
    __: None = Depends(require_warranty_plugin_active("business_id")),
    ___: None = Depends(require_business_permission_dep("warranty", "read")),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> dict:
    data = get_warranty_settings(db, business_id)
    formatted_data = format_datetime_fields(data, request)
    return success_response(formatted_data, request)


@router.put(
    "/business/{business_id}/settings",
    summary="به‌روزرسانی تنظیمات گارانتی",
)
def update_settings_endpoint(
    request: Request,
    business_id: int,
    payload: Dict[str, Any] = Body(...),
    _: None = Depends(require_business_access_dep),
    __: None = Depends(require_warranty_plugin_active("business_id")),
    ___: None = Depends(require_business_permission_dep("warranty", "manage")),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> dict:
    data = update_warranty_settings(db, business_id, payload)
    formatted_data = format_datetime_fields(data, request)
    return success_response(formatted_data, request)


# ========== Code Generation Endpoints ==========

@router.post(
    "/business/{business_id}/generate",
    summary="تولید انبوه کدهای گارانتی",
)
def generate_codes_endpoint(
    request: Request,
    business_id: int,
    payload: Dict[str, Any] = Body(...),
    _: None = Depends(require_business_access_dep),
    __: None = Depends(require_warranty_plugin_active("business_id")),
    ___: None = Depends(require_business_permission_dep("warranty", "write")),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> dict:
    result = generate_warranty_codes(
        db=db,
        business_id=business_id,
        product_id=payload.get("product_id"),
        quantity=payload.get("quantity", 1),
        warranty_duration_days=payload.get("warranty_duration_days", 365),
        user_id=ctx.get_user_id(),
        serial_format=payload.get("serial_format"),
        custom_serials=payload.get("custom_serials"),
        code_format=payload.get("code_format"),
        custom_codes=payload.get("custom_codes"),
    )
    formatted_data = format_datetime_fields(result, request)
    return success_response(formatted_data, request)


# ========== List Codes Endpoint ==========

@router.get(
    "/business/{business_id}/codes",
    summary="لیست کدهای گارانتی",
)
def list_codes_endpoint(
    request: Request,
    business_id: int,
    status: Optional[str] = None,
    product_id: Optional[int] = None,
    limit: int = 100,
    skip: int = 0,
    _: None = Depends(require_business_access_dep),
    __: None = Depends(require_warranty_plugin_active("business_id")),
    ___: None = Depends(require_business_permission_dep("warranty", "read")),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> dict:
    data = list_warranty_codes(db, business_id, status, product_id, limit, skip)
    formatted_data = format_datetime_fields(data, request)
    return success_response(formatted_data, request)


@router.get(
    "/business/{business_id}/codes/person/{person_id}",
    summary="لیست کدهای گارانتی یک Person",
)
def list_codes_by_person_endpoint(
    request: Request,
    business_id: int,
    person_id: int,
    status: Optional[str] = None,
    limit: int = 100,
    skip: int = 0,
    _: None = Depends(require_business_access_dep),
    __: None = Depends(require_warranty_plugin_active("business_id")),
    ___: None = Depends(require_business_permission_dep("warranty", "read")),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> dict:
    result = list_warranty_codes_by_person(
        db=db,
        business_id=business_id,
        person_id=person_id,
        status=status,
        limit=limit,
        skip=skip,
    )
    formatted_data = format_datetime_fields(result, request)
    return success_response(formatted_data, request)


# ========== Public Activation Endpoint ==========

@router.post(
    "/public/activate/{business_id}",
    summary="فعال‌سازی گارانتی (عمومی - بدون نیاز به احراز هویت)",
)
def activate_public_endpoint(
    request: Request,
    business_id: int,
    payload: Dict[str, Any] = Body(...),
    db: Session = Depends(get_db),
    x_forwarded_for: Optional[str] = Header(None),
    user_agent: Optional[str] = Header(None),
) -> dict:
    # استخراج IP از header
    ip_address = x_forwarded_for
    if ip_address and "," in ip_address:
        ip_address = ip_address.split(",")[0].strip()
    
    if not ip_address:
        ip_address = request.client.host if request.client else None
    
    result = activate_warranty(
        db=db,
        business_id=business_id,
        warranty_code_str=payload.get("warranty_code"),
        warranty_serial=payload.get("warranty_serial"),
        customer_name=payload.get("customer_name"),
        customer_phone=payload.get("customer_phone"),
        customer_email=payload.get("customer_email"),
        product_serial=payload.get("product_serial"),
        ip_address=ip_address,
        user_agent=user_agent,
    )
    formatted_data = format_datetime_fields(result, request)
    return success_response(formatted_data, request)


# ========== Public Tracking Endpoints ==========

@router.get(
    "/public/track/{code_or_serial}",
    summary="رهگیری گارانتی (عمومی)",
)
def track_public_endpoint(
    request: Request,
    code_or_serial: str,
    business_id: Optional[int] = None,
    db: Session = Depends(get_db),
) -> dict:
    data = track_warranty(db, code_or_serial, business_id)
    formatted_data = format_datetime_fields(data, request)
    return success_response(formatted_data, request)


@router.get(
    "/public/track/link/{link_code}",
    summary="رهگیری گارانتی از طریق لینک یکتا",
)
def track_by_link_endpoint(
    request: Request,
    link_code: str,
    db: Session = Depends(get_db),
) -> dict:
    data = track_warranty_by_link(db, link_code)
    formatted_data = format_datetime_fields(data, request)
    return success_response(formatted_data, request)


@router.get(
    "/public/business/{business_id}/info",
    summary="دریافت اطلاعات عمومی کسب و کار برای صفحه فعال‌سازی",
)
def get_business_public_info_endpoint(
    request: Request,
    business_id: int,
    db: Session = Depends(get_db),
) -> dict:
    from adapters.db.models.business import Business
    from app.core.responses import ApiError
    
    business = db.query(Business).filter(Business.id == business_id).first()
    
    if not business:
        raise ApiError("BUSINESS_NOT_FOUND", "کسب و کار یافت نشد", http_status=404)
    
    # تلاش برای دریافت logo_url از file_storage
    logo_url = None
    if business.logo_file_id:
        try:
            from adapters.db.models.file_storage import FileStorage
            logo_file = db.query(FileStorage).filter(FileStorage.id == business.logo_file_id).first()
            if logo_file:
                # استفاده از URL file storage
                logo_url = f"/api/v1/storage/files/{logo_file.id}/download"
        except Exception:
            pass
    
    data = {
        "id": business.id,
        "name": business.name,
        "logo_url": logo_url,
        "phone": business.phone,
        "mobile": business.mobile,
        "address": business.address,
        "business_type": business.business_type.value if business.business_type else None,
    }
    
    return success_response(data, request)


@router.get(
    "/public/check/{business_id}/{code}",
    summary="بررسی وضعیت کد گارانتی (عمومی)",
)
def check_warranty_endpoint(
    request: Request,
    business_id: int,
    code: str,
    db: Session = Depends(get_db),
) -> dict:
    from adapters.db.repositories.warranty_repository import WarrantyCodeRepository
    
    repo = WarrantyCodeRepository(db)
    warranty_code = repo.get_by_code(code, business_id)
    
    if not warranty_code:
        from app.core.responses import ApiError
        raise ApiError("WARRANTY_NOT_FOUND", "گارانتی در این کسب و کار یافت نشد", http_status=404)
    
    from adapters.db.models.product import Product
    from adapters.db.models.business import Business
    
    product = db.query(Product).filter(Product.id == warranty_code.product_id).first()
    business = db.query(Business).filter(Business.id == warranty_code.business_id).first()
    
    data = {
        "code": warranty_code.code,
        "status": warranty_code.status,
        "expires_at": warranty_code.expires_at,
        "product": {
            "id": product.id if product else None,
            "name": product.name if product else None,
        } if product else None,
        "business": {
            "id": business.id if business else None,
            "name": business.name if business else None,
        } if business else None,
    }
    
    formatted_data = format_datetime_fields(data, request)
    return success_response(formatted_data, request)


# ========== Delete Endpoints ==========

@router.delete(
    "/business/{business_id}/codes/{code_id}",
    summary="حذف یک کد گارانتی",
)
def delete_code_endpoint(
    request: Request,
    business_id: int,
    code_id: int,
    force: bool = False,
    _: None = Depends(require_business_access_dep),
    __: None = Depends(require_warranty_plugin_active("business_id")),
    ___: None = Depends(require_business_permission_dep("warranty", "delete")),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> dict:
    """حذف یک کد گارانتی به صورت ایمن
    
    Args:
        business_id: شناسه کسب و کار
        code_id: شناسه کد گارانتی
        force: حذف اجباری حتی اگر کد فعال شده باشد (پیش‌فرض: False)
    """
    result = delete_warranty_code(db, business_id, code_id, force)
    return success_response(result, request)


@router.post(
    "/business/{business_id}/codes/bulk-delete",
    summary="حذف گروهی کدهای گارانتی",
)
def delete_codes_bulk_endpoint(
    request: Request,
    business_id: int,
    payload: Dict[str, Any] = Body(...),
    _: None = Depends(require_business_access_dep),
    __: None = Depends(require_warranty_plugin_active("business_id")),
    ___: None = Depends(require_business_permission_dep("warranty", "delete")),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> dict:
    """حذف گروهی کدهای گارانتی به صورت ایمن
    
    Args:
        business_id: شناسه کسب و کار
        payload: شامل code_ids (لیست شناسه‌های کدها) و force (حذف اجباری)
    """
    code_ids = payload.get("code_ids", [])
    force = payload.get("force", False)
    
    if not isinstance(code_ids, list):
        from app.core.responses import ApiError
        raise ApiError("INVALID_INPUT", "code_ids باید یک آرایه باشد", http_status=400)
    
    result = delete_warranty_codes_bulk(db, business_id, code_ids, force)
    return success_response(result, request)

