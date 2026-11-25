"""فهرست لاگ کارهای مدیر سیستم."""

from __future__ import annotations

from fastapi import APIRouter, Depends, Query, Request
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import AuthContext, get_current_user
from app.core.responses import ApiError, success_response
from app.services.admin_audit_service import list_admin_actions

router = APIRouter(prefix="/admin/audit-logs", tags=["admin-audit"])


@router.get("", summary="لاگ کارهای مدیر سیستم")
def list_admin_audit_logs(
	request: Request,
	action: str | None = Query(None, max_length=64),
	skip: int = Query(0, ge=0),
	take: int = Query(50, ge=1, le=200),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
):
	if not ctx.has_app_permission("system_settings"):
		raise ApiError("FORBIDDEN", "Missing permission: system_settings", http_status=403)
	data = list_admin_actions(db, action=action, skip=skip, take=take)
	return success_response(data, request)
