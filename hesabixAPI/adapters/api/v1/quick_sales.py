from __future__ import annotations

import json
import logging
from datetime import date, datetime
from typing import Any, Dict

from fastapi import APIRouter, Body, Depends, Request
from sqlalchemy.orm import Session

from adapters.db.models.person import PersonType
from adapters.db.session import get_db
from app.core.auth_dependency import AuthContext, get_current_user
from app.core.permissions import (
    has_business_permission_for_business,
    require_business_access_dep,
    require_business_permission_dep,
)
from app.core.responses import ApiError, success_response
from app.services.quick_sales_service import (
    create_quick_sales_payment_button,
    delete_quick_sales_payment_button,
    get_configured_anonymous_customer,
    get_or_create_anonymous_customer,
    get_quick_sales_customer_balance,
    get_quick_sales_settings,
    list_quick_sales_payment_default_shortcuts,
    list_quick_sales_payment_buttons,
    reorder_quick_sales_payment_buttons,
    set_quick_sales_payment_default_shortcuts,
    set_quick_sales_payment_button_shortcut,
    set_quick_sales_payment_button_shortcuts,
    update_quick_sales_payment_button,
    update_quick_sales_settings,
)

logger = logging.getLogger(__name__)


router = APIRouter(prefix="/businesses/{business_id}/quick-sales", tags=["quick-sales"])


def _anonymous_customer_data(customer) -> dict:
    person_types = []
    if customer.person_types:
        try:
            parsed_types = json.loads(customer.person_types)
            person_types = parsed_types if isinstance(parsed_types, list) else []
        except (json.JSONDecodeError, TypeError) as exc:
            logger.warning(
                "Failed to parse person_types for customer %s: %s",
                customer.id,
                exc,
            )
    return {
        "id": customer.id,
        "name": customer.alias_name,
        "is_customer": PersonType.CUSTOMER.value in person_types,
    }


def _can(ctx: AuthContext, db: Session, business_id: int, section: str, action: str) -> bool:
    return has_business_permission_for_business(ctx, db, business_id, section, action)


def _body_date(value: Any) -> date:
    try:
        return datetime.fromisoformat(str(value)).date()
    except Exception as exc:
        raise ApiError("INVALID_DATE", "تاریخ اصلاح موجودی نامعتبر است", http_status=400) from exc


@router.get("/customer-balance", summary="مانده مشتری در فروش سریع")
def get_customer_balance_endpoint(
    request: Request,
    business_id: int,
    person_id: int,
    currency_id: int,
    as_of_date: date,
    _: None = Depends(
        require_business_permission_dep("quick_sales", "view_customer_balance")
    ),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> dict:
    data = get_quick_sales_customer_balance(
        db,
        business_id=business_id,
        person_id=person_id,
        currency_id=currency_id,
        as_of_date=as_of_date,
    )
    return success_response(data, request)


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
    summary="دریافت مشتری ناشناس تنظیم‌شده",
)
def read_anonymous_customer_endpoint(
    request: Request,
    business_id: int,
    _: None = Depends(require_business_permission_dep("invoices", "add")),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> dict:
    customer = get_configured_anonymous_customer(db, business_id)
    return success_response(_anonymous_customer_data(customer), request)


@router.post(
    "/anonymous-customer",
    summary="دریافت یا ایجاد مشتری ناشناس",
    description="دریافت مشتری ناشناس پیش‌فرض یا ایجاد آن در صورت عدم وجود",
)
def get_anonymous_customer_endpoint(
    request: Request,
    business_id: int,
    _: None = Depends(require_business_permission_dep("invoices", "add")),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> dict:
    """دریافت یا ایجاد مشتری ناشناس"""
    try:
        customer = get_or_create_anonymous_customer(db, business_id)
        return success_response(_anonymous_customer_data(customer), request)
    except Exception as e:
        logger.error(f"Error in get_anonymous_customer_endpoint for business {business_id}: {type(e).__name__}: {str(e)}", exc_info=True)
        raise


@router.get("/payment-buttons", summary="دکمه‌های پرداخت فروش سریع")
def list_payment_buttons_endpoint(
    request: Request,
    business_id: int,
    _: None = Depends(require_business_permission_dep("invoices", "add")),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> dict:
    data = list_quick_sales_payment_buttons(db, business_id, ctx.get_user_id())
    return success_response(data, request)


@router.post("/payment-buttons", summary="ایجاد دکمه پرداخت فروش سریع")
def create_payment_button_endpoint(
    request: Request,
    business_id: int,
    payload: Dict[str, Any] = Body(...),
    _: None = Depends(require_business_permission_dep("invoices", "add")),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> dict:
    data = create_quick_sales_payment_button(
        db,
        business_id=business_id,
        user_id=ctx.get_user_id(),
        payload=payload,
        can_manage_business=_can(ctx, db, business_id, "settings", "business"),
    )
    return success_response(data, request, message="QUICK_SALES_PAYMENT_BUTTON_CREATED")


@router.put("/payment-buttons/reorder", summary="تغییر ترتیب دکمه‌های پرداخت فروش سریع")
def reorder_payment_buttons_endpoint(
    request: Request,
    business_id: int,
    payload: Dict[str, Any] = Body(...),
    _: None = Depends(require_business_permission_dep("invoices", "add")),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> dict:
    data = reorder_quick_sales_payment_buttons(
        db,
        business_id=business_id,
        user_id=ctx.get_user_id(),
        button_ids=list(payload.get("button_ids") or []),
        can_manage_business=_can(ctx, db, business_id, "settings", "business"),
    )
    return success_response(data, request, message="QUICK_SALES_PAYMENT_BUTTONS_REORDERED")


@router.put(
    "/payment-buttons/{button_key}/shortcut",
    summary="تنظیم میانبر دکمه پرداخت برای کاربر جاری",
)
def update_payment_button_shortcut_endpoint(
    request: Request,
    business_id: int,
    button_key: str,
    payload: Dict[str, Any] = Body(...),
    _: None = Depends(require_business_permission_dep("invoices", "add")),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> dict:
    if "platforms" in payload:
        data = set_quick_sales_payment_button_shortcuts(
            db,
            business_id=business_id,
            user_id=ctx.get_user_id(),
            button_key=button_key,
            platforms=payload.get("platforms"),
        )
    else:
        data = set_quick_sales_payment_button_shortcut(
            db,
            business_id=business_id,
            user_id=ctx.get_user_id(),
            button_key=button_key,
            shortcut=payload.get("shortcut"),
            mode=payload.get("mode"),
            platform=str(payload.get("platform") or "windows").strip().lower(),
        )
    return success_response(data, request, message="QUICK_SALES_PAYMENT_SHORTCUT_UPDATED")


@router.get(
    "/payment-buttons/default-shortcuts",
    summary="فهرست میانبرهای پیش‌فرض دکمه‌های مشترک فروش سریع",
)
def list_payment_button_default_shortcuts_endpoint(
    request: Request,
    business_id: int,
    _: None = Depends(
        require_business_permission_dep(
            "quick_sales", "manage_default_payment_shortcuts"
        )
    ),
    db: Session = Depends(get_db),
) -> dict:
    data = list_quick_sales_payment_default_shortcuts(db, business_id)
    return success_response(data, request)


@router.put(
    "/payment-buttons/default-shortcuts",
    summary="ذخیره یکجای میانبرهای پیش‌فرض دکمه‌های مشترک فروش سریع",
)
def update_payment_button_default_shortcuts_endpoint(
    request: Request,
    business_id: int,
    payload: Dict[str, Any] = Body(...),
    _: None = Depends(
        require_business_permission_dep(
            "quick_sales", "manage_default_payment_shortcuts"
        )
    ),
    db: Session = Depends(get_db),
) -> dict:
    data = set_quick_sales_payment_default_shortcuts(
        db,
        business_id=business_id,
        items=payload.get("shortcuts"),
    )
    return success_response(
        data,
        request,
        message="QUICK_SALES_DEFAULT_PAYMENT_SHORTCUTS_UPDATED",
    )


@router.put("/payment-buttons/{button_id}", summary="ویرایش دکمه پرداخت فروش سریع")
def update_payment_button_endpoint(
    request: Request,
    business_id: int,
    button_id: int,
    payload: Dict[str, Any] = Body(...),
    _: None = Depends(require_business_permission_dep("invoices", "add")),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> dict:
    data = update_quick_sales_payment_button(
        db,
        business_id=business_id,
        button_id=button_id,
        user_id=ctx.get_user_id(),
        payload=payload,
        can_manage_business=_can(ctx, db, business_id, "settings", "business"),
    )
    return success_response(data, request, message="QUICK_SALES_PAYMENT_BUTTON_UPDATED")


@router.delete("/payment-buttons/{button_id}", summary="حذف دکمه پرداخت فروش سریع")
def delete_payment_button_endpoint(
    request: Request,
    business_id: int,
    button_id: int,
    _: None = Depends(require_business_permission_dep("invoices", "add")),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> dict:
    delete_quick_sales_payment_button(
        db,
        business_id=business_id,
        button_id=button_id,
        user_id=ctx.get_user_id(),
        can_manage_business=_can(ctx, db, business_id, "settings", "business"),
    )
    return success_response({"id": button_id}, request, message="QUICK_SALES_PAYMENT_BUTTON_DELETED")


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
    request_token = str(payload.get("request_token") or "").strip()
    if not request_token:
        raise ApiError(
            "STOCK_CORRECTION_REQUEST_TOKEN_REQUIRED",
            "شناسه درخواست اصلاح موجودی الزامی است",
            http_status=400,
        )
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
        request_token=request_token,
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
