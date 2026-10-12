from __future__ import annotations

import json
from datetime import date, datetime
import logging
from typing import Dict, Any

from fastapi import APIRouter, Depends, Request, Body
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from adapters.db.models.person import PersonType
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.permissions import (
    has_business_permission_for_business,
    require_business_access_dep,
    require_business_permission_dep,
)
from app.core.responses import ApiError, success_response
from app.services.quick_sales_service import (
    get_quick_sales_settings,
    update_quick_sales_settings,
    get_or_create_anonymous_customer,
)

logger = logging.getLogger(__name__)


router = APIRouter(prefix="/businesses/{business_id}/quick-sales", tags=["quick-sales"])


def _can(ctx: AuthContext, db: Session, business_id: int, section: str, action: str) -> bool:
    return has_business_permission_for_business(ctx, db, business_id, section, action)


def _body_date(value: Any) -> date:
    try:
        return datetime.fromisoformat(str(value)).date()
    except Exception as exc:
        raise ApiError("INVALID_DATE", "تاریخ اصلاح موجودی نامعتبر است", http_status=400) from exc


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


@router.get("/stock-discrepancies", summary="فهرست مغایرت‌های موجودی فروش سریع")
def list_stock_discrepancies_endpoint(
    request: Request,
    business_id: int,
    status: str | None = None,
    _: None = Depends(require_business_access_dep),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> dict:
    if not _can(ctx, db, business_id, "inventory", "view"):
        raise ApiError("FORBIDDEN", "دسترسی مشاهده موجودی را ندارید", http_status=403)
    from app.services.inventory_discrepancy_service import list_cases

    return success_response(list_cases(db, business_id, status), request)


@router.post("/stock-corrections", summary="اصلاح کسری پیش از ثبت فروش سریع")
def create_stock_correction_endpoint(
    request: Request,
    business_id: int,
    payload: Dict[str, Any] = Body(...),
    _: None = Depends(require_business_access_dep),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> dict:
    if payload.get("confirm_unexplained_physical_surplus") is not True:
        raise ApiError(
            "PHYSICAL_SURPLUS_CONFIRMATION_REQUIRED",
            "باید تأیید کنید که کالا واقعاً موجود است و منشأ ثبت‌نشده دیگری ندارد",
            http_status=400,
        )
    if not _can(ctx, db, business_id, "goods_expense_income", "add"):
        raise ApiError("FORBIDDEN", "مجوز ایجاد کالای درآمدشده را ندارید", http_status=403)
    from app.services.inventory_discrepancy_service import create_goods_income_correction

    result = create_goods_income_correction(
        db,
        business_id=business_id,
        user_id=ctx.get_user_id(),
        document_date=_body_date(payload.get("document_date")),
        lines=list(payload.get("lines") or []),
        description=str(payload.get("description") or "اصلاح کسری کشف‌شده در فروش سریع"),
        user_can_allocate=_can(ctx, db, business_id, "goods_expense_income", "allocate"),
        user_can_post=_can(ctx, db, business_id, "goods_expense_income", "post"),
        user_can_change_unit_cost=_can(ctx, db, business_id, "goods_expense_income", "change_unit_cost"),
    )
    db.commit()
    return success_response(result, request, message="QUICK_SALES_STOCK_CORRECTED")


@router.post("/stock-discrepancies/{case_id}/resolve", summary="رفع مغایرت با کالای درآمدشده")
def resolve_stock_discrepancy_endpoint(
    request: Request,
    business_id: int,
    case_id: int,
    payload: Dict[str, Any] = Body(...),
    _: None = Depends(require_business_access_dep),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> dict:
    if not _can(ctx, db, business_id, "goods_expense_income", "add"):
        raise ApiError("FORBIDDEN", "مجوز ایجاد کالای درآمدشده را ندارید", http_status=403)
    from app.services.inventory_discrepancy_service import resolve_case_with_goods_income

    result = resolve_case_with_goods_income(
        db,
        business_id=business_id,
        case_id=case_id,
        user_id=ctx.get_user_id(),
        lines=list(payload.get("lines") or []),
        document_date=_body_date(payload.get("document_date")),
        user_can_allocate=_can(ctx, db, business_id, "goods_expense_income", "allocate"),
        user_can_post=_can(ctx, db, business_id, "goods_expense_income", "post"),
        user_can_change_unit_cost=_can(ctx, db, business_id, "goods_expense_income", "change_unit_cost"),
    )
    return success_response(result, request, message="INVENTORY_DISCREPANCY_RESOLVED")
