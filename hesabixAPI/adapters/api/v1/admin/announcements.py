from __future__ import annotations

from typing import Any, Dict
from fastapi import APIRouter, Depends, Request, Body
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.responses import success_response, ApiError
from app.core.permissions import require_app_permission
from app.services.announcement_service import (
	admin_list,
	admin_create,
	admin_update,
	admin_delete,
	admin_publish,
)

router = APIRouter(prefix="/admin/announcements", tags=["admin_announcements"])


@router.get("", summary="لیست اعلان‌ها (ادمین)")
@require_app_permission("system_settings")
def admin_list_endpoint(
	request: Request,
	page: int = 1,
	limit: int = 20,
	level: str | None = None,
	active: bool | None = None,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
	data = admin_list(db, page=page, limit=limit, level=level, active=active)
	return success_response(data, request)


@router.post("", summary="ایجاد اعلان (ادمین)")
@require_app_permission("system_settings")
def admin_create_endpoint(
	request: Request,
	payload: Dict[str, Any] = Body(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
	data = admin_create(db, payload, created_by=ctx.get_user_id())
	return success_response(data, request)


@router.put("/{announcement_id}", summary="ویرایش اعلان (ادمین)")
@require_app_permission("system_settings")
def admin_update_endpoint(
	request: Request,
	announcement_id: int,
	payload: Dict[str, Any] = Body(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
	data = admin_update(db, announcement_id, payload)
	if not data:
		raise ApiError("NOT_FOUND", "Announcement not found", http_status=404)
	return success_response(data, request)


@router.delete("/{announcement_id}", summary="حذف اعلان (ادمین)")
@require_app_permission("system_settings")
def admin_delete_endpoint(
	request: Request,
	announcement_id: int,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
	ok = admin_delete(db, announcement_id)
	if not ok:
		raise ApiError("NOT_FOUND", "Announcement not found", http_status=404)
	return success_response({"ok": True}, request)


@router.post("/{announcement_id}/publish", summary="انتشار/توقف اعلان (ادمین)")
@require_app_permission("system_settings")
def admin_publish_endpoint(
	request: Request,
	announcement_id: int,
	payload: Dict[str, Any] = Body(default_factory=dict),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
	active = bool(payload.get("active", True))
	pinned = payload.get("is_pinned", None)
	data = admin_publish(db, announcement_id, active=active, is_pinned=pinned)
	if not data:
		raise ApiError("NOT_FOUND", "Announcement not found", http_status=404)
	return success_response(data, request)


