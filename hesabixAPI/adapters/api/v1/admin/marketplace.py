"""
API endpoints برای مدیریت بازار افزونه‌ها (Admin)
"""

from __future__ import annotations

from typing import Dict, Any, Optional

from fastapi import APIRouter, Depends, Body, Query, Request
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.responses import success_response, ApiError
from app.services.marketplace_service import (
	create_plugin,
	update_plugin,
	delete_plugin,
	create_plugin_plan,
	update_plugin_plan,
	delete_plugin_plan,
	list_all_plugins,
	check_and_update_expired_licenses,
	sync_default_marketplace_plugins,
)


router = APIRouter(prefix="/admin/marketplace", tags=["admin-marketplace"])


@router.post(
	"/plugins",
	summary="ایجاد افزونه جدید",
	description="ایجاد افزونه جدید در بازار افزونه‌ها",
)
def create_plugin_endpoint(
	request: Request,
	payload: Dict[str, Any] = Body(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	if not ctx.has_any_permission("system_settings", "superadmin"):
		raise ApiError("FORBIDDEN", "Missing permission: system_settings", http_status=403)
	
	data = create_plugin(db, payload)
	return success_response(data, request, "افزونه با موفقیت ایجاد شد")


@router.put(
	"/plugins/{plugin_id}",
	summary="ویرایش افزونه",
	description="ویرایش افزونه موجود",
)
def update_plugin_endpoint(
	plugin_id: int,
	request: Request,
	payload: Dict[str, Any] = Body(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	if not ctx.has_any_permission("system_settings", "superadmin"):
		raise ApiError("FORBIDDEN", "Missing permission: system_settings", http_status=403)
	
	data = update_plugin(db, plugin_id, payload)
	return success_response(data, request, "افزونه با موفقیت به‌روزرسانی شد")


@router.delete(
	"/plugins/{plugin_id}",
	summary="حذف افزونه",
	description="حذف افزونه (یا غیرفعال کردن در صورت استفاده)",
)
def delete_plugin_endpoint(
	plugin_id: int,
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	if not ctx.has_any_permission("system_settings", "superadmin"):
		raise ApiError("FORBIDDEN", "Missing permission: system_settings", http_status=403)
	
	result = delete_plugin(db, plugin_id)
	return success_response(result, request, result.get("message", "عملیات با موفقیت انجام شد"))


@router.get(
	"/plugins",
	summary="لیست تمام افزونه‌ها",
	description="دریافت لیست تمام افزونه‌ها (برای ادمین)",
)
def list_all_plugins_endpoint(
	request: Request,
	only_active: Optional[bool] = Query(None, description="فقط افزونه‌های فعال"),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	if not ctx.has_any_permission("system_settings", "superadmin"):
		raise ApiError("FORBIDDEN", "Missing permission: system_settings", http_status=403)
	
	data = list_all_plugins(db, only_active=only_active)
	return success_response(data, request)


@router.post(
	"/plugins/sync-defaults",
	summary="به‌روزرسانی لیست افزونه‌های پیش‌فرض بازار",
	description="ایجاد یا تکمیل افزونه‌ها و پلن‌های سیستمی (نصب‌های قدیمی و محیط‌های جدید)",
)
def sync_default_plugins_endpoint(
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	if not ctx.has_any_permission("system_settings", "superadmin"):
		raise ApiError("FORBIDDEN", "Missing permission: system_settings", http_status=403)

	result = sync_default_marketplace_plugins(db)
	if not result.get("ok"):
		raise ApiError(
			result.get("error") or "SYNC_FAILED",
			str(result.get("message") or "همگام‌سازی افزونه‌ها انجام نشد"),
			http_status=400,
		)
	return success_response(result, request, "لیست افزونه‌های پیش‌فرض به‌روزرسانی شد")


@router.post(
	"/plugins/{plugin_id}/plans",
	summary="ایجاد پلن برای افزونه",
	description="ایجاد پلن جدید برای یک افزونه",
)
def create_plugin_plan_endpoint(
	plugin_id: int,
	request: Request,
	payload: Dict[str, Any] = Body(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	if not ctx.has_any_permission("system_settings", "superadmin"):
		raise ApiError("FORBIDDEN", "Missing permission: system_settings", http_status=403)
	
	data = create_plugin_plan(db, plugin_id, payload)
	return success_response(data, request, "پلن با موفقیت ایجاد شد")


@router.put(
	"/plans/{plan_id}",
	summary="ویرایش پلن",
	description="ویرایش پلن موجود",
)
def update_plugin_plan_endpoint(
	plan_id: int,
	request: Request,
	payload: Dict[str, Any] = Body(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	if not ctx.has_any_permission("system_settings", "superadmin"):
		raise ApiError("FORBIDDEN", "Missing permission: system_settings", http_status=403)
	
	data = update_plugin_plan(db, plan_id, payload)
	return success_response(data, request, "پلن با موفقیت به‌روزرسانی شد")


@router.delete(
	"/plans/{plan_id}",
	summary="حذف پلن",
	description="حذف پلن (یا غیرفعال کردن در صورت استفاده)",
)
def delete_plugin_plan_endpoint(
	plan_id: int,
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	if not ctx.has_any_permission("system_settings", "superadmin"):
		raise ApiError("FORBIDDEN", "Missing permission: system_settings", http_status=403)
	
	result = delete_plugin_plan(db, plan_id)
	return success_response(result, request, result.get("message", "عملیات با موفقیت انجام شد"))


@router.post(
	"/licenses/check-expired",
	summary="بررسی لایسنس‌های منقضی شده",
	description="بررسی و به‌روزرسانی لایسنس‌های منقضی شده",
)
def check_expired_licenses_endpoint(
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	if not ctx.has_any_permission("system_settings", "superadmin"):
		raise ApiError("FORBIDDEN", "Missing permission: system_settings", http_status=403)
	
	result = check_and_update_expired_licenses(db)
	return success_response(result, request, f"{result['updated_count']} لایسنس به‌روزرسانی شد")

