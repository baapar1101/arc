from __future__ import annotations

from typing import Any, Dict, Optional

from fastapi import APIRouter, Depends, Body, Request, Query
from sqlalchemy.orm import Session
from pydantic import BaseModel

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.responses import success_response, ApiError
from app.services.admin_script_service import (
	list_scripts,
	create_script_run,
	list_script_runs,
	get_script_run_details,
	cancel_script_run,
)


router = APIRouter(prefix="/admin/scripts", tags=["مدیریت سیستم"])


class ScriptRunCreatePayload(BaseModel):
	params: Dict[str, Any] | None = None
	dry_run: bool = True


def _require_system_admin(ctx: AuthContext) -> None:
	if not ctx.is_superadmin():
		raise ApiError("FORBIDDEN", "Superadmin access required", http_status=403)


@router.get(
	"",
	summary="لیست اسکریپت‌های ادمین",
	description="دریافت کاتالوگ اسکریپت‌های قابل اجرا توسط مدیر سیستم",
)
def list_scripts_endpoint(
	request: Request,
	ctx: AuthContext = Depends(get_current_user),
):
	_require_system_admin(ctx)
	return success_response({"items": list_scripts()}, request)


@router.post(
	"/{script_key}/runs",
	summary="ایجاد اجرای اسکریپت",
	description="ایجاد اجرای جدید برای یک اسکریپت. اجرای واقعی در پس‌زمینه انجام می‌شود.",
)
def create_script_run_endpoint(
	request: Request,
	script_key: str,
	payload: ScriptRunCreatePayload = Body(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
):
	_require_system_admin(ctx)
	created = create_script_run(
		db=db,
		user_id=ctx.get_user_id(),
		script_key=script_key,
		params=payload.params or {},
		dry_run=payload.dry_run,
	)
	return success_response(created, request, message="SCRIPT_RUN_CREATED")


@router.get(
	"/runs",
	summary="لیست اجرای اسکریپت‌ها",
	description="لیست تاریخچه اجرای اسکریپت‌ها با امکان فیلتر",
)
def list_script_runs_endpoint(
	request: Request,
	script_key: Optional[str] = Query(None),
	status: Optional[str] = Query(None),
	take: int = Query(50, ge=1, le=500),
	skip: int = Query(0, ge=0),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
):
	_require_system_admin(ctx)
	result = list_script_runs(db, script_key=script_key, status=status, take=take, skip=skip)
	return success_response(result, request)


@router.get(
	"/runs/{run_id}",
	summary="جزئیات اجرای اسکریپت",
	description="نمایش جزئیات اجرای اسکریپت به همراه لاگ‌ها",
)
def get_script_run_endpoint(
	request: Request,
	run_id: int,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
):
	_require_system_admin(ctx)
	result = get_script_run_details(db, run_id)
	return success_response(result, request)


@router.post(
	"/runs/{run_id}/cancel",
	summary="لغو اجرای اسکریپت",
	description="علامت‌گذاری اجرای در حال انجام به عنوان لغو شده",
)
def cancel_script_run_endpoint(
	request: Request,
	run_id: int,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
):
	_require_system_admin(ctx)
	result = cancel_script_run(db, run_id)
	return success_response(result, request, message="SCRIPT_RUN_CANCELLED")

