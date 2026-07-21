"""API مدیریت پلن‌ها، صورت‌حساب‌ها و آمار پشتیبانی."""

from __future__ import annotations

from datetime import datetime
from typing import Any, Dict, Optional

from fastapi import APIRouter, Body, Depends, Query, Request
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import AuthContext, get_current_user
from app.core.responses import ApiError, success_response
from app.services.support.support_billing_service import admin_list_invoices, admin_void_invoice
from app.services.support.support_billing_stats_service import get_support_billing_stats
from app.services.support.support_plan_service import (
	create_support_plan,
	delete_support_plan,
	get_support_plan,
	list_support_plans,
	update_support_plan,
)

router = APIRouter(prefix="/admin/support-billing", tags=["admin-support-billing"])


def _require_admin(ctx: AuthContext) -> None:
	if not ctx.has_any_permission("system_settings", "superadmin"):
		raise ApiError("FORBIDDEN", "Missing permission: system_settings", http_status=403)


@router.post("/plans")
def create_plan(
	request: Request,
	payload: Dict[str, Any] = Body(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	_require_admin(ctx)
	data = create_support_plan(db, payload)
	return success_response(data, request, "پلن پشتیبانی ایجاد شد")


@router.get("/plans")
def list_plans(
	request: Request,
	only_active: Optional[bool] = Query(None),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	_require_admin(ctx)
	return success_response(list_support_plans(db, only_active=only_active), request)


@router.get("/plans/{plan_id}")
def get_plan(
	plan_id: int,
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	_require_admin(ctx)
	return success_response(get_support_plan(db, plan_id), request)


@router.put("/plans/{plan_id}")
def update_plan(
	plan_id: int,
	request: Request,
	payload: Dict[str, Any] = Body(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	_require_admin(ctx)
	data = update_support_plan(db, plan_id, payload)
	return success_response(data, request, "پلن پشتیبانی به‌روزرسانی شد")


@router.delete("/plans/{plan_id}")
def delete_plan(
	plan_id: int,
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	_require_admin(ctx)
	deleted = delete_support_plan(db, plan_id)
	msg = "پلن حذف شد" if deleted else "پلن غیرفعال شد"
	return success_response({"deleted": deleted}, request, msg)


@router.get("/invoices")
def list_invoices(
	request: Request,
	status: Optional[str] = Query(None),
	user_id: Optional[int] = Query(None),
	search: Optional[str] = Query(None),
	limit: int = Query(50, ge=1, le=200),
	offset: int = Query(0, ge=0),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	_require_admin(ctx)
	data = admin_list_invoices(
		db, status=status, user_id=user_id, search=search, limit=limit, offset=offset
	)
	return success_response(data, request)


@router.post("/invoices/{invoice_id}/void")
def void_invoice(
	invoice_id: int,
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	_require_admin(ctx)
	data = admin_void_invoice(db, invoice_id)
	return success_response(data, request, "صورت‌حساب ابطال شد")


@router.get("/stats")
def stats(
	request: Request,
	date_from: Optional[str] = Query(None),
	date_to: Optional[str] = Query(None),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	_require_admin(ctx)

	def _parse(v: Optional[str]) -> Optional[datetime]:
		if not v:
			return None
		try:
			return datetime.fromisoformat(v.replace("Z", "+00:00")).replace(tzinfo=None)
		except Exception:
			return None

	data = get_support_billing_stats(db, date_from=_parse(date_from), date_to=_parse(date_to))
	return success_response(data, request)
