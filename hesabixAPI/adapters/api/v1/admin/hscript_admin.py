"""Admin endpoints برای ممیزی اجرای گزارش‌های HScript."""

from __future__ import annotations

from typing import Optional

from fastapi import APIRouter, Depends, Query, Request
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import AuthContext, get_current_user
from app.core.permissions import require_app_permission
from app.core.responses import ApiError, format_datetime_fields, success_response
from app.services import hscript_report_service as svc


router = APIRouter(prefix="/admin/hscript", tags=["admin-hscript"])


def _require_admin(ctx: AuthContext) -> None:
	if not (ctx.is_superadmin() or ctx.has_app_permission("system_settings")):
		raise ApiError(
			"FORBIDDEN",
			"system_settings permission required",
			http_status=403,
		)


@router.get(
	"/runs",
	summary="لیست اجرای HScript (همه کسب‌وکارها)",
)
@require_app_permission("system_settings")
async def list_hscript_runs_admin(
	request: Request,
	business_id: Optional[int] = Query(default=None),
	status: Optional[str] = Query(default=None),
	skip: int = Query(default=0, ge=0),
	take: int = Query(default=50, ge=1, le=200),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
):
	_require_admin(ctx)
	data = svc.list_runs_admin(
		db,
		business_id=business_id,
		status=status,
		skip=skip,
		take=take,
	)
	return success_response(
		data=format_datetime_fields(data, request),
		request=request,
		message="HSCRIPT_ADMIN_RUNS",
	)
