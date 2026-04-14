from __future__ import annotations

import json
import logging
from typing import Dict, Any

from fastapi import APIRouter, Depends, Request, Body
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from adapters.db.models.person import PersonType
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.permissions import require_business_access_dep, require_business_permission_dep
from app.core.responses import success_response
from app.services.quick_sales_service import (
    get_quick_sales_settings,
    update_quick_sales_settings,
    get_or_create_anonymous_customer,
)

logger = logging.getLogger(__name__)


router = APIRouter(prefix="/businesses/{business_id}/quick-sales", tags=["quick-sales"])


@router.get(
    "/settings",
    summary="دریافت تنظیمات فروش سریع",
    description="دریافت تنظیمات فروش سریع یک کسب‌وکار شامل مشتری ناشناس، انبار، صندوق و سایر تنظیمات",
)
def get_quick_sales_settings_endpoint(
    request: Request,
    business_id: int,
    _: None = Depends(require_business_access_dep),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> dict:
    """دریافت تنظیمات فروش سریع"""
    data = get_quick_sales_settings(db, business_id)
    return success_response(data, request)


@router.put(
    "/settings",
    summary="ویرایش تنظیمات فروش سریع",
    description="به‌روزرسانی تنظیمات فروش سریع یک کسب‌وکار",
)
def update_quick_sales_settings_endpoint(
    request: Request,
    business_id: int,
    payload: Dict[str, Any] = Body(...),
    _: None = Depends(require_business_permission_dep("settings", "business")),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> dict:
    """به‌روزرسانی تنظیمات فروش سریع"""
    data = update_quick_sales_settings(db, business_id, payload, ctx.get_user_id())
    return success_response(data, request, message="QUICK_SALES_SETTINGS_UPDATED")


@router.get(
    "/anonymous-customer",
    summary="دریافت یا ایجاد مشتری ناشناس",
    description="دریافت مشتری ناشناس پیش‌فرض یا ایجاد آن در صورت عدم وجود",
)
def get_anonymous_customer_endpoint(
    request: Request,
    business_id: int,
    _: None = Depends(require_business_access_dep),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> dict:
    """دریافت یا ایجاد مشتری ناشناس"""
    try:
        customer = get_or_create_anonymous_customer(db, business_id)
        # بررسی اینکه آیا مشتری است یا نه
        person_types = []
        if customer.person_types:
            try:
                parsed_types = json.loads(customer.person_types)
                person_types = parsed_types if isinstance(parsed_types, list) else []
            except (json.JSONDecodeError, TypeError) as e:
                logger.warning(f"Failed to parse person_types for customer {customer.id}: {e}")
                person_types = []
        is_customer = PersonType.CUSTOMER.value in person_types
        return success_response({
            "id": customer.id,
            "name": customer.alias_name,
            "is_customer": is_customer,
        }, request)
    except Exception as e:
        logger.error(f"Error in get_anonymous_customer_endpoint for business {business_id}: {type(e).__name__}: {str(e)}", exc_info=True)
        raise

