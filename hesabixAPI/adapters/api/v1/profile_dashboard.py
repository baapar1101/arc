# Removed __future__ annotations to fix OpenAPI schema generation

from fastapi import APIRouter, Depends, Request
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from adapters.api.v1.schemas import SuccessResponse
from app.core.responses import success_response, format_datetime_fields
from app.core.auth_dependency import get_current_user, AuthContext
from app.services.profile_dashboard_widgets_service import (
    get_profile_widget_definitions,
    get_profile_dashboard_layout_profile,
    save_profile_dashboard_layout_profile,
    get_profile_widgets_batch_data,
)

router = APIRouter(prefix="/profile", tags=["profile-dashboard"])


@router.get("/dashboard/widgets/definitions",
    summary="تعاریف ویجت‌های داشبورد پروفایل",
    description="لیست ویجت‌های قابل استفاده برای داشبورد پروفایل کاربر",
    response_model=SuccessResponse,
)
def list_profile_dashboard_widget_definitions(
    request: Request,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    data = get_profile_widget_definitions(db=db, user_id=ctx.get_user_id())
    return success_response(data, request)


@router.get("/dashboard/layout",
    summary="دریافت چیدمان داشبورد پروفایل (پروفایل رسپانسیو)",
    description="چیدمان کاربر برای یک breakpoint مشخص را برمی‌گرداند. در نبود، از پیش‌فرض سیستم استفاده می‌کند.",
    response_model=SuccessResponse,
)
def get_profile_dashboard_layout(
    request: Request,
    breakpoint: str = "md",
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    profile = get_profile_dashboard_layout_profile(
        db=db,
        user_id=ctx.get_user_id(),
        breakpoint=breakpoint,
    )
    return success_response(profile, request)


@router.put("/dashboard/layout",
    summary="ذخیره چیدمان داشبورد پروفایل (پروفایل رسپانسیو)",
    description="چیدمان کاربر برای breakpoint مشخص را ذخیره می‌کند.",
    response_model=SuccessResponse,
)
def put_profile_dashboard_layout(
    request: Request,
    payload: dict,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    breakpoint = str(payload.get("breakpoint") or "md")
    items = payload.get("items") or []
    result = save_profile_dashboard_layout_profile(
        db=db,
        user_id=ctx.get_user_id(),
        breakpoint=breakpoint,
        items=items,
    )
    return success_response(result, request)


@router.post("/dashboard/data",
    summary="دریافت داده‌ی ویجت‌های پروفایل (Batch)",
    description="کلیدهای ویجت را می‌گیرد و داده‌ی هر ویجت را در یک پاسخ برمی‌گرداند.",
    response_model=SuccessResponse,
)
def post_profile_dashboard_widgets_data(
    request: Request,
    payload: dict,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    widget_keys = payload.get("widget_keys") or []
    filters = payload.get("filters") or {}
    data = get_profile_widgets_batch_data(
        db=db,
        user_id=ctx.get_user_id(),
        widget_keys=[str(k) for k in widget_keys],
        filters=filters,
    )
    formatted = format_datetime_fields(data, request)
    return success_response(formatted, request)

