from __future__ import annotations

from typing import Any, Dict
from fastapi import APIRouter, Depends, Request, Body
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.responses import success_response, ApiError
from app.services.announcement_service import user_list, mark_read, dismiss

router = APIRouter(prefix="/announcements", tags=["announcements"])


@router.get("", summary="لیست اعلان‌های کاربر")
def list_announcements_endpoint(
	request: Request,
	page: int = 1,
	limit: int = 10,
	level: str | None = None,
	only_unread: bool = False,
	locale: str | None = None,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
	data = user_list(db, ctx.get_user_id(), page=page, limit=limit, level=level, only_unread=only_unread, locale=locale)
	return success_response(data, request)


@router.post("/{announcement_id}/mark-read", summary="علامت خوانده شد")
def mark_read_endpoint(
	request: Request,
	announcement_id: int,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
	ok = mark_read(db, ctx.get_user_id(), announcement_id)
	if not ok:
		raise ApiError("UNKNOWN", "Operation failed", http_status=500)
	return success_response({"ok": True}, request)


@router.post("/{announcement_id}/dismiss", summary="پنهان کردن اعلان")
def dismiss_endpoint(
	request: Request,
	announcement_id: int,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
	ok = dismiss(db, ctx.get_user_id(), announcement_id)
	if not ok:
		raise ApiError("UNKNOWN", "Operation failed", http_status=500)
	return success_response({"ok": True}, request)


