"""خانه عملیاتی، زمان‌بندی، گزارش و لایسنس‌های در حال انقضا."""

from __future__ import annotations

from fastapi import APIRouter, Depends, Query, Request
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import AuthContext, get_current_user
from app.core.responses import ApiError, success_response
from app.services.admin_operations_service import (
	expiring_licenses,
	failed_login_report,
	inactive_businesses_report,
	list_schedules,
	operations_home,
	storage_usage_report,
)

router = APIRouter(prefix="/admin/operations", tags=["admin-operations"])


def _require_admin(ctx: AuthContext) -> None:
	if not ctx.has_app_permission("system_settings"):
		raise ApiError("FORBIDDEN", "Missing permission: system_settings", http_status=403)


@router.get("/home", summary="خلاصه عملیاتی مدیر سیستم")
def operations_home_endpoint(
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
):
	_require_admin(ctx)
	return success_response(operations_home(db), request)


@router.get("/schedules", summary="کرون ورک‌فلو و زمان‌بندی ارزیابی AI")
def schedules_endpoint(
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
):
	_require_admin(ctx)
	return success_response(list_schedules(db), request)


@router.get("/reports/storage", summary="مصرف ذخیره‌سازی به تفکیک کسب‌وکار")
def storage_report_endpoint(
	request: Request,
	limit: int = Query(30, ge=1, le=200),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
):
	_require_admin(ctx)
	return success_response(storage_usage_report(db, limit=limit), request)


@router.get("/reports/inactive-businesses", summary="کسب‌وکارهای بدون فعالیت")
def inactive_businesses_endpoint(
	request: Request,
	days: int = Query(90, ge=7, le=3650),
	limit: int = Query(50, ge=1, le=200),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
):
	_require_admin(ctx)
	return success_response(inactive_businesses_report(db, days=days, limit=limit), request)


@router.get("/reports/failed-logins", summary="شکست ورود و کپچا")
def failed_logins_endpoint(
	request: Request,
	hours: int = Query(24, ge=1, le=2160),
	limit: int = Query(80, ge=1, le=200),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
):
	_require_admin(ctx)
	return success_response(failed_login_report(db, hours=hours, limit=limit), request)


@router.get("/licenses/expiring", summary="لایسنس افزونه‌های در حال انقضا")
def expiring_licenses_endpoint(
	request: Request,
	within_days: int = Query(30, ge=1, le=365),
	limit: int = Query(100, ge=1, le=500),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
):
	_require_admin(ctx)
	return success_response(expiring_licenses(db, within_days=within_days, limit=limit), request)
