from __future__ import annotations

from typing import Any, Dict, Optional
from fastapi import APIRouter, Depends, Request, Body, HTTPException, Query
from pydantic import BaseModel
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.responses import success_response
from adapters.db.repositories.notification_repo import UserNotificationSettingRepository
from app.services.notification_service import NotificationService

router = APIRouter(prefix="/notifications", tags=["notifications"])


class SettingsPayload(BaseModel):
	telegram_enabled: Optional[bool] = None
	email_enabled: Optional[bool] = None
	sms_enabled: Optional[bool] = None
	inapp_enabled: Optional[bool] = None


@router.get("/settings", summary="دریافت تنظیمات نوتیفیکیشن کاربر")
def get_settings(
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
	user_id = ctx.get_user_id()
	repo = UserNotificationSettingRepository(db)
	rows = repo.list_for_user(user_id=user_id)
	# Defaults: همه فعال
	res = {"telegram_enabled": True, "email_enabled": True, "sms_enabled": True, "inapp_enabled": True}
	for r in rows:
		if r.event_key is None:
			if r.channel == "telegram":
				res["telegram_enabled"] = r.enabled
			elif r.channel == "email":
				res["email_enabled"] = r.enabled
			elif r.channel == "sms":
				res["sms_enabled"] = r.enabled
			elif r.channel == "inapp":
				res["inapp_enabled"] = r.enabled
	return success_response(res, request)


@router.put("/settings", summary="به‌روزرسانی تنظیمات نوتیفیکیشن کاربر")
def put_settings(
	payload: SettingsPayload,
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
	user_id = ctx.get_user_id()
	repo = UserNotificationSettingRepository(db)
	if payload.telegram_enabled is not None:
		repo.upsert(user_id=user_id, channel="telegram", event_key=None, enabled=payload.telegram_enabled)
	if payload.email_enabled is not None:
		repo.upsert(user_id=user_id, channel="email", event_key=None, enabled=payload.email_enabled)
	if payload.sms_enabled is not None:
		repo.upsert(user_id=user_id, channel="sms", event_key=None, enabled=payload.sms_enabled)
	if payload.inapp_enabled is not None:
		repo.upsert(user_id=user_id, channel="inapp", event_key=None, enabled=payload.inapp_enabled)
	return success_response({"ok": True}, request)


@router.post("/test", summary="ارسال تست نوتیفیکیشن")
def test_notification(
	channel: str = Query(..., pattern="^(telegram|email|sms|inapp)$"),
	request: Request = None,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
	user_id = ctx.get_user_id()
	svc = NotificationService(db)
	svc.send(user_id=user_id, event_key="system.test", context={"subject": "تست نوتیفیکیشن", "message": "این یک پیام تست است"}, preferred_channels=[channel])
	return success_response({"sent": True, "channel": channel}, request)


