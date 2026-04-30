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
from app.services.user_ui_preferences_service import get_user_ui_preferences, save_user_ui_preferences
from app.core.cache import get_cache

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
    cache = get_cache()
    cache_key = None

    if cache.enabled:
        cache_key = f"profile_widgets_definitions:{ctx.get_user_id()}"
        cached = cache.get(cache_key)
        if cached is not None:
            return success_response(cached, request)

    data = get_profile_widget_definitions(db=db, user_id=ctx.get_user_id())

    if cache.enabled and cache_key:
        cache.set(cache_key, data, ttl=300)

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
    cache = get_cache()
    cache_key = None

    if cache.enabled:
        cache_key = f"profile_dashboard_layout:{ctx.get_user_id()}:{breakpoint}"
        cached = cache.get(cache_key)
        if cached is not None:
            return success_response(cached, request)

    profile = get_profile_dashboard_layout_profile(
        db=db,
        user_id=ctx.get_user_id(),
        breakpoint=breakpoint,
    )

    if cache.enabled and cache_key:
        cache.set(cache_key, profile, ttl=300)

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

    # Invalidate cache برای layout پروفایل کاربر
    cache = get_cache()
    if cache.enabled:
        cache_key = f"profile_dashboard_layout:{ctx.get_user_id()}:{breakpoint}"
        cache.delete(cache_key)

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

    cache = get_cache()
    cache_key = None

    if cache.enabled:
        import json, hashlib
        widgets_part = ",".join(sorted(str(k) for k in widget_keys))
        filters_json = json.dumps(filters, sort_keys=True, ensure_ascii=False)
        filters_hash = hashlib.sha256(filters_json.encode("utf-8")).hexdigest()[:16]
        cache_key = f"profile_dashboard_data:{ctx.get_user_id()}:{widgets_part}:{filters_hash}"
        cached = cache.get(cache_key)
        if cached is not None:
            return success_response(cached, request)

    data = get_profile_widgets_batch_data(
        db=db,
        user_id=ctx.get_user_id(),
        widget_keys=[str(k) for k in widget_keys],
        filters=filters,
    )
    formatted = format_datetime_fields(data, request)

    if cache.enabled and cache_key:
        cache.set(cache_key, formatted, ttl=30)

    return success_response(formatted, request)


@router.get("/ui-preferences",
    summary="ترجیحات ظاهری / UI کاربر",
    description="شامل حالت نمایش پنل کسب‌وکار (تکی یا تب در دسکتاپ) و وضعیت تب‌ها به‌ازای هر کسب‌وکار.",
    response_model=SuccessResponse,
)
def get_ui_preferences(
    request: Request,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    data = get_user_ui_preferences(db=db, user_id=ctx.get_user_id())
    return success_response(data, request)


@router.put("/ui-preferences",
    summary="ذخیرهٔ ترجیحات ظاهری کاربر",
    response_model=SuccessResponse,
)
def put_ui_preferences(
    request: Request,
    payload: dict,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    if not isinstance(payload, dict):
        payload = {}
    result = save_user_ui_preferences(db=db, user_id=ctx.get_user_id(), payload=payload)
    return success_response(result, request)

