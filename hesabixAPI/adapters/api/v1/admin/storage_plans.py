"""
API endpoints برای مدیریت پلن‌های ذخیره‌سازی (Admin)
"""

from __future__ import annotations

from typing import Dict, Any, Optional

from fastapi import APIRouter, Depends, Body, Query, Request
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.responses import success_response, ApiError
from app.services.storage_plan_service import (
	create_storage_plan,
	update_storage_plan,
	get_storage_plan,
	list_storage_plans,
	delete_storage_plan,
)


router = APIRouter(prefix="/admin/storage-plans", tags=["admin-storage-plans"])


@router.post(
	"",
	summary="ایجاد پلن جدید",
	description="ایجاد پلن جدید برای ذخیره‌سازی توسط مدیر",
)
def create_storage_plan_endpoint(
	request: Request,
	payload: Dict[str, Any] = Body(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	if not ctx.has_any_permission("system_settings", "superadmin"):
		raise ApiError("FORBIDDEN", "Missing permission: system_settings", http_status=403)
	
	data = create_storage_plan(db, payload)
	return success_response(data, request, "پلن با موفقیت ایجاد شد")


@router.put(
	"/{plan_id}",
	summary="ویرایش پلن",
	description="ویرایش پلن موجود",
)
def update_storage_plan_endpoint(
	plan_id: int,
	request: Request,
	payload: Dict[str, Any] = Body(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	if not ctx.has_any_permission("system_settings", "superadmin"):
		raise ApiError("FORBIDDEN", "Missing permission: system_settings", http_status=403)
	
	data = update_storage_plan(db, plan_id, payload)
	return success_response(data, request, "پلن با موفقیت به‌روزرسانی شد")


@router.get(
	"",
	summary="لیست پلن‌ها",
	description="دریافت لیست تمام پلن‌های ذخیره‌سازی",
)
def list_storage_plans_endpoint(
	request: Request,
	only_active: Optional[bool] = Query(None, description="فقط پلن‌های فعال"),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	if not ctx.has_any_permission("system_settings", "superadmin"):
		raise ApiError("FORBIDDEN", "Missing permission: system_settings", http_status=403)
	
	data = list_storage_plans(db, only_active=only_active)
	return success_response(data, request)


@router.get(
	"/{plan_id}",
	summary="جزئیات پلن",
	description="دریافت جزئیات یک پلن",
)
def get_storage_plan_endpoint(
	plan_id: int,
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	if not ctx.has_any_permission("system_settings", "superadmin"):
		raise ApiError("FORBIDDEN", "Missing permission: system_settings", http_status=403)
	
	data = get_storage_plan(db, plan_id)
	return success_response(data, request)


@router.delete(
	"/{plan_id}",
	summary="حذف/غیرفعال کردن پلن",
	description="حذف یا غیرفعال کردن پلن (اگر اشتراک فعالی نداشته باشد حذف می‌شود، وگرنه فقط غیرفعال می‌شود)",
)
def delete_storage_plan_endpoint(
	plan_id: int,
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	if not ctx.has_any_permission("system_settings", "superadmin"):
		raise ApiError("FORBIDDEN", "Missing permission: system_settings", http_status=403)
	
	deleted = delete_storage_plan(db, plan_id)
	message = "پلن با موفقیت حذف شد" if deleted else "پلن با موفقیت غیرفعال شد"
	return success_response({"deleted": deleted}, request, message)

