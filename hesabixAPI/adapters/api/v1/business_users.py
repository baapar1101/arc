# Removed __future__ annotations to fix OpenAPI schema generation

from fastapi import APIRouter, Depends, Request, HTTPException
from sqlalchemy.orm import Session
import re

from adapters.db.session import get_db
from adapters.api.v1.schemas import (
    BusinessUsersListResponse, AddUserRequest, AddUserResponse,
    UpdatePermissionsRequest, UpdatePermissionsResponse, RemoveUserResponse,
    LeaveBusinessResponse
)
from app.core.responses import success_response, format_datetime_fields, ApiError
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.permissions import require_business_access, require_business_permission_dep
from adapters.db.repositories.business_permission_repo import BusinessPermissionRepository
from adapters.db.models.user import User
from adapters.db.models.business import Business
from sqlalchemy import select, and_, or_

router = APIRouter(prefix="/business", tags=["business-users"])


def _normalize_phone_for_search(phone: str) -> str | None:
    """نرمالایز کردن شماره تلفن برای جستجو - تبدیل فرمت‌های مختلف به فرمت E164"""
    if not phone:
        return None
    
    # حذف فاصله‌ها و کاراکترهای غیرعددی (به جز +)
    cleaned = re.sub(r'[^\d+]', '', phone.strip())
    
    # اگر از قبل فرمت E164 دارد (+989...)
    if cleaned.startswith('+989'):
        return cleaned
    
    # حذف + اگر در ابتدا باشد (برای پردازش)
    if cleaned.startswith('+'):
        cleaned = cleaned[1:]
    
    # تبدیل فرمت‌های مختلف به +989...
    if cleaned.startswith('00989') and len(cleaned) >= 13:
        # فرمت 00989...
        return f'+989{cleaned[5:]}'
    elif cleaned.startswith('989') and len(cleaned) >= 12:
        # فرمت 989... (بدون صفر)
        return f'+{cleaned}'
    elif cleaned.startswith('09') and len(cleaned) == 11:
        # فرمت 091... (فرمت رایج ایرانی)
        return f'+989{cleaned[2:]}'
    elif cleaned.startswith('9') and len(cleaned) == 10:
        # فرمت 9... (بدون صفر و کد کشور)
        return f'+989{cleaned}'
    
    # اگر فرمت شناخته شده نیست، همان را برگردان
    return phone


@router.get("/{business_id}/users/{user_id}", 
    summary="دریافت جزئیات کاربر", 
    description="دریافت جزئیات کاربر و دسترسی‌هایش در کسب و کار",
    responses={
        200: {
            "description": "جزئیات کاربر با موفقیت دریافت شد",
            "content": {
                "application/json": {
                    "example": {
                        "success": True,
                        "message": "جزئیات کاربر دریافت شد",
                        "user": {
                            "id": 1,
                            "business_id": 1,
                            "user_id": 2,
                            "user_name": "علی احمدی",
                            "user_email": "ali@example.com",
                            "user_phone": "09123456789",
                            "role": "member",
                            "status": "active",
                            "added_at": "2024-01-01T00:00:00Z",
                            "last_active": "2024-01-01T12:00:00Z",
                            "permissions": {
                                "people": {
                                    "add": True,
                                    "view": True,
                                    "edit": False,
                                    "delete": False
                                }
                            }
                        }
                    }
                }
            }
        },
        401: {
            "description": "کاربر احراز هویت نشده است"
        },
        403: {
            "description": "دسترسی غیرمجاز به کسب و کار"
        },
        404: {
            "description": "کاربر یافت نشد"
        }
    }
)
@require_business_access("business_id")
def get_user_details(
    request: Request,
    business_id: int,
    user_id: int,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    _: None = Depends(require_business_permission_dep("settings", "users")),
) -> dict:
    """دریافت جزئیات کاربر و دسترسی‌هایش"""
    import logging
    logger = logging.getLogger(__name__)
    
    current_user_id = ctx.get_user_id()
    logger.info(f"Getting user details for user {user_id} in business {business_id}, current user: {current_user_id}")
    
    # بررسی وجود کسب‌وکار
    business = db.get(Business, business_id)
    if not business:
        logger.error(f"Business {business_id} not found")
        raise HTTPException(status_code=404, detail="کسب و کار یافت نشد")
    
    # Get user details
    user = db.get(User, user_id)
    if not user:
        logger.warning(f"User {user_id} not found")
        raise HTTPException(status_code=404, detail="کاربر یافت نشد")
    
    # Get user permissions for this business
    permission_repo = BusinessPermissionRepository(db)
    permission_obj = permission_repo.get_by_user_and_business(user_id, business_id)
    
    # Determine role and permissions
    if business.owner_id == user_id:
        role = "owner"
        permissions = {}  # Owner has all permissions
    else:
        role = "member"
        permissions = permission_obj.business_permissions if permission_obj else {}
    
    # Format user data
    user_data = {
        "id": permission_obj.id if permission_obj else user_id,
        "business_id": business_id,
        "user_id": user_id,
        "user_name": f"{user.first_name or ''} {user.last_name or ''}".strip(),
        "user_email": user.email or "",
        "user_phone": user.mobile,
        "role": role,
        "status": "active",
        "added_at": permission_obj.created_at if permission_obj else business.created_at,
        "last_active": permission_obj.updated_at if permission_obj else business.updated_at,
        "permissions": permissions,
    }
    
    logger.info(f"Returning user data: {user_data}")
    
    # Format datetime fields based on calendar type
    formatted_user_data = format_datetime_fields(user_data, request)
    
    return success_response(
        data={"user": formatted_user_data},
        request=request,
        message="جزئیات کاربر دریافت شد"
    )


@router.get("/{business_id}/users", 
    summary="لیست کاربران کسب و کار", 
    description="دریافت لیست کاربران یک کسب و کار",
    response_model=BusinessUsersListResponse,
    responses={
        200: {
            "description": "لیست کاربران با موفقیت دریافت شد",
            "content": {
                "application/json": {
                    "example": {
                        "success": True,
                        "message": "لیست کاربران دریافت شد",
                        "users": [
                            {
                                "id": 1,
                                "business_id": 1,
                                "user_id": 2,
                                "user_name": "علی احمدی",
                                "user_email": "ali@example.com",
                                "user_phone": "09123456789",
                                "role": "member",
                                "status": "active",
                                "added_at": "2024-01-01T00:00:00Z",
                                "last_active": "2024-01-01T12:00:00Z",
                                "permissions": {
                                    "sales": {
                                        "read": True,
                                        "write": True,
                                        "delete": False
                                    },
                                    "reports": {
                                        "read": True,
                                        "export": True
                                    }
                                }
                            }
                        ],
                        "total_count": 1
                    }
                }
            }
        },
        401: {
            "description": "کاربر احراز هویت نشده است"
        },
        403: {
            "description": "دسترسی غیرمجاز به کسب و کار"
        }
    }
)
@require_business_access("business_id")
def get_users(
    request: Request,
    business_id: int,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    _: None = Depends(require_business_permission_dep("settings", "users")),
) -> dict:
    """دریافت لیست کاربران کسب و کار"""
    import logging
    logger = logging.getLogger(__name__)
    
    current_user_id = ctx.get_user_id()
    logger.info(f"Getting users for business {business_id}, current user: {current_user_id}")
    
    # بررسی وجود کسب‌وکار
    business = db.get(Business, business_id)
    if not business:
        logger.error(f"Business {business_id} not found")
        raise HTTPException(status_code=404, detail="کسب و کار یافت نشد")
    
    # Get business permissions for this business
    permission_repo = BusinessPermissionRepository(db)
    business_permissions = permission_repo.get_business_users(business_id)
    logger.info(f"Found {len(business_permissions)} business permissions for business {business_id}")
    
    # Format users data
    formatted_users = []
    
    # Add business owner first
    owner = db.get(User, business.owner_id)
    if owner:
        logger.info(f"Adding business owner: {owner.id} - {owner.email}")
        owner_data = {
            "id": business.owner_id,  # Use owner_id as id
            "business_id": business_id,
            "user_id": business.owner_id,
            "user_name": f"{owner.first_name or ''} {owner.last_name or ''}".strip(),
            "user_email": owner.email or "",
            "user_phone": owner.mobile,
            "role": "owner",
            "status": "active",
            "added_at": business.created_at,
            "last_active": business.updated_at,
            "permissions": {},  # Owner has all permissions
        }
        formatted_users.append(owner_data)
    else:
        logger.warning(f"Business owner {business.owner_id} not found in users table")
    
    # Add other users with permissions
    for perm in business_permissions:
        # Skip if this is the owner (already added)
        if perm.user_id == business.owner_id:
            logger.info(f"Skipping owner user {perm.user_id} as already added")
            continue
            
        user = db.get(User, perm.user_id)
        if user:
            logger.info(f"Adding user with permissions: {user.id} - {user.email}")
            user_data = {
                "id": perm.id,
                "business_id": perm.business_id,
                "user_id": perm.user_id,
                "user_name": f"{user.first_name or ''} {user.last_name or ''}".strip(),
                "user_email": user.email or "",
                "user_phone": user.mobile,
                "role": "member",
                "status": "active",
                "added_at": perm.created_at,
                "last_active": perm.updated_at,
                "permissions": perm.business_permissions or {},
            }
            formatted_users.append(user_data)
        else:
            logger.warning(f"User {perm.user_id} not found in users table")
    
    logger.info(f"Returning {len(formatted_users)} users for business {business_id}")
    
    # Format datetime fields based on calendar type
    formatted_users = format_datetime_fields(formatted_users, request)
    
    return success_response(
        data={
            "users": formatted_users,
            "total_count": len(formatted_users)
        },
        request=request,
        message="لیست کاربران دریافت شد"
    )


@router.post("/{business_id}/users", 
    summary="افزودن کاربر به کسب و کار", 
    description="افزودن کاربر جدید به کسب و کار با ایمیل یا شماره تلفن",
    response_model=AddUserResponse,
    responses={
        200: {
            "description": "کاربر با موفقیت اضافه شد",
            "content": {
                "application/json": {
                    "example": {
                        "success": True,
                        "message": "کاربر با موفقیت اضافه شد",
                        "user": {
                            "id": 1,
                            "business_id": 1,
                            "user_id": 2,
                            "user_name": "علی احمدی",
                            "user_email": "ali@example.com",
                            "user_phone": "09123456789",
                            "role": "member",
                            "status": "active",
                            "added_at": "2024-01-01T00:00:00Z",
                            "last_active": None,
                            "permissions": {}
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
            "description": "دسترسی غیرمجاز یا مجوز کافی نیست"
        },
        404: {
            "description": "کاربر یافت نشد"
        }
    }
)
@require_business_access("business_id")
def add_user(
    request: Request,
    business_id: int,
    add_request: AddUserRequest,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    _: None = Depends(require_business_permission_dep("settings", "users")),
) -> dict:
    """افزودن کاربر به کسب و کار"""
    import logging
    logger = logging.getLogger(__name__)
    
    current_user_id = ctx.get_user_id()
    logger.info(f"Adding user to business {business_id}, current user: {current_user_id}")
    logger.info(f"Add request: {add_request.email_or_phone}")
    
    # بررسی وجود کسب‌وکار
    business = db.get(Business, business_id)
    if not business:
        logger.error(f"Business {business_id} not found")
        raise ApiError("BUSINESS_NOT_FOUND", "کسب و کار یافت نشد", http_status=404)
    
    # Find user by email or phone
    logger.info(f"Searching for user with email/phone: {add_request.email_or_phone}")
    
    # Check if input is a phone number (not email)
    is_phone = '@' not in add_request.email_or_phone
    
    # Normalize phone number if it's a phone number
    search_queries = [add_request.email_or_phone]
    if is_phone:
        normalized_phone = _normalize_phone_for_search(add_request.email_or_phone)
        if normalized_phone and normalized_phone != add_request.email_or_phone:
            search_queries.append(normalized_phone)
            logger.info(f"Normalized phone: {normalized_phone}")
    
    # Search for user with original or normalized phone/email
    user = None
    for query in search_queries:
        user = db.query(User).filter(
            (User.email == query) | 
            (User.mobile == query)
        ).first()
        if user:
            logger.info(f"Found user with query: {query}")
            break
    
    if not user:
        logger.warning(f"User not found with email/phone: {add_request.email_or_phone}")
        raise ApiError("USER_NOT_FOUND", "کاربر یافت نشد. لطفاً ابتدا کاربر را در سیستم ثبت‌نام کنید.", http_status=404)
    
    logger.info(f"Found user: {user.id} - {user.email}")
    
    # Check if user is already added to this business
    permission_repo = BusinessPermissionRepository(db)
    existing_permission = permission_repo.get_by_user_and_business(user.id, business_id)
    
    if existing_permission:
        logger.warning(f"User {user.id} already exists in business {business_id}")
        raise ApiError("USER_ALREADY_ADDED", "کاربر قبلاً به این کسب و کار اضافه شده است", http_status=400)
    
    # Add user to business with default permissions
    logger.info(f"Adding user {user.id} to business {business_id}")
    permission_obj = permission_repo.create_or_update(
        user_id=user.id,
        business_id=business_id,
        permissions={'join': True}  # Default permissions with join access
    )
    
    logger.info(f"Created permission object: {permission_obj.id}")
    
    # Format user data
    user_data = {
        "id": permission_obj.id,
        "business_id": permission_obj.business_id,
        "user_id": permission_obj.user_id,
        "user_name": f"{user.first_name or ''} {user.last_name or ''}".strip(),
        "user_email": user.email or "",
        "user_phone": user.mobile,
        "role": "member",
        "status": "active",
        "added_at": permission_obj.created_at,
        "last_active": None,
        "permissions": permission_obj.business_permissions or {},
    }
    
    logger.info(f"Returning user data: {user_data}")
    
    # Format datetime fields based on calendar type
    formatted_user_data = format_datetime_fields(user_data, request)
    
    return success_response(
        data={"user": formatted_user_data},
        request=request,
        message="کاربر با موفقیت اضافه شد"
    )


@router.put("/{business_id}/users/{user_id}/permissions", 
    summary="به‌روزرسانی دسترسی‌های کاربر", 
    description="به‌روزرسانی دسترسی‌های یک کاربر در کسب و کار",
    response_model=UpdatePermissionsResponse,
    responses={
        200: {
            "description": "دسترسی‌ها با موفقیت به‌روزرسانی شد",
            "content": {
                "application/json": {
                    "example": {
                        "success": True,
                        "message": "دسترسی‌ها با موفقیت به‌روزرسانی شد"
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
            "description": "دسترسی غیرمجاز یا مجوز کافی نیست"
        },
        404: {
            "description": "کاربر یافت نشد"
        }
    }
)
@require_business_access("business_id")
def update_permissions(
    request: Request,
    business_id: int,
    user_id: int,
    update_request: UpdatePermissionsRequest,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    _: None = Depends(require_business_permission_dep("settings", "users")),
) -> dict:
    """به‌روزرسانی دسترسی‌های کاربر"""
    current_user_id = ctx.get_user_id()
    
    # بررسی وجود کسب‌وکار
    business = db.get(Business, business_id)
    if not business:
        raise HTTPException(status_code=404, detail="کسب و کار یافت نشد")
    
    # Check if target user exists
    target_user = db.get(User, user_id)
    if not target_user:
        raise HTTPException(status_code=404, detail="کاربر یافت نشد")
    
    # Update permissions
    permission_repo = BusinessPermissionRepository(db)
    permission_obj = permission_repo.create_or_update(
        user_id=user_id,
        business_id=business_id,
        permissions=update_request.permissions
    )
    
    return success_response(
        data={},
        request=request,
        message="دسترسی‌ها با موفقیت به‌روزرسانی شد"
    )


@router.delete("/{business_id}/users/{user_id}", 
    summary="حذف کاربر از کسب و کار", 
    description="حذف کاربر از کسب و کار",
    response_model=RemoveUserResponse,
    responses={
        200: {
            "description": "کاربر با موفقیت حذف شد",
            "content": {
                "application/json": {
                    "example": {
                        "success": True,
                        "message": "کاربر با موفقیت حذف شد"
                    }
                }
            }
        },
        401: {
            "description": "کاربر احراز هویت نشده است"
        },
        403: {
            "description": "دسترسی غیرمجاز یا مجوز کافی نیست"
        },
        404: {
            "description": "کاربر یافت نشد"
        }
    }
)
@require_business_access("business_id")
def remove_user(
    request: Request,
    business_id: int,
    user_id: int,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    _: None = Depends(require_business_permission_dep("settings", "users")),
) -> dict:
    """حذف کاربر از کسب و کار"""
    current_user_id = ctx.get_user_id()
    
    # بررسی وجود کسب‌وکار
    business = db.get(Business, business_id)
    if not business:
        raise HTTPException(status_code=404, detail="کسب و کار یافت نشد")
    
    # Check if target user is business owner
    if business and business.owner_id == user_id:
        raise HTTPException(status_code=400, detail="نمی‌توان مالک کسب و کار را حذف کرد")
    
    # Remove user permissions
    permission_repo = BusinessPermissionRepository(db)
    success = permission_repo.delete_by_user_and_business(user_id, business_id)
    
    if not success:
        raise HTTPException(status_code=404, detail="کاربر یافت نشد")
    
    return success_response(
        data={},
        request=request,
        message="کاربر با موفقیت حذف شد"
    )


@router.delete("/{business_id}/leave", 
    summary="خروج از کسب و کار", 
    description="خروج خودکار کاربر از کسب و کار (فقط برای اعضای غیر از مالک)",
    response_model=LeaveBusinessResponse,
    responses={
        200: {
            "description": "کاربر با موفقیت از کسب و کار خارج شد",
            "content": {
                "application/json": {
                    "example": {
                        "success": True,
                        "message": "شما با موفقیت از کسب و کار خارج شدید"
                    }
                }
            }
        },
        400: {
            "description": "خطا: کاربر مالک کسب و کار است یا عضو نیست"
        },
        401: {
            "description": "کاربر احراز هویت نشده است"
        },
        403: {
            "description": "دسترسی غیرمجاز"
        },
        404: {
            "description": "کسب و کار یافت نشد"
        }
    }
)
@require_business_access("business_id")
def leave_business(
    request: Request,
    business_id: int,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    """خروج خودکار کاربر از کسب و کار"""
    import logging
    logger = logging.getLogger(__name__)
    
    current_user_id = ctx.get_user_id()
    logger.info(f"User {current_user_id} attempting to leave business {business_id}")
    
    # بررسی وجود کسب‌وکار
    business = db.get(Business, business_id)
    if not business:
        logger.error(f"Business {business_id} not found")
        raise HTTPException(status_code=404, detail="کسب و کار یافت نشد")
    
    # بررسی اینکه کاربر مالک کسب و کار نباشد
    if business.owner_id == current_user_id:
        logger.warning(f"User {current_user_id} is business owner, cannot leave")
        raise HTTPException(
            status_code=400, 
            detail="مالک کسب و کار نمی‌تواند از کسب و کار خارج شود. برای حذف کسب و کار از بخش تنظیمات استفاده کنید."
        )
    
    # بررسی اینکه کاربر عضو کسب و کار باشد
    permission_repo = BusinessPermissionRepository(db)
    permission_obj = permission_repo.get_by_user_and_business(current_user_id, business_id)
    
    if not permission_obj:
        logger.warning(f"User {current_user_id} is not a member of business {business_id}")
        raise HTTPException(
            status_code=400, 
            detail="شما عضو این کسب و کار نیستید"
        )
    
    # حذف دسترسی‌های کاربر
    logger.info(f"Removing user {current_user_id} from business {business_id}")
    success = permission_repo.delete_by_user_and_business(current_user_id, business_id)
    
    if not success:
        logger.error(f"Failed to remove user {current_user_id} from business {business_id}")
        raise HTTPException(
            status_code=500, 
            detail="خطا در خروج از کسب و کار"
        )
    
    logger.info(f"User {current_user_id} successfully left business {business_id}")
    return success_response(
        data={},
        request=request,
        message="شما با موفقیت از کسب و کار خارج شدید"
    )


@router.get("/{business_id}/users/telegram-connected",
    summary="لیست کاربران متصل به تلگرام",
    description="دریافت لیست کاربران عضو کسب و کار که به ربات تلگرام متصل هستند",
    responses={
        200: {
            "description": "لیست کاربران متصل به تلگرام",
        },
        401: {
            "description": "کاربر احراز هویت نشده است"
        },
        403: {
            "description": "دسترسی غیرمجاز به کسب و کار"
        }
    }
)
@require_business_access("business_id")
def get_telegram_connected_users(
    request: Request,
    business_id: int,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    """دریافت لیست کاربران عضو کسب و کار که به ربات تلگرام متصل هستند"""
    import logging
    logger = logging.getLogger(__name__)
    
    current_user_id = ctx.get_user_id()
    logger.info(f"Getting telegram-connected users for business {business_id}, current user: {current_user_id}")
    
    # بررسی وجود کسب‌وکار
    business = db.get(Business, business_id)
    if not business:
        logger.error(f"Business {business_id} not found")
        raise HTTPException(status_code=404, detail="کسب و کار یافت نشد")
    
    # دریافت لیست کاربران عضو کسب و کار
    permission_repo = BusinessPermissionRepository(db)
    business_permissions = permission_repo.get_business_users(business_id)
    
    # جمع‌آوری user_id های عضو کسب و کار (شامل owner)
    user_ids = {business.owner_id}
    for perm in business_permissions:
        if perm.user_id:
            user_ids.add(perm.user_id)
    
    # دریافت کاربرانی که telegram_chat_id دارند
    stmt = select(User).where(
        and_(
            User.id.in_(list(user_ids)),
            User.telegram_chat_id.isnot(None)
        )
    )
    connected_users = db.execute(stmt).scalars().all()
    
    # فرمت کردن داده‌ها
    formatted_users = []
    for user in connected_users:
        # تعیین نقش کاربر
        role = "owner" if user.id == business.owner_id else "member"
        
        user_data = {
            "user_id": user.id,
            "name": f"{user.first_name or ''} {user.last_name or ''}".strip() or user.email or "کاربر",
            "email": user.email or "",
            "mobile": user.mobile or "",
            "telegram_chat_id": user.telegram_chat_id,
            "role": role,
        }
        formatted_users.append(user_data)
    
    logger.info(f"Found {len(formatted_users)} telegram-connected users for business {business_id}")
    
    return success_response(
        data={
            "users": formatted_users,
            "total": len(formatted_users)
        },
        request=request,
        message="لیست کاربران متصل به تلگرام دریافت شد"
    )
